# Scheduling unattended exports

Interactive sign-in is fine for occasional use. To refresh the data every day without anyone
signing in, the scripts can sign in as an application with a certificate.

> **Run the export at least as often as your audit retention period** (180 days or 1 year).
> Once a record ages out of the audit log it cannot be exported. Daily is typical.

This takes about 30 minutes, once, and needs someone who can register applications and grant
admin consent, plus an Exchange administrator.

| | Commercial | GCC | GCC High |
| --- | --- | --- | --- |
| Register the application at | entra.microsoft.com | entra.microsoft.com | **entra.microsoft.us** |
| `-Organization` / `-TenantId` | contoso.onmicrosoft.com | contoso.onmicrosoft.com | contoso.onmicrosoft**.us** |

The steps follow Microsoft's
[app-only authentication for Exchange Online PowerShell](https://learn.microsoft.com/powershell/exchange/app-only-auth-powershell-v2)
guide, which is the authoritative reference if anything here has changed.

## 1. Create a certificate

On the PC that will run the task, signed in as the account the task will run as:

```powershell
$cert = New-SelfSignedCertificate -Subject "CN=Copilot Dashboard Export" -CertStoreLocation "Cert:\CurrentUser\My" -KeySpec KeyExchange -KeyExportPolicy NonExportable -NotAfter (Get-Date).AddYears(1)
$cert.Thumbprint
Export-Certificate -Cert $cert -FilePath "$env:USERPROFILE\Desktop\CopilotDashboardExport.cer"
```

- **`-KeySpec KeyExchange` matters.** Exchange Online app-only sign-in does not support the CNG
  certificates that Windows creates by default.
- `NonExportable` keeps the private key on this PC. Only the public `.cer` file leaves it.
- Your organisation may require a certificate from its own CA instead of a self-signed one.
- Put a renewal reminder in your calendar. When the certificate expires the task starts failing.

Note the thumbprint. Do not store the `.cer` (or any `.pfx`) in this repository.

## 2. Register the application

In the Microsoft Entra admin center for your cloud:

1. **Applications > App registrations > New registration**. Name it `Copilot Dashboard Export`,
   single tenant, no redirect URI. Note the **Application (client) ID**.
2. **Certificates & secrets > Certificates > Upload certificate** - upload the `.cer` file.
3. **API permissions > Add a permission**, choosing **Application permissions** each time:

   | API | Permission | Used by |
   | --- | --- | --- |
   | Microsoft Graph | `User.Read.All` | `Get-CopilotUsers.ps1` |
   | Microsoft Graph | `Organization.Read.All` | `Get-CopilotUsers.ps1` |
   | Office 365 Exchange Online (under **APIs my organization uses**) | `Exchange.ManageAsApp` | `Get-CopilotAuditEvents.ps1` |

4. Select **Grant admin consent**.

These are read permissions, but they are tenant-wide. Anyone who holds the certificate's private
key can read every user's profile and search the audit log, so protect the PC accordingly.

## 3. Let the application search the audit log

`Exchange.ManageAsApp` only lets the application connect; Exchange roles decide what it can do.
Grant it just the audit-search role. In PowerShell, as an administrator:

```powershell
# Microsoft Graph - look up the enterprise application.   GCC High: add  -Environment USGov
Connect-MgGraph -Scopes Application.Read.All
$app = Get-MgServicePrincipal -Filter "DisplayName eq 'Copilot Dashboard Export'"

# Exchange Online - create the pointer and the role group.   GCC High: add  -ExchangeEnvironmentName O365USGovGCCHigh
Connect-ExchangeOnline
New-ServicePrincipal -AppId $app.AppId -ObjectId $app.Id -DisplayName "Copilot Dashboard Export"
$sp = Get-ServicePrincipal -Identity "Copilot Dashboard Export"
New-RoleGroup -Name "Copilot Audit Export (app)" -Roles "View-Only Audit Logs"
Add-RoleGroupMember -Identity "Copilot Audit Export (app)" -Member $sp.Identity
```

`$app.Id` must be the object ID of the **enterprise application** (service principal), not the
object ID shown on the app registration page. `Get-MgServicePrincipal` returns the right one.
`Get-MgServicePrincipal` is in the `Microsoft.Graph.Applications` module.

The simpler but much broader alternative is to assign the application the **Compliance
Administrator** role in Entra ID. Prefer the role group.

Allow up to an hour for the role to take effect.

## 4. Test it

```powershell
cd <path-to>\copilotdashboard\examples
.\Invoke-DailyRefresh.ps1 -Cloud gcch -AppId <app-id> -Tenant contoso.onmicrosoft.us -CertificateThumbprint <thumbprint>
```

Use `commercial` or `gcc` and your `.onmicrosoft.com` domain for those clouds. No sign-in window
should appear. Check `C:\M365CopilotReport\DailyRefresh-Transcript.txt`.

[`Invoke-DailyRefresh.ps1`](../examples/Invoke-DailyRefresh.ps1) simply runs the two scripts with
the certificate parameters and returns a failure code if either fails. You can call the scripts
directly instead:

```powershell
.\Get-CopilotUsers.ps1      -AppId <app-id> -TenantId     <tenant-domain> -CertificateThumbprint <thumbprint>
.\Get-CopilotAuditEvents.ps1 -AppId <app-id> -Organization <tenant-domain> -CertificateThumbprint <thumbprint>
```

## 5. Create the scheduled task

Run as the **same account that created the certificate** (it is in that account's certificate
store). Adjust the paths.

```powershell
$arguments = '-NoProfile -ExecutionPolicy RemoteSigned -File "C:\Tools\copilotdashboard\examples\Invoke-DailyRefresh.ps1" ' +
             '-Cloud gcch -AppId <app-id> -Tenant contoso.onmicrosoft.us -CertificateThumbprint <thumbprint>'

$action  = New-ScheduledTaskAction -Execute 'pwsh.exe' -Argument $arguments
$trigger = New-ScheduledTaskTrigger -Daily -At 6am
$settings = New-ScheduledTaskSettingsSet -StartWhenAvailable -ExecutionTimeLimit (New-TimeSpan -Hours 6)

Register-ScheduledTask -TaskName 'Copilot Dashboard Export' -Action $action -Trigger $trigger -Settings $settings -Description 'Exports Copilot usage data for the Power BI report'
```

- Use `powershell.exe` instead of `pwsh.exe` if PowerShell 7 is not installed.
- For the task to run when nobody is logged on, open it in Task Scheduler and choose **Run whether
  user is logged on or not**. For a dedicated service account, create the certificate while
  signed in as that account, or create it in `Cert:\LocalMachine\My` and give the account read
  access to the private key.
- The application ID and thumbprint are identifiers, not secrets - the secret is the private key
  in the certificate store.

## After it is running

- The task's **Last Run Result** is `0x0` on success and `0x1` if an export failed.
- `AuditScriptLog.txt` records every search window. Lines starting `WARN` or `ERROR` deserve a look.
- A failed run is safe to repeat: the events export resumes where it stopped and never writes
  the same row twice.
- Power BI Desktop still needs a manual **Refresh**, or publish the report and use a data
  gateway - see [Power BI setup](power-bi-setup.md#publishing).

## Removing access

Delete the app registration (or just its certificate) in Entra ID, remove the role group with
`Remove-RoleGroup "Copilot Audit Export (app)"`, delete the certificate from the PC, and
unregister the task.
