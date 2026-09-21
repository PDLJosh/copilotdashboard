# Microsoft 365 Copilot Usage Dashboard - Commercial, GCC and GCC High

See who is using Microsoft 365 Copilot, in which apps, how often, and how adoption is trending
across departments and managers - in a Power BI report that runs entirely on your own PC from
data in your own tenant.

Two PowerShell scripts export the data to CSV files. A Power BI template turns those files into
the report. Nothing is sent to a third-party service.

```
 Purview unified audit log --Get-CopilotAuditEvents.ps1--> Copilot_Events.csv --+
                                                                                +--> M365 Copilot Audit Report.pbit --> your report
 Entra ID users + licenses --Get-CopilotUsers.ps1--------> Copilot_Users.csv --+
```

This repository packages the community
[M365 Copilot Audit Report](https://github.com/BojanBuhac/M365-Copilot-Audit-Report) by Bojan Buhac
for three Microsoft 365 clouds, with the correct endpoints and license detection for each.

## Pick your cloud

| Your tenant | Use this folder | Exchange Online | Microsoft Graph | Power BI service |
| --- | --- | --- | --- | --- |
| Microsoft 365 commercial / worldwide | [`commercial/`](commercial/README.md) | worldwide | worldwide | app.powerbi.com |
| Microsoft 365 **GCC** | [`gcc/`](gcc/README.md) | worldwide | worldwide | app.powerbigov.us |
| Microsoft 365 **GCC High** | [`gcch/`](gcch/README.md) | `O365USGovGCCHigh` | `USGov` | app.high.powerbigov.us |

Not sure which you have? If your users sign in at `login.microsoftonline.us` and your tenant
domain ends in `.onmicrosoft.us`, you are in GCC High. GCC tenants use the same sign-in and
`.onmicrosoft.com` domains as commercial tenants but are licensed with "G" plans (G3, G5).
See [docs/cloud-differences.md](docs/cloud-differences.md). DoD tenants are covered there too.

## Quick start

You need Power BI Desktop, PowerShell, and an account that can search the audit log and read
users. The full list is in [docs/prerequisites.md](docs/prerequisites.md).

1. **Download** this repository (green **Code** button > **Download ZIP**) and unzip it.
2. **Open PowerShell** in the folder for your cloud, for example `gcch`.
3. **Export the users**:
   ```powershell
   .\Get-CopilotUsers.ps1
   ```
4. **Export the Copilot events**. The first run can take a while; later runs only fetch what is new:
   ```powershell
   .\Get-CopilotAuditEvents.ps1
   ```
5. **Open** `report\M365 Copilot Audit Report.pbit` in Power BI Desktop and enter:

   | Parameter | Value |
   | --- | --- |
   | Copilot Log File Path | `C:\M365CopilotReport\Copilot_Events.csv` |
   | Users Log File Path | `C:\M365CopilotReport\Copilot_Users.csv` |
   | InteractionDurationSec | `30` |

   Select **Load**, then save the report as a `.pbix` file **outside this folder**.

To refresh the report later, run the two scripts again and select **Refresh** in Power BI Desktop.
The step-by-step guide for your cloud is in its folder's README.

> If PowerShell says the script "is not digitally signed", the files were marked as downloaded
> from the internet. Review them, then run `Get-ChildItem -Recurse *.ps1 | Unblock-File`.

### Try it first with made-up data

You can see the report before touching your tenant. Open the template and point the two file
parameters at [`examples/sample-data`](examples/sample-data) - a fictitious 31-person "Contoso"
with four months of activity. See [examples/README.md](examples/README.md).

## What the report shows

Overall usage, agent usage, organisation comparison and decomposition, impact (time spent),
adoption, and trends, with slicers for period, application, employee, position and department,
and an option to anonymise employee names. Screenshots are in the
[upstream project's README](https://github.com/BojanBuhac/M365-Copilot-Audit-Report#readme).

Users without a Copilot license who use Copilot Chat are included, and the organisation views
use each user's manager from Entra ID.

## Documentation

| Guide | What it covers |
| --- | --- |
| [Prerequisites](docs/prerequisites.md) | Roles, modules, licenses and how to check that auditing is on |
| [Power BI setup](docs/power-bi-setup.md) | Loading the template, anonymising names, publishing, hosting the app logos yourself |
| [Scheduling](docs/scheduling.md) | Unattended daily exports with certificate sign-in and Task Scheduler |
| [Cloud differences](docs/cloud-differences.md) | Every value that differs between Commercial, GCC, GCC High and DoD |
| [Data handling](docs/data-handling.md) | What the CSV files contain and how to protect them |
| [Troubleshooting](docs/troubleshooting.md) | Common errors and fixes |
| [Examples](examples/README.md) | Copy-and-paste commands and sample data |

## What is different from the upstream project

The Power BI template is the upstream file, unmodified. The scripts were reworked:

- **Three cloud editions** with the right endpoints built in - nothing to edit before running.
- **License detection that works in government clouds.** Upstream matches one commercial product
  ID. These scripts find any product in your tenant that contains a Microsoft 365 Copilot
  service plan, which covers government products and suites that bundle Copilot.
- **No lost or duplicated events.** Audit records can take up to 24 hours to become searchable.
  Incremental runs re-read the previous 24 hours and skip rows that were already exported.
- **Large tenants handled automatically.** A search window that reaches the 50,000-record limit
  is split; failed searches are retried.
- **Works on non-English Windows** and on both Windows PowerShell 5.1 and PowerShell 7.
- **Parameters instead of edits**, optional unattended sign-in, and no silent module installs.

The full list is in [NOTICE.md](NOTICE.md).

## How this was verified

Stated plainly, so you know what you are relying on:

- **Verified by automated tests** (`Invoke-Pester ./tests`, no tenant required): event
  classification, the CSV layout the template expects, incremental and late-arriving events,
  de-duplication, paging, window splitting, retries, license detection, manager lookup, and that
  the installed Exchange Online and Microsoft Graph modules accept the GCC High parameters.
  The scripts were also run under Windows PowerShell 5.1.
- **Verified against Microsoft documentation**: every cloud endpoint, environment name and
  portal address. Sources are listed in [docs/cloud-differences.md](docs/cloud-differences.md).
- **Not verified**: the scripts have not been run by the maintainer against a live tenant in
  every cloud. The GCC Copilot product ID is community-reported and no GCC High product ID is
  published, which is why license detection does not depend on them. If something does not
  work in your tenant, please open an issue.

## Repository layout

```
commercial/  gcc/  gcch/   Ready-to-run scripts and a guide for each cloud (generated - do not edit)
report/                    The Power BI template and its checksum
docs/                      Guides
examples/                  Sample data, its generator, and a daily-refresh wrapper
src/                       Script templates and cloud profiles (edit these)
tools/                     Build-CloudScripts.ps1 - regenerates the three editions from src/
tests/                     Pester tests
```

Contributors: edit `src/`, run `.\tools\Build-CloudScripts.ps1`, then `Invoke-Pester .\tests`.

## Keep tenant data out of this repository

The exported CSV files contain user names, sign-in names and the names and addresses of files
Copilot touched. A saved `.pbix` contains a copy of all of it. **Do not commit them, attach them
to issues, or store them in a fork.** The default output folder is outside the repository and
`.gitignore` blocks the usual file names as a safety net. See [docs/data-handling.md](docs/data-handling.md).

## License and credits

GPL-3.0. Derived from [BojanBuhac/M365-Copilot-Audit-Report](https://github.com/BojanBuhac/M365-Copilot-Audit-Report),
which credits the [Office365itpros](https://github.com/12Knocksinna/Office365itpros) team.
See [NOTICE.md](NOTICE.md) and [LICENSE](LICENSE).

This is a community project provided as-is, without warranty. It is not affiliated with,
endorsed by, or supported by Microsoft.
