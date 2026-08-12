@isTest
private class ScenarioTemplateServiceTest {

    // =========================================================================
    // Template retrieval tests
    // =========================================================================

    @isTest
    static void salesCloudTemplates_returnsFourScenarios() {
        List<ScenarioTemplateService.ScenarioTemplate> templates =
            ScenarioTemplateService.getSalesCloudTemplates();

        System.assertEquals(4, templates.size(), 'Sales Cloud should have 4 scenarios');
    }

    @isTest
    static void salesCloudTemplates_containsRequiredScenarios() {
        List<ScenarioTemplateService.ScenarioTemplate> templates =
            ScenarioTemplateService.getSalesCloudTemplates();

        Set<String> classNames = new Set<String>();
        for (ScenarioTemplateService.ScenarioTemplate t : templates) {
            classNames.add(t.apexClassName);
        }

        System.assert(classNames.contains('AccountCrudScenario'),    'Missing AccountCrudScenario');
        System.assert(classNames.contains('ContactCrudScenario'),    'Missing ContactCrudScenario');
        System.assert(classNames.contains('OpportunityCrudScenario'),'Missing OpportunityCrudScenario');
        System.assert(classNames.contains('LeadConversionScenario'), 'Missing LeadConversionScenario');
    }

    @isTest
    static void salesCloudTemplates_allHaveRequiredFields() {
        for (ScenarioTemplateService.ScenarioTemplate t :
                ScenarioTemplateService.getSalesCloudTemplates()) {
            System.assertNotEquals(null, t.scenarioName,   'scenarioName must be set');
            System.assertNotEquals(null, t.apexClassName,  'apexClassName must be set');
            System.assertNotEquals(null, t.executionOrder, 'executionOrder must be set');
            System.assertNotEquals(null, t.timeout,        'timeout must be set');
            System.assertNotEquals(null, t.cpuBudget,      'cpuBudget must be set');
            System.assertNotEquals(null, t.soqlBudget,     'soqlBudget must be set');
            System.assertNotEquals(null, t.dmlBudget,      'dmlBudget must be set');
            System.assertEquals('Sales', t.cloudType,     'cloudType must be Sales');
            System.assertNotEquals(null, t.description,    'description must be set');
        }
    }

    @isTest
    static void serviceCloudTemplates_returnsThreeScenarios() {
        List<ScenarioTemplateService.ScenarioTemplate> templates =
            ScenarioTemplateService.getServiceCloudTemplates();

        System.assertEquals(3, templates.size(), 'Service Cloud should have 3 scenarios');
    }

    @isTest
    static void serviceCloudTemplates_containsRequiredScenarios() {
        List<ScenarioTemplateService.ScenarioTemplate> templates =
            ScenarioTemplateService.getServiceCloudTemplates();

        Set<String> classNames = new Set<String>();
        for (ScenarioTemplateService.ScenarioTemplate t : templates) {
            classNames.add(t.apexClassName);
        }

        System.assert(classNames.contains('CaseCreationScenario'),     'Missing CaseCreationScenario');
        System.assert(classNames.contains('FlowExecutionScenario'),    'Missing FlowExecutionScenario');
        System.assert(classNames.contains('AutomationTriggerScenario'),'Missing AutomationTriggerScenario');
    }

    @isTest
    static void experienceCloudTemplates_returnsTwoScenarios() {
        List<ScenarioTemplateService.ScenarioTemplate> templates =
            ScenarioTemplateService.getExperienceCloudTemplates();

        System.assertEquals(2, templates.size(), 'Experience Cloud should have 2 scenarios');
    }

    @isTest
    static void experienceCloudTemplates_containsRequiredScenarios() {
        List<ScenarioTemplateService.ScenarioTemplate> templates =
            ScenarioTemplateService.getExperienceCloudTemplates();

        Set<String> classNames = new Set<String>();
        for (ScenarioTemplateService.ScenarioTemplate t : templates) {
            classNames.add(t.apexClassName);
        }

        System.assert(classNames.contains('IntegrationConnectivityScenario'),
            'Missing IntegrationConnectivityScenario');
        System.assert(classNames.contains('ReportQueryScenario'),
            'Missing ReportQueryScenario');
    }

    // =========================================================================
    // validateApexClasses tests
    // =========================================================================

    @isTest
    static void validateApexClasses_existingClassReturnsTrue() {
        Map<String, Boolean> result = ScenarioTemplateService.validateApexClasses(
            new List<String>{ 'AccountCrudScenario' }
        );

        System.assertEquals(1, result.size());
        System.assertEquals(true, result.get('AccountCrudScenario'),
            'AccountCrudScenario should be found via Type.forName');
    }

    @isTest
    static void validateApexClasses_nonExistentClassReturnsFalse() {
        Map<String, Boolean> result = ScenarioTemplateService.validateApexClasses(
            new List<String>{ 'NonExistentClass_WO082_12345' }
        );

        System.assertEquals(1, result.size());
        System.assertEquals(false, result.get('NonExistentClass_WO082_12345'),
            'Non-existent class should return false');
    }

    @isTest
    static void validateApexClasses_mixedResults() {
        Map<String, Boolean> result = ScenarioTemplateService.validateApexClasses(
            new List<String>{ 'AccountCrudScenario', 'DoesNotExistClass_WO082' }
        );

        System.assertEquals(2, result.size());
        System.assertEquals(true,  result.get('AccountCrudScenario'));
        System.assertEquals(false, result.get('DoesNotExistClass_WO082'));
    }

    @isTest
    static void validateApexClasses_nullInputReturnsEmptyMap() {
        Map<String, Boolean> result = ScenarioTemplateService.validateApexClasses(null);
        System.assertNotEquals(null, result);
        System.assertEquals(0, result.size());
    }

    // =========================================================================
    // bulkDeployTemplates tests
    // =========================================================================

    @isTest
    static void bulkDeployTemplates_nullInput_returnsFailure() {
        ScenarioTemplateService.DeployTemplatesResult result =
            ScenarioTemplateService.bulkDeployTemplates(null);

        System.assertEquals(false, result.success);
        System.assertNotEquals(null, result.errorMessage);
    }

    @isTest
    static void bulkDeployTemplates_emptyInput_returnsFailure() {
        ScenarioTemplateService.DeployTemplatesResult result =
            ScenarioTemplateService.bulkDeployTemplates(new List<Map<String, Object>>());

        System.assertEquals(false, result.success);
    }

    @isTest
    static void bulkDeployTemplates_newScenario_deploysSuccessfully() {
        MetadataDeployService.bypassDeployment = true;

        List<Map<String, Object>> scenarios = new List<Map<String, Object>>{
            buildScenarioMap('WO082_Test_Deploy_NEW', 'WO082 Test Deploy',
                'AccountCrudScenario', 'Sales', 10, 30, 2000, 25, 10, true)
        };

        Test.startTest();
        ScenarioTemplateService.DeployTemplatesResult result =
            ScenarioTemplateService.bulkDeployTemplates(scenarios);
        Test.stopTest();

        System.assertEquals(true, result.success,
            'Deployment should succeed when bypassDeployment=true');
        System.assertEquals(1, result.deployedCount, 'Should deploy 1 scenario');
        System.assertEquals(0, result.skippedNames.size(), 'No scenarios should be skipped');
    }

    @isTest
    static void bulkDeployTemplates_existingScenario_skips() {
        MetadataDeployService.bypassDeployment = true;

        // Account_CRUD already exists in CMT from WO-004
        List<Map<String, Object>> scenarios = new List<Map<String, Object>>{
            buildScenarioMap('Account_CRUD', 'Account CRUD',
                'AccountCrudScenario', 'Sales', 10, 30, 2000, 25, 10, true)
        };

        Test.startTest();
        ScenarioTemplateService.DeployTemplatesResult result =
            ScenarioTemplateService.bulkDeployTemplates(scenarios);
        Test.stopTest();

        System.assertEquals(true, result.success, 'Should succeed even if all skipped');
        System.assertEquals(0, result.deployedCount, 'No new scenarios should be deployed');
        System.assertEquals(1, result.skippedNames.size(), 'Account_CRUD should be skipped');
        System.assertEquals('Account_CRUD', result.skippedNames[0]);
    }

    @isTest
    static void bulkDeployTemplates_missingClass_addsWarning() {
        MetadataDeployService.bypassDeployment = true;

        List<Map<String, Object>> scenarios = new List<Map<String, Object>>{
            buildScenarioMap('WO082_Missing_Class', 'Missing Class Test',
                'NonExistentApexClass_WO082', 'Experience', 80, 45, 3000, 20, 5, false)
        };

        Test.startTest();
        ScenarioTemplateService.DeployTemplatesResult result =
            ScenarioTemplateService.bulkDeployTemplates(scenarios);
        Test.stopTest();

        System.assertEquals(1, result.warningClassNames.size(),
            'Should add warning for non-existent class');
        System.assertEquals('NonExistentApexClass_WO082', result.warningClassNames[0]);
        // Still deploys (class warning does not block deployment)
        System.assertEquals(1, result.deployedCount, 'Should still deploy despite class warning');
    }

    @isTest
    static void bulkDeployTemplates_mixedNewAndExisting_deploysOnlyNew() {
        MetadataDeployService.bypassDeployment = true;

        List<Map<String, Object>> scenarios = new List<Map<String, Object>>{
            buildScenarioMap('Account_CRUD', 'Account CRUD',
                'AccountCrudScenario', 'Sales', 10, 30, 2000, 25, 10, true),
            buildScenarioMap('WO082_Brand_New_Scenario', 'Brand New',
                'AccountCrudScenario', 'Sales', 15, 30, 2000, 25, 10, false)
        };

        Test.startTest();
        ScenarioTemplateService.DeployTemplatesResult result =
            ScenarioTemplateService.bulkDeployTemplates(scenarios);
        Test.stopTest();

        System.assertEquals(1, result.deployedCount, 'Should deploy 1 new scenario');
        System.assertEquals(1, result.skippedNames.size(), 'Should skip 1 existing scenario');
    }

    @isTest
    static void bulkDeployTemplates_containerHasCorrectRecord() {
        MetadataDeployService.bypassDeployment = true;

        List<Map<String, Object>> scenarios = new List<Map<String, Object>>{
            buildScenarioMap('WO082_Container_Test', 'Container Test',
                'AccountCrudScenario', 'Sales', 10, 30, 2000, 25, 10, true)
        };

        Test.startTest();
        ScenarioTemplateService.bulkDeployTemplates(scenarios);
        Test.stopTest();

        System.assertNotEquals(null, MetadataDeployService.lastContainer,
            'Container should be captured for test assertion');
    }

    // =========================================================================
    // Helper
    // =========================================================================

    private static Map<String, Object> buildScenarioMap(
        String scenarioName, String label, String apexClassName,
        String cloudType, Integer executionOrder, Integer timeout,
        Integer cpuBudget, Integer soqlBudget, Integer dmlBudget, Boolean critical
    ) {
        return new Map<String, Object>{
            'scenarioName'   => scenarioName,
            'label'          => label,
            'apexClassName'  => apexClassName,
            'cloudType'      => cloudType,
            'executionOrder' => executionOrder,
            'timeout'        => timeout,
            'cpuBudget'      => cpuBudget,
            'soqlBudget'     => soqlBudget,
            'dmlBudget'      => dmlBudget,
            'critical'       => critical,
            'description'    => 'Test description for ' + scenarioName
        };
    }
}
