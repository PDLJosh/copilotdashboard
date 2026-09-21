# Pester 5 tests for Get-CopilotUsers.ps1. No tenant is needed: the Microsoft Graph cmdlets are
# replaced with fakes that serve synthetic users and products.
#   Invoke-Pester ./tests

BeforeAll {
    $script:RepoRoot = Split-Path -Parent $PSScriptRoot
    $script:UsersScript = Join-Path $RepoRoot 'gcch\Get-CopilotUsers.ps1'

    $script:CopilotSku = '11111111-1111-1111-1111-111111111111'
    $script:SuiteSku = '22222222-2222-2222-2222-222222222222'      # a suite that bundles Copilot
    $script:OfficeSku = '33333333-3333-3333-3333-333333333333'
    $script:ChatPlan = 'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa'
    $script:AppsPlan = 'bbbbbbbb-bbbb-bbbb-bbbb-bbbbbbbbbbbb'

    function New-FakeSku ([string]$SkuId, [string]$PartNumber, [hashtable]$Plans) {
        [pscustomobject]@{
            SkuId         = $SkuId
            SkuPartNumber = $PartNumber
            ServicePlans  = @($Plans.GetEnumerator() | ForEach-Object { [pscustomobject]@{ ServicePlanName = $_.Key; ServicePlanId = $_.Value } })
        }
    }

    function New-FakeUser {
        param([string]$Name, [string]$JobTitle = 'Analyst', [object[]]$Licenses = @(), [string]$ManagerName, [string]$Department = 'Finance')
        $upn = ($Name -replace ' ', '.').ToLowerInvariant() + '@contoso.us'
        $manager = $null
        if ($ManagerName) {
            $manager = [pscustomobject]@{
                Id                   = [guid]::NewGuid().ToString()
                AdditionalProperties = @{ displayName = $ManagerName; userPrincipalName = ($ManagerName -replace ' ', '.').ToLowerInvariant() + '@contoso.us' }
            }
        }
        [pscustomobject]@{
            Id = [guid]::NewGuid().ToString(); DisplayName = $Name; UserPrincipalName = $upn; JobTitle = $JobTitle
            Department = $Department; City = 'Reston'; Country = 'United States'; UsageLocation = 'US'
            AssignedLicenses = $Licenses; Manager = $manager
        }
    }

    function New-FakeLicense ([string]$SkuId, [string[]]$DisabledPlans = @()) {
        [pscustomobject]@{ SkuId = $SkuId; DisabledPlans = $DisabledPlans }
    }

    function global:Get-MgSubscribedSku { param([switch]$All) $global:FakeSkus }
    function global:Get-MgUser {
        param([switch]$All, $Property, $ExpandProperty, $UserId)
        if ($ExpandProperty -and $global:RejectExpand) { throw 'Expand is not supported' }
        if ($ExpandProperty) { return $global:FakeUsers }
        $global:FakeUsers | Select-Object -Property * -ExcludeProperty Manager
    }
    function global:Get-MgUserManager {
        param($UserId)
        $user = $global:FakeUsers | Where-Object { $_.Id -eq $UserId }
        if (-not $user.Manager) { throw 'Resource not found' }
        $user.Manager
    }

    function Invoke-UsersScript ([string]$Folder, [hashtable]$Extra = @{}) {
        & $script:UsersScript -OutputFolder $Folder -UseExistingSession @Extra 3> $null 6> $null
    }
}

AfterAll {
    'Get-MgSubscribedSku', 'Get-MgUser', 'Get-MgUserManager' | ForEach-Object { Remove-Item "function:\$_" -ErrorAction SilentlyContinue }
    'FakeSkus', 'FakeUsers', 'RejectExpand' | ForEach-Object { Remove-Variable -Name $_ -Scope Global -ErrorAction SilentlyContinue }
}

Describe 'Get-CopilotUsers.ps1' {
    BeforeEach {
        $global:RejectExpand = $false
        $script:Folder = Join-Path $TestDrive ([guid]::NewGuid().ToString())
        $script:Csv = Join-Path $Folder 'Copilot_Users.csv'
        $global:FakeSkus = @(
            New-FakeSku $CopilotSku 'Microsoft_365_Copilot_Example' @{ M365_COPILOT_BUSINESS_CHAT = $ChatPlan; M365_COPILOT_APPS = $AppsPlan }
            New-FakeSku $SuiteSku 'Example_Suite_With_Copilot' @{ EXCHANGE_S_ENTERPRISE = 'cccccccc-cccc-cccc-cccc-cccccccccccc'; M365_COPILOT_BUSINESS_CHAT = $ChatPlan }
            New-FakeSku $OfficeSku 'Example_Office_Suite' @{ EXCHANGE_S_ENTERPRISE = 'cccccccc-cccc-cccc-cccc-cccccccccccc' }
        )
        $global:FakeUsers = @(
            New-FakeUser 'Avery Howard' -Licenses @(New-FakeLicense $OfficeSku; New-FakeLicense $CopilotSku) -ManagerName 'Jordan Reyes'
            New-FakeUser 'Casey Morgan' -Licenses @(New-FakeLicense $OfficeSku)
            New-FakeUser 'Devon Blake' -Licenses @(New-FakeLicense $SuiteSku)
            New-FakeUser 'Emery Quinn' -Licenses @(New-FakeLicense $CopilotSku -DisabledPlans @($ChatPlan, $AppsPlan))
            New-FakeUser 'Room 4 North' -JobTitle $null -Licenses @(New-FakeLicense $CopilotSku)
        )
    }

    It 'creates the 11-column file the Power BI template expects' {
        Invoke-UsersScript $Folder
        (Get-Content $Csv)[0] | Should -BeExactly '"EntraID","DisplayName","UserPrincipalName","JobTitle","Department","City","Country","UsageLocation","ManagerName","ManagerUPN","HasCopilotLicense"'
        [System.IO.File]::ReadAllBytes($Csv)[0] | Should -Be ([byte][char]'"') -Because 'the file must not start with a byte order mark'
    }

    It 'discovers Copilot products from their service plans, including suites that bundle Copilot' {
        Invoke-UsersScript $Folder
        $rows = Import-Csv $Csv
        ($rows | Where-Object DisplayName -eq 'Avery Howard').HasCopilotLicense | Should -Be 'True'
        ($rows | Where-Object DisplayName -eq 'Devon Blake').HasCopilotLicense | Should -Be 'True'
        ($rows | Where-Object DisplayName -eq 'Casey Morgan').HasCopilotLicense | Should -Be 'False'
    }

    It 'does not count a license whose Copilot service plans are all disabled' {
        Invoke-UsersScript $Folder
        (Import-Csv $Csv | Where-Object DisplayName -eq 'Emery Quinn').HasCopilotLicense | Should -Be 'False'
    }

    It 'uses only explicit product IDs when discovery is disabled' {
        Invoke-UsersScript $Folder @{ DisableSkuDiscovery = $true; CopilotSkuId = @($SuiteSku.ToUpperInvariant()) }
        $rows = Import-Csv $Csv
        ($rows | Where-Object DisplayName -eq 'Devon Blake').HasCopilotLicense | Should -Be 'True'
        ($rows | Where-Object DisplayName -eq 'Avery Howard').HasCopilotLicense | Should -Be 'False'
    }

    It 'exports everyone as unlicensed, with a warning, when the tenant has no Copilot product' {
        $global:FakeSkus = @(New-FakeSku $OfficeSku 'Example_Office_Suite' @{ EXCHANGE_S_ENTERPRISE = 'cccccccc-cccc-cccc-cccc-cccccccccccc' })
        $warnings = & $script:UsersScript -OutputFolder $Folder -UseExistingSession 3>&1 6> $null | Where-Object { $_ -is [System.Management.Automation.WarningRecord] }
        ($warnings.Message -join ' ') | Should -Match 'No Microsoft 365 Copilot product was found'
        @(Import-Csv $Csv | Where-Object HasCopilotLicense -eq 'True').Count | Should -Be 0
    }

    It 'skips accounts without a job title unless asked to include them' {
        Invoke-UsersScript $Folder
        (Import-Csv $Csv).DisplayName | Should -Not -Contain 'Room 4 North'
        Invoke-UsersScript $Folder @{ IncludeUsersWithoutJobTitle = $true }
        (Import-Csv $Csv).DisplayName | Should -Contain 'Room 4 North'
    }

    It 'exports manager details, and leaves them empty when there is no manager' {
        Invoke-UsersScript $Folder
        $rows = Import-Csv $Csv
        $avery = $rows | Where-Object DisplayName -eq 'Avery Howard'
        $avery.ManagerName | Should -Be 'Jordan Reyes'
        $avery.ManagerUPN | Should -Be 'jordan.reyes@contoso.us'
        ($rows | Where-Object DisplayName -eq 'Casey Morgan').ManagerName | Should -BeNullOrEmpty
    }

    It 'falls back to one manager lookup per user when the service rejects the expansion' {
        $global:RejectExpand = $true
        Invoke-UsersScript $Folder
        (Import-Csv $Csv | Where-Object DisplayName -eq 'Avery Howard').ManagerName | Should -Be 'Jordan Reyes'
    }
}
