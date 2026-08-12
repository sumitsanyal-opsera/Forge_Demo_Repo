public with sharing class PermissionSetAssignmentCheck implements IChecklistCheck {

    private static final String CHECK_NAME = 'Permission Set Assignment';
    private static final String CHECK_TYPE = 'PERMISSION_SET';

    public ChecklistResult execute(ChecklistContext ctx) {
        List<String> psNames = extractPermissionSetNames(ctx.manifestComponents);

        if (psNames.isEmpty()) {
            return new ChecklistResult(
                CHECK_NAME, CHECK_TYPE,
                ChecklistResult.Status.WARNING,
                'Permission sets assigned to expected profiles',
                'No permission sets in manifest',
                'No PermissionSet components found in deployment manifest — skipping assignment check'
            );
        }

        List<PermissionSetAssignment> assignments;
        try {
            assignments = [
                SELECT Id, PermissionSet.Name, AssigneeId
                FROM PermissionSetAssignment
                WHERE PermissionSet.Name IN :psNames
                WITH SECURITY_ENFORCED
            ];
        } catch (Exception e) {
            return new ChecklistResult(
                CHECK_NAME, CHECK_TYPE,
                ChecklistResult.Status.WARNING,
                'PermissionSetAssignment queryable',
                'Query failed',
                'PermissionSetAssignment query failed: ' + ErrorSanitizer.sanitize(e.getMessage())
            );
        }

        Map<String, Integer> assignmentCounts = new Map<String, Integer>();
        for (String psName : psNames) {
            assignmentCounts.put(psName, 0);
        }
        for (PermissionSetAssignment psa : assignments) {
            String psName = psa.PermissionSet.Name;
            if (assignmentCounts.containsKey(psName)) {
                assignmentCounts.put(psName, assignmentCounts.get(psName) + 1);
            }
        }

        List<String> unassigned = new List<String>();
        for (String psName : psNames) {
            if (assignmentCounts.get(psName) == 0) {
                unassigned.add(psName);
            }
        }

        if (!unassigned.isEmpty()) {
            return new ChecklistResult(
                CHECK_NAME, CHECK_TYPE,
                ChecklistResult.Status.FAIL,
                String.join(psNames, ', ') + ' — all assigned',
                'Unassigned: ' + String.join(unassigned, ', '),
                'One or more permission sets have zero assignments: '
                    + String.join(unassigned, ', ')
            );
        }

        return new ChecklistResult(
            CHECK_NAME, CHECK_TYPE,
            ChecklistResult.Status.PASS,
            String.join(psNames, ', ') + ' — all assigned',
            assignments.size() + ' assignment(s) found across ' + psNames.size() + ' permission set(s)',
            'All ' + psNames.size() + ' permission set(s) verified as assigned in org'
        );
    }

    private static List<String> extractPermissionSetNames(List<ManifestComponent> components) {
        List<String> names = new List<String>();
        for (ManifestComponent comp : components) {
            if ('PermissionSet'.equalsIgnoreCase(comp.componentType)) {
                names.add(comp.componentName);
            }
        }
        return names;
    }
}
