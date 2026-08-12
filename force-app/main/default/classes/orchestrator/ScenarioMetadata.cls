global with sharing class ScenarioMetadata {

    global final String  scenarioName;
    global final String  description;
    global final Boolean isCritical;
    global final String  cloudType;
    global final Integer executionOrder;

    global ScenarioMetadata(
        String  scenarioName,
        String  description,
        Boolean isCritical,
        String  cloudType,
        Integer executionOrder
    ) {
        if (String.isBlank(scenarioName)) {
            throw new IllegalArgumentException('scenarioName must not be blank');
        }
        this.scenarioName   = scenarioName;
        this.description    = description;
        this.isCritical     = (isCritical != null) ? isCritical : false;
        this.cloudType      = cloudType;
        this.executionOrder = executionOrder;
    }
}
