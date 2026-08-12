# Connected App Setup Guide: Smoke Test CI/CD Integration

This guide walks through configuring the **Smoke Test CI/CD Integration** Connected App for OAuth 2.0 JWT Bearer flow authentication from external CI/CD pipelines (GitHub Actions, Jenkins, GitLab CI, Azure DevOps).

> **Security note:** Private keys and consumer secrets are **never** committed to this repository. All secrets are stored in your CI/CD platform's secret management system.

---

## Table of Contents

1. [Prerequisites](#1-prerequisites)
2. [Certificate Generation](#2-certificate-generation)
3. [Certificate Upload to Salesforce](#3-certificate-upload-to-salesforce)
4. [Deploy the Connected App](#4-deploy-the-connected-app)
5. [Consumer Key Retrieval](#5-consumer-key-retrieval)
6. [Permission Set Pre-Authorization](#6-permission-set-pre-authorization)
7. [IP Restriction Configuration](#7-ip-restriction-configuration)
8. [CI/CD Platform Configuration](#8-cicd-platform-configuration)
   - [8.1 GitHub Actions](#81-github-actions)
   - [8.2 Jenkins](#82-jenkins)
   - [8.3 GitLab CI](#83-gitlab-ci)
   - [8.4 Azure DevOps](#84-azure-devops)
9. [JWT Bearer Flow Testing](#9-jwt-bearer-flow-testing)
10. [Troubleshooting](#10-troubleshooting)

---

## 1. Prerequisites

Before starting, verify the following conditions are met:

- **My Domain** is enabled in the target Salesforce org (required for OAuth flows). Modern scratch orgs have My Domain enabled by default. To check: Setup > My Domain.
- The **SmokeTestCenter package** or its metadata is deployed to the target org (provides `SmokeTest_API_User` and `SmokeTest_Admin` permission sets from WO-007).
- A **dedicated integration user** (not a named human user) exists in the target org. Recommended:
  - Profile: Minimum Access — Salesforce
  - Username: `smoketest-cicd@<your-org-domain>.com`
  - The user must have logged in at least once before JWT Bearer flow will succeed (Salesforce requirement).
- OpenSSL is installed locally (for certificate generation in step 2).
- You have the `sf` Salesforce CLI installed.

---

## 2. Certificate Generation

Generate a self-signed X.509 certificate and private key pair. The **public certificate** is uploaded to Salesforce; the **private key** stays in your CI/CD secret management system.

### 2.1 Generate the private key and self-signed certificate

```bash
# Generate a 2048-bit RSA private key
openssl genrsa -out smoketest_cicd.key 2048

# Generate a self-signed X.509 certificate (valid for 365 days)
openssl req -new -x509 -key smoketest_cicd.key \
  -out smoketest_cicd.crt \
  -days 365 \
  -subj "/C=US/ST=State/L=City/O=YourOrg/CN=SmokeTestCICD"
```

### 2.2 Verify the certificate

```bash
openssl x509 -in smoketest_cicd.crt -text -noout
```

Confirm the output shows:
- `Public Key Algorithm: rsaEncryption`
- `Public-Key: (2048 bit)`

### 2.3 Secure the private key

Store `smoketest_cicd.key` in your CI/CD platform's secret management (see [Section 8](#8-cicd-platform-configuration)).

**Never commit `smoketest_cicd.key` to any repository.**

> **Certificate renewal:** Self-signed certificates expire. Set a calendar reminder before the expiration date. Renewal requires uploading a new certificate and updating the Connected App (see [Troubleshooting](#10-troubleshooting) for certificate expiration errors).

---

## 3. Certificate Upload to Salesforce

### Option A: Upload via Setup UI (recommended for initial setup)

1. Log in to the target Salesforce org as a System Administrator.
2. Navigate to **Setup > Security > Certificate and Key Management**.
3. Click **Import from Keystore**, OR select **Create Self-Signed Certificate** if you prefer Salesforce to generate the key pair (download the keystore immediately — the private key cannot be retrieved later).
4. If using the certificate from Step 2, click **Import from Keystore** is not quite right — for an externally generated cert, follow the alternate path:
   - Navigate to **Setup > App Manager**.
   - Find **Smoke Test CI/CD Integration** and click **Edit**.
   - Under **API (Enable OAuth Settings)**, check **Use Digital Signatures**.
   - Click **Choose File** and upload `smoketest_cicd.crt`.
   - Note the certificate name assigned. Update `SmokeTestConnectedApp.connectedApp-meta.xml`'s `<certificate>` element to match this name if it differs from `SmokeTestCICDCert`.

### Option B: Upload via Metadata API

Create a `Certificate` metadata record and deploy it alongside the Connected App:

```xml
<!-- force-app/main/default/certs/SmokeTestCICDCert.certificate-meta.xml -->
<?xml version="1.0" encoding="UTF-8"?>
<Certificate xmlns="http://soap.sforce.com/2006/04/metadata">
    <caSigned>false</caSigned>
    <encryptedWithPlatformEncryption>false</encryptedWithPlatformEncryption>
    <expirationDate>2026-01-01</expirationDate>
    <keySize>2048</keySize>
    <masterLabel>SmokeTestCICDCert</masterLabel>
    <privateKeyExportable>false</privateKeyExportable>
</Certificate>
```

Note: When deploying a Certificate metadata type, Salesforce generates its own key pair. To use your externally generated certificate, use Option A above.

---

## 4. Deploy the Connected App

```bash
# Deploy only the Connected App metadata to the target org
sf project deploy start \
  --source-dir force-app/main/default/connectedApps \
  --target-org <your-org-alias>

# Or deploy the full project
sf project deploy start --target-org <your-org-alias>
```

**Expected result:** The deployment succeeds and the Connected App appears in Setup > App Manager with the label **Smoke Test CI/CD Integration**.

If a Connected App with the same `fullName` already exists in the target org, the deployment updates the existing record. Verify the existing record's configuration is not overwritten in a way that breaks existing integrations before deploying.

---

## 5. Consumer Key Retrieval

The consumer key (used as the `iss` and `client_id` values in the JWT assertion) is auto-generated by Salesforce on deployment and cannot be set in advance.

### Steps to retrieve the consumer key

1. Navigate to **Setup > App Manager**.
2. Find **Smoke Test CI/CD Integration** in the list.
3. Click the dropdown arrow at the right of the row and select **View**.
4. Copy the value shown for **Consumer Key**.

### Store the consumer key as a CI/CD secret

Store the consumer key in your CI/CD platform using the secret name `SALESFORCE_CONSUMER_KEY` (see [Section 8](#8-cicd-platform-configuration) for platform-specific instructions).

**The consumer key is not a secret** (it is the OAuth client identifier, equivalent to a username), but store it as a secret to allow rotation without code changes.

---

## 6. Permission Set Pre-Authorization

The Connected App is configured with `permittedUsers: AdminApprovedUsersArePreAuthorized`. This means only users with the `SmokeTest_API_User` or `SmokeTest_Admin` permission set assigned can authenticate.

### Assign SmokeTest_API_User to the CI/CD integration user

```bash
# Using Salesforce CLI
sf org assign permset \
  --name SmokeTest_API_User \
  --on-behalf-of smoketest-cicd@<your-org-domain>.com \
  --target-org <your-org-alias>
```

Or via the Setup UI:
1. Navigate to **Setup > Users**.
2. Find the CI/CD integration user and click their name.
3. Scroll to **Permission Set Assignments** and click **Edit Assignments**.
4. Move **SmokeTest_API_User** from Available to Enabled and save.

### Verify the assignment

```bash
sf data query \
  --query "SELECT Assignee.Username, PermissionSet.Name FROM PermissionSetAssignment WHERE Assignee.Username = 'smoketest-cicd@<your-org-domain>.com'" \
  --target-org <your-org-alias>
```

---

## 7. IP Restriction Configuration

The Connected App is deployed with `ipRelaxation: EnforceIpRestrictions` for production security. You must configure the allowed IP ranges to match your CI/CD platform's egress IPs.

### Configure IP ranges via Setup UI

1. Navigate to **Setup > App Manager**.
2. Find **Smoke Test CI/CD Integration** and click **Edit**.
3. Scroll to **IP Relaxation** and select **Enforce IP restrictions**.
4. Under **Trusted IP Range for OAuth Tokens**, add the CIDR blocks for your CI/CD platform:

| Platform | IP Range Documentation |
|---|---|
| GitHub Actions | [github.com/meta](https://api.github.com/meta) — see `actions` key |
| Jenkins | Your Jenkins controller's egress IP(s) |
| GitLab CI | [docs.gitlab.com/ee/user/gitlab_com/index.html#ip-range](https://docs.gitlab.com/ee/user/gitlab_com/index.html#ip-range) |
| Azure DevOps | [azure.microsoft.com/en-us/products/devops/agents](https://learn.microsoft.com/en-us/azure/devops/organizations/security/allow-list-ip-url) |

### Development/scratch org environments

For scratch orgs and local development testing, temporarily set **IP Relaxation** to **Relax IP restrictions** (Setup > App Manager > Edit) or add your development machine's IP. Revert to **Enforce IP restrictions** before promoting to production.

---

## 8. CI/CD Platform Configuration

All examples below use the following variable names for secrets:

| Secret name | Value |
|---|---|
| `SALESFORCE_CONSUMER_KEY` | Consumer key from Step 5 |
| `SALESFORCE_PRIVATE_KEY` | Contents of `smoketest_cicd.key` (PEM format, full file) |
| `SALESFORCE_USERNAME` | Integration user username (e.g., `smoketest-cicd@example.com`) |
| `SALESFORCE_LOGIN_URL` | `https://login.salesforce.com` (or `https://test.salesforce.com` for sandboxes) |

---

### 8.1 GitHub Actions

#### Storing secrets

1. Navigate to your repository on GitHub.
2. Go to **Settings > Secrets and variables > Actions**.
3. Click **New repository secret** for each of the four secrets above.
   - For `SALESFORCE_PRIVATE_KEY`, paste the entire PEM file contents including the `-----BEGIN RSA PRIVATE KEY-----` header and footer.

#### Workflow example (plain text — not executable)

```
name: Smoke Test Post-Deployment

on:
  workflow_dispatch:
  push:
    branches: [main]

jobs:
  smoke-test:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4

      - name: Install Salesforce CLI
        run: npm install -g @salesforce/cli

      - name: Authenticate to Salesforce via JWT Bearer
        env:
          CONSUMER_KEY: ${{ secrets.SALESFORCE_CONSUMER_KEY }}
          PRIVATE_KEY: ${{ secrets.SALESFORCE_PRIVATE_KEY }}
          SF_USERNAME: ${{ secrets.SALESFORCE_USERNAME }}
          LOGIN_URL: ${{ secrets.SALESFORCE_LOGIN_URL }}
        run: |
          echo "$PRIVATE_KEY" > /tmp/smoketest_cicd.key
          sf org login jwt \
            --client-id "$CONSUMER_KEY" \
            --jwt-key-file /tmp/smoketest_cicd.key \
            --username "$SF_USERNAME" \
            --instance-url "$LOGIN_URL" \
            --alias smoketest-org
          rm -f /tmp/smoketest_cicd.key

      - name: Trigger Smoke Tests
        run: |
          ACCESS_TOKEN=$(sf org display --target-org smoketest-org --json | jq -r '.result.accessToken')
          INSTANCE_URL=$(sf org display --target-org smoketest-org --json | jq -r '.result.instanceUrl')
          curl -s -X POST "$INSTANCE_URL/services/apexrest/v1/run" \
            -H "Authorization: Bearer $ACCESS_TOKEN" \
            -H "Content-Type: application/json" \
            -d '{"targetOrg":"production","rollbackPolicyOverride":"RECOMMEND_ONLY"}'
```

> **Note:** Replace `${{ secrets.* }}` with your actual GitHub secret names. The `sf org login jwt` command constructs and submits the JWT assertion automatically.

---

### 8.2 Jenkins

#### Storing credentials

1. Navigate to **Jenkins > Manage Jenkins > Credentials > System > Global credentials**.
2. Add a **Secret text** credential for each secret:
   - `SALESFORCE_CONSUMER_KEY` (ID: `sf-consumer-key`)
   - `SALESFORCE_USERNAME` (ID: `sf-username`)
   - `SALESFORCE_LOGIN_URL` (ID: `sf-login-url`)
3. Add a **Secret file** credential for the private key:
   - Upload `smoketest_cicd.key` as a secret file with ID `sf-private-key-file`.

#### Jenkinsfile example (plain text — not executable)

```
pipeline {
    agent any
    environment {
        SF_CONSUMER_KEY = credentials('sf-consumer-key')
        SF_USERNAME     = credentials('sf-username')
        SF_LOGIN_URL    = credentials('sf-login-url')
    }
    stages {
        stage('Authenticate') {
            steps {
                withCredentials([file(credentialsId: 'sf-private-key-file', variable: 'SF_KEY_FILE')]) {
                    sh '''
                        sf org login jwt \
                          --client-id "$SF_CONSUMER_KEY" \
                          --jwt-key-file "$SF_KEY_FILE" \
                          --username "$SF_USERNAME" \
                          --instance-url "$SF_LOGIN_URL" \
                          --alias smoketest-org
                    '''
                }
            }
        }
        stage('Run Smoke Tests') {
            steps {
                sh '''
                    ACCESS_TOKEN=$(sf org display --target-org smoketest-org --json | jq -r .result.accessToken)
                    INSTANCE_URL=$(sf org display --target-org smoketest-org --json | jq -r .result.instanceUrl)
                    curl -s -X POST "$INSTANCE_URL/services/apexrest/v1/run" \
                      -H "Authorization: Bearer $ACCESS_TOKEN" \
                      -H "Content-Type: application/json" \
                      -d "{\"targetOrg\":\"production\"}"
                '''
            }
        }
    }
}
```

---

### 8.3 GitLab CI

#### Storing CI/CD variables

1. Navigate to your project on GitLab.
2. Go to **Settings > CI/CD > Variables**.
3. Add each variable with **Masked** enabled (and **Protected** for production branches):
   - `SALESFORCE_CONSUMER_KEY` — type: Variable
   - `SALESFORCE_USERNAME` — type: Variable
   - `SALESFORCE_LOGIN_URL` — type: Variable
   - `SALESFORCE_PRIVATE_KEY` — type: Variable, paste full PEM content; check **Expand variable reference** OFF

#### .gitlab-ci.yml example (plain text — not executable)

```
stages:
  - smoke-test

smoke-test:
  stage: smoke-test
  image: node:20
  before_script:
    - npm install -g @salesforce/cli
    - echo "$SALESFORCE_PRIVATE_KEY" > /tmp/smoketest.key
  script:
    - sf org login jwt
        --client-id "$SALESFORCE_CONSUMER_KEY"
        --jwt-key-file /tmp/smoketest.key
        --username "$SALESFORCE_USERNAME"
        --instance-url "$SALESFORCE_LOGIN_URL"
        --alias smoketest-org
    - |
      ACCESS_TOKEN=$(sf org display --target-org smoketest-org --json | jq -r '.result.accessToken')
      INSTANCE_URL=$(sf org display --target-org smoketest-org --json | jq -r '.result.instanceUrl')
      curl -s -X POST "$INSTANCE_URL/services/apexrest/v1/run"
        -H "Authorization: Bearer $ACCESS_TOKEN"
        -H "Content-Type: application/json"
        -d '{"targetOrg":"production","rollbackPolicyOverride":"RECOMMEND_ONLY"}'
  after_script:
    - rm -f /tmp/smoketest.key
  only:
    - main
```

---

### 8.4 Azure DevOps

#### Storing secrets in Azure Key Vault / Pipeline variables

1. Navigate to your Azure DevOps project.
2. Go to **Pipelines > Library > Variable Groups**.
3. Create a variable group named `salesforce-smoketest-secrets`.
4. Add the following variables, marking each as **secret**:
   - `SF_CONSUMER_KEY`
   - `SF_USERNAME`
   - `SF_LOGIN_URL`
   - `SF_PRIVATE_KEY` (paste full PEM; Azure DevOps stores as a protected variable)

Alternatively, store `SF_PRIVATE_KEY` as an Azure Key Vault secret and reference it via a Key Vault-linked variable group.

#### azure-pipelines.yml example (plain text — not executable)

```
trigger:
  - main

pool:
  vmImage: ubuntu-latest

variables:
  - group: salesforce-smoketest-secrets

steps:
  - task: NodeTool@0
    inputs:
      versionSpec: '20.x'

  - script: npm install -g @salesforce/cli
    displayName: Install Salesforce CLI

  - script: |
      echo "$(SF_PRIVATE_KEY)" > /tmp/smoketest.key
      sf org login jwt \
        --client-id "$(SF_CONSUMER_KEY)" \
        --jwt-key-file /tmp/smoketest.key \
        --username "$(SF_USERNAME)" \
        --instance-url "$(SF_LOGIN_URL)" \
        --alias smoketest-org
      rm -f /tmp/smoketest.key
    displayName: Authenticate via JWT Bearer

  - script: |
      ACCESS_TOKEN=$(sf org display --target-org smoketest-org --json | jq -r '.result.accessToken')
      INSTANCE_URL=$(sf org display --target-org smoketest-org --json | jq -r '.result.instanceUrl')
      curl -s -X POST "$INSTANCE_URL/services/apexrest/v1/run" \
        -H "Authorization: Bearer $ACCESS_TOKEN" \
        -H "Content-Type: application/json" \
        -d '{"targetOrg":"production","rollbackPolicyOverride":"RECOMMEND_ONLY"}'
    displayName: Trigger Smoke Tests
```

---

## 9. JWT Bearer Flow Testing

Use the following steps to manually test the complete JWT Bearer flow before wiring it into a CI/CD pipeline.

### 9.1 What the CI/CD platform does internally

When `sf org login jwt` runs, the CLI performs the following steps on your behalf:

1. **Constructs a JWT assertion** with these claims:
   ```
   Header: { "alg": "RS256" }
   Payload:
   {
     "iss": "<consumer_key>",
     "sub": "<salesforce_username>",
     "aud": "https://login.salesforce.com",
     "exp": <unix_timestamp_now + 300>
   }
   ```

2. **Signs the JWT** using the private key (RS256 / SHA-256 with RSA).

3. **POSTs to the Salesforce token endpoint:**
   ```
   POST https://login.salesforce.com/services/oauth2/token
   Content-Type: application/x-www-form-urlencoded

   grant_type=urn%3Aietf%3Aparams%3Aoauth%3Agrant-type%3Ajwt-bearer
   &assertion=<signed_jwt>
   ```

4. **Receives an access token** (valid for up to 1 hour):
   ```json
   {
     "access_token": "00D...",
     "scope": "api refresh_token",
     "instance_url": "https://yourorg.my.salesforce.com",
     "id": "https://login.salesforce.com/id/00D.../005...",
     "token_type": "Bearer"
   }
   ```

### 9.2 Manual curl test

```bash
# Step 1: Generate the JWT assertion (requires jwt-cli or a script)
# This is a simplified example — use sf CLI in practice

CONSUMER_KEY="<your_consumer_key>"
SF_USERNAME="smoketest-cicd@example.com"
LOGIN_URL="https://login.salesforce.com"

sf org login jwt \
  --client-id "$CONSUMER_KEY" \
  --jwt-key-file ./smoketest_cicd.key \
  --username "$SF_USERNAME" \
  --instance-url "$LOGIN_URL" \
  --alias smoketest-test-org

# Step 2: Get the access token from the authenticated session
ACCESS_TOKEN=$(sf org display --target-org smoketest-test-org --json | jq -r '.result.accessToken')
INSTANCE_URL=$(sf org display --target-org smoketest-test-org --json | jq -r '.result.instanceUrl')

# Step 3: Call the Smoke Test health endpoint
curl -s -X GET "$INSTANCE_URL/services/apexrest/v1/health" \
  -H "Authorization: Bearer $ACCESS_TOKEN" \
  -H "Content-Type: application/json"

# Expected success response:
# { "status": "healthy", "timestamp": "2025-01-01T00:00:00Z" }
```

### 9.3 Triggering a smoke test run

```bash
curl -s -X POST "$INSTANCE_URL/services/apexrest/v1/run" \
  -H "Authorization: Bearer $ACCESS_TOKEN" \
  -H "Content-Type: application/json" \
  -d '{
    "targetOrg": "production",
    "rollbackPolicyOverride": "RECOMMEND_ONLY",
    "timeout": 300,
    "securityScoreThreshold": 80
  }'

# Expected success response (202 Accepted):
# {
#   "executionId": "<18-char-id>",
#   "status": "QUEUED",
#   "estimatedDurationSeconds": 120,
#   "webhookCallbackUrl": null
# }
```

---

## 10. Troubleshooting

### error: invalid_grant

**HTTP response:**
```json
{ "error": "invalid_grant", "error_description": "user hasn't approved this consumer" }
```

**Causes and fixes:**
- The integration user does not have `SmokeTest_API_User` or `SmokeTest_Admin` assigned. See [Section 6](#6-permission-set-pre-authorization).
- The username in the JWT `sub` claim does not match any active user in the org. Verify username spelling and user status.
- The JWT `aud` claim is `https://test.salesforce.com` but you are targeting a production org (or vice versa). Match `LOGIN_URL` to the org type.
- The integration user has never logged in to the org. Log in once via browser as that user.

---

### error: invalid_grant (certificate mismatch)

**HTTP response:**
```json
{ "error": "invalid_grant", "error_description": "Failed: : Couldn't validate jwt token." }
```

**Causes and fixes:**
- The private key used to sign the JWT does not match the public certificate uploaded to the Connected App. Regenerate the certificate pair and re-upload.
- The certificate referenced in `SmokeTestConnectedApp.connectedApp-meta.xml` does not match the certificate name in the org. Check Setup > App Manager > View > Certificate field.
- The certificate has expired. Regenerate and re-upload. See [Section 2](#2-certificate-generation).

---

### error: invalid_client

**HTTP response:**
```json
{ "error": "invalid_client", "error_description": "client identifier invalid" }
```

**Causes and fixes:**
- The `SALESFORCE_CONSUMER_KEY` secret contains the wrong value or trailing whitespace. Re-retrieve the consumer key from Setup > App Manager (see [Section 5](#5-consumer-key-retrieval)).
- The Connected App was re-deployed (overwritten) and a new consumer key was generated. Update the secret in your CI/CD platform.

---

### error: user_authentication_failed

**HTTP response:**
```json
{ "error": "user_authentication_failed", "error_description": "user_authentication_failed" }
```

**Causes and fixes:**
- The integration user is inactive or frozen. Navigate to Setup > Users, find the user, and check the **Active** checkbox.
- The user's profile has been changed and no longer permits API access. Ensure the profile includes **API Enabled** system permission.
- The Connected App's `permittedUsers` setting was changed. Verify it remains `AdminApprovedUsersArePreAuthorized`.

---

### error: IP restriction failure (no error body returned, connection refused or 401)

**Symptom:** Token request or API call fails with a 401 or network-level rejection, no JSON error body.

**Causes and fixes:**
- The CI/CD runner's egress IP is not in the Connected App's trusted IP ranges. Retrieve the current egress IP from the CI/CD run logs and add it to Setup > App Manager > [App] > Edit > Trusted IP Ranges.
- GitHub Actions IP ranges change over time. Re-check [https://api.github.com/meta](https://api.github.com/meta) and update the CIDR list.
- For development testing, temporarily set IP Relaxation to **Relax IP restrictions** in Setup > App Manager.

---

### Certificate expiration

**Symptom:** `invalid_grant` errors begin after the certificate's expiration date.

**Steps to renew:**
1. Generate a new certificate pair (see [Section 2](#2-certificate-generation)).
2. Upload the new public certificate to the Connected App (see [Section 3](#3-certificate-upload-to-salesforce)).
3. Update `SALESFORCE_PRIVATE_KEY` in all CI/CD platform secret stores with the new private key.
4. No consumer key rotation is required — the certificate and key are separate from the OAuth client identifier.

---

### Connected App not visible in Setup > App Manager after deployment

**Cause:** The deployment may have completed with partial success, or the Connected App label collides with an existing one.

**Fix:**
```bash
sf project deploy start \
  --source-dir force-app/main/default/connectedApps \
  --target-org <your-org-alias> \
  --verbose
```

Review the deployment output for errors. If an existing Connected App with the same API name (`SmokeTestConnectedApp`) already exists, the deployment updates it — this is expected behavior.
