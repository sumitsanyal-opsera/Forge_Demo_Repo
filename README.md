# Salesforce Post-Deployment Smoke Testing

Automated health checks that validate critical business workflows immediately after every Salesforce deployment — bridging the gap between technical deployment validation and functional application validation.

---

## Namespace Decision

**Namespace prefix: `stcenter`** (Smoke Test Center)

This namespace is defined in `sfdx-project.json` and propagates to all metadata artifacts, particularly the **Protected Custom Metadata Types** used for webhook HMAC secret storage (`SmokeTestAlertRoute__mdt`). The namespace was chosen because:

- It is short (8 characters), readable, and descriptive of the package's purpose.
- It does not conflict with common Salesforce-managed namespaces (`sf`, `c`, `force`, etc.).
- It satisfies Salesforce's alphanumeric-only, no-leading-digit constraint.

> **Important**: The namespace prefix **cannot be changed** after the unlocked package is created without recreating the package from scratch. If `stcenter` is already registered in your Dev Hub org, use the fallback: `smktst`.

---

## Project Structure

```
salesforce-smoke-test-center/
├── sfdx-project.json               # SFDX project config (sourceApiVersion 60.0, namespace, package dirs)
├── config/
│   └── project-scratch-def.json    # Scratch org definition (Enterprise, LightningExperience, API, PlatformEvents)
├── package.json                    # Node.js tooling (LWC Jest, ESLint, Prettier)
├── jest.config.js                  # LWC Jest configuration with module name mappings
├── .prettierrc                     # Prettier formatting rules (Apex, XML, JS, HTML)
├── .prettierignore                 # Files excluded from Prettier
├── .gitignore                      # Salesforce DX-compatible Git ignore rules
└── force-app/
    └── main/
        └── default/
            ├── applications/       # Lightning Apps (SmokeTestCenter.app-meta.xml)
            ├── classes/            # Apex classes and test classes
            ├── connectedApps/      # OAuth 2.0 Connected App for CI/CD JWT Bearer auth
            ├── customMetadata/     # Custom Metadata Type records (config, scenarios, alerts)
            ├── events/             # Platform Event definitions
            ├── flexipages/         # Lightning FlexiPages (dashboard pages)
            ├── layouts/            # Page layouts
            ├── lwc/                # Lightning Web Components (dashboard, config screens)
            ├── objects/            # Custom Objects (SmokeTestExecution__c, etc.)
            ├── permissionsets/     # Permission Sets (SmokeTest_Admin, SmokeTest_Dashboard_Viewer)
            ├── tabs/               # Custom tabs
            └── triggers/           # Apex triggers (AuditLog immutability enforcement)
```

---

## Architecture Overview

The system is a **Salesforce-native** post-deployment smoke test orchestrator running entirely within the Salesforce platform ecosystem:

- **Orchestration**: Queueable Apex chains with circuit-breaker logic (governor-limit-aware)
- **API**: Versioned REST endpoints at `/services/apexrest/smoketest/v1/`
- **Dashboard**: Lightning Web Components with Platform Event–driven real-time refresh
- **Configuration**: Custom Metadata Types (deployable via CI/CD, no SOQL count impact)
- **Auth**: OAuth 2.0 JWT Bearer flow via Connected App for CI/CD pipelines
- **Audit**: Immutable `SmokeTestAuditLog__c` (Apex trigger blocks UPDATE/DELETE)

See `architecture.md` (internal) for the full architectural decision log.

---

## Getting Started

### Prerequisites

- Salesforce CLI (`sf`) v2.x or higher
- Node.js ≥ 18.0.0
- Dev Hub org with PlatformEvents and unlocked package features enabled

### 1. Install Node.js Dependencies

```bash
npm install
```

### 2. Authorize Your Dev Hub

```bash
sf org login web --set-default-dev-hub --alias DevHub
```

### 3. Create a Scratch Org

```bash
sf org create scratch \
  --definition-file config/project-scratch-def.json \
  --set-default \
  --alias SmokeTestDev \
  --duration-days 30
```

### 4. Deploy the Source

```bash
sf project deploy start --target-org SmokeTestDev
```

### 5. Validate the Project Structure (CI/CD gate)

```bash
sf project deploy validate \
  --manifest package.xml \
  --target-org SmokeTestDev
```

### 6. Run LWC Unit Tests

```bash
npm run test:lwc
```

Or with coverage:

```bash
npm run test:lwc -- --coverage
```

---

## CI/CD Integration

The REST API supports triggering smoke tests from any CI/CD platform:

```bash
# Example: trigger smoke test suite from any pipeline
curl -X POST https://<org-domain>/services/apexrest/smoketest/v1/run \
  -H "Authorization: Bearer <oauth-token>" \
  -H "Content-Type: application/json" \
  -d '{"targetOrg": "<alias>", "scenarios": "all"}'
```

Pre-built pipeline templates are provided for GitHub Actions, Jenkins, GitLab CI, and Azure DevOps (see `force-app/` CI/CD documentation when implemented).

---

## Key Custom Metadata Types

| CMT Name | Purpose |
|----------|---------|
| `SmokeTestConfig__mdt` | Global settings: timeouts, security thresholds, rollback policy |
| `SmokeTestScenario__mdt` | Scenario registry: enabled/disabled, execution order, governor budgets |
| `SmokeTestChecklist__mdt` | Post-deploy checklist: custom metadata integrity checks |
| `SmokeTestAlertRoute__mdt` | Alert routing rules per persona (Protected type for webhook secrets) |

---

## Key Custom Objects

| Object | Classification | Purpose |
|--------|---------------|---------|
| `SmokeTestExecution__c` | Internal | Overall execution record per deployment |
| `SmokeTestResult__c` | Internal | Per-scenario pass/fail results |
| `SmokeTestAuditLog__c` | Confidential | Immutable audit trail (blocks UPDATE/DELETE) |
| `SmokeTestSecurityScore__c` | Confidential | Pre/post security health score comparison |

---

## Development Workflow

1. Create a feature branch from `main`
2. Develop against a scratch org (`sf org create scratch`)
3. Run `npm run test:lwc` for LWC unit tests
4. Run `sf project deploy validate` before opening a PR
5. Merge triggers CI/CD pipeline → smoke test validation in staging org

---

## Fallback Namespace

If `stcenter` is already registered in the Dev Hub:

- Primary: `stcenter`
- Fallback 1: `smktst`
- Fallback 2: `depsmoke`

Update `sfdx-project.json` → `"namespace"` field if a fallback is needed before first package version creation.
