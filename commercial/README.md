# Commercial edition

For **Microsoft 365 commercial (worldwide)** tenants - Business and Enterprise plans,
sign-in at `login.microsoftonline.com`.

Government tenant? Use [`../gcc`](../gcc/README.md) or [`../gcch`](../gcch/README.md).

## What this edition connects to

| | Value | Handled by |
| --- | --- | --- |
| Exchange Online PowerShell | Worldwide (no environment parameter) | Built into `Get-CopilotAuditEvents.ps1` |
| Microsoft Graph | Worldwide (`graph.microsoft.com`) | Built into `Get-CopilotUsers.ps1` |
| Copilot license product ID | `639dec6b-bb19-468b-871c-c5c441c4b0cb` (Microsoft_365_Copilot) | Built in, **and** discovered from your tenant's service plans |
| Microsoft Entra admin center | https://entra.microsoft.com | You |
| Microsoft Purview portal | https://purview.microsoft.com | You |
| Power BI service | https://app.powerbi.com | You |

You do not need to edit the scripts.

## Before you start

- [ ] **Power BI Desktop**, current version ([Microsoft Store](https://aka.ms/pbidesktopstore)).
- [ ] **PowerShell 7** (recommended) or Windows PowerShell 5.1.
- [ ] PowerShell modules, installed once:
      ```powershell
      Install-Module ExchangeOnlineManagement, Microsoft.Graph.Authentication, Microsoft.Graph.Users, Microsoft.Graph.Identity.DirectoryManagement -Scope CurrentUser
      ```
- [ ] An account with the **View-Only Audit Logs** role in Exchange Online, and permission to read
      users in Entra ID (for example **Global Reader**). Details and the commands to grant them:
      [prerequisites](../docs/prerequisites.md).
- [ ] Auditing is on, and Copilot has been in use long enough to have something to report.

> The events file lists the names and addresses of documents that Copilot opened for each user.
> Treat the output as confidential. See [data handling](../docs/data-handling.md).

## Step 1 - Export users

```powershell
cd <path-to>\copilotdashboard\commercial
.\Get-CopilotUsers.ps1
```

Sign in when the browser opens. The first time, an administrator must consent to `User.Read.All`
and `Organization.Read.All` for *Microsoft Graph Command Line Tools*.

Expected output:

```
Connected to Microsoft Graph (Commercial).
Copilot product: 639dec6b-bb19-468b-871c-c5c441c4b0cb  Microsoft_365_Copilot  (known ID)
Read 5120 users from Entra ID; 5120 have a job title and will be exported.
Report exported to C:\M365CopilotReport\Copilot_Users.csv
Users exported: 5120. With a Microsoft 365 Copilot license: 900.
```

**Check the `Copilot product` lines.** They show which licenses the script treated as Microsoft 365
Copilot. Products found from their service plans are marked `discovered` - this is how suites that
bundle Copilot, education and other variants are picked up. If a product is missing, add it:

```powershell
.\Get-CopilotUsers.ps1 -CopilotSkuId xxxxxxxx-xxxx-xxxx-xxxx-xxxxxxxxxxxx
```

## Step 2 - Export Copilot events

```powershell
.\Get-CopilotAuditEvents.ps1
```

Sign in when prompted. The script searches the audit log one day at a time, starting 365 days
back. If your tenant keeps audit records for 180 days (Audit Standard), save time on the first run:

```powershell
.\Get-CopilotAuditEvents.ps1 -InitialLookbackDays 180
```

When it finishes you have `C:\M365CopilotReport\Copilot_Events.csv`. Run the same command again
whenever you want to update the data; it continues from where it stopped. Progress and any
problems are recorded in `C:\M365CopilotReport\AuditScriptLog.txt`.

## Step 3 - Build the report

1. Open `..\report\M365 Copilot Audit Report.pbit` in Power BI Desktop.
2. Enter the parameters and select **Load**:

   | Parameter | Value |
   | --- | --- |
   | Copilot Log File Path | `C:\M365CopilotReport\Copilot_Events.csv` |
   | Users Log File Path | `C:\M365CopilotReport\Copilot_Users.csv` |
   | InteractionDurationSec | `30` |

3. Save as a `.pbix` file, not inside this folder.

More detail, including how to anonymise names: [Power BI setup](../docs/power-bi-setup.md).

## Publishing to Power BI (optional)

Publish from Power BI Desktop to a workspace at https://app.powerbi.com. Because the report reads
local files, scheduled refresh in the service needs an on-premises data gateway. Many teams
simply refresh in Desktop and republish.

## Run it every day without signing in

See [scheduling](../docs/scheduling.md):

```powershell
.\Get-CopilotAuditEvents.ps1 -AppId <app-id> -Organization contoso.onmicrosoft.com -CertificateThumbprint <thumbprint>
.\Get-CopilotUsers.ps1      -AppId <app-id> -TenantId     contoso.onmicrosoft.com -CertificateThumbprint <thumbprint>
```

## All parameters

```powershell
Get-Help .\Get-CopilotAuditEvents.ps1 -Full
Get-Help .\Get-CopilotUsers.ps1 -Full
```

Something not working? [Troubleshooting](../docs/troubleshooting.md).

---
*The two scripts in this folder are generated from [`../src`](../src). To change them, edit the
templates there and run `tools\Build-CloudScripts.ps1`.*
