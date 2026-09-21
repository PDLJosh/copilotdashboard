<#
.SYNOPSIS
    Exports Entra ID users, their managers and their Microsoft 365 Copilot license status
    to Copilot_Users.csv (GCC edition).

.DESCRIPTION
    Reads users from Microsoft Graph and writes <OutputFolder>\Copilot_Users.csv in the
    11-column layout that "M365 Copilot Audit Report.pbit" expects. The file is replaced on
    every run.

    A user counts as Copilot-licensed when they hold a product (SKU) that contains an enabled
    Microsoft 365 Copilot service plan. Copilot products are found two ways:
      * discovery - any product in the tenant with a service plan named M365_COPILOT*,
        which also covers suites that bundle Copilot;
      * known IDs - the product IDs built into this edition plus any passed in -CopilotSkuId.

    This edition targets Microsoft 365 Government Community Cloud (GCC) tenants.

.PARAMETER OutputFolder
    Folder for Copilot_Users.csv. Created if it does not exist.

.PARAMETER CopilotSkuId
    Additional product (SKU) IDs to treat as Microsoft 365 Copilot. Use this if the script
    reports that it found no Copilot product in your tenant.

.PARAMETER DisableSkuDiscovery
    Only use the built-in and -CopilotSkuId product IDs; do not inspect service plans.

.PARAMETER IncludeUsersWithoutJobTitle
    By default only users with a job title are exported, which keeps service, shared and
    room accounts out of the report. Use this switch to export every user.

.PARAMETER AppId
    Application (client) ID for unattended, certificate-based sign-in. See docs/scheduling.md.

.PARAMETER TenantId
    Tenant ID or domain for unattended sign-in, for example contoso.onmicrosoft.com.

.PARAMETER CertificateThumbprint
    Thumbprint of the certificate (in the CurrentUser or LocalMachine store) for unattended sign-in.

.PARAMETER UseExistingSession
    Use the Microsoft Graph session that is already connected in this window instead of
    connecting and disconnecting.

.PARAMETER InstallMissingModules
    Install the required Microsoft Graph modules for the current user if they are missing.

.EXAMPLE
    .\Get-CopilotUsers.ps1

    Interactive sign-in, output to C:\M365CopilotReport.

.EXAMPLE
    .\Get-CopilotUsers.ps1 -OutputFolder D:\CopilotReport -CopilotSkuId 11111111-2222-3333-4444-555555555555

.EXAMPLE
    .\Get-CopilotUsers.ps1 -AppId 00000000-0000-0000-0000-000000000000 -TenantId contoso.onmicrosoft.com -CertificateThumbprint 0123456789ABCDEF0123456789ABCDEF01234567

    Unattended run, for example from Task Scheduler.

.NOTES
    Derived from Audit-Get-Users.ps1 in https://github.com/BojanBuhac/M365-Copilot-Audit-Report (GPL-3.0).
    Licensed under GPL-3.0. See LICENSE and NOTICE.md.
#>
[CmdletBinding(DefaultParameterSetName = 'Interactive')]
param(
    [string]$OutputFolder = 'C:\M365CopilotReport',

    [string[]]$CopilotSkuId = @(),

    [switch]$DisableSkuDiscovery,

    [switch]$IncludeUsersWithoutJobTitle,

    [Parameter(ParameterSetName = 'AppOnly', Mandatory = $true)]
    [string]$AppId,

    [Parameter(ParameterSetName = 'AppOnly', Mandatory = $true)]
    [string]$TenantId,

    [Parameter(ParameterSetName = 'AppOnly', Mandatory = $true)]
    [string]$CertificateThumbprint,

    [Parameter(ParameterSetName = 'ExistingSession', Mandatory = $true)]
    [switch]$UseExistingSession,

    [switch]$InstallMissingModules
)

#region Cloud profile: GCC
# Generated from src/clouds.psd1 by tools/Build-CloudScripts.ps1. Do not edit by hand.
$CloudProfile = @{
    Name                    = 'GCC'
    ExchangeEnvironmentName = ''   # empty = worldwide endpoints, parameter is omitted
    GraphEnvironment        = ''   # empty = worldwide endpoints, parameter is omitted
    KnownCopilotSkuIds      = @('a920a45e-67da-4a1a-b408-460d7a2453ce')
}
#endregion

$RequiredModules = 'Microsoft.Graph.Authentication', 'Microsoft.Graph.Users', 'Microsoft.Graph.Identity.DirectoryManagement'
$GraphScopes = 'User.Read.All', 'Organization.Read.All'
$CopilotServicePlanPattern = 'M365_COPILOT*'
$UserProperties = 'Id', 'DisplayName', 'UserPrincipalName', 'JobTitle', 'Department', 'City', 'Country', 'UsageLocation', 'AssignedLicenses'
$Utf8NoBom = New-Object System.Text.UTF8Encoding($false)

# Returns a table of Copilot products in the tenant: SKU ID -> part number and Copilot service plan IDs.
function Resolve-CopilotSku ([string[]]$KnownSkuIds, [bool]$Discover) {
    $known = @($KnownSkuIds | Where-Object { $_ } | ForEach-Object { $_.ToLowerInvariant() })
    $copilotSkus = @{}
    $tenantSkus = @(Get-MgSubscribedSku -All -ErrorAction Stop)

    foreach ($sku in $tenantSkus) {
        $skuId = "$($sku.SkuId)".ToLowerInvariant()
        $copilotPlans = @($sku.ServicePlans | Where-Object { $_.ServicePlanName -like $CopilotServicePlanPattern })
        $source = $null
        if ($known -contains $skuId) { $source = 'known ID' }
        elseif ($Discover -and $copilotPlans.Count -gt 0) { $source = 'discovered' }

        if ($source) {
            $copilotSkus[$skuId] = @{
                SkuPartNumber = $sku.SkuPartNumber
                Source        = $source
                PlanIds       = @($copilotPlans | ForEach-Object { "$($_.ServicePlanId)".ToLowerInvariant() })
            }
        }
    }

    if ($copilotSkus.Count -eq 0) {
        Write-Warning "No Microsoft 365 Copilot product was found in this tenant, so every user will be exported with HasCopilotLicense = False."
        $candidates = @($tenantSkus | Where-Object { $_.SkuPartNumber -like '*COPILOT*' -or @($_.ServicePlans | Where-Object { $_.ServicePlanName -like '*COPILOT*' }).Count -gt 0 })
        if ($candidates.Count -gt 0) {
            Write-Warning "Products in this tenant that mention Copilot - pass the right SkuId with -CopilotSkuId:"
            $candidates | ForEach-Object { Write-Warning ("    {0}  {1}" -f $_.SkuId, $_.SkuPartNumber) }
        }
    }
    return $copilotSkus
}

# True when one of the user's licenses is a Copilot product with at least one Copilot service plan enabled.
function Test-CopilotLicense ($AssignedLicenses, [hashtable]$CopilotSkus) {
    foreach ($license in @($AssignedLicenses)) {
        $skuId = "$($license.SkuId)".ToLowerInvariant()
        if (-not $CopilotSkus.ContainsKey($skuId)) { continue }

        $planIds = @($CopilotSkus[$skuId].PlanIds)
        if ($planIds.Count -eq 0) { return $true }
        $disabled = @($license.DisabledPlans | ForEach-Object { "$_".ToLowerInvariant() })
        if (@($planIds | Where-Object { $disabled -notcontains $_ }).Count -gt 0) { return $true }
    }
    return $false
}

# Power BI reads the file with QuoteStyle.None, so a line break inside a value would split the row.
function Remove-LineBreaks ($Value) {
    if ($null -eq $Value) { return $null }
    return ([string]$Value) -replace '[\r\n]+', ' '
}

# Dot-source the script to load the functions above without running an export (used by the tests).
if ($MyInvocation.InvocationName -eq '.') { return }

#region Prepare output
$OutputFolder = $ExecutionContext.SessionState.Path.GetUnresolvedProviderPathFromPSPath($OutputFolder)
if (-not (Test-Path -LiteralPath $OutputFolder -PathType Container)) {
    New-Item -ItemType Directory -Path $OutputFolder -Force | Out-Null
}
$csvUsersPath = Join-Path $OutputFolder 'Copilot_Users.csv'
#endregion

#region Connect to Microsoft Graph
$connected = $false
if (-not $UseExistingSession) {
    $missing = @($RequiredModules | Where-Object { -not (Get-Module -ListAvailable -Name $_) })
    if ($missing.Count -gt 0) {
        if (-not $InstallMissingModules) {
            Write-Host "Required Microsoft Graph modules are not installed. Install them with:" -ForegroundColor Yellow
            Write-Host "    Install-Module $($missing -join ', ') -Scope CurrentUser" -ForegroundColor Yellow
            Write-Host "or run this script again with -InstallMissingModules." -ForegroundColor Yellow
            exit 1
        }
        Write-Host "Installing modules: $($missing -join ', ')..."
        Install-Module -Name $missing -Force -AllowClobber -Scope CurrentUser -ErrorAction Stop
    }
    Import-Module $RequiredModules -ErrorAction Stop

    $connectParams = @{ NoWelcome = $true; ErrorAction = 'Stop' }
    if ($CloudProfile.GraphEnvironment) { $connectParams.Environment = $CloudProfile.GraphEnvironment }
    if ($PSCmdlet.ParameterSetName -eq 'AppOnly') {
        $connectParams.ClientId = $AppId
        $connectParams.TenantId = $TenantId
        $connectParams.CertificateThumbprint = $CertificateThumbprint
    } else {
        $connectParams.Scopes = $GraphScopes
    }

    try {
        Connect-MgGraph @connectParams
        $connected = $true
        Write-Host "Connected to Microsoft Graph ($($CloudProfile.Name))."
    } catch {
        Write-Host "Failed to connect to Microsoft Graph ($($CloudProfile.Name)): $_" -ForegroundColor Red
        exit 1
    }
}
#endregion

try {
    $copilotSkus = Resolve-CopilotSku -KnownSkuIds (@($CloudProfile.KnownCopilotSkuIds) + @($CopilotSkuId)) -Discover (-not $DisableSkuDiscovery)
    foreach ($skuId in $copilotSkus.Keys) {
        Write-Host ("Copilot product: {0}  {1}  ({2})" -f $skuId, $copilotSkus[$skuId].SkuPartNumber, $copilotSkus[$skuId].Source)
    }

    # Expanding the manager returns it with each user. If the service rejects the expansion,
    # fall back to one manager lookup per user.
    $managerExpanded = $true
    try {
        $users = @(Get-MgUser -All -Property $UserProperties -ExpandProperty 'manager($select=id,displayName,userPrincipalName)' -ErrorAction Stop)
    } catch {
        Write-Warning "Could not read managers together with users ($_). Falling back to one lookup per user, which is slower."
        $managerExpanded = $false
        $users = @(Get-MgUser -All -Property $UserProperties -ErrorAction Stop)
    }

    if (-not $IncludeUsersWithoutJobTitle) {
        $users = @($users | Where-Object { $_.JobTitle })
    }
    Write-Host "Processing $($users.Count) users..."

    $results = foreach ($user in $users) {
        $managerName = ""
        $managerUPN = ""

        $manager = $null
        if ($managerExpanded) {
            $manager = $user.Manager
        } else {
            try { $manager = Get-MgUserManager -UserId $user.Id -ErrorAction Stop } catch { $manager = $null }
        }
        if ($manager -and $manager.AdditionalProperties) {
            $managerName = [string]$manager.AdditionalProperties['displayName']
            $managerUPN = [string]$manager.AdditionalProperties['userPrincipalName']
        }

        [PSCustomObject][Ordered]@{
            EntraID           = $user.Id
            DisplayName       = Remove-LineBreaks $user.DisplayName
            UserPrincipalName = $user.UserPrincipalName
            JobTitle          = Remove-LineBreaks $user.JobTitle
            Department        = Remove-LineBreaks $user.Department
            City              = Remove-LineBreaks $user.City
            Country           = Remove-LineBreaks $user.Country
            UsageLocation     = $user.UsageLocation
            ManagerName       = Remove-LineBreaks $managerName
            ManagerUPN        = $managerUPN
            HasCopilotLicense = Test-CopilotLicense -AssignedLicenses $user.AssignedLicenses -CopilotSkus $copilotSkus
        }
    }

    # Write to a temporary file first so an interrupted run never leaves a half-written CSV behind.
    $tempPath = "$csvUsersPath.tmp"
    $csv = @($results | ConvertTo-Csv -NoTypeInformation)
    if ($csv.Count -eq 0) {
        $csv = @('"EntraID","DisplayName","UserPrincipalName","JobTitle","Department","City","Country","UsageLocation","ManagerName","ManagerUPN","HasCopilotLicense"')
    }
    [System.IO.File]::WriteAllLines($tempPath, [string[]]$csv, $Utf8NoBom)
    Move-Item -LiteralPath $tempPath -Destination $csvUsersPath -Force

    $licensed = @($results | Where-Object { $_.HasCopilotLicense }).Count
    Write-Host "Report exported to $csvUsersPath" -ForegroundColor Green
    Write-Host "Users exported: $(@($results).Count). With a Microsoft 365 Copilot license: $licensed."
} catch {
    Write-Host "ERROR: $_" -ForegroundColor Red
    exit 1
} finally {
    if ($connected) { Disconnect-MgGraph -ErrorAction SilentlyContinue | Out-Null }
}
