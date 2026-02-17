# Kickstarter: Maester & UTCM Dashboard

A turnkey deployment for running [Maester](https://maester.dev) security posture tests and [Unified Tenant Configuration Management (UTCM)](https://learn.microsoft.com/en-us/graph/unified-tenant-configuration-management-concept-overview) drift detection against your Microsoft 365 tenant — all from a single Azure Web App.

---

## What You Get

| Capability | Description |
|---|---|
| **Maester Test Runs** | Automated daily Pester-based security tests across Entra ID, Exchange Online, Teams, SharePoint, and Compliance |
| **HTML Report Browser** | Calendar-based navigation of full Maester HTML results with side-by-side comparison |
| **UTCM Drift Detection** (BETA) | Continuous monitoring of tenant configuration with severity-scored drift alerts |
| **Baseline Management** | Create, accept, or reject configuration changes against a known-good baseline |
| **Webhook Notifications** | Fire-and-forget HTTP POST events for drift, report completion, monitor deletion, and more |
| **Kanban Board** | Track remediation of failed tests across Backlog / Doing / Done columns |
| **Storage & Log Management** | Built-in cleanup tools, log viewer with severity highlighting, and retention policies |
| **SSO Authentication** | Azure App Service Easy Auth with Entra ID — no anonymous access |

> [!IMPORTANT]
> **UTCM requires additional setup.** Before using Unified Tenant Configuration Management features, you must onboard the UTCM service principal and grant permissions. Use the included `Enable-UTCM.ps1` script or follow the official Microsoft documentation:
> [Set up authentication for UTCM](https://learn.microsoft.com/en-us/graph/utcm-authentication-setup)

---

## Architecture

```text
+--------------------------+       +-------------------------+
|   Azure App Service      |       |   Microsoft Graph API   |
|   (Linux Container)      |<----->|   (Beta)                |
|                          |       +-------------------------+
|  +---------+-----------+ |
|  | Go Web  | PowerShell| |       +-------------------------+
|  | Server  | Runner    | |       |   GHCR Container        |
|  +---------+-----------+ |       |   Registry              |
|  | SQLite  | Cron      | |       +-------------------------+
|  +---------+-----------+ |
+--------------------------+
         |
         v
  Webhook Destinations
  (Teams, Slack, Logic Apps)
```

**Stack:**

- **Backend**: Go (static binary, ~15 MB)
- **Automation**: PowerShell 7 with Az.Accounts, ExchangeOnlineManagement, MicrosoftTeams, Maester, Pester
- **Database**: SQLite for UTCM history and offline access
- **Container**: Alpine Linux with cron scheduling and optional SSH (port 2222)
- **Frontend**: Vanilla JavaScript, HTML templates, CSS variables (light/dark theme)

---

## Prerequisites

Before deploying, you need an **Entra ID App Registration** with a client secret. This is used for Single Sign-On (SSO) so only authenticated users in your tenant can access the dashboard.

### 1. Create an App Registration

1. Go to the [Azure Portal](https://portal.azure.com) > **Microsoft Entra ID** > **App registrations** > **New registration**
2. Set a name (e.g., `Maester Dashboard`)
3. Under **Supported account types**, select **Accounts in this organizational directory only**
4. Leave **Redirect URI** blank for now (you'll add it after deployment)
5. Click **Register**
6. Copy the **Application (client) ID** — you'll need it during deployment

### 2. Create a Client Secret

1. In your new App Registration, go to **Certificates & secrets** > **Client secrets** > **New client secret**
2. Set a description (e.g., `Maester Dashboard SSO`) and an expiry
3. Click **Add**
4. Copy the **Secret value** immediately — it won't be shown again

### 3. Grant User.Read Permission

1. Go to **API permissions** > **Add a permission** > **Microsoft Graph** > **Delegated permissions**
2. Search for and add `User.Read`
3. Click **Grant admin consent** for your tenant

> You'll enter the **Client ID** and **Client Secret** in the deployment wizard below.

---

## Deployment

### Option A: One-Click Deploy

Click the button below to deploy directly from the Azure Portal. The wizard will guide you through selecting a resource group, naming the Web App, and connecting a Service Principal for SSO.

[![Deploy to Azure](https://aka.ms/deploytoazurebutton)](https://portal.azure.com/#create/Microsoft.Template/uri/https%3A%2F%2Fraw.githubusercontent.com%2Ffortytwoservices%2Fkickstarter-maester-and-utcm%2Fmain%2Fazuredeploy.json/createUIDefinitionUri/https%3A%2F%2Fraw.githubusercontent.com%2Ffortytwoservices%2Fkickstarter-maester-and-utcm%2Fmain%2FcreateUiDefinition.json)

After deployment, the outputs will show a **Redirect URI** — add it to your App Registration's authentication settings to finalize SSO:

```
https://<your-web-app>.azurewebsites.net/.auth/login/aad/callback
```

### Option B: Azure CLI

```bash
# Create a resource group
az group create --name "rg-maester-dashboard" --location "norwayeast"

# Deploy the ARM template
az deployment group create \
  --resource-group "rg-maester-dashboard" \
  --template-file "azuredeploy.json" \
  --parameters siteName="maester-dashboard" \
               tenantId="<your-tenant-id>" \
               authClientId="<your-app-client-id>" \
               authClientSecret="<your-client-secret>" \
               location="norwayeast"
```

### What Gets Deployed

| Resource | Type | Details |
|---|---|---|
| App Service Plan | `Microsoft.Web/serverfarms` | B1 Linux (skipped if you select an existing plan) |
| Web App | `Microsoft.Web/sites` | Linux container pulling `ghcr.io/fortytwoservices/maester-dashboard:production` |
| Managed Identity | `Microsoft.ManagedIdentity/userAssignedIdentities` | Used for Microsoft Graph API access |
| Auth Settings | `Microsoft.Web/sites/config` | Entra ID Easy Auth with your Service Principal |

---

## Post-Deployment Setup

### 1. Grant API Permissions

The managed identity needs Microsoft Graph (and optionally Exchange/SharePoint) permissions to run tests and monitor configuration.

**Quick setup** (Graph only — covers Entra ID tests):

```powershell
./scripts/Grant-APIPermissions.ps1 -identityAccountName '<identityName>' -Tenant '<tenantId>'
```

**Full setup** (all workloads):

```powershell
./scripts/Grant-APIPermissions.ps1 -identityAccountName '<identityName>' -Tenant '<tenantId>' -IncludeExchangeOnline -IncludeSharePoint
```

> Requires **Global Administrator**, **Privileged Role Administrator**, or **Cloud Application Administrator** privileges.

### 2. Enable UTCM (Optional)

For configuration drift monitoring, you must first onboard UTCM in the tenant. This provisions the UTCM first-party service principal and grants it permissions to read workload configuration data.

```powershell
./scripts/Enable-UTCM.ps1 -TenantId '<tenantId>'
```

This grants the UTCM service principal (AppId `03b07b79-c5bc-4b5e-9bfa-13acf4a99998`) the following Graph permissions:

- `Directory.Read.All`, `Policy.Read.All`, `Policy.Read.ConditionalAccess`
- `User.Read.All`, `Application.Read.All`, `Group.Read.All`
- `RoleManagement.Read.Directory`, `Policy.Read.AuthenticationMethod`
- `Organization.Read.All`, `SharePointTenantSettings.Read.All`

**Exchange Online** resources require Exchange RBAC roles instead of Graph permissions. After running `Enable-UTCM.ps1`, connect to Exchange Online PowerShell and run:

```powershell
Connect-ExchangeOnline
New-ManagementRoleAssignment -Role 'View-Only Configuration' -App '<utcm-sp-object-id>'
New-ManagementRoleAssignment -Role 'Security Reader' -App '<utcm-sp-object-id>'
```

See [Application access policies in Exchange Online](https://learn.microsoft.com/en-us/exchange/permissions-exo/application-rbac) for details.

### 3. Verify the Schedule

Tests run **daily at 02:00 AM UTC** by default. Adjust from **Settings** > **Schedule** in the dashboard.

### 4. Set Up Monitoring (Optional)

Navigate to **Tenant Config** and run the **Monitoring Wizard** to select which configuration types to monitor and create initial baselines.

---

## Required Permissions

### Microsoft Graph

<details>
<summary><strong>Entra ID / Directory</strong></summary>

- `DeviceManagementConfiguration.Read.All`
- `DeviceManagementManagedDevices.Read.All`
- `Directory.Read.All`
- `DirectoryRecommendations.Read.All`
- `IdentityRiskEvent.Read.All`
- `Policy.Read.All`
- `Policy.Read.ConditionalAccess`
- `PrivilegedAccess.Read.AzureAD`
- `Reports.Read.All`
- `RoleEligibilitySchedule.Read.Directory`
- `RoleManagement.Read.All`
- `SecurityIdentitiesSensors.Read.All`
- `SecurityIdentitiesHealth.Read.All`
- `UserAuthenticationMethod.Read.All`
</details>

<details>
<summary><strong>Microsoft Teams</strong></summary>

- `Team.ReadBasic.All`
- `TeamSettings.Read.All`
- `Channel.ReadBasic.All`
- `ChannelSettings.Read.All`
- `TeamsAppInstallation.ReadForTeam.All`
- `TeamMember.Read.All`
- `Chat.Read.All`
- `OnlineMeetings.Read.All`
- `TeamsTab.Read.All`
</details>

<details>
<summary><strong>Security & Compliance</strong></summary>

- `SecurityEvents.Read.All`
- `ThreatIndicators.Read.All`
- `SecurityActions.Read.All`
- `SecurityAlert.Read.All`
- `AttackSimulation.Read.All`
</details>

<details>
<summary><strong>SharePoint</strong></summary>

- `SharePointTenantSettings.Read.All`
- `Sites.Read.All`
</details>

<details>
<summary><strong>User, Group, and Application</strong></summary>

- `User.Read.All`
- `Group.Read.All`
- `GroupMember.Read.All`
- `Application.Read.All`
- `AuditLog.Read.All`
</details>

### Exchange Online

The managed identity requires one of these Exchange Online roles:

- **View-Only Configuration** or **O365SupportViewConfig**

For Security & Compliance tests, the identity also requires the **Exchange Administrator** or **Compliance Administrator** Entra ID role.

### SharePoint

- `Sites.Read.All` (SharePoint Online API)

---

## Dashboard Pages

| Page | Description |
|---|---|
| **Home** | Overview with version info, update notifications, and quick links |
| **Maester** | Calendar view, embedded HTML reports, side-by-side comparison, on-demand test runs |
| **Tenant Config** (BETA) | UTCM Dashboard, Monitoring, Changes — drift detection and baseline management |
| **Kanban** | Track remediation of failed tests across Backlog/Doing/Done |
| **Logs** | Real-time log viewer with severity highlighting and auto-refresh |
| **Settings** | Schedule, emergency access accounts, default services, storage cleanup, webhooks |
| **Help** | Embedded documentation |

---

## Webhook Notifications

Send HTTP POST events to external endpoints (Teams, Slack, Logic Apps, Power Automate).

| Event Type | Trigger | Payload |
|---|---|---|
| `ReportFinished` | Maester test run completes | Job ID, status, duration, report link |
| `ChangeDetected` | Configuration drift found | Drift ID, monitor ID, severity, summary, resource details |
| `ChangeDecided` | Drift accepted or rejected | Change ID, decision, decided by, comment |
| `BaselineCreated` | New baseline snapshot created | Monitor ID, snapshot details |
| `MonitorHealthChanged` | Monitor health status changes | Monitor ID, old/new health |
| `MonitorDeleted` | A monitor is deleted | Monitor ID, display name, deleted by (UPN), method |
| `TestPing` | Manual test from Settings | Test message with timestamp |

Configure in **Settings** > **Webhook Notifications**. Multiple destinations supported with 3-retry delivery and exponential backoff.

### Example: Azure Logic App

1. Create a Logic App with an **HTTP trigger**
2. Add a **Switch** action on `triggerBody()?['eventType']`
3. Route `ChangeDetected` to a Teams message, `ReportFinished` to an email, etc.
4. Add the Logic App HTTP POST URL in **Settings** > **Webhook Notifications**

---

## Supported UTCM Resource Types

The built-in **Entra CA preset** monitors these resource types:

| Resource Type |
|---|
| `microsoft.entra.conditionalAccessPolicy` |
| `microsoft.entra.namedLocationPolicy` |
| `microsoft.entra.authenticationContextClassReference` |
| `microsoft.entra.authenticationStrengthPolicy` |
| `microsoft.entra.authenticationMethodPolicy` |
| `microsoft.entra.authorizationPolicy` |
| `microsoft.entra.securityDefaults` |
| `microsoft.entra.externalIdentityPolicy` |
| `microsoft.entra.crossTenantAccessPolicy` |
| `microsoft.entra.tenantDetails` |

---

## Environment Variables

| Variable | Required | Description |
|---|---|---|
| `AZURE_TENANT_ID` | Yes | Entra tenant ID |
| `AZURE_CLIENT_ID` | Yes | Client ID of the managed identity (set automatically by ARM template) |

---

## Troubleshooting

| Problem | Solution |
|---|---|
| **Tests skipped for a workload** | Check managed identity permissions. Review **Logs** for connection errors. |
| **Exchange / Compliance tests not running** | Run permissions script with `-IncludeExchangeOnline`. Verify Exchange and Entra ID roles. |
| **Teams tests not running** | Verify Teams Graph permissions. MicrosoftTeams module >= 5.8.1 required. |
| **Graph connection fails** | Graph is required for all tests. Check logs for auth errors. |
| **Tenant Config shows no data** | Enable UTCM in Settings. Run the Monitoring Wizard. Verify ConfigurationMonitoring permissions. |
| **Webhook not firing** | Check Settings > Webhook Notifications — ensure enabled and URL is correct. Review logs for delivery errors. |
| **Update notification won't dismiss** | Clear browser cache or check that the container digest file is writable. |

---

## Repository Contents

```text
kickstarter-maester-and-utcm/
├── azuredeploy.json            # ARM template for Azure deployment
├── createUiDefinition.json     # Azure Portal custom deployment UI
├── scripts/
│   ├── Grant-APIPermissions.ps1  # Grant Maester Graph/Exchange/SharePoint permissions
│   └── Enable-UTCM.ps1          # Onboard UTCM: provision SP + grant workload permissions
├── LICENSE                     # MIT License
└── README.md                   # This file
```

---

## Links

- [Maester Documentation](https://maester.dev)
- [UTCM Concept Overview](https://learn.microsoft.com/en-us/graph/unified-tenant-configuration-management-concept-overview)
- [Fortytwo Services](https://www.fortytwo.io)
- [Report an Issue](https://github.com/fortytwoservices/kickstarter-maester-and-utcm/issues)

---

## License

This project is licensed under the [MIT License](LICENSE).
