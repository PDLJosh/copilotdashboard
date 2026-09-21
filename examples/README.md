# Examples

Copy-and-paste commands for common situations. Run them from the folder for your cloud
(`commercial`, `gcc` or `gcch`) unless the example says otherwise. The commands are the same in
every cloud; only the folder changes.

| In this folder | What it is |
| --- | --- |
| [`sample-data/`](sample-data) | Fictitious `Copilot_Events.csv` and `Copilot_Users.csv` - a made-up 31-person "Contoso", about 3,200 events over four months |
| [`New-SampleData.ps1`](New-SampleData.ps1) | The generator for that data. Reads nothing from any tenant. |
| [`Invoke-DailyRefresh.ps1`](Invoke-DailyRefresh.ps1) | Runs both exports unattended; see [scheduling](../docs/scheduling.md) |

## 1. See the report before touching your tenant

Open `report\M365 Copilot Audit Report.pbit` and enter the full paths to the sample files:

| Parameter | Value (adjust to where you unzipped the repository) |
| --- | --- |
| Copilot Log File Path | `C:\Tools\copilotdashboard\examples\sample-data\Copilot_Events.csv` |
| Users Log File Path | `C:\Tools\copilotdashboard\examples\sample-data\Copilot_Users.csv` |
| InteractionDurationSec | `30` |

The committed sample ends on 15 September 2026. For data that ends today - so the report's date
slicers look current - generate your own:

```powershell
.\examples\New-SampleData.ps1 -OutputFolder C:\M365CopilotReport\Sample
```

More days, or a different random organisation:

```powershell
.\examples\New-SampleData.ps1 -OutputFolder C:\M365CopilotReport\Sample -Days 300 -Seed 42
```

This is also the safe way to demonstrate the report, take screenshots, or reproduce a problem
for a GitHub issue without exposing real names.

## 2. First export, default settings

```powershell
.\Get-CopilotUsers.ps1
.\Get-CopilotAuditEvents.ps1
```

Output goes to `C:\M365CopilotReport`.

## 3. A different output folder

```powershell
.\Get-CopilotUsers.ps1      -OutputFolder D:\Reports\Copilot
.\Get-CopilotAuditEvents.ps1 -OutputFolder D:\Reports\Copilot
```

Use the same folder for both, and the same folder every time - the events export finds its
previous file there and continues from it.

## 4. A faster first run when audit records are kept for 180 days

```powershell
.\Get-CopilotAuditEvents.ps1 -InitialLookbackDays 180
```

Or a quick trial of the last two weeks:

```powershell
.\Get-CopilotAuditEvents.ps1 -OutputFolder C:\M365CopilotReport\Trial -InitialLookbackDays 14
```

## 5. The routine refresh

Exactly the same commands as the first export. The events script reports what it did:

```
Existing export found. Newest event: 2026-09-20 21:14:52Z. Resuming from 2026-09-19 21:14:52Z.
...
Script complete! Retrieved 1874 audit records between ... New rows written: 912. Already exported (skipped): 962.
```

"Already exported" rows are the previous 24 hours being re-read to catch audit records that
arrived late. That is expected.

## 6. Pre-fill the sign-in name

```powershell
.\Get-CopilotAuditEvents.ps1 -UserPrincipalName admin@contoso.com
```

## 7. Reuse a connection you already have

Useful when you run several tools in one session, or must sign in a particular way:

```powershell
# GCC High shown. For Commercial and GCC, leave out the two environment parameters.
Connect-ExchangeOnline -ExchangeEnvironmentName O365USGovGCCHigh
Connect-MgGraph -Environment USGov -Scopes User.Read.All, Organization.Read.All

.\Get-CopilotUsers.ps1      -UseExistingSession
.\Get-CopilotAuditEvents.ps1 -UseExistingSession
```

With `-UseExistingSession` the scripts neither connect nor disconnect.

## 8. The tenant's Copilot license was not recognised

```powershell
.\Get-CopilotUsers.ps1 -CopilotSkuId xxxxxxxx-xxxx-xxxx-xxxx-xxxxxxxxxxxx
```

Several IDs are allowed: `-CopilotSkuId id1, id2`. To count **only** the IDs you give and ignore
automatic discovery:

```powershell
.\Get-CopilotUsers.ps1 -DisableSkuDiscovery -CopilotSkuId xxxxxxxx-xxxx-xxxx-xxxx-xxxxxxxxxxxx
```

## 9. Include accounts that have no job title

```powershell
.\Get-CopilotUsers.ps1 -IncludeUsersWithoutJobTitle
```

## 10. Very busy tenant

Nothing to do - the search window is reduced automatically when needed. To start smaller and
avoid the retries:

```powershell
.\Get-CopilotAuditEvents.ps1 -IntervalMinutes 240
```

## 11. Unattended, from Task Scheduler

```powershell
.\examples\Invoke-DailyRefresh.ps1 -Cloud gcc -AppId <app-id> -Tenant contoso.onmicrosoft.com -CertificateThumbprint <thumbprint>
```

Set-up steps: [scheduling](../docs/scheduling.md).

## 12. Check the scripts yourself

No tenant needed; takes a few seconds:

```powershell
Install-Module Pester -MinimumVersion 5.0 -Scope CurrentUser   # once
Invoke-Pester .\tests
```
