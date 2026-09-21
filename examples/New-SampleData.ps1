<#
.SYNOPSIS
    Creates fictitious Copilot_Events.csv and Copilot_Users.csv files for trying out the report.

.DESCRIPTION
    Generates a made-up "Contoso" organisation and several months of made-up Copilot activity in
    exactly the layout that Get-CopilotAuditEvents.ps1 and Get-CopilotUsers.ps1 produce. Nothing
    is read from any tenant. The same -Seed and -EndDate always produce the same files.

.PARAMETER OutputFolder
    Folder to write the two CSV files to. Created if it does not exist.

.PARAMETER Days
    Number of days of activity to generate, counting back from -EndDate.

.PARAMETER EndDate
    Last day of generated activity. Defaults to today so the report's date slicers look current.

.PARAMETER Seed
    Seed for the random number generator.

.EXAMPLE
    .\examples\New-SampleData.ps1 -OutputFolder C:\M365CopilotReport\Sample
#>
[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)]
    [string]$OutputFolder,

    [ValidateRange(7, 365)]
    [int]$Days = 120,

    [DateTime]$EndDate = (Get-Date).Date,

    [int]$Seed = 365
)

$random = New-Object System.Random($Seed)
$invariant = [System.Globalization.CultureInfo]::InvariantCulture
$utf8NoBom = New-Object System.Text.UTF8Encoding($false)
$domain = 'contoso.com'

function Get-RandomItem ([object[]]$Items) { $Items[$random.Next($Items.Count)] }

# Deterministic GUID so that repeated runs produce identical files.
function New-SeededGuid {
    $bytes = New-Object byte[] 16
    $random.NextBytes($bytes)
    (New-Object Guid (, $bytes)).ToString()
}

#region Organisation
$firstNames = 'Avery', 'Blake', 'Casey', 'Devon', 'Emery', 'Finley', 'Harper', 'Jordan', 'Kendall', 'Logan', 'Morgan', 'Noel', 'Parker', 'Quinn', 'Reese', 'Rowan', 'Sawyer', 'Skyler', 'Taylor', 'Robin'
$lastNames = 'Ashford', 'Bellamy', 'Calloway', 'Draper', 'Ellison', 'Fairbanks', 'Garrison', 'Holloway', 'Iverson', 'Kingsley', 'Lockwood', 'Merritt', 'Northrop', 'Oakley', 'Prescott', 'Radcliffe', 'Sinclair', 'Thackeray', 'Underhill', 'Whitlock'
$departments = [ordered]@{
    'Finance'     = 'Financial Analyst', 'Senior Accountant', 'Budget Analyst'
    'Engineering' = 'Software Engineer', 'Senior Engineer', 'Program Manager'
    'Sales'       = 'Account Executive', 'Sales Specialist', 'Solution Advisor'
    'Operations'  = 'Operations Analyst', 'Project Coordinator', 'Logistics Planner'
    'Legal'       = 'Paralegal', 'Counsel', 'Contracts Specialist'
}
$cities = 'Seattle', 'Denver', 'Austin', 'Chicago', 'Reston'

$usedNames = New-Object 'System.Collections.Generic.HashSet[string]'
function New-Person ([string]$JobTitle, [string]$Department, $Manager, [bool]$Licensed) {
    do { $name = "$(Get-RandomItem $firstNames) $(Get-RandomItem $lastNames)" } until ($usedNames.Add($name))
    [pscustomobject]@{
        EntraID           = New-SeededGuid
        DisplayName       = $name
        UserPrincipalName = ($name -replace ' ', '.').ToLowerInvariant() + "@$domain"
        JobTitle          = $JobTitle
        Department        = $Department
        City              = Get-RandomItem $cities
        Country           = 'United States'
        UsageLocation     = 'US'
        ManagerName       = if ($Manager) { $Manager.DisplayName } else { '' }
        ManagerUPN        = if ($Manager) { $Manager.UserPrincipalName } else { '' }
        HasCopilotLicense = $Licensed
    }
}

$people = New-Object System.Collections.Generic.List[object]
$ceo = New-Person 'Chief Executive Officer' 'Executive' $null $true
$people.Add($ceo)
foreach ($department in $departments.Keys) {
    $head = New-Person "Director of $department" $department $ceo $true
    $people.Add($head)
    foreach ($i in 1..5) {
        # About one in five staff have no Copilot license; they still show up through Copilot Chat.
        $people.Add((New-Person (Get-RandomItem $departments[$department]) $department $head ($random.NextDouble() -gt 0.2)))
    }
}
#endregion

#region Activity
$agents = 'benefitsHelper', 'itHelpdesk', 'travelPolicy'
$documents = @{
    Word       = @{ Extension = 'docx'; Names = 'Project Plan', 'Quarterly Review', 'Policy Draft', 'Meeting Notes', 'Proposal' }
    Excel      = @{ Extension = 'xlsx'; Names = 'FY26 Budget', 'Forecast', 'Pipeline Tracker', 'Headcount Plan', 'Expense Summary' }
    PowerPoint = @{ Extension = 'pptx'; Names = 'Town Hall', 'Customer Briefing', 'Roadmap', 'Kickoff Deck', 'Status Update' }
}
# App name as written by Get-CopilotAuditEvents.ps1, and its relative share of activity.
$appWeights = [ordered]@{
    'Copilot for M365 Chat' = 38; 'Teams' = 16; 'Word' = 12; 'Outlook' = 11; 'Excel' = 8
    'PowerPoint' = 6; 'Copilot Studio Agent' = 5; 'Loop' = 2; 'Whiteboard' = 1; 'Stream' = 1
}
$appPool = foreach ($app in $appWeights.Keys) { , $app * $appWeights[$app] }
# Hour-of-day weights (UTC) concentrated on a working day.
$hourPool = foreach ($hour in 0..23) { $weight = switch ($hour) { { $_ -in 14..17 } { 10 } { $_ -in 13, 18, 19, 20 } { 6 } { $_ -in 12, 21, 22 } { 3 } default { 1 } }; , $hour * $weight }

function New-EventRow ([DateTime]$When, $Person, [string]$App) {
    $location = $null; $context = $null; $resources = ''; $resourceLocations = ''; $action = ''; $agentName = ''
    $site = "https://contoso.sharepoint.com/sites/$($Person.Department)/Shared Documents"
    $oneDrive = "https://contoso-my.sharepoint.com/personal/$(($Person.UserPrincipalName -replace '[@.]', '_'))/Documents"

    switch ($App) {
        { $_ -in 'Word', 'Excel', 'PowerPoint' } {
            $file = "$(Get-RandomItem $documents[$App].Names).$($documents[$App].Extension)"
            if ($random.NextDouble() -lt 0.6) { $location = 'SharePoint Online'; $context = "$site/$file" } else { $location = 'OneDrive for Business'; $context = "$oneDrive/$file" }
            $resources = $file; $resourceLocations = $context; $action = 'Read'
        }
        'Teams' {
            $kind = $random.Next(3)
            if ($kind -eq 0) { $location = 'Teams meeting'; $context = "https://teams.microsoft.com/l/meetup-join/19:meeting_$(New-SeededGuid)@thread.v2" }
            elseif ($kind -eq 1) { $location = 'Teams Channel'; $context = "https://teams.microsoft.com/l/message/19:$(New-SeededGuid)@thread.tacv2?ctx=channel" }
            else { $location = 'Teams Chat'; $context = "https://teams.microsoft.com/l/chat/19:$(New-SeededGuid)@unq.gbl.spaces?ctx=chat" }
        }
        'Copilot for M365 Chat' {
            $context = "19:$(New-SeededGuid)@thread.v2"
            if ($random.NextDouble() -lt 0.35) {
                $kind = Get-RandomItem @('Word', 'Excel', 'PowerPoint')
                $file = "$(Get-RandomItem $documents[$kind].Names).$($documents[$kind].Extension)"
                $resources = $file; $resourceLocations = "$site/$file"; $action = 'Read'
            }
        }
        'Copilot Studio Agent' { $context = "19:$(New-SeededGuid)@thread.v2"; $agentName = Get-RandomItem $agents }
        'Stream' { $location = 'Stream video player'; $context = "$site/Recordings/All Hands.mp4" }
        'Loop' { $location = 'SharePoint Online'; $context = "$site/Workspace Notes.loop" }
        default { $context = "19:$(New-SeededGuid)@thread.v2" }
    }

    [pscustomobject][ordered]@{
        TimeStamp                     = $When.ToString('dd-MMM-yyyy HH:mm:ss', $invariant)
        User                          = $Person.UserPrincipalName
        App                           = $App
        Location                      = $location
        'App context'                 = $context
        'Accessed Resources'          = $resources
        'Accessed Resource Locations' = $resourceLocations
        Action                        = $action
        AgentName                     = $agentName
    }
}

# Each person gets an engagement level; adoption ramps up over the period.
$engagement = @{}
foreach ($person in $people) { $engagement[$person.UserPrincipalName] = if ($person.HasCopilotLicense) { 0.5 + $random.NextDouble() * 3.5 } else { $random.NextDouble() * 0.6 } }

$rows = New-Object System.Collections.Generic.List[object]
$firstDay = $EndDate.Date.AddDays(-$Days)
for ($offset = 0; $offset -le $Days; $offset++) {
    $day = $firstDay.AddDays($offset)
    $dayFactor = if ($day.DayOfWeek -in 'Saturday', 'Sunday') { 0.08 } else { 1.0 }
    $rampFactor = 0.35 + 0.65 * ($offset / $Days)
    foreach ($person in $people) {
        $expected = $engagement[$person.UserPrincipalName] * $dayFactor * $rampFactor
        $count = [int][Math]::Floor($expected) + $(if ($random.NextDouble() -lt ($expected % 1)) { 1 } else { 0 })
        for ($i = 0; $i -lt $count; $i++) {
            $when = $day.AddHours((Get-RandomItem $hourPool)).AddSeconds($random.Next(3600))
            # People without a license only have Copilot Chat.
            $app = if ($person.HasCopilotLicense) { Get-RandomItem $appPool } else { 'Copilot for M365 Chat' }
            $rows.Add((New-EventRow $when $person $app))
        }
    }
}
#endregion

#region Write files
$OutputFolder = $ExecutionContext.SessionState.Path.GetUnresolvedProviderPathFromPSPath($OutputFolder)
if (-not (Test-Path -LiteralPath $OutputFolder)) { New-Item -ItemType Directory -Path $OutputFolder -Force | Out-Null }

$sortedRows = $rows | Sort-Object { [DateTime]::ParseExact($_.TimeStamp, 'dd-MMM-yyyy HH:mm:ss', $invariant) }
[System.IO.File]::WriteAllLines((Join-Path $OutputFolder 'Copilot_Events.csv'), [string[]]@($sortedRows | ConvertTo-Csv -NoTypeInformation), $utf8NoBom)
[System.IO.File]::WriteAllLines((Join-Path $OutputFolder 'Copilot_Users.csv'), [string[]]@($people | ConvertTo-Csv -NoTypeInformation), $utf8NoBom)

Write-Host "Wrote $($rows.Count) fictitious events and $($people.Count) fictitious users to $OutputFolder" -ForegroundColor Green
#endregion
