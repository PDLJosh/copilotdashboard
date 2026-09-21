<#
.SYNOPSIS
    Runs both exports unattended with certificate sign-in. Intended for Task Scheduler.

.DESCRIPTION
    Calls Get-CopilotUsers.ps1 and Get-CopilotAuditEvents.ps1 from the folder of the cloud you
    choose, writes a transcript next to the CSV files, and exits with a non-zero code if either
    export fails so that Task Scheduler shows the run as failed.

    Set up the application and certificate first: see docs/scheduling.md.

.PARAMETER Cloud
    Which edition to run: commercial, gcc or gcch.

.PARAMETER AppId
    Application (client) ID of the app registration.

.PARAMETER Tenant
    The tenant's initial domain, for example contoso.onmicrosoft.com (contoso.onmicrosoft.us in GCC High).

.PARAMETER CertificateThumbprint
    Thumbprint of the certificate whose public key was uploaded to the app registration.

.PARAMETER OutputFolder
    Folder for the CSV files, the export log and the transcript.

.EXAMPLE
    .\Invoke-DailyRefresh.ps1 -Cloud gcch -AppId 00000000-0000-0000-0000-000000000000 -Tenant contoso.onmicrosoft.us -CertificateThumbprint 0123456789ABCDEF0123456789ABCDEF01234567
#>
[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)]
    [ValidateSet('commercial', 'gcc', 'gcch')]
    [string]$Cloud,

    [Parameter(Mandatory = $true)]
    [string]$AppId,

    [Parameter(Mandatory = $true)]
    [string]$Tenant,

    [Parameter(Mandatory = $true)]
    [string]$CertificateThumbprint,

    [string]$OutputFolder = 'C:\M365CopilotReport'
)

$scriptFolder = Join-Path (Split-Path -Parent $PSScriptRoot) $Cloud
if (-not (Test-Path -LiteralPath $OutputFolder)) { New-Item -ItemType Directory -Path $OutputFolder -Force | Out-Null }
Start-Transcript -Path (Join-Path $OutputFolder 'DailyRefresh-Transcript.txt') -Force | Out-Null

$failed = $false
try {
    & (Join-Path $scriptFolder 'Get-CopilotUsers.ps1') -OutputFolder $OutputFolder -AppId $AppId -TenantId $Tenant -CertificateThumbprint $CertificateThumbprint
    if ($LASTEXITCODE) { $failed = $true }

    & (Join-Path $scriptFolder 'Get-CopilotAuditEvents.ps1') -OutputFolder $OutputFolder -AppId $AppId -Organization $Tenant -CertificateThumbprint $CertificateThumbprint
    if ($LASTEXITCODE) { $failed = $true }
} finally {
    Stop-Transcript | Out-Null
}

if ($failed) { exit 1 }
