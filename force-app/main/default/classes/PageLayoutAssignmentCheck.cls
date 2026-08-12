public with sharing class PageLayoutAssignmentCheck implements IChecklistCheck {

    private static final String CHECK_NAME  = 'Page Layout Assignment';
    private static final String CHECK_TYPE  = 'PAGE_LAYOUT';
    private static final String API_VERSION = 'v60.0';

    public ChecklistResult execute(ChecklistContext ctx) {
        List<String> layoutNames = extractLayoutNames(ctx.manifestComponents);

        if (layoutNames.isEmpty()) {
            return new ChecklistResult(
                CHECK_NAME, CHECK_TYPE,
                ChecklistResult.Status.WARNING,
                'Page layouts assigned to profiles',
                'No layouts in manifest',
                'No Layout components found in deployment manifest — skipping assignment check'
            );
        }

        List<String> quotedNames = new List<String>();
        for (String name : layoutNames) {
            quotedNames.add('\'' + String.escapeSingleQuotes(name) + '\'');
        }

        String soql = 'SELECT Id,Layout.Name,ProfileId FROM ProfileLayout'
            + ' WHERE Layout.Name IN (' + String.join(quotedNames, ',') + ')';

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

        Map<String, Integer> assignmentCounts = new Map<String, Integer>();
        for (String name : layoutNames) {
            assignmentCounts.put(name, 0);
        }
        for (Object rec : records) {
            Map<String, Object> r          = (Map<String, Object>) rec;
            Map<String, Object> layoutObj  = (Map<String, Object>) r.get('Layout');
            if (layoutObj == null) continue;
            String layoutName = String.valueOf(layoutObj.get('Name'));
            if (assignmentCounts.containsKey(layoutName)) {
                assignmentCounts.put(layoutName, assignmentCounts.get(layoutName) + 1);
            }
        }

        List<String> unassigned = new List<String>();
        List<String> ambiguous  = new List<String>();
        for (String layoutName : layoutNames) {
            Integer count = assignmentCounts.get(layoutName);
            if (count == 0) {
                unassigned.add(layoutName);
            } else if (count > 1) {
                ambiguous.add(layoutName);
            }
        }

        if (!unassigned.isEmpty()) {
            return new ChecklistResult(
                CHECK_NAME, CHECK_TYPE,
                ChecklistResult.Status.FAIL,
                String.join(layoutNames, ', ') + ' — all assigned to a profile',
                'Unassigned: ' + String.join(unassigned, ', '),
                'One or more page layouts have no profile assignments: '
                    + String.join(unassigned, ', ')
            );
        }

        if (!ambiguous.isEmpty()) {
            return new ChecklistResult(
                CHECK_NAME, CHECK_TYPE,
                ChecklistResult.Status.WARNING,
                'Each layout assigned to exactly one profile',
                'Multiple assignments: ' + String.join(ambiguous, ', '),
                'One or more page layouts are assigned to multiple profiles — verify assignment is correct: '
                    + String.join(ambiguous, ', ')
            );
        }

        return new ChecklistResult(
            CHECK_NAME, CHECK_TYPE,
            ChecklistResult.Status.PASS,
            String.join(layoutNames, ', ') + ' — all assigned',
            records.size() + ' assignment(s) found across ' + layoutNames.size() + ' layout(s)',
            'All ' + layoutNames.size() + ' layout(s) verified as assigned in org'
        );
    }

    private static List<String> extractLayoutNames(List<ManifestComponent> components) {
        List<String> names = new List<String>();
        for (ManifestComponent comp : components) {
            if ('Layout'.equalsIgnoreCase(comp.componentType)) {
                names.add(comp.componentName);
            }
        }
        return names;
    }
}
