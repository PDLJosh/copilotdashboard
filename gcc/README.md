# GCC edition

For **Microsoft 365 Government Community Cloud (GCC)** tenants - government "G" plans (G3, G5),
sign-in at `login.microsoftonline.com`, tenant domain ending in `.onmicrosoft.com`.

If your tenant domain ends in `.onmicrosoft.us`, you are in GCC High: use [`../gcch`](../gcch/README.md).
For commercial tenants use [`../commercial`](../commercial/README.md).

## What is specific to GCC

GCC runs on the same Exchange Online and Microsoft Graph endpoints as commercial Microsoft 365,
so the connection is the same. Two things differ:

| | GCC value | Handled by |
| --- | --- | --- |
| Copilot license product ID | Different from commercial (`a920a45e-67da-4a1a-b408-460d7a2453ce`, community-reported) | Built in, **and** discovered from your tenant's service plans |
| Power BI service | https://app.powerbigov.us | You |
| Exchange Online PowerShell | Worldwide (no environment parameter) | Built into `Get-CopilotAuditEvents.ps1` |
| Microsoft Graph | Worldwide (`graph.microsoft.com`) | Built into `Get-CopilotUsers.ps1` |
| Microsoft Entra admin center | https://entra.microsoft.com | You |
| Microsoft Purview portal | https://purview.microsoft.com | You |

The license ID is the reason the commercial script produces a report with **zero licensed users**
in a GCC tenant. This edition fixes that. You do not need to edit the scripts.

## Before you start

- [ ] **Power BI Desktop**, current version.
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
> Keep the output on a workstation and drive that are approved for your agency's data.
> See [data handling](../docs/data-handling.md).

## Step 1 - Export users

```powershell
cd <path-to>\copilotdashboard\gcc
.\Get-CopilotUsers.ps1
```

Sign in when the browser opens. The first time, an administrator must consent to `User.Read.All`
and `Organization.Read.All` for *Microsoft Graph Command Line Tools*.

Expected output:

```
Connected to Microsoft Graph (GCC).
Copilot product: a920a45e-67da-4a1a-b408-460d7a2453ce  <product name>  (known ID)
Read 2250 users from Entra ID; 2250 have a job title and will be exported.
Report exported to C:\M365CopilotReport\Copilot_Users.csv
Users exported: 2250. With a Microsoft 365 Copilot license: 480.
```

**Check the `Copilot product` line.** It shows which license the script treated as Microsoft 365
Copilot, and whether it matched the built-in ID (`known ID`) or was found from its service plans
(`discovered`). If you see *"No Microsoft 365 Copilot product was found"*, the script lists the
products in your tenant that mention Copilot; run it again with the right one:

```powershell
.\Get-CopilotUsers.ps1 -CopilotSkuId xxxxxxxx-xxxx-xxxx-xxxx-xxxxxxxxxxxx
```

## Step 2 - Export Copilot events

```powershell
.\Get-CopilotAuditEvents.ps1
```

Sign in when prompted. The script searches the audit log one day at a time, starting 365 days
back. If your tenant keeps audit records for 180 days, save time on the first run:

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

3. Save as a `.pbix` file on an approved drive, not inside this folder.

More detail, including how to anonymise names: [Power BI setup](../docs/power-bi-setup.md).

The template loads ten application logos from `raw.githubusercontent.com`. No tenant data is
sent. If your network blocks that address the report still works; see
[hosting the logos yourself](../docs/power-bi-setup.md#hosting-the-app-logos-yourself).

## Publishing to Power BI (optional)

Sign in to Power BI Desktop with your GCC account and publish to a workspace at
https://app.powerbigov.us. Free licenses do not exist in government clouds; publishers and
viewers need Power BI Pro (or Premium capacity). Because the report reads local files, scheduled
refresh in the service needs an on-premises data gateway. Many teams simply refresh in Desktop
and republish.

## What to expect in GCC data

Some Copilot features arrive in GCC later than in commercial tenants. Microsoft's
[service description](https://learn.microsoft.com/office365/servicedescriptions/office-365-platform-service-description/microsoft-365-copilot#feature-availability)
lists current availability. An app with no rows in your report may not be available in GCC yet.

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
