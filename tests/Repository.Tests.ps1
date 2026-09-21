# Pester 5 tests that keep the three cloud editions, the sample data and the installed
# PowerShell modules consistent with each other.
#   Invoke-Pester ./tests

BeforeDiscovery {
    $script:RepoRoot = Split-Path -Parent $PSScriptRoot
    $script:Editions = @(
        @{ Folder = 'commercial'; ExchangeEnvironment = '';                 GraphEnvironment = '' }
        @{ Folder = 'gcc';        ExchangeEnvironment = '';                 GraphEnvironment = '' }
        @{ Folder = 'gcch';       ExchangeEnvironment = 'O365USGovGCCHigh'; GraphEnvironment = 'USGov' }
    )
    $script:ScriptFiles = @(Get-ChildItem -Path $RepoRoot -Recurse -Include *.ps1, *.psd1 | ForEach-Object { @{ Path = $_.FullName; Name = $_.FullName.Substring($RepoRoot.Length + 1) } })
    $script:HasExchangeModule = [bool](Get-Module -ListAvailable ExchangeOnlineManagement)
    $script:HasGraphModule = [bool](Get-Module -ListAvailable Microsoft.Graph.Authentication)
}

BeforeAll {
    $script:RepoRoot = Split-Path -Parent $PSScriptRoot

    # Reads $CloudProfile out of a generated script without running the script.
    function Get-CloudProfile ([string]$Path) {
        $ast = [System.Management.Automation.Language.Parser]::ParseFile($Path, [ref]$null, [ref]$null)
        $assignment = $ast.Find({ param($node) $node -is [System.Management.Automation.Language.AssignmentStatementAst] -and $node.Left.Extent.Text -eq '$CloudProfile' }, $false)
        $assignment.Right.Expression.SafeGetValue()
    }
}

Describe 'Generated scripts' {
    It 'are up to date with the templates in src/' {
        & (Join-Path $RepoRoot 'tools\Build-CloudScripts.ps1') -Check *> $null
        $LASTEXITCODE | Should -Be 0 -Because 'tools/Build-CloudScripts.ps1 must be run after editing src/'
    }

    It '<Name> parses without errors and is plain ASCII (safe for Windows PowerShell 5.1)' -ForEach $ScriptFiles {
        $errors = $null
        [void][System.Management.Automation.Language.Parser]::ParseFile($Path, [ref]$null, [ref]$errors)
        $errors | Should -BeNullOrEmpty
        [regex]::Matches([System.IO.File]::ReadAllText($Path), '[^\x00-\x7F]').Count | Should -Be 0
    }
}

Describe 'Cloud edition <Folder>' -ForEach $Editions {
    It 'targets the right Exchange Online and Microsoft Graph environments' {
        foreach ($script in 'Get-CopilotAuditEvents.ps1', 'Get-CopilotUsers.ps1') {
            $cloudProfile = Get-CloudProfile (Join-Path $RepoRoot "$Folder\$script")
            $cloudProfile.ExchangeEnvironmentName | Should -Be $ExchangeEnvironment
            $cloudProfile.GraphEnvironment | Should -Be $GraphEnvironment
        }
    }

    It 'has its own README' {
        Join-Path $RepoRoot "$Folder\README.md" | Should -Exist
    }
}

Describe 'Installed modules accept what the scripts pass to them' {
    It 'Connect-ExchangeOnline supports the GCC High environment and certificate sign-in' -Skip:(-not $HasExchangeModule) {
        Import-Module ExchangeOnlineManagement
        $command = Get-Command Connect-ExchangeOnline
        [enum]::GetNames($command.Parameters['ExchangeEnvironmentName'].ParameterType) | Should -Contain 'O365USGovGCCHigh'
        'AppId', 'Organization', 'CertificateThumbprint', 'UserPrincipalName', 'ShowBanner' | ForEach-Object { $command.Parameters.Keys | Should -Contain $_ }
    }

    It 'Connect-MgGraph supports the USGov environment and certificate sign-in' -Skip:(-not $HasGraphModule) {
        Import-Module Microsoft.Graph.Authentication
        (Get-MgEnvironment).Name | Should -Contain 'USGov'
        ((Get-MgEnvironment | Where-Object Name -eq 'USGov').GraphEndpoint) | Should -Be 'https://graph.microsoft.us'
        $command = Get-Command Connect-MgGraph
        'Environment', 'ClientId', 'TenantId', 'CertificateThumbprint', 'Scopes', 'NoWelcome' | ForEach-Object { $command.Parameters.Keys | Should -Contain $_ }
    }
}

Describe 'Sample data' {
    It 'matches the column layout the scripts produce' {
        $events = Join-Path $RepoRoot 'examples\sample-data\Copilot_Events.csv'
        $users = Join-Path $RepoRoot 'examples\sample-data\Copilot_Users.csv'
        (Get-Content $events -TotalCount 1) | Should -BeExactly '"TimeStamp","User","App","Location","App context","Accessed Resources","Accessed Resource Locations","Action","AgentName"'
        (Get-Content $users -TotalCount 1) | Should -BeExactly '"EntraID","DisplayName","UserPrincipalName","JobTitle","Department","City","Country","UsageLocation","ManagerName","ManagerUPN","HasCopilotLicense"'
    }

    It 'only contains the fictitious contoso.com organisation' {
        $users = Import-Csv (Join-Path $RepoRoot 'examples\sample-data\Copilot_Users.csv')
        @($users | Where-Object { $_.UserPrincipalName -notlike '*@contoso.com' }).Count | Should -Be 0
        $events = Import-Csv (Join-Path $RepoRoot 'examples\sample-data\Copilot_Events.csv')
        @($events | Where-Object { $_.User -notlike '*@contoso.com' }).Count | Should -Be 0
        @($events | Where-Object { $users.UserPrincipalName -notcontains $_.User }).Count | Should -Be 0 -Because 'every sample event should belong to a sample user'
    }
}

Describe 'Power BI template' {
    It 'is byte-for-byte the upstream file recorded in report/SHA256SUMS' {
        $expected = (Get-Content (Join-Path $RepoRoot 'report\SHA256SUMS') | Where-Object { $_ -match '\.pbit$' }) -split '\s+' | Select-Object -First 1
        (Get-FileHash (Join-Path $RepoRoot 'report\M365 Copilot Audit Report.pbit') -Algorithm SHA256).Hash | Should -Be $expected
    }
}
