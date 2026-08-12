public class ChecklistContext {

    public Id executionId;
    public List<ManifestComponent> manifestComponents;
    public Map<String, SmokeTestChecklist__mdt> checklistConfig;

    public interface IHttpCallout {
        HttpResponse send(HttpRequest req);
    }

    @TestVisible
    public IHttpCallout httpCallout;

    public ChecklistContext(
        Id executionId,
        List<ManifestComponent> manifestComponents,
        Map<String, SmokeTestChecklist__mdt> checklistConfig,
        IHttpCallout httpCallout
    ) {
        this.executionId        = executionId;
        this.manifestComponents = manifestComponents != null
            ? manifestComponents : new List<ManifestComponent>();
        this.checklistConfig    = checklistConfig != null
            ? checklistConfig : new Map<String, SmokeTestChecklist__mdt>();
        this.httpCallout        = httpCallout;
    }
}
