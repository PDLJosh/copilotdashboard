# Notice and attribution

This project is a derivative work of
**[M365 Copilot And Copilot Chat Audit Power BI Report](https://github.com/BojanBuhac/M365-Copilot-Audit-Report)**
by Bojan Buhac, licensed under the GNU General Public License v3.0. This project is distributed
under the same license; see [LICENSE](LICENSE).

The upstream export script credits the
[Office365itpros](https://github.com/12Knocksinna/Office365itpros) team for the audit-record
parsing approach, and so does this project.

## What comes from upstream

| Item | Status |
| --- | --- |
| `report/M365 Copilot Audit Report.pbit` | **Unmodified.** Byte-for-byte copy of `scripts/M365 Copilot Audit Report.pbit` at upstream commit [`e222d76`](https://github.com/BojanBuhac/M365-Copilot-Audit-Report/commit/e222d763459120f131fcede9ed364c1eb6893933). Its SHA-256 is recorded in [`report/SHA256SUMS`](report/SHA256SUMS). |
| `*/Get-CopilotAuditEvents.ps1` | **Modified.** Derived from upstream `scripts/Audit-Get-Events.ps1`. |
| `*/Get-CopilotUsers.ps1` | **Modified.** Derived from upstream `scripts/Audit-Get-Users.ps1`. |

## Summary of modifications (September 2026)

- Packaged as three cloud editions - Commercial, GCC and GCC High - generated from one set of
  templates so they cannot drift apart.
- GCC High: connects to the `O365USGovGCCHigh` Exchange Online environment and the `USGov`
  Microsoft Graph environment; recognises `teams.microsoft.us` and `sharepoint.us` URLs.
- Settings are parameters (`-OutputFolder` and others) instead of edits to the script body.
- Copilot licenses are detected from the tenant's service plans rather than a single
  hard-coded product ID, so government products and suites that bundle Copilot are recognised.
- Incremental runs re-read a configurable overlap period and skip rows that were already
  exported, so audit records that Microsoft 365 ingests late are not lost and no duplicates
  are written.
- Search windows that reach the 50,000-record limit are split automatically; failed searches
  are retried.
- Timestamps are written with the invariant culture so the export works on non-English
  Windows; files are written as UTF-8 without a byte order mark on both Windows PowerShell 5.1
  and PowerShell 7.
- Optional certificate-based (unattended) sign-in for scheduled runs.
- Modules are no longer installed silently; the manager lookup no longer needs two Graph calls
  per user.
- Loads a matching set of Microsoft Graph module versions, so machines with several versions
  installed no longer fail with "Assembly with same name is already loaded".
- Classifies events by the host applications in Microsoft's audit documentation (Copilot Chat via
  Office.com, the Microsoft 365 app, Edge and Bing; on-canvas and side-pane variants of Word,
  PowerPoint and Outlook; OneNote, SharePoint and others), and logs a per-run summary of how each
  host was mapped.
- Recognises already-exported events by their audit values rather than the whole CSV line, so a
  newer script version that classifies an event differently does not duplicate it.
- Adds -DisableWAM for machines where the Windows account broker crashes PowerShell at sign-in.
- Incremental runs mark the resumed timestamp as UTC. Without this, Exchange Online treated it as
  local time and rejected the next search window on machines outside UTC.
- The users export reports how many users Microsoft Graph returned and how many have a job title,
  and warns when the job-title filter removes everyone.
- Added documentation, fictitious sample data and automated tests.

The CSV column layout is unchanged, so the upstream Power BI template works as-is.

## Trademarks

Microsoft, Microsoft 365, Microsoft 365 Copilot, Power BI, Microsoft Entra, Microsoft Purview,
Exchange, SharePoint, OneDrive and Teams are trademarks of the Microsoft group of companies.
This is a community project. It is not affiliated with, endorsed by, or supported by Microsoft.
