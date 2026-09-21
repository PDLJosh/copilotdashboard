# Prerequisites

The same for every cloud unless noted. Portal addresses for each cloud are in
[cloud-differences.md](cloud-differences.md).

## Software on the PC that runs the export

| Requirement | Notes |
| --- | --- |
| Windows 10/11 or Windows Server | Power BI Desktop is Windows-only. |
| Power BI Desktop | Keep it current; the template uses recent features. |
| PowerShell 7 (recommended) or Windows PowerShell 5.1 | Both are tested. |
| `ExchangeOnlineManagement` module | For the audit export. |
| `Microsoft.Graph.Authentication`, `Microsoft.Graph.Users`, `Microsoft.Graph.Identity.DirectoryManagement` | For the users export. You do **not** need the full `Microsoft.Graph` bundle. |

Install the modules once:

```powershell
Install-Module ExchangeOnlineManagement, Microsoft.Graph.Authentication, Microsoft.Graph.Users, Microsoft.Graph.Identity.DirectoryManagement -Scope CurrentUser
```

The scripts never install anything unless you add `-InstallMissingModules`.

If scripts are blocked from running, allow locally reviewed scripts for your account:

```powershell
Set-ExecutionPolicy RemoteSigned -Scope CurrentUser
Get-ChildItem -Recurse *.ps1 | Unblock-File      # run in the unzipped folder, after reviewing the files
```

## In the tenant

### 1. Auditing is turned on

It is on by default for enterprise and government tenants. To check, connect to Exchange Online
PowerShell and run:

```powershell
Get-AdminAuditLogConfig | Format-List UnifiedAuditLogIngestionEnabled
```

`True` means audit records are being collected. If it is `False`, nothing has been recorded and
there is nothing to export until an administrator
[turns auditing on](https://learn.microsoft.com/purview/audit-log-enable-disable).

### 2. How far back your data goes

| Licence of the user who performed the activity | Audit records kept for |
| --- | --- |
| Audit (Standard) - most E3/G3 plans | 180 days |
| Audit (Premium) - E5/G5 or the compliance add-on | 1 year |

The first export looks back 365 days by default. Use `-InitialLookbackDays 180` to skip searching
a period that holds no data. **Run the export at least once within your retention period**: once
Microsoft 365 ages a record out of the audit log, it cannot be recovered, but rows already in
your CSV stay there.

### 3. Permission to search the audit log (for `Get-CopilotAuditEvents.ps1`)

The script uses the `Search-UnifiedAuditLog` cmdlet, which is an Exchange Online cmdlet. The
account needs the **View-Only Audit Logs** (or **Audit Logs**) role **in Exchange Online**.

> Being a member of *Audit Reader* in the Microsoft Purview portal lets you search in the portal,
> but the PowerShell cmdlet checks Exchange Online roles. This is the most common cause of
> "`Search-UnifiedAuditLog` is not recognized".

The least-privilege way to grant it - run once by an Exchange administrator, in Exchange Online
PowerShell:

```powershell
New-RoleGroup -Name "Copilot Audit Export" -Roles "View-Only Audit Logs" -Members adele@contoso.com
```

To add someone later:

```powershell
Add-RoleGroupMember -Identity "Copilot Audit Export" -Member alex@contoso.com
```

Alternatives that also work, but grant much more: the *Compliance Management* or *Organization
Management* role groups in Exchange Online, or the *Compliance Administrator* or *Global
Administrator* Entra roles. Role changes can take up to an hour to apply; sign out and back in.

### 4. Permission to read users and licenses (for `Get-CopilotUsers.ps1`)

The script signs in to Microsoft Graph with these delegated permissions:

| Permission | Why |
| --- | --- |
| `User.Read.All` | Name, job title, department, location, assigned licenses and manager of every user |
| `Organization.Read.All` | The list of products (SKUs) in the tenant, to find the ones that include Copilot |

- **Consent:** the first time anyone in the tenant uses these permissions with *Microsoft Graph
  Command Line Tools*, an administrator who can grant consent (Privileged Role Administrator,
  Cloud Application Administrator or Global Administrator) has to approve them. After that,
  other users are not asked again.
- **The account that runs the script** needs to be able to read all users - **Global Reader** is a
  good read-only choice.

### 5. Good data in Entra ID

The report groups people by what is in the directory. Before you judge the report, check that
users have:

- **Department** and **Job title** - used by most slicers. By default the users export skips
  accounts with no job title, which keeps shared mailboxes, rooms and service accounts out of
  the report. If real people are missing a job title, fix the directory or add
  `-IncludeUsersWithoutJobTitle`.
- **Manager** - used by the organisation comparison and decomposition pages.
- **City**, **Country**, **Usage location** - optional.

### 6. Microsoft 365 Copilot in use

Users need Copilot licenses, or to be using Copilot Chat, for there to be anything in the audit
log. Allow a few weeks of activity before drawing conclusions about adoption.
