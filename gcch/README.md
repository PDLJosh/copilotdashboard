# GCC High edition

For **Microsoft 365 Government GCC High** tenants - sign-in at `login.microsoftonline.us`,
tenant domain ending in `.onmicrosoft.us`.

Not GCC High? Use [`../commercial`](../commercial/README.md) or [`../gcc`](../gcc/README.md).
For DoD, see [cloud differences](../docs/cloud-differences.md#dod).

## What is specific to GCC High

| | GCC High value | Handled by |
| --- | --- | --- |
| Exchange Online PowerShell | `-ExchangeEnvironmentName O365USGovGCCHigh` | Built into `Get-CopilotAuditEvents.ps1` |
| Microsoft Graph | `-Environment USGov` (`graph.microsoft.us`) | Built into `Get-CopilotUsers.ps1` |
| Teams and SharePoint addresses | `teams.microsoft.us`, `*.sharepoint.us` | Recognised when events are classified |
| Copilot license product ID | Not published by Microsoft | Discovered from your tenant's service plans |
| Microsoft Entra admin center | https://entra.microsoft.us | You |
| Microsoft Purview portal | https://purview.microsoft.us | You |
| Power BI service | https://app.high.powerbigov.us | You |

You do not need to edit the scripts.

## Before you start

- [ ] **Power BI Desktop**, current version. In restricted environments install the
      [downloadable installer](https://www.microsoft.com/download/details.aspx?id=58494) rather than the Store app.
- [ ] **PowerShell 7** (recommended) or Windows PowerShell 5.1.
- [ ] PowerShell modules, installed once:
      ```powershell
      Install-Module ExchangeOnlineManagement, Microsoft.Graph.Authentication, Microsoft.Graph.Users, Microsoft.Graph.Identity.DirectoryManagement -Scope CurrentUser
      ```
      If the PowerShell Gallery is not reachable from your network, follow your organisation's
      process for approved modules, or see [offline installation](../docs/troubleshooting.md#the-powershell-gallery-is-blocked).
- [ ] An account with the **View-Only Audit Logs** role in Exchange Online, and permission to read
      users in Entra ID (for example **Global Reader**). Details and the commands to grant them:
      [prerequisites](../docs/prerequisites.md).
- [ ] Auditing is on, and Copilot has been in use long enough to have something to report.

> **Handle the output as you would the source data.** The events file lists the names and
> addresses of documents that Copilot opened for each user. In a GCC High tenant those names
> can themselves be sensitive. Run the scripts on a workstation that is authorised for your
> tenant's data and keep the output there. See [data handling](../docs/data-handling.md).

## Step 1 - Export users

```powershell
cd <path-to>\copilotdashboard\gcch
.\Get-CopilotUsers.ps1
```

A browser window opens at `login.microsoftonline.us`. Sign in. The first time, an administrator
must consent to `User.Read.All` and `Organization.Read.All` for *Microsoft Graph Command Line Tools*.

Expected output:

```
Connected to Microsoft Graph (GCC High).
Copilot product: xxxxxxxx-xxxx-xxxx-xxxx-xxxxxxxxxxxx  <product name>  (discovered)
Processing 1284 users...
Report exported to C:\M365CopilotReport\Copilot_Users.csv
Users exported: 1284. With a Microsoft 365 Copilot license: 310.
```

**Check the `Copilot product` line.** It shows which license the script treated as Microsoft 365
Copilot. If instead you see *"No Microsoft 365 Copilot product was found"*, the script lists the
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

3. Save as a `.pbix` file on an authorised drive, not inside this folder.

More detail, including how to anonymise names: [Power BI setup](../docs/power-bi-setup.md).

### Two things GCC High teams usually ask about

**Does the report call out to the internet?** Only for ten application logos (Word, Excel,
Teams and so on), which the template loads from `raw.githubusercontent.com`. No tenant data is
sent. If that address is blocked, the report still works and the logos appear as broken images.
To remove the dependency, host the logos internally - see
[hosting the logos yourself](../docs/power-bi-setup.md#hosting-the-app-logos-yourself).

**Is the template safe to open?** It is the upstream project's file, unmodified. Verify it before
opening:

```powershell
(Get-FileHash '..\report\M365 Copilot Audit Report.pbit' -Algorithm SHA256).Hash
Get-Content ..\report\SHA256SUMS
```

The template includes six Power BI custom visuals (Chiclet Slicer, Timeline, Radar Chart,
Table Heatmap, KPI Donut Chart, Advanced Toggle Switch). If your Power BI tenant settings block
uncertified custom visuals, those visuals will not render until an administrator allows them.

## Publishing to Power BI (optional)

Sign in to Power BI Desktop with your GCC High account and publish to a workspace at
https://app.high.powerbigov.us. Free licenses do not exist in government clouds; publishers and
viewers need Power BI Pro (or Premium capacity). Because the report reads local files, scheduled
refresh in the service needs an on-premises data gateway registered in your GCC High tenant.
Many teams simply refresh in Desktop and republish.

## What to expect in GCC High data

Copilot features arrive in GCC High later than in commercial tenants. Microsoft's
[service description](https://learn.microsoft.com/office365/servicedescriptions/office-365-platform-service-description/microsoft-365-copilot#feature-availability)
lists current availability. An app with no rows in your report may simply not be available in
GCC High yet - for example, at the time of writing Copilot in Teams and Copilot in SharePoint
were listed as not yet available in GCC High.

## Run it every day without signing in

See [scheduling](../docs/scheduling.md). In GCC High, register the application at
https://entra.microsoft.us and use your `.onmicrosoft.us` domain for `-Organization`:

```powershell
.\Get-CopilotAuditEvents.ps1 -AppId <app-id> -Organization contoso.onmicrosoft.us -CertificateThumbprint <thumbprint>
.\Get-CopilotUsers.ps1      -AppId <app-id> -TenantId     contoso.onmicrosoft.us -CertificateThumbprint <thumbprint>
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
