# Forge Implementation Log

| Field | Value |
|-------|-------|
| Project | 3bc0663f-83a5-4205-9ef9-a02c251a4d0b |
| Branch | forge/salesforce-post-deployment-smo-8c15a830-run2-46wo |
| Started | 2026-08-12T09:13:48Z |

---

## WO-001: User Story: WO-001 - Initialize Salesforce DX Project Scaffolding Structure
- **Status:** completed
- **Commit:** `856b2b0`
- **Files:** 27 (+506/-1)
- **Duration:** 311ss
- **Approach:** Created all Salesforce DX project scaffolding from scratch following the standard SFDX project template. Chose namespace 'stcenter' (Smoke Test Center) for the unlocked package, documented with fallback options. Set sourceApiVersion 60.0 throughout. Created all required force-app/main/default/ subdirectories with .gitkeep files for git tracking. Configured LWC Jest testing with @salesforce/sfdx-lwc-jest and common module name mock stubs. Added Prettier configuration with Apex and XML plugin support.

## WO-002: User Story: WO-002 - Create SmokeTestExecution and SmokeTestResult Custom Objects
- **Status:** completed
- **Commit:** `38071de`
- **Files:** 31 (+715/-0)
- **Duration:** 413ss
- **Approach:** Created two Custom Object metadata definitions in Salesforce DX source format. SmokeTestExecution__c is the master record (sharingModel Private, AutoNumber EXEC-{0000}) with 15 custom fields covering the full execution lifecycle. SmokeTestResult__c is the detail record (sharingModel ControlledByParent, AutoNumber RES-{00000}) with 13 custom fields including a Master-Detail relationship to SmokeTestExecution__c. All picklists are restricted. DeploymentId__c is marked as externalId for indexed lookups. Both object XMLs include custom index definitions on high-cardinality query fields. ErrorMessage__c and ErrorStackTrace__c descriptions explicitly require PII masking. Both objects have inline XML comments noting Internal data classification and 90-day retention.

## WO-003: User Story: WO-003 - Create SecurityScore and AuditLog Objects with Immutability
- **Status:** completed
- **Commit:** `1409c04`
- **Files:** 28 (+625/-0)
- **Duration:** 402ss
- **Approach:** Created two Confidential-tier Custom Objects with full field definitions, then implemented the AuditLog immutability enforcement layer using a trigger-handler pattern. SmokeTestSecurityScore__c uses a Lookup (not MasterDetail) to SmokeTestExecution__c to avoid cascading deletes across data classification tiers. ScoreDelta__c is a Formula field using IF(OR(ISBLANK)) to handle null scores gracefully. SmokeTestAuditLog__c has custom indexes on Timestamp__c, Action__c, and Actor__c for the three primary query patterns. The trigger delegates to a handler class with static methods, enabling testability and single-responsibility. The test class uses Database.update(list, false) with allOrNone=false for the bulk test to collect per-record errors rather than catching a single exception, verifying all 200 records individually receive the error.

## WO-004: User Story: WO-004 - Define SmokeTestConfig and SmokeTestScenario Custom Metadata Types
- **Status:** completed
- **Commit:** `80b0802`
- **Files:** 40 (+962/-0)
- **Duration:** 436ss
- **Approach:** Created two Custom Metadata Type definitions in Salesforce DX source format under objects/ (same structure as Custom Objects but with fieldManageability: DeveloperControlled on all fields, and no sharingModel). Created the SmokeTestConfig__mdt Default record and all 10 SmokeTestScenario__mdt records as md-meta.xml files in the customMetadata/ directory. Override number fields on scenario records are explicitly set to xsi:null to allow null (indicating use-global-default) rather than omitting the element. All CMT fields use fieldManageability: DeveloperControlled to restrict field value changes to deployments, not Setup UI edits.

## WO-005: User Story: WO-005 - Define SmokeTestChecklist and AlertRoute Custom Metadata Types
- **Status:** completed
- **Commit:** `06147f0`
- **Files:** 28 (+683/-0)
- **Duration:** 687ss
- **Approach:** Created two Custom Metadata Type definitions in Salesforce DX source format. SmokeTestChecklist__mdt is Public visibility with 7 fields and 5 default records covering core post-deployment verification checks (Flows, Permission Sets, Page Layouts, Custom Settings, Scheduled Jobs). SmokeTestAlertRoute__mdt is Protected visibility — this prevents subscriber orgs from reading WebhookSecret__c values via the Metadata API, leveraging the stcenter namespace established in WO-001. All 8 AlertRoute fields and 5 default records are created with placeholder webhook values for the Slack route. All CMT fields use fieldManageability: DeveloperControlled consistent with WO-004 patterns. A verification script uses getAll() to assert record counts and field values for both types.

## WO-006: User Story: WO-006 - Define Platform Events for Deployment and Test Lifecycle
- **Status:** completed
- **Commit:** `ae3d62d`
- **Files:** 22 (+257/-0)
- **Duration:** 275ss
- **Approach:** Created three Platform Event definitions in Salesforce DX source format under objects/ using the standard CustomObject schema with eventType HighVolume and publishBehavior PublishImmediately. Platform Events use only Text, Number, Checkbox, and DateTime field types (no Picklist or LookupRelationship support). All field descriptions document the expected publisher and subscriber for each event, satisfying AC-6. A verification script uses EventBus.publish() with SaveResult assertions for all three event types.

## WO-012: User Story: WO-012 - Build PII Masking ErrorSanitizer Utility Class
- **Status:** completed
- **Commit:** `4722e5f`
- **Files:** 6 (+593/-0)
- **Duration:** 526ss
- **Approach:** Implemented ErrorSanitizer as a stateless static utility class with three compiled Pattern constants (EMAIL_PATTERN, PHONE_PATTERN, SSN_PATTERN) stored as private static finals for one-time class-load compilation. A PatternReplacement inner class holds each pattern, its replacement token, and a name — enabling future extension without modifying the sanitize loop. Patterns are applied in SSN-first order to prevent partial-match issues. A 50ms CPU budget guard in sanitize() returns a partially-sanitized string with [SANITIZATION_TIMEOUT] appended rather than blocking the calling transaction. sanitizeStackTrace() splits on newlines and processes per line to preserve Apex class/method/line references. SanitizationTestData provides static fixture constants for reuse across epics. ErrorSanitizerTest contains 23 test methods covering all patterns, false-positive prevention, stack trace preservation, and performance.

## WO-014: User Story: WO-014 - Build Standardized API Response Builder Class
- **Status:** completed
- **Commit:** `8dd0f9d`
- **Files:** 6 (+728/-0)
- **Duration:** 481ss
- **Approach:** Implemented SmokeTestApiResponse as a fluent builder with a private constructor and 8 static factory methods. A private Boolean isError field routes builder calls to either the ApiErrorBody error path or the flexible withBody(Object) success path. ApiErrorBody auto-generates a 32-character referenceId using Crypto.generateAesKey(128) and an ISO-8601 UTC timestamp at construction time. Five typed success body inner classes (RunAcknowledgment, ExecutionStatus, ExecutionResults, ScenarioResult, MetadataIntegrity) cover the three API contract response shapes. The send() method validates RestContext.response availability and throws a custom IllegalStateException if null. sanitizeErrorMessage() chains ErrorSanitizer.sanitize() for PII removal followed by regex stripping of Apex class/trigger/line-number patterns to satisfy OWASP A10. ApiResponseTestHelper provides reusable test utilities for downstream REST endpoint tests. SmokeTestApiResponseTest contains 16 tests covering all status codes, success shapes, headers, security, and edge cases.

## WO-015: User Story: WO-015 - Define ISmokeTestScenario Interface and Base Contracts
- **Status:** completed
- **Commit:** `023913f`
- **Files:** 16 (+583/-0)
- **Duration:** 614ss
- **Approach:** Implemented the ISmokeTestScenario Strategy pattern interface and all supporting value objects in force-app/main/default/classes/orchestrator/. A shared IllegalArgumentException class (extends Exception) provides a single named exception type for constructor validation across all value classes. All value classes use final fields with constructor initialization for immutability. GovernorBudgetConfig uses constructor chaining — the default no-arg constructor delegates to the full constructor with architecture defaults (5000ms CPU, 50 SOQL, 50 DML, 30s timeout). SmokeTestContext initializes parameters to an empty Map when null is passed. ScenarioResult is constructed exclusively through success() and failure() static factory methods (private constructor). MockSmokeTestScenario is a reusable @isTest fixture in force-app/test/default/classes/orchestrator/ with three constructors covering pass, fail, and timeout configurations. ISmokeTestScenarioTest provides 20 test methods exercising all value class construction, all validation failure paths, and all three MockSmokeTestScenario execution paths.

## WO-007: User Story: WO-007 - Create Three-Tier RBAC Permission Sets with FLS
- **Status:** completed
- **Commit:** `c5201e7`
- **Files:** 5 (+1248/-0)
- **Duration:** 548ss
- **Approach:** Created three permission set XML files implementing the deny-by-default three-tier RBAC model. Each permission set has explicit objectPermissions and fieldPermissions for every relevant object and field, using the standard SFDX PermissionSet metadata format. SmokeTest_Dashboard_Viewer grants Read-only on both Internal-tier objects (Execution, Result) with all 15+13 custom fields readable but not editable, Subscribe (allowRead=true) on SmokeTestProgress__e and SmokeTestComplete__e, and SmokeTestCenter app visibility. SmokeTest_Admin grants full CRUD on Execution/Result, Read/Create on SecurityScore (all 10 fields including RawResponse__c, with ScoreDelta__c formula field read-only), Read-only on AuditLog (all 9 fields readable/not-editable to enforce immutability at permission set level in addition to the trigger layer), Publish+Subscribe on all 3 Platform Events, and SmokeTestCenter app visibility. SmokeTest_API_User grants Read/Create (no Edit/Delete) on Execution/Result with all fields editable for create operations, Publish+Subscribe on DeploymentComplete__e and SmokeTestComplete__e, and no app visibility. All three permission sets include placeholder XML comments for future classAccesses (EPIC-02 REST resources) and deferred tabSettings (no tab definitions exist yet). SmokeTestPermissionSetTest.cls provides 18 integration test methods using @TestSetup to create three Minimum Access profile users, assigns permission sets via PermissionSetAssignment, and validates the access matrix via System.runAs() + Schema.describe() calls and WITH SECURITY_ENFORCED negative tests.

## WO-010: User Story: WO-010 - Implement Immutable Audit Log Writer Service
- **Status:** completed
- **Commit:** `6b83acf`
- **Files:** 20 (+975/-0)
- **Duration:** 755ss
- **Approach:** Extended the existing SmokeTestAuditLog__c custom object (from WO-003) with 7 new fields needed by the audit service: ActorUserId__c (Text 18, stores user ID as string for automated-process compatibility), ActionType__c (Text 50, allow-list enforced in builder), OldValue__c / NewValue__c (LongTextArea 32000 each, truncated at limit with [TRUNCATED] suffix), ChangeReason__c (Text 255, required by builder when ActionType is CONFIGURATION_CHANGE), Outcome__c (Text 50), and Execution__c (Lookup to SmokeTestExecution__c). IDmlHandler interface with DefaultDmlHandler implementation enables dependency injection for unit testing without database access. AuditLogEntry uses the Builder pattern with compile-time validation: blank/invalid actionType throws AuditLogException, missing changeReason for CONFIGURATION_CHANGE throws. AuditLogWriter runs without sharing so any transaction can write audit records; it sets the timestamp server-side, defaults null actorUserId to the running user, truncates LongTextArea fields, and falls back to an async Queueable when fewer than 2 DML statements remain. SmokeTest_Admin permission set was extended with read-only access to all 7 new fields (editable=false per immutability policy).

## WO-016: User Story: WO-016 - Build SmokeTestDataFactory with SObject Factory Methods
- **Status:** completed
- **Commit:** `6cc565e`
- **Files:** 4 (+790/-0)
- **Duration:** 381ss
- **Approach:** Created SmokeTestDataFactory.cls in the new force-app/main/default/classes/scenarios/ subdirectory. The class is a non-@isTest public with sharing utility that can be called from both production smoke test scenarios and @isTest unit tests. A private static integer counter (zeroPad-formatted to 3 digits) provides unique names across consecutive calls in the same transaction. The mergeDefaults() private helper builds a result map from defaults and then putAll(overrides), so caller-provided values always win. applyFields() iterates the merged map calling SObject.put() per field, catching SObjectException and re-throwing as SmokeTestDataFactoryException with the invalid field name and SObject type identified. createContact() and createOpportunity() both detect a missing AccountId in the override map and auto-call createAccount() to satisfy the parent requirement. Bulk variants (createAccounts, createContacts, etc.) construct individual records in a loop (each with a unique name from the counter) and bulk-insert in one DML statement. Contact/Opportunity bulk methods create one shared parent Account before the loop. DmlException is never caught — it propagates to the caller per the work order requirement. SmokeTestDataFactoryTest.cls lives in force-app/test/default/classes/scenarios/ and provides 30 test methods covering all acceptance criteria.

## WO-020: User Story: WO-020 - Build GovernorLimitBudget Tracker for Per-Scenario Monitoring
- **Status:** completed
- **Commit:** `148e5c0`
- **Files:** 8 (+483/-0)
- **Duration:** 392ss
- **Approach:** Created three new classes in force-app/main/default/classes/orchestrator/ following the existing global-scope pattern established by GovernorBudgetConfig and IllegalArgumentException. IllegalStateException is a standalone global exception class (same pattern as IllegalArgumentException). GovernorConsumptionReport is an immutable value object with 9 final fields (soqlUsed, dmlUsed, cpuUsed, soqlBudget, dmlBudget, cpuBudget, soqlExceeded, dmlExceeded, cpuExceeded); the constructor calculates exceeded flags using strict > comparison (at exact boundary, used == budget is not exceeded). GovernorLimitBudget stores three private baseline integers and a baselineCaptured flag; captureBaseline() reads the three Limits values with no other side effects; isWithinBudget() computes deltas and compares with <= (inclusive — exact boundary is within budget); getConsumptionReport() constructs a GovernorConsumptionReport from the deltas and the config's budget fields; both check methods call a private assertBaselineCaptured() helper that throws IllegalStateException with the caller method name included for diagnostics. The 18-method test class verifies controlled operations (3 SOQL + 2 DML) produce exact expected consumption counts, boundary arithmetic, repeated baseline overwrite, and IllegalStateException guards on both public methods.

## WO-026: User Story: WO-026 - Implement SmokeTestApiValidator Input Validation Service
- **Status:** completed
- **Commit:** `bc70754`
- **Files:** 6 (+857/-0)
- **Duration:** 721ss
- **Approach:** Implemented a stateless, with-sharing Apex validation service (SmokeTestApiValidator) with three public static entry points: validateRunRequest (POST /v1/run), validateExecutionId (path parameter), and validateHealthRequest (GET /v1/health). All Pattern.compile() calls are at class-load time in private static final fields. validateRunRequest enforces: blank/size guard (1 MB), JSON.deserializeUntyped + type check, unknown-field allow-list loop, required targetOrg regex validation, and optional field validators for scenarioFilter, rollbackPolicyOverride, timeout, securityScoreThreshold, and webhookCallbackUrl. SSRF prevention uses a static SOQL query (no string interpolation) against SmokeTestAlertRoute__mdt.CallbackUrlPattern__c and string-based host extraction via @TestVisible extractHost(). Error messages contain no stack traces, class names, or org IDs per OWASP A10. A new CallbackUrlPattern__c Text(255) field was added to SmokeTestAlertRoute__mdt and seeded in the DevOps_PipelineFailures CMT record (hooks.slack.com) so webhook allow-list tests work without SeeAllData.

## WO-008: User Story: WO-008 - Configure Connected App for CI/CD JWT Authentication
- **Status:** completed
- **Commit:** `745c101`
- **Files:** 2 (+690/-0)
- **Duration:** 291ss
- **Approach:** Created the Connected App metadata XML in standard Salesforce DX source format at force-app/main/default/connectedApps/SmokeTestConnectedApp.connectedApp-meta.xml with label 'Smoke Test CI/CD Integration', OAuth 2.0 JWT Bearer flow configuration (certificate placeholder 'SmokeTestCICDCert'), scopes limited to Api+RefreshToken, oauthPolicy with permittedUsers=AdminApprovedUsersArePreAuthorized and ipRelaxation=EnforceIpRestrictions, and pre-authorization for both SmokeTest_API_User and SmokeTest_Admin permission sets. Inline XML comments document the auto-generated consumer key, the per-org certificate upload requirement, and IP restriction environment-specific configuration. Created docs/connected-app-setup.md with 10 sections covering all required topics: prerequisites, OpenSSL certificate generation, Salesforce certificate upload (Setup UI and Metadata API options), sf CLI deployment, consumer key retrieval, permission set pre-authorization, IP restriction configuration, CI/CD platform configuration for all four platforms with pipeline snippet examples, manual JWT Bearer flow testing with curl, and a troubleshooting section covering all common error scenarios. No private keys, consumer secrets, or real credentials are committed.

## WO-009: User Story: WO-009 - Create Integration User Profile and Service Account
- **Status:** completed
- **Commit:** `a588597`
- **Files:** 7 (+1088/-0)
- **Duration:** 595ss
- **Approach:** Created SmokeTest_Integration_Profile as a custom profile based on Minimum Access with userPermissions ApiEnabled=true and ViewSetup=true, and read-only objectPermissions (allowRead=true, allowCreate/Edit/Delete=false) for Account, Contact, Opportunity, Case, and Lead. Created SmokeTestPostInstallHandler implementing the InstallHandler interface; it builds the username from UserInfo.getOrganizationName() with RFC-safe character sanitization and sandbox suffix detection, checks for existing users (idempotent), creates the user with the integration profile, and assigns SmokeTest_API_User permission set — catching DUPLICATE_USERNAME and LICENSE_LIMIT_EXCEEDED DmlException messages gracefully and logging errors via System.debug without blocking installation. Created SmokeTestIntegrationUserTest with 16 test methods covering DML restrictions on all five standard objects, SOQL read access, profile permission verification via PermissionSet proxy query, mocked Tooling API SecurityHealthCheck HTTP callout, and post-install handler tests using Test.testInstall() for fresh install, upgrade, and idempotent double-invocation paths. Created docs/integration-user-setup.md with license options, automated and manual user creation steps, permission set assignment, Tooling API curl verification, and troubleshooting. Created scripts/verify-integration-user.apex for end-to-end scratch org verification including profile permissions and a live Tooling API SecurityHealthCheck callout.

## WO-017: User Story: WO-017 - Implement Record CRUD Smoke Test Scenario Classes
- **Status:** completed
- **Commit:** `2197575`
- **Files:** 20 (+1201/-0)
- **Duration:** 481ss
- **Approach:** Implemented five ISmokeTestScenario classes in force-app/main/default/classes/scenarios/ following a consistent structural pattern: @TestVisible injection flags (injectException + triggerAssertFail) for test coverage of all 4 catch branches without DI framework; WITH SECURITY_ENFORCED on all SOQL queries; errorDetail capped at 1000 chars via private cap() helper; DmlException/QueryException/System.AssertException/Exception caught separately with distinct errorType codes. AccountCrudScenario: 4-step CRUD (create/read/update-verify/delete-verify), scenarioName='Account_CRUD', cloudType='Sales'. ContactCrudScenario: create with auto-parent-Account via factory, verify AccountId, update Email, delete Contact, scenarioName='Contact_CRUD', cloudType='Sales'. OpportunityCrudScenario: create, verify Amount=10000 at each of three stage progression steps (Prospecting→Qualification→Closed Won), delete, scenarioName='Opportunity_Pipeline' (matches CMT record). CaseCreationScenario: create, verify Status='New'/Origin='Web'/OwnerId not null, update to Status='Working', scenarioName='Case_Creation', cloudType='Service'. LeadConversionScenario: dynamically queries converted LeadStatus (avoids hardcoded 'Closed - Converted'), converts via Database.convertLead(), verifies all 3 result record Ids are non-null and queryable; returns CONFIGURATION_ERROR if no converted status exists. All 5 have isCritical=true and return default GovernorBudgetConfig (5000ms/50 SOQL/50 DML/30s). Five test classes in force-app/test/default/classes/scenarios/ each with 8+ methods: success path via Test.startTest/stopTest, DmlException/UnexpectedException/AssertionFailed via @TestVisible flags, 1500-char truncation test, getMetadata() assertions, getGovernorBudget() assertions, ISmokeTestScenario polymorphism.

## WO-018: User Story: WO-018 - Implement Flow and Automation Trigger Scenario Classes
- **Status:** completed
- **Commit:** `39bea40`
- **Files:** 8 (+796/-0)
- **Duration:** 1112ss
- **Approach:** Implemented two ISmokeTestScenario classes following the exact structural pattern established in WO-017. FlowExecutionScenario: queries FlowDefinitionView (api v43+) for the flow named by context.parameters['flowApiName']; checks ActiveVersionId != null for active status; invokes Flow.Interview.createInterview() for AutoLaunchedFlow processType only (screen flows get activation-only check); errorTypes FLOW_NOT_FOUND / FLOW_INACTIVE / FLOW_EXECUTION_ERROR / CONFIGURATION_ERROR. FlowCheckResult public inner class allows test injection of mock FlowDefinitionView results since FlowDefinitionView is a read-only view SObject that cannot be inserted in @isTest contexts. AutomationTriggerScenario: creates Account via SmokeTestDataFactory.createAccount(); allow-lists the triggerFieldName against Account.SObjectType.getDescribe().fields.getMap() before using it in dynamic SOQL (OWASP A03 injection prevention); re-queries with 'SELECT fieldName FROM Account WHERE Id = :accId WITH SECURITY_ENFORCED'; compares String.valueOf(actualFieldValue) to triggerFieldExpectedValue; AUTOMATION_NOT_FIRED error includes expected/actual values and a note that the failure may indicate deactivated automation. Both scenarios: @TestVisible injectException + triggerAssertFail flags for exception-branch coverage; errorDetail capped at 1000 chars via private cap() helper; isCritical=true, cloudType='Automation', orders 60 and 70 (matching CMT ExecutionOrder__c values of 6 and 7 from WO-004). Test classes each have 13 test methods; real SOQL path exercised in one test per class without using injection flags (testFlowNotFound_RealQuery passes a non-existent flow name; testAutomationNotFired_RealQuery uses Description field with a value that won't exist after a plain insert).

## WO-019: User Story: WO-019 - Implement Flexipage, Report, and Integration Connectivity Scenarios
- **Status:** completed
- **Commit:** `9da8076`
- **Files:** 15 (+1131/-1)
- **Duration:** 730ss
- **Approach:** Implemented three ISmokeTestScenario classes completing the default 10-scenario suite. IntegrationConnectivityScenario: performs HTTP GET to endpointUrl parameter (or expands namedCredential to callout:NC); 10 000ms timeout; ENDPOINT_ERROR on non-2xx response, CALLOUT_EXCEPTION on network failure, CONFIGURATION_ERROR when neither parameter is provided. ReportQueryScenario: reads soqlQuery from context.parameters (CMT-sourced trusted input); executes via Database.query(); QUERY_ERROR on QueryException, GOVERNOR_LIMIT_EXCEEDED on System.LimitException (runtime safety net — not unit-testable via injection since LimitException cannot be instantiated; covered by injection of QueryException instead), CONFIGURATION_ERROR when query blank; zero-row results count as pass (validates execution not data). FlexipageRenderScenario: validates DeveloperName against [a-zA-Z][a-zA-Z0-9_]* before embedding in Tooling API SOQL (injection prevention); constructs Tooling API endpoint from URL.getOrgDomainUrl() + /services/data/v60.0/tooling/query/; sets Bearer auth header; FLEXIPAGE_NOT_FOUND when totalSize=0, FLEXIPAGE_MISCONFIGURED when totalSize>0 but records array empty, TOOLING_API_ERROR on non-2xx or CalloutException, PARSE_ERROR on malformed JSON. All three use @TestVisible injectException + triggerAssertFail flags. CMT record PageLayout_Render updated: ScenarioClass__c changed from 'PageLayoutRenderScenario' to 'FlexipageRenderScenario' to match the WO-specified class name. MockHttpCallout provides reusable HttpCalloutMock with configurable status/body and a throwingCallout() factory for simulating CalloutException.

## WO-021: User Story: WO-021 - Build ScenarioTimeoutHandler for Per-Scenario Timeout Enforcement
- **Status:** completed
- **Commit:** `fc5bd72`
- **Files:** 6 (+377/-0)
- **Duration:** 493ss
- **Approach:** Implemented cooperative per-scenario timeout enforcement using Limits.getCpuTime(). ScenarioTimeoutException.cls extends Exception with a 2-arg constructor (elapsedMs, timeoutMs) that formats a descriptive message including both values via setMessage(). ScenarioTimeoutHandler.cls holds a private Integer startCpuTime and Boolean timerStarted (initialized false): startTimer() records Limits.getCpuTime() and sets timerStarted=true; getElapsedMs() asserts timerStarted (throws IllegalStateException if not) then returns injectedElapsedMs if set else Limits.getCpuTime()-startCpuTime; isTimedOut(Integer timeoutSeconds) validates timeoutSeconds>0 (throws IllegalArgumentException otherwise), asserts timer started, and returns getElapsedMs()>=(timeoutSeconds*1000); checkAndThrow(Integer timeoutSeconds) calls isTimedOut and throws ScenarioTimeoutException(getElapsedMs(), timeoutSeconds*1000) if timed out. A @TestVisible static Integer injectedElapsedMs field allows tests to reliably trigger the timeout path without requiring actual CPU burn, following the same @TestVisible injection pattern used throughout the scenario classes. Real CPU loop tests cover the basic 'elapsed is non-negative' assertion.

## WO-022: User Story: WO-022 - Implement CircuitBreakerService for Governor Limit Protection
- **Status:** completed
- **Commit:** `620e775`
- **Files:** 5 (+548/-0)
- **Duration:** 492ss
- **Approach:** Implemented CircuitBreakerService using the cooperative circuit breaker pattern. State fields: consecutiveGovernorFailures (Integer, default 0), circuitOpen (Boolean, default false), executionId (Id), threshold (Integer, default 3). recordGovernorFailure() increments consecutiveGovernorFailures; when >= threshold, sets circuitOpen=true and calls publishCircuitBreakerEvent(). recordSuccess() and recordFunctionalFailure() both reset consecutiveGovernorFailures to 0 but do NOT close an already-open circuit. isOpen()/isClosed() expose the current state. reset() closes the circuit (intended for end-of-run teardown). saveState() serializes {consecutiveGovernorFailures, circuitOpen} to JSON and writes CircuitBreakerState__c (new LongTextArea field) + CircuitBreakerTripped__c (existing checkbox) on SmokeTestExecution__c; DML exceptions are swallowed and logged so the service never crashes the orchestrator. loadState(Id) static factory re-hydrates both fields from the SmokeTestExecution__c record (falls back to checkbox if JSON is null). Threshold is loaded from SmokeTestConfig__mdt Default.CircuitBreakerThreshold__c (=3) via SOQL in the public constructor; a @TestVisible private constructor accepts an explicit threshold to avoid CMT SOQL in tests. publishCircuitBreakerEvent() publishes SmokeTestProgress__e(ExecutionId__c, ScenarioStatus__c='CIRCUIT_BREAKER_TRIPPED', CurrentPhase__c=descriptive message); EventBus.publish failures are swallowed. @TestVisible static Boolean eventPublished and String lastEventStatus flags allow tests to verify event publication without querying the event bus. CircuitBreakerState__c field (LongTextArea 1000) created as a new field on SmokeTestExecution__c to persist the consecutive count alongside the existing CircuitBreakerTripped__c checkbox.

## WO-044: User Story: WO-044 - Smoke Test Center App Shell and Navigation
- **Status:** completed
- **Commit:** `94d9576`
- **Files:** 15 (+869/-0)
- **Duration:** 1012ss
- **Approach:** Extended the existing SmokeTestCenter Lightning App (added Smoke_Test_Center tab reference rather than creating a duplicate app file, per integration rules). Created a Lightning Tab pointing to a new Flexipage (Smoke_Test_Center_Home) that hosts the smokeTestCenter LWC. The LWC shell implements: (1) @wire(checkUserPermissions) to load the running user's permission level server-side; (2) three conditional rendering blocks using if:true — loading spinner, error banner with retry, access-denied card; (3) SLDS grid layout with sidebar (slds-size_2-of-12) + main content (slds-size_10-of-12); (4) SLDS vertical-navigation sidebar with three sections (Dashboard, Configuration, History) and 8 nav items (Overview, Execution Detail, Security Health, Test Scenarios, CI/CD Integration, Alert Routing, Execution History, Audit Log); (5) NavigationMixin.Navigate called on each sidebar click dispatching standard__navItemPage events; (6) admin-only slot rendered via if:true={isAdmin} for security panels. SmokeTestDashboardController.cls queries PermissionSetAssignment with WITH SECURITY_ENFORCED (OWASP A01) and returns a Map with permissionLevel ('admin'|'viewer'|'none'), isAdmin, isViewer. handleRetry() clears error state and makes a fresh imperative checkUserPermissions() call. Jest tests use registerApexTestWireAdapter from @salesforce/sfdx-lwc-jest to drive all three permission paths plus error states and navigation dispatch.

## WO-023: User Story: WO-023 - Build ScenarioDispatcher with Strategy Pattern Routing
- **Status:** completed
- **Commit:** `0939125`
- **Files:** 6 (+921/-0)
- **Duration:** 771ss
- **Approach:** Implemented ScenarioDispatcher using the Strategy pattern. Two inner classes support the API: ScenarioConfig (mirrors SmokeTestScenario__mdt fields, implements Comparable for sort) and DispatchResult (bundles ScenarioResult with GovernorConsumptionReport). The dispatcher has two constructors: a production no-arg constructor and a @TestVisible constructor that accepts an injected List<ScenarioConfig> to bypass CMT SOQL in tests. getEnabledScenarios() queries SmokeTestScenario__mdt with WHERE IsEnabled__c=true ORDER BY ExecutionOrder__c ASC when using the production constructor, or filters and sorts the injected list. The main dispatch(ScenarioConfig, SmokeTestContext) method: (1) checks isEnabled — returns SKIPPED_DISABLED without executing; (2) validates scenarioClass via Type.forName() — CLASS_NOT_FOUND if null or blank; (3) calls newInstance() — TypeException/no-no-arg-constructor → INSTANTIATION_ERROR; (4) checks instanceof ISmokeTestScenario — INSTANTIATION_ERROR if fails; (5) builds effective GovernorBudgetConfig (CMT overrides win over scenario defaults); (6) calls tracker.captureBaseline() and timer.startTimer(); (7) calls scenario.execute() then timer.checkAndThrow() post-execution (cooperative timeout); (8) catches ScenarioTimeoutException → TIMED_OUT, DmlException → DML_EXCEPTION, QueryException → QUERY_EXCEPTION, Exception → UNEXPECTED_ERROR; (9) calls tracker.getConsumptionReport() and wraps in DispatchResult. An AC-1 compatible dispatch(String, SmokeTestContext) overload creates a default-enabled ScenarioConfig and delegates to the main method. ConfigurableMockScenario is a new @isTest global class with a no-arg constructor and @TestVisible static control flags (shouldPass, shouldThrow*, injectedError*), enabling Type.forName() resolution in test context without requiring a pre-built instance.

## WO-037: User Story: WO-037 - Implement SecurityHealthCheckService Tooling API Integration
- **Status:** completed
- **Commit:** `d520866`
- **Files:** 10 (+898/-0)
- **Duration:** 643ss
- **Approach:** Created the smoketest-security module following the interface-first pattern. ISecurityHealthCheckService defines a single captureScore() method. SecurityHealthCheckResult is the strongly-typed wrapper with a ThresholdStatus enum (PASS/FAIL/ERROR/SKIPPED), SecurityRiskCategory inner class (categoryName, score, settings), SecuritySetting inner class (settingName, value, recommendation), and static factory methods error() and skipped(). SecurityHealthCheckService implements the interface with: (1) a nested public IHttpCallout interface and DefaultHttpCallout inner class for production use, (2) a @TestVisible package-private constructor accepting IHttpCallout and IDmlHandler for unit test injection, (3) a @TestVisible injectedApiCallsRemaining static field to control pre-flight API limit checks in tests, (4) buildRequest() that constructs an HttpRequest to URL.getOrgDomainUrl() + Tooling API path with Authorization: Bearer <sessionId>, (5) parseResponse() handling HTTP 401/403/500 and 200 with exact WO error messages, (6) parseSuccessBody() using JSON.deserializeUntyped() with null-safe field access and empty-result handling, (7) writeAuditLog() via AuditLogEntry.Builder + AuditLogWriter on all outcomes including SKIPPED. MockSecurityHealthCheckResponse implements both SecurityHealthCheckService.IHttpCallout and HttpCalloutMock, providing seven factory methods: success(), partialData(), emptyResult(), malformed(), authFailure(), permissionFailure(), serverError(). SecurityHealthCheckServiceTest has 14 test methods covering all paths.

## WO-045: User Story: WO-045 - Deployment Status Banner LWC Component
- **Status:** completed
- **Commit:** `7673463`
- **Files:** 9 (+708/-0)
- **Duration:** 434ss
- **Approach:** Added getLatestExecution to SmokeTestDashboardController as @AuraEnabled(cacheable=true) querying SmokeTestExecution__c with WITH SECURITY_ENFORCED ORDER BY CreatedDate DESC LIMIT 1, returning null when no records exist. Used actual deployed field names (ExecutionTimeMs__c, InitiatedBy__c, TriggerSource__c) rather than the WO spec names (DurationMs__c, TriggeredBy__c) which don't exist on the object. Added 5 Apex tests covering no-records, pass, fail, in-progress, and multi-record scenarios. StatusBanner LWC uses @wire(getLatestExecution), derives status from Status__c picklist (Queued/In Progress → inprogress, Failed/Aborted → fail, Completed + OverallResult__c → pass/fail) and renders three visual states: slds-alert_success + utility:success icon + 'Pass' text; slds-alert_error + utility:error + 'Fail'; slds-alert_offline + utility:spinner + 'In Progress'. WCAG compliance: color class + lightning-icon with alternative-text + bold text label + slds-assistive-text — color is never the sole indicator. Deployer identity shows InitiatedBy__r.Name (relationship query), falling back to TriggerSource__c then 'System' for platform-event-triggered runs. Duration formatted as 'Xm Ys' from ExecutionTimeMs__c; in-progress records compute elapsed from StartTime__c to Date.now(). Wire errors show an inline fallback with retry link and dispatch a bubbling loaderror custom event to the parent shell. Component renders nothing (no DOM nodes) when execution is null, deferring to the onboarding/empty-state card.

## WO-049: User Story: WO-049 - Historical Trend Chart with Accessible Table
- **Status:** completed
- **Commit:** `cd1600e`
- **Files:** 7 (+1090/-0)
- **Duration:** 529ss
- **Approach:** Added getExecutionHistory to SmokeTestDashboardController as @AuraEnabled(cacheable=true) using actual Status__c picklist values ('Completed' and 'Failed', not the WO's 'Complete') and confirmed field names (no TimedOutScenarios__c exists — derived as total-passed-failed in JS). Created trendChart LWC with wire adapter, SVG coordinate system (viewBox 620x290, C_LEFT=47, C_RIGHT=610, C_TOP=12, C_BOTTOM=250), computed bars getter that reverses DESC query order so oldest bar is left, filters out TotalScenarios__c=0/null records to avoid division by zero, and calculates bar dimensions from pass rate. Three-color scheme: #4CAF50 (>=80%), #FF9800 (50-79%), #F44336 (<50%) with SVG pattern overlays — diagonal stripes for warning range, crosshatch for error range — satisfying WCAG color-independence. Accessible data table always present in DOM via slds-assistive-text class (screen reader accessible without interaction); toggle button switches to visible with aria-expanded and aria-controls. SVG carries role=img, aria-label, and aria-describedby linking to the table element. Y-axis gridlines at 0/25/50/75/100%. X-axis labels thinned per data density (every 1/2/5 bars for <=10/<=20/30 records). Hover tooltip shows pass rate, date, and counts via positioned div. Error state dispatches retry via imperative Apex call. Five Apex tests added covering empty list, single record, status filter exclusion, LIMIT enforcement, and field population.

## WO-053: User Story: WO-053 - First-Time User Onboarding Empty State Card
- **Status:** completed
- **Commit:** `c5e31bb`
- **Files:** 10 (+653/-5)
- **Duration:** 873ss
- **Approach:** Created a self-contained onboardingCard LWC component (presentational, no wire) that renders when the parent smokeTestCenter detects no execution records. The parent shell (smokeTestCenter) gained a second @wire for getLatestExecution: _executionData starts as undefined (not yet loaded), becomes null when the wire returns null (no records), or an SObject when records exist. The showOnboarding getter returns true only when hasAccess && _executionData === null — this means the dashboard panels show by default while execution data loads (preserving all existing test behavior) and only toggle to onboarding when the wire explicitly resolves to null. The onboarding card provides: a welcome heading and sample dashboard screenshot (SVG static resource with dashboard wireframe), 3-step ordered instructions using Custom Labels, 3 cloud template SLDS cards (Sales/Service/Experience Cloud) from a module-level JS constant array, and a brand CTA button that calls NavigationMixin.Navigate({type:'standard__navItemPage', attributes:{apiName:'scenarios'}}). Non-admin (viewer) users see the same card but with the configure button disabled and an admin-required message — fulfilling the edge case in the WO. Image load failure (onerror) sets imageLoadError=true, toggling from img.sample-screenshot to an SLDS illustration fallback div. All 12 Custom Labels are defined in CustomLabels.labels-meta.xml using the c namespace with categories=onboarding.

## WO-066: User Story: WO-066 - Implement MetadataIntegrityService with Tooling API Comparison
- **Status:** completed
- **Commit:** `d0241a3`
- **Files:** 21 (+1308/-0)
- **Duration:** 894ss
- **Approach:** Implemented MetadataIntegrityService as a without-sharing Apex service that loads DeploymentManifest__c JSON from SmokeTestExecution__c, parses it via DeploymentManifestParser, groups components by type, makes one Tooling API REST callout per distinct type, evaluates each component (PASS/FAIL/WARNING), and persists results as SmokeTestResult__c records with ResultType__c='METADATA_INTEGRITY'. New schema fields on both SObjects support the manifest and per-component tracking. Value types are handled: FlowDefinition checks ActiveVersionId, ApexClass/ApexTrigger check Status field. Unsupported types yield WARNING rather than hard failures.

## WO-075: User Story: WO-075 - Write Apex Unit Tests for All Scenario Implementations
- **Status:** completed
- **Commit:** `874f156`
- **Files:** 11 (+394/-0)
- **Duration:** 556ss
- **Approach:** WO-017/018/019 had already created all 10 test classes with happy-path, exception-injection, metadata, and budget assertion tests (8-13 methods per class). WO-075 adds the missing acceptance criteria: (1) added createUserWithProfile(String) to SmokeTestDataFactory for profile-based test users; (2) added testGovernorLimitBudget() to all 10 test classes using Limits.getQueries/getDmlStatements/getCpuTime deltas within Test.startTest/stopTest; (3) added testRunAsSystemAdministrator(), testRunAsStandardUser(), and testRunAsMinimumAccessProfile_FailsGracefully() to AccountCrudScenarioTest and OpportunityCrudScenarioTest. The 10th scenario is FlexipageRenderScenario (not PlatformEventScenario as in WO spec) — its governor test uses MockHttpCallout with a FOUND_BODY fixture.

## WO-081: User Story: WO-081 - Test Scenarios Configuration Page with CRUD Operations
- **Status:** completed
- **Commit:** `5512d1f`
- **Files:** 18 (+2492/-5)
- **Duration:** 865ss
- **Approach:** Built the full Test Scenarios Configuration Page as a multi-layer stack. (1) MetadataDeployService.cls wraps Metadata.Operations.enqueueDeployment() with a @TestVisible bypassDeployment flag so tests can exercise all controller code paths without hitting the real async Metadata API. (2) SmokeTestScenarioController.cls provides four @AuraEnabled methods: getScenarios (cacheable, uses SmokeTestScenario__mdt.getAll() — no SOQL — sorted by ExecutionOrder__c), toggleScenario, createScenario, updateScenario. All write methods validate inputs server-side (DeveloperName regex, numeric ranges, ISmokeTestScenario instanceof check), call MetadataDeployService, then write an immutable SmokeTestAuditLog__c via AuditLogWriter.Builder with mandatory changeReason. Admin guard uses SOQL on PermissionSetAssignment matching the existing SmokeTestDashboardController pattern. (3) testScenariosPage LWC wires getScenarios, implements FilterBar (text + category + status), InfoBanner (live region for screen readers), toggle buttons with aria-checked and per-row spinner, and AddScenarioModal integration. (4) addScenarioModal LWC performs client-side validation matching server rules before dispatching a save event; Escape key, X button, and Cancel button all dispatch close. (5) smokeTestCenter.html extended with isScenariosPage conditional that shows c-test-scenarios-page when activePageId === 'scenarios' while preserving the existing admin-panels slot for all other pages.

## WO-085: User Story: WO-085 - Settings and Security Configuration Page with Batch Save
- **Status:** completed
- **Commit:** `ce65daf`
- **Files:** 27 (+1988/-6)
- **Duration:** 766ss
- **Approach:** Added 7 new SmokeTestConfig__mdt fields for settings not already present in the CMT schema. Created SettingsController with getSettings (cacheable wire) and saveSettings (validates numeric ranges, enforces audit log retention >= 365, requires changeReason for rollback policy changes, deploys via MetadataDeployService, writes one AuditLogEntry per changed field). Created three LWCs: stickyFooterSaveBar (fixed SLDS docked-form-footer, aria-live polite, dispatches save/discard), changeReasonModal (role=dialog, Escape key, validates non-empty reason, dispatches confirm with reason string or cancel), and settingsPage (5-card form, dirty-state tracking via JSON.stringify comparison, rollback policy intercepted to open modal first, _pendingChangeReason stored for save, field-level error rendering). Wired settingsPage into smokeTestCenter navigation by adding 'settings' to PAGE_IDS, adding isSettingsPage getter, adding Settings nav item under Configuration, and rendering c-settings-page conditionally alongside the existing isScenariosPage pattern.

## WO-024: User Story: WO-024 - Build SmokeTestOrchestrator Queueable Chain with Result Aggregation
- **Status:** completed
- **Commit:** `f9f008f`
- **Files:** 4 (+1061/-0)
- **Duration:** 802ss
- **Approach:** Implemented SmokeTestOrchestrator as a global without sharing Queueable class. The static factory startExecution(triggerSource) creates SmokeTestExecution__c, loads enabled scenarios via ScenarioDispatcher.getEnabledScenarios() and the SuiteTimeoutSec__c from SmokeTestConfig__mdt, then enqueues the first Queueable link. Each execute() link: (1) checks suite timeout — elapsed >= suiteTimeoutSec*1000ms marks remaining as SKIPPED_SUITE_TIMEOUT and finalizes; (2) loads CircuitBreakerService state (or uses injectedCb) — if open, marks remaining as SKIPPED_CIRCUIT_BREAKER and finalizes; (3) dispatches the scenario at currentIndex via ScenarioDispatcher.dispatch(); (4) inserts SmokeTestResult__c with Status, ExecutionTimeMs, ErrorMessage, governor counts; (5) publishes SmokeTestProgress__e; (6) updates CB (recordGovernorFailure/Success/FunctionalFailure) and calls cb.saveState(); (7) if more scenarios and CB is closed and not timed out and !bypassEnqueue: enqueues next link (catching System.AsyncException for flex queue full → SKIPPED_QUEUE_FULL); otherwise: handles remaining skips and calls doFinalize. Finalization queries all SmokeTestResult__c, computes Pass/Fail/Partial, updates SmokeTestExecution__c with all aggregates, and publishes SmokeTestComplete__e. Top-level try-catch updates execution to 'Failed' and publishes error completion event on any unhandled exception.

## WO-038: User Story: WO-038 - Build Security Score Threshold Comparator and Configuration
- **Status:** completed
- **Commit:** `9c80651`
- **Files:** 8 (+655/-0)
- **Duration:** 404ss
- **Approach:** Implemented a pure business-logic SecurityScoreComparator that evaluates pre/post SecurityHealthCheckResult objects against two configurable thresholds. Config is read zero-SOQL via SmokeTestConfig__mdt.getAll() using the existing SecurityScoreAbsoluteThreshold__c (default 80) and SecurityScoreRelativeThreshold__c (default 5) fields — reusing over creating duplicates per integration rules. Boundary semantics: post < threshold (strict less-than) for absolute fail; delta > maxDrop (strict greater-than) for delta fail. Category diff walks pre/post riskCategories lists and flags added, removed, or score-changed categories.

## WO-039: User Story: WO-039 - Implement Security Check Graceful Degradation Handling
- **Status:** completed
- **Commit:** `6641204`
- **Files:** 8 (+475/-36)
- **Duration:** 583ss
- **Approach:** Added three degradation paths to SecurityHealthCheckService: (1) HTTP 403 now returns 'View Setup and Configuration permission required for the integration user', (2) HTTP 500 returns 'Unable to retrieve security health score — Tooling API unavailable (HTTP 500)', (3) pre-flight check changed from ==0 to <5 with message 'API call limit approaching — security check skipped to preserve budget'. CalloutException is now caught separately from general Exception with a 'Network error connecting to Tooling API' message. SecurityHealthCheckCache.cls provides Platform Cache (local.SmokeTestCache, 60s TTL) with automatic static-map fallback for test contexts and unsupported org editions. SecurityCacheTTL__c CMT field configures the TTL. SecurityScoreComparator already handled ERROR/SKIPPED short-circuit from WO-038.

## WO-051: User Story: WO-051 - Platform Event Real-Time Dashboard Subscription
- **Status:** completed
- **Commit:** `ad9e24b`
- **Files:** 7 (+592/-13)
- **Duration:** 600ss
- **Approach:** Extended smokeTestCenter.js with lightning/empApi subscription logic. connectedCallback registers onError and subscribes to /event/SmokeTestProgress__e and /event/SmokeTestComplete__e with replay ID -1. Progress events update a @track progressData object (idempotent — ignores events with lower completedScenarios count) and start a 30-second setInterval auto-refresh timer. Complete events dispatch 'refreshdashboard' CustomEvent and clear the timer. Reconnection retries up to 3 times (5s delay each) on empApi errors; after MAX_RETRY_ATTEMPTS the component activates fallback mode showing a warning banner and starting the auto-refresh timer. disconnectedCallback clears timer and unsubscribes. The HTML adds a content-header bar with progress indicator, manual refresh button, and fallback warning. A lightning/empApi Jest mock + two Platform Event payload fixtures enable unit tests without a scratch org.

## WO-067: User Story: WO-067 - Implement Five Default Post-Deployment Checklist Validations
- **Status:** completed
- **Commit:** `3892658`
- **Files:** 20 (+1363/-0)
- **Duration:** 759ss
- **Approach:** Implemented Strategy pattern: IChecklistCheck interface, ChecklistResult value class, ChecklistContext DTO with injectable IHttpCallout for Tooling API mocking. Five check classes: FlowActivationCheck (Tooling API FlowDefinition, verifies ActiveVersionId), PermissionSetAssignmentCheck (SOQL PermissionSetAssignment, zero-assignment = FAIL), PageLayoutAssignmentCheck (Tooling API ProfileLayout, multi-assignment = WARNING), ConfigValueCheck (reads enabled SOQLValidation CMT entries, executes Query__c, non-empty result = PASS), ScheduledJobCheck (CronTrigger WAITING state, supports named job list from CMT ExpectedResult__c). ChecklistEvaluator orchestrates all five in sequence without short-circuit, injects DefaultHttpCallout and IDmlHandler, persists to SmokeTestResult__c with ResultType__c = 'CHECKLIST'. ChecklistEvaluatorTest uses MockHttpCallout and MockDmlHandler for full isolation.

## WO-082: User Story: WO-082 - Guided Setup Wizard with Cloud Scenario Templates
- **Status:** completed
- **Commit:** `1ba39a1`
- **Files:** 19 (+1766/-19)
- **Duration:** 911ss
- **Approach:** Built the Guided Setup Wizard bottom-up: ScenarioTemplateService provides static template definitions for 9 scenarios across 3 clouds plus Apex class validation via Type.forName and bulk deploy via a single Metadata.DeployContainer. MetadataDeployService got a deployBulk() method for pre-built containers. Three child LWCs (cloudTemplateCard, scenarioPreviewTable, guidedSetupWizard) implement the 3-step wizard. TestScenariosPage renders the wizard inline for empty state and as a modal overlay for the 'Add from Templates' button on non-empty state.

## WO-025: User Story: WO-025 - Implement DeploymentComplete Platform Event Trigger for Auto-Initiation
- **Status:** completed
- **Commit:** `b5c2650`
- **Files:** 6 (+564/-0)
- **Duration:** 331ss
- **Approach:** Thin trigger delegates to DeploymentCompleteTriggerHandler.handleEvents(). Handler resolves ShadowMode__c from SmokeTestConfig__mdt.getAll() (with @TestVisible override), validates DeploymentId__c, performs bulk SOQL duplicate detection (5-minute window), handles same-batch duplicates with an in-memory Set, writes an audit record in shadow mode, and calls SmokeTestOrchestrator.startExecution('Platform Event') for valid non-duplicate events — updating the returned execution record with DeploymentId__c. All exceptions are caught to prevent Platform Event bus disruption.

## WO-027: User Story: WO-027 - Build SmokeTestRunResource POST /v1/run Endpoint
- **Status:** completed
- **Commit:** `b77c99b`
- **Files:** 4 (+670/-0)
- **Duration:** 559ss
- **Approach:** Thin controller pattern: SmokeTestRunResource.doPost() delegates validation to SmokeTestApiValidator, permission check to a private hasPermission() SOQL helper, rate limiting to isQueueCapacityExceeded() reading BackpressureQueueDepthPct__c from CMT, execution record creation with Status='Queued' and all request fields, orchestrator enqueueing via the global SmokeTestOrchestrator constructor (with empty-scenario guard), audit logging via AuditLogWriter (try-catch wrapped), and 202 response via direct RestContext manipulation using the existing SmokeTestApiResponse.RunAcknowledgment shape.

## WO-040: User Story: WO-040 - Integrate Security Health Check into Orchestrator Flow
- **Status:** completed
- **Commit:** `919d71d`
- **Files:** 12 (+840/-29)
- **Duration:** 996ss
- **Approach:** Pre/post security capture injected into the Queueable chain without adding extra Queueable steps: pre-capture runs at currentIndex==0 before scenario dispatch (using a local effectivePreResult variable since preSecurityResult is a private final field), post-capture runs inside doFinalize() before doFinalizeForExecution(). A private 8-arg constructor carries preSecurityResult through chain enqueues. All security steps are wrapped in try-catch so failures are non-blocking. Field name mapping: existing SmokeTestSecurityScore__c fields (Execution__c, AbsoluteThreshold__c, RelativeThreshold__c, CheckedAt__c) are used — only ThresholdStatus__c and RiskCategories__c are new. SmokeTestSecurityComplete__e is a new HighVolume platform event.

## WO-041: User Story: WO-041 - Implement Role-Based Scenario Execution with System.runAs
- **Status:** completed
- **Commit:** `3b36126`
- **Files:** 8 (+1005/-0)
- **Duration:** 767ss
- **Approach:** Implemented the decorator pattern for role-based scenario execution. RoleBasedScenarioExecutor wraps any ISmokeTestScenario in System.runAs() blocks using a temporary test user created via SmokeTestDataFactory.createUserWithProfile(). Permission failures (NoAccessException, InsufficientAccessException, access-related DmlException) are caught, parsed with regex and string matching to extract object/field name and permission type, and wrapped in PermissionFailureDetail. Results include the profile name and are persisted to SmokeTestResult__c with RoleProfile__c set. Used the existing RoleProfile__c field (Text 255) rather than creating a duplicate ExecutionProfile__c field since RoleProfile__c already exists on both SmokeTestResult__c and SmokeTestScenario__mdt.

## WO-056: User Story: WO-056 - Alert Dispatch Service with In-App and Email
- **Status:** completed
- **Commit:** `8ffc68f`
- **Files:** 25 (+1600/-0)
- **Duration:** 783ss
- **Approach:** Built the pluggable alerting engine with interface-first design. IAlertChannelAdapter defines the contract; AlertDispatchService is the orchestrator that reads SmokeTestAlertRoute__mdt.getAll(), filters by new Enabled__c field, applies AlertOnFail/Pass and ScenarioFilter__c tag matching (against failedScenarioNames and SmokeTestScenario__mdt.BusinessProcess__c CMT lookup), resolves recipients via PermissionSetAssignment queries, and dispatches independently per route with full error isolation. InAppNotificationAdapter uses Messaging.CustomNotification with graceful handling for missing CustomNotificationType. EmailAlertAdapter batches in groups of 10 to respect governor limits and escapes HTML in the body. Added Enabled__c Checkbox field to SmokeTestAlertRoute__mdt (required by AC2) and updated all 5 existing CMT records. Used ROLE_TO_PERM_SET static map to translate RecipientRole__c values (Team Lead, Business Owner, etc.) to permission set names for PermissionSetAssignment queries. AlertPayload carries only securityThresholdBreached boolean — no numeric score values, per Confidential data classification.

## WO-068: User Story: WO-068 - Implement Custom Checklist Items with SOQL Query Validation
- **Status:** completed
- **Commit:** `7cd75e8`
- **Files:** 18 (+1004/-1)
- **Duration:** 1050ss
- **Approach:** Built the custom checklist extension on top of the existing ChecklistEvaluator/ChecklistResult/ChecklistContext architecture. ChecklistQueryValidator implements 5 independent validation checks (syntax via Database.getQueryLocator(), DML keyword regex, restricted object allow-list, LIMIT clause enforcement up to 10000, binding variable detection) collecting ALL errors rather than failing fast. CustomChecklistProcessor filters SmokeTestChecklist__mdt records by IsEnabled__c=true and CheckType__c='query', validates each query, executes via Database.query(), and compares the returned row count as a string against ExpectedResult__c (blank=any rows pass). ChecklistEvaluator extended to call CustomChecklistProcessor after 5 default checks and merge results. Added @TestVisible checklistConfigOverride to ChecklistEvaluator so existing tests that assert results.size()==5 remain isolated from deployed CMT records. Added logPolicyChange() convenience method to AuditLogWriter for use by admin tooling when CMT records are modified. Key field name mapping: WO spec uses Enabled__c/ExpectedValue__c/ActualValueQuery__c but existing CMT fields are IsEnabled__c/ExpectedResult__c/Query__c — existing names preserved to avoid breaking deployed code.

## WO-076: User Story: WO-076 - Write Apex Unit Tests for Orchestrator and Dispatcher
- **Status:** completed
- **Commit:** `e0e4968`
- **Files:** 0 (+0/-0)
- **Duration:** 311ss
- **Approach:** All 5 required test classes (SmokeTestOrchestratorTest, CircuitBreakerServiceTest, ScenarioDispatcherTest, ScenarioTimeoutHandlerTest, GovernorLimitBudgetTest) were already implemented and committed to the branch in a prior execution pass. The tests use ConfigurableMockScenario (a flexible configurable mock with static flags: shouldPass, shouldThrowDmlException, shouldThrowQueryException, shouldThrowException, injectedErrorType, injectedErrorDetail, and a reset() method) plus MockSmokeTestScenario (a constructor-injected mock) rather than 4 separate named mock classes, achieving the same coverage with less code. No new files were required for this WO.

## WO-028: User Story: WO-028 - Build SmokeTestStatusResource GET /v1/status Endpoint
- **Status:** completed
- **Commit:** `9a5c43f`
- **Files:** 4 (+583/-0)
- **Duration:** 598ss
- **Approach:** Thin REST controller following the same patterns as SmokeTestRunResource. Extracts executionId from the last URL path segment, validates via SmokeTestApiValidator.validateExecutionId(), checks permission set (with @TestVisible permissionCheckOverride for test isolation), runs 2 SOQL queries (execution record + result records), builds a response Map with executionId/status/scenarios/executionDurationMs/timestamp, and sends via SmokeTestApiResponse.success200(). Status values are normalized from Salesforce picklist values (Queued/In Progress/Completed/Failed/Aborted) to API values (queued/in_progress/complete/failed). Pending scenario placeholders are added by comparing TotalScenarios__c against the count of actual result records. Duration uses stored ExecutionTimeMs__c for terminal executions and live DateTime arithmetic for in-progress ones.
