# Integration User Setup Guide: SmokeTest Service Account

This guide covers the creation and configuration of the dedicated **SmokeTest Integration** service account user that the CI/CD pipeline uses for Tooling API SecurityHealthCheck queries and system-level smoke test operations.

> **Security note:** The integration user is read-only for all standard business objects. It can create and read `SmokeTestExecution__c` and `SmokeTestResult__c` records (via `SmokeTest_API_User` permission set) but cannot modify any business data.

---

## Table of Contents

1. [License Requirements](#1-license-requirements)
2. [Automated Setup via Post-Install Handler](#2-automated-setup-via-post-install-handler)
3. [Manual User Creation via Setup UI](#3-manual-user-creation-via-setup-ui)
4. [Permission Set Assignment Verification](#4-permission-set-assignment-verification)
5. [Tooling API Access Verification](#5-tooling-api-access-verification)
6. [Troubleshooting](#6-troubleshooting)

---

## 1. License Requirements

The integration user requires one of the following Salesforce license types:

### Option A: Standard Salesforce License (default)

- Available in all org editions.
- Consumes one licensed user seat.
- The `SmokeTest_Integration_Profile` is configured with `userLicense: Salesforce`.

### Option B: Salesforce Integration License (preferred for production)

- Dedicated integration license — does **not** consume a named-user seat.
- Available in orgs with the "Salesforce Integration" add-on.
- Costs less than a full Salesforce license and is designed for service-account API use cases.
- To check availability: Setup > Company Information > User Licenses.
- If using this license type, change the profile's `<userLicense>` element to `Salesforce Integration` and redeploy.

### Why ViewSetup is required

The `View Setup and Configuration` permission (`ViewSetup`) enables the integration user to execute Tooling API queries, specifically against the `SecurityHealthCheck` object. Without this permission, the Tooling API call returns `INSUFFICIENT_ACCESS`. This is the **minimum** permission needed — the user does not require `ManageUsers`, `ModifyAllData`, or any other administrative permission.

---

## 2. Automated Setup via Post-Install Handler

When the SmokeTestCenter package is installed or upgraded, `SmokeTestPostInstallHandler` runs automatically and:

1. Constructs a username: `smoketest-integration@<orgdomain>.com` (or `.sandboxname` suffix in sandboxes).
2. Checks if the user already exists (idempotent).
3. Creates the user with `SmokeTest_Integration_Profile`.
4. Assigns the `SmokeTest_API_User` permission set.

### Manual invocation (non-packaged deployments / scratch orgs)

For deployments that do not go through the package installation path, run the handler via anonymous Apex in the target org:

```apex
new SmokeTestPostInstallHandler().onInstall(null);
```

Or using the Salesforce CLI:

```bash
sf apex run \
  --file scripts/verify-integration-user.apex \
  --target-org <your-org-alias>
```

### What to do if the handler fails

If the handler logs an error (visible in Setup > Debug Logs), follow the [Manual User Creation](#3-manual-user-creation-via-setup-ui) steps below. Common failure reasons:
- The `SmokeTest_Integration_Profile` has not been deployed yet — deploy the profile first, then re-run the handler.
- License limit exceeded — see [Option B](#option-b-salesforce-integration-license-preferred-for-production) or free an existing license.

---

## 3. Manual User Creation via Setup UI

Use these steps when the post-install handler cannot run or when you need to create the user in a specific sandbox.

### Step 1: Verify the profile is deployed

Navigate to **Setup > Profiles**. Confirm `SmokeTest_Integration_Profile` appears in the list. If it does not, deploy the package metadata first:

```bash
sf project deploy start --target-org <your-org-alias>
```

### Step 2: Create the integration user

1. Navigate to **Setup > Users > Users**.
2. Click **New User**.
3. Fill in the following fields:

| Field | Value |
|---|---|
| First Name | `SmokeTest` |
| Last Name | `Integration` |
| Alias | `smkint` |
| Email | `smoketest-integration@<your-domain>.com` |
| Username | `smoketest-integration@<your-org-domain>.com` |
| Profile | `SmokeTest_Integration_Profile` |
| User License | `Salesforce` (or `Salesforce Integration` if available) |
| Time Zone | Your org's time zone |
| Locale | `English (United States)` |
| Email Encoding | `Unicode (UTF-8)` |
| Language | `English` |
| Active | ✓ Checked |

4. Click **Save**.

> **Username uniqueness:** Salesforce usernames must be globally unique across all orgs. For sandboxes, append the sandbox name: `smoketest-integration@<domain>.com.<sandboxname>`.

### Step 3: Disable password login (OAuth-only access)

The integration user should authenticate exclusively via OAuth 2.0 JWT Bearer flow (see `docs/connected-app-setup.md`). To prevent password login:

1. Open the user record.
2. Click **Reset Password** to force a password reset email — do not use this email.
3. Do **not** store or share the user's password. The user will authenticate via JWT Bearer only.

Optionally, in orgs with SSO configured, you can set the Login Policy to **Single Sign-On Required** for this user.

---

## 4. Permission Set Assignment Verification

### Assign via CLI (recommended for scripted environments)

```bash
sf org assign permset \
  --name SmokeTest_API_User \
  --on-behalf-of smoketest-integration@<your-org-domain>.com \
  --target-org <your-org-alias>
```

### Assign via Setup UI

1. Navigate to **Setup > Users**.
2. Click the integration user's name.
3. Scroll to **Permission Set Assignments** and click **Edit Assignments**.
4. Move **SmokeTest API User** from Available to Enabled.
5. Click **Save**.

### Verify the assignment via SOQL

```bash
sf data query \
  --query "SELECT Assignee.Username, PermissionSet.Name FROM PermissionSetAssignment WHERE Assignee.Username = 'smoketest-integration@<domain>.com' AND PermissionSet.Name = 'SmokeTest_API_User'" \
  --target-org <your-org-alias>
```

Expected output: one row showing the username and `SmokeTest_API_User`.

---

## 5. Tooling API Access Verification

### Automated verification script

Run `scripts/verify-integration-user.apex` as an anonymous Apex execution in the scratch org. This script:
1. Queries for the integration user.
2. Confirms `SmokeTest_API_User` is assigned.
3. Makes a Tooling API HTTP callout to `SecurityHealthCheck` using the user's session.
4. Outputs the health check score.

```bash
sf apex run \
  --file scripts/verify-integration-user.apex \
  --target-org <your-org-alias>
```

### Manual Tooling API verification via curl

After obtaining an access token for the integration user (via JWT Bearer flow — see `docs/connected-app-setup.md`):

```bash
ACCESS_TOKEN="<integration_user_access_token>"
INSTANCE_URL="https://yourorg.my.salesforce.com"

curl -s -G "$INSTANCE_URL/services/data/v60.0/tooling/query/" \
  --data-urlencode "q=SELECT Id, Score FROM SecurityHealthCheck" \
  -H "Authorization: Bearer $ACCESS_TOKEN" \
  -H "Content-Type: application/json"
```

**Expected success response:**
```json
{
  "size": 1,
  "totalSize": 1,
  "done": true,
  "queryLocator": null,
  "entityTypeName": "SecurityHealthCheck",
  "records": [
    {
      "attributes": { "type": "SecurityHealthCheck" },
      "Id": "...",
      "Score": 85
    }
  ]
}
```

**Expected failure (missing ViewSetup):**
```json
{
  "errorCode": "INSUFFICIENT_ACCESS",
  "message": "You do not have the level of access necessary to perform the operation you requested."
}
```

If you see the failure response, verify that `ViewSetup` is enabled on the `SmokeTest_Integration_Profile` (Setup > Profiles > SmokeTest Integration Profile > System Permissions > View Setup and Configuration).

---

## 6. Troubleshooting

### Integration user not created after post-install handler ran

**Check the debug logs:** Setup > Debug Logs. Look for entries from `SmokeTestPostInstallHandler`. Common error messages:

| Log message | Cause | Fix |
|---|---|---|
| `Profile "SmokeTest_Integration_Profile" not found` | Profile not deployed | Deploy package metadata before handler |
| `License limit exceeded` | No free Salesforce licenses | Free a license or use Salesforce Integration license |
| `Duplicate username` | User already exists globally | No action needed — user is present |

### ViewSetup permission not working

Verify the profile was deployed successfully and the permission is enabled:

```bash
sf data query \
  --query "SELECT Id, PermissionsViewSetup, PermissionsApiEnabled FROM PermissionSet WHERE Profile.Name = 'SmokeTest_Integration_Profile' AND IsOwnedByProfile = true" \
  --target-org <your-org-alias>
```

Both `PermissionsViewSetup` and `PermissionsApiEnabled` must be `true`.

### Tooling API returns INSUFFICIENT_ACCESS

1. Confirm the running user is the integration user (not an admin running under a different context).
2. Confirm `ViewSetup` is enabled on the profile (see above).
3. Confirm the access token is for the integration user — decode the JWT and check the `sub` claim.

### DUPLICATE_USERNAME error in post-install handler

The username `smoketest-integration@<domain>.com` exists in another Salesforce org globally. The handler skips creation and logs a warning. If the existing user is in a different org and this org also needs the integration user, the handler must be manually invoked with a different username. Modify `USERNAME_LOCAL_PART` in a local override or create the user manually with a unique username suffix.

### Integration user cannot call the smoke test REST API

Ensure the Connected App (`SmokeTestConnectedApp`) has the `SmokeTest_API_User` permission set in its pre-authorized users list (see `docs/connected-app-setup.md`). The user must have been active and logged in at least once for JWT Bearer flow to work.

### Integration user sandbox username

In sandbox environments, Salesforce requires usernames to be globally unique. The post-install handler automatically appends the sandbox name suffix based on the current admin user's username pattern. If the handler does not detect the suffix correctly (e.g., non-standard username pattern), create the user manually with the convention: `smoketest-integration@<domain>.com.<sandboxname>`.
