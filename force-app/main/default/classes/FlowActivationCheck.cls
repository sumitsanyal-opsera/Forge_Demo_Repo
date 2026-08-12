public with sharing class FlowActivationCheck implements IChecklistCheck {

    private static final String CHECK_NAME  = 'Flow Activation';
    private static final String CHECK_TYPE  = 'FLOW_ACTIVATION';
    private static final String API_VERSION = 'v60.0';

    public ChecklistResult execute(ChecklistContext ctx) {
        List<String> flowNames = extractFlowNames(ctx.manifestComponents);

        if (flowNames.isEmpty()) {
            return new ChecklistResult(
                CHECK_NAME, CHECK_TYPE,
                ChecklistResult.Status.WARNING,
                'Active flows in manifest',
                'No flows in manifest',
                'No Flow components found in deployment manifest — skipping activation check'
            );
        }

        List<String> quotedNames = new List<String>();
        for (String name : flowNames) {
            quotedNames.add('\'' + String.escapeSingleQuotes(name) + '\'');
        }

        String soql = 'SELECT Id,DeveloperName,ActiveVersionId FROM FlowDefinition'
            + ' WHERE DeveloperName IN (' + String.join(quotedNames, ',') + ')';

        String endpoint = URL.getSalesforceBaseUrl().toExternalForm()
            + '/services/data/' + API_VERSION + '/tooling/query/?q='
            + EncodingUtil.urlEncode(soql, 'UTF-8');

        HttpRequest req = new HttpRequest();
        req.setEndpoint(endpoint);
        req.setMethod('GET');
        req.setHeader('Authorization', 'Bearer ' + UserInfo.getSessionId());
        req.setHeader('Content-Type', 'application/json');

        HttpResponse res;
        try {
            res = ctx.httpCallout.send(req);
        } catch (Exception e) {
            return new ChecklistResult(
                CHECK_NAME, CHECK_TYPE,
                ChecklistResult.Status.WARNING,
                'Tooling API reachable',
                'Callout failed',
                'Tooling API callout failed: ' + ErrorSanitizer.sanitize(e.getMessage())
            );
        }

        if (res.getStatusCode() != 200) {
            return new ChecklistResult(
                CHECK_NAME, CHECK_TYPE,
                ChecklistResult.Status.WARNING,
                'HTTP 200 from Tooling API',
                'HTTP ' + res.getStatusCode(),
                'Tooling API returned HTTP ' + res.getStatusCode()
            );
        }

        Map<String, Object> body    = (Map<String, Object>) JSON.deserializeUntyped(res.getBody());
        List<Object>        records = (List<Object>) body.get('records');
        if (records == null) {
            records = new List<Object>();
        }

        Map<String, String> activeVersionById = new Map<String, String>();
        for (Object rec : records) {
            Map<String, Object> r       = (Map<String, Object>) rec;
            String              devName = String.valueOf(r.get('DeveloperName'));
            Object              active  = r.get('ActiveVersionId');
            activeVersionById.put(devName, active != null ? String.valueOf(active) : null);
        }

        List<String> notFound = new List<String>();
        List<String> inactive = new List<String>();
        for (String flowName : flowNames) {
            if (!activeVersionById.containsKey(flowName)) {
                notFound.add(flowName);
            } else if (activeVersionById.get(flowName) == null) {
                inactive.add(flowName);
            }
        }

        if (!notFound.isEmpty() || !inactive.isEmpty()) {
            List<String> issues = new List<String>();
            if (!notFound.isEmpty()) {
                issues.add('Not found: ' + String.join(notFound, ', '));
            }
            if (!inactive.isEmpty()) {
                issues.add('Inactive: ' + String.join(inactive, ', '));
            }
            return new ChecklistResult(
                CHECK_NAME, CHECK_TYPE,
                ChecklistResult.Status.FAIL,
                String.join(flowNames, ', ') + ' — all active',
                String.join(issues, '; '),
                'One or more Flows are not activated. ' + String.join(issues, '. ')
            );
        }

        return new ChecklistResult(
            CHECK_NAME, CHECK_TYPE,
            ChecklistResult.Status.PASS,
            String.join(flowNames, ', ') + ' — all active',
            'All ' + flowNames.size() + ' flow(s) active',
            'All ' + flowNames.size() + ' Flow(s) verified as active in org'
        );
    }

    private static List<String> extractFlowNames(List<ManifestComponent> components) {
        List<String> names = new List<String>();
        for (ManifestComponent comp : components) {
            if ('Flow'.equalsIgnoreCase(comp.componentType)
                    || 'FlowDefinition'.equalsIgnoreCase(comp.componentType)) {
                names.add(comp.componentName);
            }
        }
        return names;
    }
}
