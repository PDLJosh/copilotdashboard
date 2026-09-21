# Troubleshooting

Start with `C:\M365CopilotReport\AuditScriptLog.txt` for the events export, and the console
output for the users export.

## Connecting

### `Search-UnifiedAuditLog` is not recognized

You connected, but your account does not hold an Exchange Online role that includes the cmdlet,
so Exchange did not load it. You need **View-Only Audit Logs** or **Audit Logs** *in Exchange
Online* - membership of *Audit Reader* in the Purview portal is not enough for PowerShell. See
[prerequisites](prerequisites.md#3-permission-to-search-the-audit-log-for-get-copilotauditeventsps1).
Roles can take up to an hour to apply; close PowerShell and sign in again.

Check what you have:

```powershell
Get-ManagementRoleAssignment -RoleAssignee you@contoso.com -Role "View-Only Audit Logs" -Delegating:$false
```

### GCC High: sign-in fails, loops, or says the account does not exist

You are probably running the wrong edition. The `commercial` and `gcc` scripts sign in at
`login.microsoftonline.com`, where a GCC High account does not exist. Use the scripts in
[`gcch/`](../gcch/README.md). The first line of output names the cloud:
`Connected to Exchange Online (GCC High).`

The reverse also happens: a GCC tenant is **not** GCC High. If your domain ends in
`.onmicrosoft.com`, use [`gcc/`](../gcc/README.md).

### The sign-in window never appears, or hangs

Common on jump boxes and hardened desktops, where the Windows account broker (WAM) cannot show
its window.

- Exchange Online: connect yourself with WAM disabled, then tell the script to reuse the session:
  ```powershell
  Connect-ExchangeOnline -DisableWAM                                                # Commercial, GCC
  Connect-ExchangeOnline -DisableWAM -ExchangeEnvironmentName O365USGovGCCHigh      # GCC High
  .\Get-CopilotAuditEvents.ps1 -UseExistingSession
  ```
- Microsoft Graph: turn WAM off once (the setting is remembered), then run the script normally:
  ```powershell
  Set-MgGraphOption -DisableLoginByWAM $true
  ```

`-UseExistingSession` is also the answer if your organisation requires a particular sign-in
method (device code, a specific browser, a privileged access workstation flow): connect the way
you must, then run the script with `-UseExistingSession`.

### "Need admin approval" when running `Get-CopilotUsers.ps1`

Nobody has yet consented to `User.Read.All` and `Organization.Read.All` for *Microsoft Graph
Command Line Tools* in your tenant. Ask an administrator who can grant consent to run the script
once and tick **Consent on behalf of your organization**, or to grant it in the Entra admin
center under **Enterprise applications**.

### The PowerShell Gallery is blocked

On a PC that can reach the gallery, save the modules, then copy them across by your approved
transfer process:

```powershell
Save-Module ExchangeOnlineManagement, Microsoft.Graph.Authentication, Microsoft.Graph.Users, Microsoft.Graph.Identity.DirectoryManagement -Path C:\Temp\Modules
```

Copy the folders into `Documents\PowerShell\Modules` (PowerShell 7) or
`Documents\WindowsPowerShell\Modules` (Windows PowerShell 5.1) on the target PC.

### "cannot be loaded because running scripts is disabled" / "is not digitally signed"

```powershell
Set-ExecutionPolicy RemoteSigned -Scope CurrentUser
Get-ChildItem -Recurse *.ps1 | Unblock-File
```

Review the scripts before unblocking them. If a Group Policy enforces `AllSigned`, ask your
administrator to sign the scripts with your organisation's code-signing certificate.

## Events export

### It finishes, but `Copilot_Events.csv` is empty or missing

- Auditing may be off - see [prerequisites](prerequisites.md#1-auditing-is-turned-on).
- Nobody has used Copilot in the period, or the records are older than your retention period.
- Check the same search in the Purview portal (**Audit > New search**, record type
  *CopilotInteraction*). If the portal finds records and the script does not, open an issue.

### The first run is very slow

It makes at least one search per day of lookback, and each search takes several seconds even when
empty. Use `-InitialLookbackDays 180` if you keep audit records for 180 days. You can stop the
script with Ctrl+C and run it again later; it resumes from the last event it saved.

### "Audit search failed 3 times" and the script stops

The audit search service is sometimes slow or returns errors. The script retries each window
three times and then stops rather than skip a period. Nothing is lost: run it again and it
continues from where it stopped. If it fails repeatedly at the same date, try smaller windows:

```powershell
.\Get-CopilotAuditEvents.ps1 -IntervalMinutes 360
```

### "Reducing the interval" messages

Normal in busy tenants. One audit search can return at most 50,000 records, so the script halves
the window when it reaches the limit and grows it back afterwards. You do not need to do anything.

### "Expected N records ... but received M" in the log

The service reported more records than it delivered for a window. A small difference usually
means the service double-counted duplicates. If the difference is large, run the script again:
the overlap re-reads the most recent day and adds whatever was missed. For an older period,
export to a new folder with a fresh lookback and compare.

### Numbers are lower than the Microsoft 365 admin center's Copilot usage report

The two measure different things. The admin center counts active users per app from service
telemetry. This report counts `CopilotInteraction` audit records. Expect the trends to agree, not
the totals.

### I want to start again

Rename or delete `Copilot_Events.csv`. The next run does a full lookback. Deleting only some
rows from the middle of the file is not supported.

### I used the upstream script before. Can I keep my file?

Yes. The column layout is identical. Point `-OutputFolder` at the folder containing your existing
`Copilot_Events.csv` and the script continues from its newest event. The exception is a file
created on non-English Windows, where upstream wrote localised month names; start a new file in
that case.

## Users export

### Every user shows `HasCopilotLicense = False`

Look at the script output. If it says *"No Microsoft 365 Copilot product was found"*, it also
lists the products in your tenant that mention Copilot. Re-run with the right one:

```powershell
.\Get-CopilotUsers.ps1 -CopilotSkuId xxxxxxxx-xxxx-xxxx-xxxx-xxxxxxxxxxxx
```

To see every product in the tenant and its service plans yourself:

```powershell
Get-MgSubscribedSku -All | Select-Object SkuId, SkuPartNumber, @{n='Plans';e={$_.ServicePlans.ServicePlanName -join ', '}} | Format-List
```

Please open an issue with the **product and service plan names** (not your tenant details) so
detection can be improved for everyone.

### Some people are missing

By default, accounts with no **Job title** are skipped to keep rooms, shared mailboxes and service
accounts out of the report. Populate the job title in Entra ID, or include everyone:

```powershell
.\Get-CopilotUsers.ps1 -IncludeUsersWithoutJobTitle
```

People who appear in the events but not in the users file show up in the report without a
department or manager.

### "Could not read managers together with users ... Falling back"

Informational. Your cloud's Microsoft Graph rejected the faster query, so the script looks up
each manager separately. The result is the same; it just takes longer.

### It is slow in a large tenant

Reading tens of thousands of users takes several minutes. If you see the fallback message above,
it takes considerably longer, because each user needs a separate request.

## Power BI

See [If a visual is empty](power-bi-setup.md#if-a-visual-is-empty) and
[Custom visuals](power-bi-setup.md#custom-visuals).

## Still stuck?

Open an issue with: the edition (commercial, gcc, gcch), your PowerShell version
(`$PSVersionTable.PSVersion`), the module versions
(`Get-Module ExchangeOnlineManagement, Microsoft.Graph.Authentication -ListAvailable`), and the
error text. **Do not attach your CSV files, `.pbix`, tenant name or user names.**
