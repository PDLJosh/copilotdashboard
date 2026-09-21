# Data handling

The export is small, but it is sensitive. This page says exactly what is collected so you can
decide how to protect it and who should see the report.

## What the scripts read

| Script | Reads | From | Writes anything to the tenant? |
| --- | --- | --- | --- |
| `Get-CopilotAuditEvents.ps1` | `CopilotInteraction` audit records | Purview unified audit log, through Exchange Online PowerShell | No |
| `Get-CopilotUsers.ps1` | Users, their managers, their licenses, and the tenant's product list | Microsoft Graph | No |

Both scripts are read-only. They send nothing anywhere except the Microsoft 365 endpoints for
your cloud, and they write only to the output folder.

## What ends up in the files

**`Copilot_Events.csv`** - one row per Copilot interaction:

| Column | Example | Sensitivity |
| --- | --- | --- |
| TimeStamp | `05-Mar-2026 14:07:09` (UTC) | |
| User | `adele@contoso.com` | Personal data |
| App | `Word` | |
| Location | `SharePoint Online` | |
| App context | Address of the document, chat or meeting Copilot was used in | **Can reveal file, site, team and meeting names** |
| Accessed Resources | Names of files Copilot read to answer | **Can reveal file names** |
| Accessed Resource Locations | Addresses of those files | **Can reveal site structure and file names** |
| Action | `Read` | |
| AgentName | Name of a Copilot Studio agent | |

**Prompts and responses are not exported.** The scripts write only the nine columns above. They
never write the text of what a user asked or what Copilot answered, and they do not request it
from any other service.

**`Copilot_Users.csv`** - one row per user: Entra object ID, display name, sign-in name, job
title, department, city, country, usage location, manager's name and sign-in name, and whether
they hold a Copilot license.

**`AuditScriptLog.txt`** - dates and record counts only. No user data.

**Your saved `.pbix`** - a complete copy of both CSV files, readable by anyone who can open it,
whatever the visuals show.

## Recommendations

1. **Keep the output folder private.** Restrict `C:\M365CopilotReport` to the people who run the
   export:
   ```powershell
   icacls C:\M365CopilotReport /inheritance:r /grant:r "$($env:USERNAME):(OI)(CI)F" "Administrators:(OI)(CI)F"
   ```
2. **Keep it where your data is allowed to be.** File names can carry the same sensitivity as
   the files. In GCC High in particular, treat the export as you would the documents it names:
   an authorised workstation, an authorised drive, and no personal cloud storage or email.
3. **Never put it in this repository or a fork, and never attach it to a GitHub issue.** The
   `.gitignore` blocks the usual file names, but it cannot stop an attachment. If you need help
   with a problem, share the error message and the matching `AuditScriptLog.txt` lines, or
   reproduce it with [`examples/New-SampleData.ps1`](../examples/New-SampleData.ps1).
4. **Decide who sees named individuals.** The report shows each person's activity by name.
   Involve HR, your privacy officer, or your works council or union where that is expected, and
   be clear about purpose: measuring adoption and targeting training, not monitoring individuals.
   Use the [anonymised view](power-bi-setup.md#anonymise-employee-names) for wider audiences.
5. **Set a retention period** for the CSV files and old `.pbix` copies, and delete what you no
   longer need. The events file grows without limit; to start over, archive or delete it and the
   next run begins a fresh lookback.
6. **Protect the certificate** if you schedule the export - see [scheduling](scheduling.md).

## Third-party connections

The scripts make none. The Power BI template downloads ten application logos from
`raw.githubusercontent.com` when the report is displayed; no tenant data is included in those
requests. You can remove that dependency - see
[hosting the logos yourself](power-bi-setup.md#hosting-the-app-logos-yourself).
