/**
 * Parses the DeploymentManifest__c JSON field from SmokeTestExecution__c into
 * a typed List of ManifestComponent objects.
 *
 * Expected manifest format:
 *   [{"name":"AccountService","type":"ApexClass"},{"name":"Account_Flow","type":"Flow"},...]
 *
 * Validates:
 *   - Non-blank JSON input (blank → empty list)
 *   - Top-level array (not object)
 *   - Each entry is a JSON object with non-blank "name" and "type" keys
 *   - Duplicates (same name+type) are silently deduplicated
 *
 * Throws ManifestParseException for malformed JSON or schema violations.
 */
public class DeploymentManifestParser {

    /**
     * Parses a manifest JSON string into a deduplicated List of ManifestComponent.
     *
     * Returns an empty list for blank/null input.
     * Throws ManifestParseException for malformed JSON or invalid schema.
     */
    public static List<ManifestComponent> parse(String manifestJson) {
        if (String.isBlank(manifestJson)) {
            return new List<ManifestComponent>();
        }

        Object parsed;
        try {
            parsed = JSON.deserializeUntyped(manifestJson);
        } catch (JSONException ex) {
            throw new ManifestParseException(
                'DeploymentManifest__c contains malformed JSON: ' + ex.getMessage()
            );
        }

        if (!(parsed instanceof List<Object>)) {
            throw new ManifestParseException(
                'DeploymentManifest__c must be a JSON array (got ' +
                parsed.getClass().getName() + ')'
            );
        }

        List<Object> items = (List<Object>) parsed;
        List<ManifestComponent> components = new List<ManifestComponent>();
        Set<String> seen = new Set<String>();

        Integer idx = 0;
        for (Object item : items) {
            if (!(item instanceof Map<String, Object>)) {
                throw new ManifestParseException(
                    'Manifest entry at index ' + idx + ' must be a JSON object'
                );
            }
            Map<String, Object> entry = (Map<String, Object>) item;

            Object nameObj = entry.get('name');
            Object typeObj = entry.get('type');

            String name = nameObj != null ? String.valueOf(nameObj).trim() : '';
            String type = typeObj != null ? String.valueOf(typeObj).trim() : '';

            if (String.isBlank(name)) {
                throw new ManifestParseException(
                    'Manifest entry at index ' + idx + ' has blank or missing "name" field'
                );
            }
            if (String.isBlank(type)) {
                throw new ManifestParseException(
                    'Manifest entry at index ' + idx + ' has blank or missing "type" field'
                );
            }

            // Deduplicate: same name+type combination is skipped silently
            String dedupKey = name + '|' + type;
            if (!seen.contains(dedupKey)) {
                seen.add(dedupKey);
                components.add(new ManifestComponent(name, type));
            }

            idx++;
        }

        return components;
    }

    public class ManifestParseException extends Exception {}
}
