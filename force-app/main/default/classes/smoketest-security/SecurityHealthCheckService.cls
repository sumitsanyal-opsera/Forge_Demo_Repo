/**
 * Queries the Salesforce SecurityHealthCheck Tooling API object to retrieve
 * the org's current security health score, risk categories, and remediation links.
 *
 * Design decisions:
 *   - IHttpCallout nested interface: allows constructor injection of a mock HTTP
 *     handler in unit tests without requiring Test.setMock(); production code
 *     uses DefaultHttpCallout which delegates to new Http().send().
 *   - SecurityHealthCheckCache: 60-second org-scoped cache prevents redundant
 *     Tooling API queries during concurrent smoke test executions.
 *   - Pre-flight Limits.getApiCallsRemaining() guard: returns SKIPPED before
 *     consuming any callout budget when fewer than 5 API calls remain.
 *   - All outcomes (PASS, FAIL, ERROR, SKIPPED) are logged to SmokeTestAuditLog__c
 *     via AuditLogWriter before returning to the caller.
 *   - JSON parsing uses JSON.deserializeUntyped() with null-safe field access so
 *     unexpected or missing fields are tolerated gracefully.
 *   - Authentication: uses the running user's session ID via UserInfo.getSessionId().
 *     For pipeline service accounts, ensure the calling context has an active session.
 */
public with sharing class SecurityHealthCheckService implements ISecurityHealthCheckService {

    // =========================================================================
    // Injectable HTTP callout interface
    // =========================================================================

    public interface IHttpCallout {
        HttpResponse send(HttpRequest req);
    }

    @TestVisible
    private static class DefaultHttpCallout implements IHttpCallout {
        public HttpResponse send(HttpRequest req) {
            return new Http().send(req);
        }
    }

    // =========================================================================
    // Constants
    // =========================================================================

    private static final String  TOOLING_API_QUERY_PATH =
        '/services/data/v60.0/tooling/query/?q=SELECT+Id%2CScore%2CSecurityRiskCategory+FROM+SecurityHealthCheck';

    private static final String  RESOURCE_TYPE       = 'SecurityHealthCheck';
    private static final String  RESOURCE_ID         = 'SecurityHealthCheck';
    private static final String  CONFIG_RECORD        = 'Default';
    private static final Integer DEFAULT_CACHE_TTL    = 60;
    private static final Integer DEFAULT_MIN_API_CALLS = 5;

    private static final String  REMEDIATION_LINK =
        'https://help.salesforce.com/s/articleView?id=sf.security_health_check.htm';

    // =========================================================================
    // Test injection points
    // =========================================================================

    @TestVisible private static Integer injectedApiCallsRemaining = null;

    // =========================================================================
    // Fields
    // =========================================================================

    private final IHttpCallout   http;
    private final AuditLogWriter auditWriter;

    // =========================================================================
    // Constructors
    // =========================================================================

    public SecurityHealthCheckService() {
        this(new DefaultHttpCallout(), new DefaultDmlHandler());
    }

    @TestVisible
    SecurityHealthCheckService(IHttpCallout http, IDmlHandler dml) {
        this.http        = http;
        this.auditWriter = new AuditLogWriter(dml);
    }

    // =========================================================================
    // ISecurityHealthCheckService
    // =========================================================================

    public SecurityHealthCheckResult captureScore() {
        // ── Cache check ──────────────────────────────────────────────────────
        String orgId    = UserInfo.getOrganizationId();
        Integer cacheTtl = DEFAULT_CACHE_TTL;

        Map<String, SmokeTestConfig__mdt> allConfigs = SmokeTestConfig__mdt.getAll();
        if (allConfigs != null && allConfigs.containsKey(CONFIG_RECORD)) {
            SmokeTestConfig__mdt cfg = allConfigs.get(CONFIG_RECORD);
            if (cfg.SecurityCacheTTL__c != null) {
                cacheTtl = Integer.valueOf(cfg.SecurityCacheTTL__c);
            }
        }

        SecurityHealthCheckResult cached = SecurityHealthCheckCache.get(orgId);
        if (cached != null) {
            return cached;
        }

        // ── Pre-flight API budget check ───────────────────────────────────────
        Integer callsRemaining = injectedApiCallsRemaining != null
            ? injectedApiCallsRemaining
            : Limits.getApiCallsRemaining();

        if (callsRemaining < DEFAULT_MIN_API_CALLS) {
            SecurityHealthCheckResult skipped = SecurityHealthCheckResult.skipped(
                'API call limit approaching — security check skipped to preserve budget');
            writeAuditLog(skipped);
            return skipped;
        }

        // ── Tooling API callout ───────────────────────────────────────────────
        SecurityHealthCheckResult result;
        try {
            HttpRequest req = buildRequest();
            HttpResponse res = http.send(req);
            result = parseResponse(res);
        } catch (CalloutException ce) {
            result = SecurityHealthCheckResult.error(
                'Network error connecting to Tooling API: ' + ce.getMessage());
        } catch (Exception e) {
            result = SecurityHealthCheckResult.error(
                'Unexpected error during Tooling API callout: ' + e.getMessage());
        }

        // ── Cache result (not SKIPPED — that path returns above) ─────────────
        SecurityHealthCheckCache.put(orgId, result, cacheTtl);

        writeAuditLog(result);
        return result;
    }

    // =========================================================================
    // Private — request / response helpers
    // =========================================================================

    private HttpRequest buildRequest() {
        String sessionId = UserInfo.getSessionId();
        String baseUrl   = URL.getOrgDomainUrl().toExternalForm();

        HttpRequest req = new HttpRequest();
        req.setEndpoint(baseUrl + TOOLING_API_QUERY_PATH);
        req.setMethod('GET');
        req.setHeader('Authorization', 'Bearer ' + sessionId);
        req.setHeader('Content-Type', 'application/json');
        return req;
    }

    private SecurityHealthCheckResult parseResponse(HttpResponse res) {
        Integer statusCode = res.getStatusCode();

        if (statusCode == 401) {
            return SecurityHealthCheckResult.error(
                'Authentication failed for integration user — verify Connected App and session validity');
        }
        if (statusCode == 403) {
            return SecurityHealthCheckResult.error(
                'View Setup and Configuration permission required for the integration user');
        }
        if (statusCode == 500) {
            return SecurityHealthCheckResult.error(
                'Unable to retrieve security health score — Tooling API unavailable (HTTP 500)');
        }
        if (statusCode != 200) {
            return SecurityHealthCheckResult.error(
                'Unexpected HTTP status ' + statusCode + ' from Tooling API');
        }

        return parseSuccessBody(res.getBody());
    }

    private SecurityHealthCheckResult parseSuccessBody(String body) {
        try {
            Object parsed = JSON.deserializeUntyped(body);
            if (!(parsed instanceof Map<String, Object>)) {
                return SecurityHealthCheckResult.error(
                    'Malformed Tooling API response — check API version compatibility');
            }
            Map<String, Object> root    = (Map<String, Object>) parsed;
            List<Object>        records = (List<Object>) root.get('records');

            if (records == null || records.isEmpty()) {
                SecurityHealthCheckResult r = new SecurityHealthCheckResult();
                r.overallScore      = -1;
                r.thresholdStatus   = SecurityHealthCheckResult.ThresholdStatus.ERROR;
                r.diagnosticMessage =
                    'No SecurityHealthCheck records found — org may not have Health Check configured';
                return r;
            }

            Map<String, Object> record = (Map<String, Object>) records[0];
            Integer score = record.get('Score') != null
                ? Integer.valueOf(String.valueOf(record.get('Score')))
                : -1;

            List<SecurityHealthCheckResult.SecurityRiskCategory> categories =
                parseRiskCategories(record.get('SecurityRiskCategory'));

            SecurityHealthCheckResult r = new SecurityHealthCheckResult();
            r.overallScore      = score;
            r.riskCategories    = categories;
            r.remediationLinks  = new List<String>{ REMEDIATION_LINK };
            r.thresholdStatus   = score >= 0
                ? SecurityHealthCheckResult.ThresholdStatus.PASS
                : SecurityHealthCheckResult.ThresholdStatus.FAIL;
            r.diagnosticMessage = 'Security health score captured successfully. Score: ' + score;
            return r;

        } catch (JSONException je) {
            return SecurityHealthCheckResult.error(
                'Malformed Tooling API response — check API version compatibility');
        } catch (Exception e) {
            return SecurityHealthCheckResult.error(
                'Error parsing Tooling API response: ' + e.getMessage());
        }
    }

    private List<SecurityHealthCheckResult.SecurityRiskCategory> parseRiskCategories(Object raw) {
        List<SecurityHealthCheckResult.SecurityRiskCategory> categories =
            new List<SecurityHealthCheckResult.SecurityRiskCategory>();
        if (raw == null) {
            return categories;
        }
        try {
            if (!(raw instanceof List<Object>)) {
                return categories;
            }
            for (Object catObj : (List<Object>) raw) {
                if (!(catObj instanceof Map<String, Object>)) {
                    continue;
                }
                Map<String, Object> catMap = (Map<String, Object>) catObj;
                SecurityHealthCheckResult.SecurityRiskCategory cat =
                    new SecurityHealthCheckResult.SecurityRiskCategory();
                cat.categoryName = catMap.get('name') != null
                    ? String.valueOf(catMap.get('name')) : 'Unknown';
                cat.score = catMap.get('score') != null
                    ? Integer.valueOf(String.valueOf(catMap.get('score'))) : 0;
                cat.settings = parseSettings(catMap.get('settings'));
                categories.add(cat);
            }
        } catch (Exception e) {
            System.debug(LoggingLevel.WARN,
                'SecurityHealthCheckService: error parsing risk category — ' + e.getMessage());
        }
        return categories;
    }

    private List<SecurityHealthCheckResult.SecuritySetting> parseSettings(Object raw) {
        List<SecurityHealthCheckResult.SecuritySetting> settings =
            new List<SecurityHealthCheckResult.SecuritySetting>();
        if (raw == null) {
            return settings;
        }
        try {
            if (!(raw instanceof List<Object>)) {
                return settings;
            }
            for (Object settingObj : (List<Object>) raw) {
                if (!(settingObj instanceof Map<String, Object>)) {
                    continue;
                }
                Map<String, Object> sm = (Map<String, Object>) settingObj;
                SecurityHealthCheckResult.SecuritySetting setting =
                    new SecurityHealthCheckResult.SecuritySetting();
                setting.settingName    = sm.get('settingName') != null
                    ? String.valueOf(sm.get('settingName')) : 'Unknown';
                setting.value          = sm.get('value') != null
                    ? String.valueOf(sm.get('value')) : null;
                setting.recommendation = sm.get('recommendation') != null
                    ? String.valueOf(sm.get('recommendation')) : null;
                settings.add(setting);
            }
        } catch (Exception e) {
            System.debug(LoggingLevel.WARN,
                'SecurityHealthCheckService: error parsing setting — ' + e.getMessage());
        }
        return settings;
    }

    // =========================================================================
    // Private — audit logging
    // =========================================================================

    private void writeAuditLog(SecurityHealthCheckResult result) {
        try {
            AuditLogEntry entry = new AuditLogEntry.Builder()
                .actorUserId(UserInfo.getUserId())
                .actionType(AuditLogEntry.ACTION_TEST_EXECUTION)
                .resourceId(RESOURCE_ID)
                .resourceType(RESOURCE_TYPE)
                .outcome(result.thresholdStatus.name())
                .build();
            auditWriter.logAction(entry);
        } catch (Exception e) {
            System.debug(LoggingLevel.WARN,
                'SecurityHealthCheckService: audit log write failed — ' + e.getMessage());
        }
    }
}
