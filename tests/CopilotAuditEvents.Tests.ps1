# Pester 5 tests for Get-CopilotAuditEvents.ps1. No tenant is needed: Search-UnifiedAuditLog is
# replaced with a fake that serves synthetic audit records.
#   Invoke-Pester ./tests

BeforeAll {
    $script:RepoRoot = Split-Path -Parent $PSScriptRoot
    $script:EventsScript = Join-Path $RepoRoot 'commercial\Get-CopilotAuditEvents.ps1'

    function New-FakeAuditRecord {
        param(
            [string]$Identity = [guid]::NewGuid().ToString(),
            [datetime]$CreationDate,
            [string]$User = 'adele.vance@contoso.com',
            [string]$AppHost = 'bizchat',
            [object[]]$Contexts = @(),
            [object[]]$AccessedResources = @(),
            [string]$AppIdentity = 'Copilot.MicrosoftCopilot.BizChat',
            [string]$ThreadId = '19:thread-1@thread.v2'
        )
        $auditData = @{
            Operation        = 'CopilotInteraction'
            AppIdentity      = $AppIdentity
            CopilotEventData = @{
                AppHost           = $AppHost
                ThreadId          = $ThreadId
                Contexts          = $Contexts
                AccessedResources = $AccessedResources
            }
        }
        [pscustomobject]@{
            Identity     = $Identity
            CreationDate = $CreationDate
            UserIds      = $User
            AuditData    = ($auditData | ConvertTo-Json -Depth 6 -Compress)
            ResultIndex  = 0
            ResultCount  = 0
        }
    }

    # Serves $global:FakeAuditLog the way the real cmdlet does: filtered by date range,
    # paged per SessionId, with ResultIndex/ResultCount stamped on every record.
    function global:Search-UnifiedAuditLog {
        param($StartDate, $EndDate, $RecordType, $SessionId, $SessionCommand, $ResultSize)
        $global:SearchCalls++
        if ($global:FailNextSearches -gt 0) { $global:FailNextSearches--; throw 'Simulated transient service error' }

        $inRange = @($global:FakeAuditLog | Where-Object { $_.CreationDate -ge $StartDate -and $_.CreationDate -lt $EndDate })
        $total = $inRange.Count
        if ($global:ReportedCountOverride -and (($EndDate - $StartDate).TotalMinutes -gt $global:OverrideAboveMinutes)) { $total = $global:ReportedCountOverride }

        if (-not $global:SessionOffsets.ContainsKey($SessionId)) { $global:SessionOffsets[$SessionId] = 0 }
        $offset = $global:SessionOffsets[$SessionId]
        $page = @($inRange | Select-Object -Skip $offset -First $global:FakePageSize)
        $global:SessionOffsets[$SessionId] = $offset + $page.Count

        $index = $offset
        foreach ($record in $page) {
            $index++
            $record.ResultIndex = $index
            $record.ResultCount = $total
            $record
        }
    }

    function Reset-FakeService {
        $global:FakeAuditLog = @()
        $global:SessionOffsets = @{}
        $global:SearchCalls = 0
        $global:FailNextSearches = 0
        $global:FakePageSize = 5000
        $global:ReportedCountOverride = 0
        $global:OverrideAboveMinutes = 0
    }

    function Invoke-EventsScript ([string]$Folder, [hashtable]$Extra = @{}) {
        & $script:EventsScript -OutputFolder $Folder -UseExistingSession @Extra *> $null
    }
}

AfterAll {
    Remove-Item function:\Search-UnifiedAuditLog -ErrorAction SilentlyContinue
    'FakeAuditLog', 'SessionOffsets', 'SearchCalls', 'FailNextSearches', 'FakePageSize', 'ReportedCountOverride', 'OverrideAboveMinutes' |
        ForEach-Object { Remove-Variable -Name $_ -Scope Global -ErrorAction SilentlyContinue }
}

Describe 'ConvertTo-CopilotEventRow' {
    BeforeAll {
        . $script:EventsScript
        $script:LogFile = Join-Path $TestDrive 'convert.log'
        $script:When = [datetime]::new(2026, 3, 5, 14, 7, 9, [DateTimeKind]::Utc)
    }

    It 'writes the timestamp in the invariant dd-MMM-yyyy format the report parses' {
        $previous = [cultureinfo]::CurrentCulture
        try {
            [cultureinfo]::CurrentCulture = 'fr-FR'
            (ConvertTo-CopilotEventRow (New-FakeAuditRecord -CreationDate $When)).TimeStamp | Should -BeExactly '05-Mar-2026 14:07:09'
        } finally { [cultureinfo]::CurrentCulture = $previous }
    }

    It 'maps <AppHost> with context type <Type> to <Expected>' -ForEach @(
        @{ AppHost = 'bizchat';        Type = $null;          Expected = 'Copilot for M365 Chat' }
        @{ AppHost = 'Outlook';        Type = $null;          Expected = 'Outlook' }
        @{ AppHost = 'Copilot Studio'; Type = $null;          Expected = 'Copilot Studio Agent' }
        @{ AppHost = 'Office';         Type = 'docx';         Expected = 'Word' }
        @{ AppHost = 'Office';         Type = 'xlsx';         Expected = 'Excel' }
        @{ AppHost = 'Office';         Type = 'pptx';         Expected = 'PowerPoint' }
        @{ AppHost = 'Office';         Type = 'TeamsMeeting'; Expected = 'Teams' }
        @{ AppHost = 'Office';         Type = 'StreamVideo';  Expected = 'Stream' }
        @{ AppHost = 'Word';           Type = $null;          Expected = 'Word' }
        @{ AppHost = 'SomethingNew';   Type = $null;          Expected = 'Copilot for M365' }
    ) {
        $contexts = if ($Type) { @(@{ Id = 'https://contoso.sharepoint.com/sites/hr/doc'; Type = $Type }) } else { @() }
        (ConvertTo-CopilotEventRow (New-FakeAuditRecord -CreationDate $When -AppHost $AppHost -Contexts $contexts)).App | Should -Be $Expected
    }

    It 'recognises Teams chats on the <Domain> domain' -ForEach @(
        @{ Domain = 'teams.microsoft.com' }      # Commercial and GCC
        @{ Domain = 'teams.microsoft.us' }       # GCC High
        @{ Domain = 'dod.teams.microsoft.us' }   # DoD
    ) {
        $contexts = @(@{ Id = "https://$Domain/l/chat/19:abc/conversations?ctx=chat"; Type = 'TeamsChat' })
        $row = ConvertTo-CopilotEventRow (New-FakeAuditRecord -CreationDate $When -AppHost 'Teams' -Contexts $contexts)
        $row.App | Should -Be 'Teams'
        $row.Location | Should -Be 'Teams Chat'
    }

    It 'distinguishes Teams channels, SharePoint and OneDrive locations' {
        $channel = @(@{ Id = 'https://teams.microsoft.us/l/message/19:abc?ctx=channel'; Type = 'TeamsChannel' })
        (ConvertTo-CopilotEventRow (New-FakeAuditRecord -CreationDate $When -Contexts $channel)).Location | Should -Be 'Teams Channel'
        $site = @(@{ Id = 'https://contoso.sharepoint.us/sites/hr/plan.docx'; Type = 'docx' })
        (ConvertTo-CopilotEventRow (New-FakeAuditRecord -CreationDate $When -Contexts $site)).Location | Should -Be 'SharePoint Online'
        $personal = @(@{ Id = 'https://contoso-my.sharepoint.com/personal/adele/plan.docx'; Type = 'docx' })
        (ConvertTo-CopilotEventRow (New-FakeAuditRecord -CreationDate $When -Contexts $personal)).Location | Should -Be 'OneDrive for Business'
    }

    It 'extracts the agent name from a Copilot Studio AppIdentity' {
        $record = New-FakeAuditRecord -CreationDate $When -AppHost 'Copilot Studio' -AppIdentity 'Copilot.Studio.cr123_benefitsHelper'
        (ConvertTo-CopilotEventRow $record).AgentName | Should -Be 'benefitsHelper'
    }

    It 'joins accessed resources and strips line breaks that would split a CSV row' {
        $resources = @(
            @{ Name = "Budget`r`nFY26.xlsx"; Id = 'https://contoso.sharepoint.com/sites/fin/Budget.xlsx'; Action = 'Read' }
            @{ Name = 'Plan.docx'; Id = 'https://contoso.sharepoint.com/sites/fin/Plan.docx'; Action = 'Read' }
        )
        $row = ConvertTo-CopilotEventRow (New-FakeAuditRecord -CreationDate $When -AccessedResources $resources)
        $row.'Accessed Resources' | Should -Be 'Budget FY26.xlsx, Plan.docx'
        $row.Action | Should -Be 'Read'
    }

    It 'still produces a row when AuditData is not valid JSON' {
        $record = New-FakeAuditRecord -CreationDate $When
        $record.AuditData = '{not json'
        $row = ConvertTo-CopilotEventRow $record
        $row.App | Should -Be 'Copilot for M365'
        $row.User | Should -Be 'adele.vance@contoso.com'
    }
}

Describe 'Get-CopilotAuditEvents.ps1 export' {
    BeforeEach {
        Reset-FakeService
        Mock Start-Sleep { }        # the script backs off between retries; tests should not wait
        $script:Folder = Join-Path $TestDrive ([guid]::NewGuid().ToString())
        $script:Csv = Join-Path $Folder 'Copilot_Events.csv'
        $script:Now = [datetime]::UtcNow
    }

    It 'creates the 9-column file the Power BI template expects' {
        $global:FakeAuditLog = @(New-FakeAuditRecord -CreationDate $Now.AddDays(-2))
        Invoke-EventsScript $Folder @{ InitialLookbackDays = 5 }

        $lines = @(Get-Content $Csv)
        $lines[0] | Should -BeExactly '"TimeStamp","User","App","Location","App context","Accessed Resources","Accessed Resource Locations","Action","AgentName"'
        $lines.Count | Should -Be 2
        [System.IO.File]::ReadAllBytes($Csv)[0] | Should -Be ([byte][char]'"') -Because 'the file must not start with a byte order mark'
    }

    It 'writes rows in date order and removes duplicate records returned by the service' {
        $a = New-FakeAuditRecord -Identity 'a' -CreationDate $Now.AddHours(-30)
        $b = New-FakeAuditRecord -Identity 'b' -CreationDate $Now.AddHours(-40)
        $global:FakeAuditLog = @($a, $b, $a)
        Invoke-EventsScript $Folder @{ InitialLookbackDays = 3; IntervalMinutes = 1440 }

        $rows = @(Import-Csv $Csv)
        $rows.Count | Should -Be 2
        [datetime]::ParseExact($rows[0].TimeStamp, 'dd-MMM-yyyy HH:mm:ss', [cultureinfo]::InvariantCulture) |
            Should -BeLessThan ([datetime]::ParseExact($rows[1].TimeStamp, 'dd-MMM-yyyy HH:mm:ss', [cultureinfo]::InvariantCulture))
    }

    It 'pages through windows that hold more records than one call returns' {
        $global:FakePageSize = 3
        $global:FakeAuditLog = @(1..8 | ForEach-Object { New-FakeAuditRecord -CreationDate $Now.AddHours(-10).AddMinutes($_) -User "user$_@contoso.com" })
        Invoke-EventsScript $Folder @{ InitialLookbackDays = 1 }
        @(Import-Csv $Csv).Count | Should -Be 8
    }

    It 'is incremental: a second run adds only new events and picks up late-arriving ones' {
        $early = New-FakeAuditRecord -CreationDate $Now.AddHours(-50) -User 'early@contoso.com'
        $recent = New-FakeAuditRecord -CreationDate $Now.AddHours(-5) -User 'recent@contoso.com'
        $global:FakeAuditLog = @($early, $recent)
        Invoke-EventsScript $Folder @{ InitialLookbackDays = 3 }
        @(Import-Csv $Csv).Count | Should -Be 2

        # "late" happened before the newest exported event but only became searchable afterwards.
        $late = New-FakeAuditRecord -CreationDate $Now.AddHours(-9) -User 'late@contoso.com'
        $new = New-FakeAuditRecord -CreationDate $Now.AddMinutes(-20) -User 'new@contoso.com'
        $global:FakeAuditLog = @($early, $recent, $late, $new)
        Invoke-EventsScript $Folder

        $users = @(Import-Csv $Csv).User
        $users.Count | Should -Be 4
        $users | Should -Contain 'late@contoso.com'
        @($users | Where-Object { $_ -eq 'recent@contoso.com' }).Count | Should -Be 1
    }

    It 'changes nothing when it runs again with no new events' {
        $global:FakeAuditLog = @(1..5 | ForEach-Object { New-FakeAuditRecord -CreationDate $Now.AddHours(-$_) -User "user$_@contoso.com" })
        Invoke-EventsScript $Folder @{ InitialLookbackDays = 2 }
        $before = Get-FileHash $Csv
        Invoke-EventsScript $Folder
        (Get-FileHash $Csv).Hash | Should -Be $before.Hash
    }

    It 'keeps genuinely repeated rows instead of collapsing them' {
        $when = $Now.AddHours(-3)
        $global:FakeAuditLog = @(
            New-FakeAuditRecord -Identity 'twin-1' -CreationDate $when
            New-FakeAuditRecord -Identity 'twin-2' -CreationDate $when
        )
        Invoke-EventsScript $Folder @{ InitialLookbackDays = 1 }
        Invoke-EventsScript $Folder
        @(Import-Csv $Csv).Count | Should -Be 2
    }

    It 'resumes from a file written by the upstream script' {
        New-Item -ItemType Directory -Path $Folder | Out-Null
        $stamp = $Now.AddHours(-6).ToString('dd-MMM-yyyy HH:mm:ss', [cultureinfo]::InvariantCulture)
        @(
            '"TimeStamp","User","App","Location","App context","Accessed Resources","Accessed Resource Locations","Action","AgentName"'
            "`"$stamp`",`"old@contoso.com`",`"Word`",,,`"`",`"`",`"`",`"`""
        ) | Set-Content -Path $Csv -Encoding utf8
        $global:FakeAuditLog = @(
            New-FakeAuditRecord -CreationDate $Now.AddDays(-20) -User 'ancient@contoso.com'
            New-FakeAuditRecord -CreationDate $Now.AddHours(-1) -User 'fresh@contoso.com'
        )
        Invoke-EventsScript $Folder

        $users = @(Import-Csv $Csv).User
        $users | Should -Contain 'fresh@contoso.com'
        $users | Should -Not -Contain 'ancient@contoso.com' -Because 'incremental runs must not re-read the whole lookback period'
    }

    It 'halves the search window when a window reaches the 50,000 record limit' {
        $global:FakeAuditLog = @(1..6 | ForEach-Object { New-FakeAuditRecord -CreationDate $Now.AddHours(-20).AddHours($_ * 3) -User "user$_@contoso.com" })
        $global:ReportedCountOverride = 50000
        $global:OverrideAboveMinutes = 400          # any window longer than 400 minutes claims to be full
        Invoke-EventsScript $Folder @{ InitialLookbackDays = 1; IntervalMinutes = 1440 }

        @(Import-Csv $Csv).Count | Should -Be 6
        (Get-Content (Join-Path $Folder 'AuditScriptLog.txt')) -join "`n" | Should -Match 'Reducing the interval to 720 minutes'
    }

    It 'retries a failed search and still exports everything' {
        $global:FakeAuditLog = @(New-FakeAuditRecord -CreationDate $Now.AddHours(-2))
        $global:FailNextSearches = 2
        Invoke-EventsScript $Folder @{ InitialLookbackDays = 1 }
        @(Import-Csv $Csv).Count | Should -Be 1
    }
}
