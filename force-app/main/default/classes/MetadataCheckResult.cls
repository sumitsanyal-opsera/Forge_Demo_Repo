/**
 * Immutable value class holding the verification outcome for one metadata component.
 * Produced by MetadataIntegrityService and aggregated into MetadataIntegrityResult.
 */
public class MetadataCheckResult {

    public enum Status { PASS, FAIL, WARNING }

    public Status status        { get; private set; }
    public String componentName { get; private set; }
    public String componentType { get; private set; }
    public String expectedState { get; private set; }
    public String actualState   { get; private set; }
    public String detail        { get; private set; }

    public MetadataCheckResult(
        Status status,
        String componentName,
        String componentType,
        String expectedState,
        String actualState,
        String detail
    ) {
        this.status        = status;
        this.componentName = componentName;
        this.componentType = componentType;
        this.expectedState = expectedState;
        this.actualState   = actualState;
        this.detail        = detail;
    }
}
