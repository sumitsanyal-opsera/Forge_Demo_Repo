/**
 * Thin caching layer for SecurityHealthCheckResult to prevent redundant Tooling API
 * queries during concurrent smoke test executions.
 *
 * Primary store  — Platform Cache Organization partition (local.SmokeTestCache),
 *                  60-second TTL, org-scoped key.
 * Fallback store — static Map, same TTL logic.
 *                  Used automatically when Platform Cache is unavailable (edition
 *                  restrictions, partition not configured) or when bypassPlatformCache
 *                  is set to true in unit tests.
 *
 * Cache key format: SecurityHealthCheck_{organizationId}
 */
public with sharing class SecurityHealthCheckCache {

    private static final String PARTITION_NAME   = 'local.SmokeTestCache';
    private static final String CACHE_KEY_PREFIX = 'SecurityHealthCheck_';

    // =========================================================================
    // Test control
    // =========================================================================

    @TestVisible static Boolean bypassPlatformCache = false;

    // =========================================================================
    // Static fallback cache
    // =========================================================================

    @TestVisible static Map<String, CachedEntry> staticCache =
        new Map<String, CachedEntry>();

    @TestVisible
    class CachedEntry {
        @TestVisible SecurityHealthCheckResult result;
        @TestVisible Long expiresAtMs;

        CachedEntry(SecurityHealthCheckResult r, Integer ttlSeconds) {
            this.result      = r;
            this.expiresAtMs = Datetime.now().addSeconds(ttlSeconds).getTime();
        }

        Boolean isExpired() {
            return Datetime.now().getTime() > expiresAtMs;
        }
    }

    // =========================================================================
    // Public API
    // =========================================================================

    /**
     * Returns a cached result for the given org, or null if none exists / expired.
     */
    public static SecurityHealthCheckResult get(String orgId) {
        String key = CACHE_KEY_PREFIX + orgId;

        if (!bypassPlatformCache) {
            try {
                Cache.OrgPartition part = Cache.Org.getPartition(PARTITION_NAME);
                Object cached = part.get(key);
                if (cached instanceof SecurityHealthCheckResult) {
                    return (SecurityHealthCheckResult) cached;
                }
            } catch (Exception e) {
                System.debug(LoggingLevel.WARN,
                    'SecurityHealthCheckCache: Platform Cache unavailable — '
                    + 'falling back to static cache. Reason: ' + e.getMessage());
            }
        }

        CachedEntry entry = staticCache.get(key);
        if (entry != null) {
            if (!entry.isExpired()) {
                return entry.result;
            }
            staticCache.remove(key);
        }
        return null;
    }

    /**
     * Stores a result in both the Platform Cache and the static fallback.
     * @param orgId      Organization ID used to namespace the key
     * @param result     Result to cache
     * @param ttlSeconds Time-to-live in seconds
     */
    public static void put(String orgId, SecurityHealthCheckResult result, Integer ttlSeconds) {
        String key = CACHE_KEY_PREFIX + orgId;

        if (!bypassPlatformCache) {
            try {
                Cache.OrgPartition part = Cache.Org.getPartition(PARTITION_NAME);
                part.put(key, result, ttlSeconds);
            } catch (Exception e) {
                System.debug(LoggingLevel.WARN,
                    'SecurityHealthCheckCache: Platform Cache put failed — '
                    + 'static cache only. Reason: ' + e.getMessage());
            }
        }

        staticCache.put(key, new CachedEntry(result, ttlSeconds));
    }
}
