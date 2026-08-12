/**
 * Immutable value class representing a single component entry from a deployment manifest.
 * Constructed by DeploymentManifestParser; consumed by MetadataIntegrityService.
 */
public class ManifestComponent {

    public String componentName { get; private set; }
    public String componentType { get; private set; }

    public ManifestComponent(String componentName, String componentType) {
        if (String.isBlank(componentName)) {
            throw new IllegalArgumentException('ManifestComponent: componentName cannot be blank');
        }
        if (String.isBlank(componentType)) {
            throw new IllegalArgumentException('ManifestComponent: componentType cannot be blank');
        }
        this.componentName = componentName;
        this.componentType = componentType;
    }

    private class IllegalArgumentException extends Exception {}
}
