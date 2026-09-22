<#
.SYNOPSIS
    Exports Microsoft 365 Copilot interaction events from the Purview unified audit log
    to Copilot_Events.csv (Commercial edition).

.DESCRIPTION
    Reads CopilotInteraction records with Search-UnifiedAuditLog and appends them to
    <OutputFolder>\Copilot_Events.csv in the 9-column layout that
    "M365 Copilot Audit Report.pbit" expects.

    The first run looks back -InitialLookbackDays. Later runs are incremental: they resume
    from the newest event already in the CSV, re-read the previous -OverlapHours to pick up
    audit records that Microsoft 365 ingested late, and skip rows that are already in the file.

    This edition targets Microsoft 365 commercial / worldwide tenants.

.PARAMETER OutputFolder
    Folder for Copilot_Events.csv and AuditScriptLog.txt. Created if it does not exist.

.PARAMETER InitialLookbackDays
    How far back the first run searches. Audit (Standard) keeps records for 180 days,
    Audit (Premium) for one year. Ignored once the CSV contains events.

.PARAMETER OverlapHours
    Hours before the newest exported event to search again on incremental runs.
    Audit records can take up to 24 hours to become searchable. Use 0 to disable.

.PARAMETER IntervalMinutes
    Size of each search window. A single window can return at most 50,000 records; the
    script halves the window automatically when a window reaches that limit.

.PARAMETER UserPrincipalName
    Optional sign-in name to pre-fill the interactive sign-in prompt.

.PARAMETER DisableWAM
    Sign in through the web browser instead of the Windows account broker (WAM). Use this if
    the sign-in prompt never appears, or PowerShell closes or hangs when the prompt should open.

.PARAMETER AppId
    Application (client) ID for unattended, certificate-based sign-in. See docs/scheduling.md.

.PARAMETER Organization
    Tenant's initial domain for unattended sign-in, for example contoso.onmicrosoft.com.

.PARAMETER CertificateThumbprint
    Thumbprint of the certificate (in the CurrentUser or LocalMachine store) for unattended sign-in.

.PARAMETER UseExistingSession
    Use the Exchange Online PowerShell session that is already connected in this window
    instead of connecting and disconnecting.

.PARAMETER InstallMissingModules
    Install the ExchangeOnlineManagement module for the current user if it is missing.

.EXAMPLE
    .\Get-CopilotAuditEvents.ps1

    Interactive sign-in, output to C:\M365CopilotReport.

.EXAMPLE
    .\Get-CopilotAuditEvents.ps1 -OutputFolder D:\CopilotReport -InitialLookbackDays 180

.EXAMPLE
    .\Get-CopilotAuditEvents.ps1 -AppId 00000000-0000-0000-0000-000000000000 -Organization contoso.onmicrosoft.com -CertificateThumbprint 0123456789ABCDEF0123456789ABCDEF01234567

    Unattended run, for example from Task Scheduler.

.NOTES
    Derived from Audit-Get-Events.ps1 in https://github.com/BojanBuhac/M365-Copilot-Audit-Report
    (GPL-3.0), which credits https://github.com/12Knocksinna/Office365itpros.
    Licensed under GPL-3.0. See LICENSE and NOTICE.md.
#>
[CmdletBinding(DefaultParameterSetName = 'Interactive')]
param(
    [string]$OutputFolder = 'C:\M365CopilotReport',

    [ValidateRange(1, 365)]
    [int]$InitialLookbackDays = 365,

    [ValidateRange(0, 168)]
    [int]$OverlapHours = 24,

    [ValidateRange(5, 1440)]
    [int]$IntervalMinutes = 1440,

    [Parameter(ParameterSetName = 'Interactive')]
    [string]$UserPrincipalName,

    [Parameter(ParameterSetName = 'Interactive')]
    [switch]$DisableWAM,

    [Parameter(ParameterSetName = 'AppOnly', Mandatory = $true)]
    [string]$AppId,

    [Parameter(ParameterSetName = 'AppOnly', Mandatory = $true)]
    [string]$Organization,

    [Parameter(ParameterSetName = 'AppOnly', Mandatory = $true)]
    [string]$CertificateThumbprint,

    [Parameter(ParameterSetName = 'ExistingSession', Mandatory = $true)]
    [switch]$UseExistingSession,

    [switch]$InstallMissingModules
)

#region Cloud profile: Commercial
# Generated from src/clouds.psd1 by tools/Build-CloudScripts.ps1. Do not edit by hand.
$CloudProfile = @{
    Name                    = 'Commercial'
    ExchangeEnvironmentName = ''   # empty = worldwide endpoints, parameter is omitted
    GraphEnvironment        = ''   # empty = worldwide endpoints, parameter is omitted
    KnownCopilotSkuIds      = @('639dec6b-bb19-468b-871c-c5c441c4b0cb')
}
#endregion

$TimestampFormat = 'dd-MMM-yyyy HH:mm:ss'
$Invariant = [System.Globalization.CultureInfo]::InvariantCulture
$Utf8NoBom = New-Object System.Text.UTF8Encoding($false)
$TeamsUrlPattern = '*://*teams.microsoft.*/*'
$MaxRecordsPerWindow = 50000
$MinIntervalMinutes = 5
$MaxWindowAttempts = 3
$RetryDelaySeconds = 15
$script:AppHostSummary = @{}       # 'AppHost -> App' counts, logged at the end to help improve the mapping
# Host applications named in Microsoft's audit documentation, mapped to the app names the report
# uses. Used when the record carries no recognised file or meeting context.
# https://learn.microsoft.com/purview/audit-copilot#common-apphost-scenarios-in-copilot
$AppHostMap = @{
    'BizChat' = 'Copilot for M365 Chat'; 'Bing' = 'Copilot for M365 Chat'; 'Edge' = 'Copilot for M365 Chat'
    'Office' = 'Copilot for M365 Chat'; 'M365App' = 'Copilot for M365 Chat'
    'OfficeCopilotNotebook' = 'Copilot for M365 Chat'; 'OfficeCopilotSearchAnswer' = 'Copilot for M365 Chat'
    'OneNoteCopilotNotebook' = 'Copilot for M365 Chat'
    'Word' = 'Word'; 'WordOnCanvas' = 'Word'
    'Excel' = 'Excel'
    'PowerPoint' = 'PowerPoint'; 'PowerPointOnCanvas' = 'PowerPoint'
    'Outlook' = 'Outlook'; 'OutlookOnCanvas' = 'Outlook'; 'OutlookSidepane' = 'Outlook'
    'Teams' = 'Teams'; 'Loop' = 'Loop'; 'Whiteboard' = 'Whiteboard'; 'Stream' = 'Stream'
    'OneNote' = 'OneNote'; 'SharePoint' = 'SharePoint'; 'OneDrive' = 'OneDrive'
    'Forms' = 'Forms'; 'Planner' = 'Planner'; 'Designer' = 'Designer'
    'VivaEngage' = 'Viva Engage'; 'VivaGoals' = 'Viva Goals'; 'VivaPulse' = 'Viva Pulse'
    'Copilot Studio' = 'Copilot Studio Agent'
}

function Write-LogFile ([string]$Message) {
    $final = [DateTime]::UtcNow.ToString('s') + ':' + $Message
    $final | Out-File -FilePath $script:LogFile -Append -Encoding utf8
}

# The CSV always starts a data row with the quoted 20-character timestamp, which is UTC. The result
# is marked as UTC: Exchange Online treats a date without a kind as local time, which would shift
# every incremental search window by the machine's time-zone offset.
function Get-CsvLineTimestamp ([string]$Line) {
    if ($Line.Length -lt 22 -or $Line[0] -ne '"') { return $null }
    $parsed = [DateTime]::MinValue
    $styles = [System.Globalization.DateTimeStyles]::AssumeUniversal -bor [System.Globalization.DateTimeStyles]::AdjustToUniversal
    if ([DateTime]::TryParseExact($Line.Substring(1, 20), $TimestampFormat, $Invariant, $styles, [ref]$parsed)) {
        return $parsed
    }
    return $null
}

# Identifies an exported event by the values that come straight from the audit record. The derived
# App, Location and AgentName columns are left out so that a newer script version that classifies
# an event differently still recognises it as already exported.
function Get-EventKey ($Row) {
    return (($Row.TimeStamp, $Row.User, $Row.'App context', $Row.'Accessed Resource Locations', $Row.Action) -join [char]31)
}

# Finds the newest exported event and counts the rows inside the overlap period so that
# re-read audit records can be skipped without collapsing genuinely repeated rows.
function Get-ExistingEventState ([string]$Path, [int]$OverlapHours) {
    $state = @{
        NewestTimestamp = $null
        OverlapRows     = New-Object 'System.Collections.Generic.Dictionary[string,int]'
    }
    if (-not (Test-Path -LiteralPath $Path -PathType Leaf)) { return $state }

    $header = $null
    foreach ($line in [System.IO.File]::ReadLines($Path)) {
        if ($null -eq $header) { $header = $line }
        $timestamp = Get-CsvLineTimestamp $line
        if ($null -ne $timestamp -and ($null -eq $state.NewestTimestamp -or $timestamp -gt $state.NewestTimestamp)) {
            $state.NewestTimestamp = $timestamp
        }
    }
    if ($null -eq $state.NewestTimestamp) { return $state }

    $cutoff = $state.NewestTimestamp.AddHours(-$OverlapHours)
    $overlapLines = New-Object 'System.Collections.Generic.List[string]'
    foreach ($line in [System.IO.File]::ReadLines($Path)) {
        $timestamp = Get-CsvLineTimestamp $line
        if ($null -ne $timestamp -and $timestamp -ge $cutoff) { $overlapLines.Add($line) }
    }
    if ($overlapLines.Count -gt 0) {
        foreach ($row in ((@($header) + @($overlapLines)) | ConvertFrom-Csv)) {
            $key = Get-EventKey $row
            if ($state.OverlapRows.ContainsKey($key)) { $state.OverlapRows[$key]++ } else { $state.OverlapRows[$key] = 1 }
        }
    }
    return $state
}

# Power BI reads the file with QuoteStyle.None, so a line break inside a value would split the row.
function Remove-LineBreaks ($Value) {
    if ($null -eq $Value) { return $null }
    return ([string]$Value) -replace '[\r\n]+', ' '
}

function ConvertTo-CopilotEventRow ($Record) {
    $AuditData = $null
    try {
        $AuditData = $Record.AuditData | ConvertFrom-Json -ErrorAction Stop
    } catch {
        Write-LogFile "WARN: Could not parse AuditData for record $($Record.Identity): $_"
    }
    $CopilotApp = 'Copilot for M365'; $Context = $null; $CopilotLocation = $null

    Switch ($AuditData.CopilotEventData.Contexts.Type) {
        "xlsx" {
            $CopilotApp = "Excel"
        }
        "docx" {
            $CopilotApp = "Word"
        }
        "pptx" {
            $CopilotApp = "PowerPoint"
        }
        "TeamsMeeting" {
            $CopilotApp = "Teams"
            $CopilotLocation = "Teams meeting"
        }
        "whiteboard" {
            $CopilotApp = "Whiteboard"
        }
        "loop" {
            $CopilotApp = "Loop"
        }
        "StreamVideo" {
            $CopilotApp = "Stream"
            $CopilotLocation = "Stream video player"
        }
    }

    # teams.microsoft.com (Commercial, GCC), teams.microsoft.us (GCC High), dod.teams.microsoft.us (DoD)
    If ($AuditData.CopilotEventData.Contexts.Id -like $TeamsUrlPattern) {
        $CopilotApp = "Teams"
    } ElseIf ($AuditData.CopilotEventData.AppHost -eq "bizchat") {
        $CopilotApp = "Copilot for M365 Chat"
    } ElseIf ($AuditData.CopilotEventData.AppHost -eq "Outlook") {
        $CopilotApp = "Outlook"
    } ElseIf ($AuditData.CopilotEventData.AppHost -eq "Copilot Studio") {
        $CopilotApp = "Copilot Studio Agent"
    } ElseIf ($CopilotApp -eq 'Copilot for M365' -and $AuditData.CopilotEventData.AppHost -and $AppHostMap.ContainsKey([string]$AuditData.CopilotEventData.AppHost)) {
        # No recognised file or meeting context: classify by the host application Microsoft recorded.
        $CopilotApp = $AppHostMap[[string]$AuditData.CopilotEventData.AppHost]
    }

    If ($AuditData.CopilotEventData.Contexts.Id) {
        $Context = $AuditData.CopilotEventData.Contexts.Id
    } ElseIf ($AuditData.CopilotEventData.ThreadId) {
        $Context = $AuditData.CopilotEventData.ThreadId
    }

    $AgentName = ""
    if ($CopilotApp -eq "Copilot Studio Agent" -and $AuditData.AppIdentity -match '.*_(.+?)$') {
        $AgentName = $Matches[1]
    } elseif ($CopilotApp -eq "Copilot Studio Agent" -and $AuditData.AppIdentity -match '.*-(.+?)$') {
        $AgentName = $Matches[1]
    }

    If ($AuditData.CopilotEventData.Contexts.Id -like "*/sites/*") {
        $CopilotLocation = "SharePoint Online"
    } ElseIf ($AuditData.CopilotEventData.Contexts.Id -like $TeamsUrlPattern) {
        If ($AuditData.CopilotEventData.Contexts.Id -like "*ctx=channel*") {
            $CopilotLocation = "Teams Channel"
        } Else {
            $CopilotLocation = "Teams Chat"
        }
    } ElseIf ($AuditData.CopilotEventData.Contexts.Id -like "*/personal/*") {
        $CopilotLocation = "OneDrive for Business"
    }

    # Report the resources used by Copilot and the action (like read) used to access them
    [array]$AccessedResources = $AuditData.CopilotEventData.AccessedResources.Name | Sort-Object -Unique
    [string]$AccessedResources = $AccessedResources -join ", "
    [array]$AccessedResourceLocations = $AuditData.CopilotEventData.AccessedResources.Id | Sort-Object -Unique
    [string]$AccessedResourceLocations = $AccessedResourceLocations -join ", "
    [array]$AccessedResourceActions = $AuditData.CopilotEventData.AccessedResources.Action | Sort-Object -Unique
    [string]$AccessedResourceActions = $AccessedResourceActions -join ", "

    $summaryKey = "$(if ($AuditData.CopilotEventData.AppHost) { $AuditData.CopilotEventData.AppHost } else { '(no AppHost)' }) -> $CopilotApp"
    $script:AppHostSummary[$summaryKey] = 1 + $(if ($script:AppHostSummary.ContainsKey($summaryKey)) { $script:AppHostSummary[$summaryKey] } else { 0 })

    $created = [DateTime]$Record.CreationDate
    if ($created.Kind -eq [DateTimeKind]::Local) { $created = $created.ToUniversalTime() }
    if ($Context -is [array]) { $Context = $Context -join ", " }

    [PSCustomObject][Ordered]@{
        TimeStamp                     = $created.ToString($TimestampFormat, $Invariant)
        User                          = Remove-LineBreaks $Record.UserIds
        App                           = $CopilotApp
        Location                      = $CopilotLocation
        'App context'                 = Remove-LineBreaks $Context
        'Accessed Resources'          = Remove-LineBreaks $AccessedResources
        'Accessed Resource Locations' = Remove-LineBreaks $AccessedResourceLocations
        Action                        = Remove-LineBreaks $AccessedResourceActions
        AgentName                     = Remove-LineBreaks $AgentName
    }
}

# Pages through one search window. Returns the de-duplicated records, or TooLarge when the
# window holds more records than a single audit search session can return.
function Get-AuditWindowRecords ([DateTime]$Start, [DateTime]$End, [switch]$IgnoreLimit) {
    $sessionId = [Guid]::NewGuid().ToString() + "_" + "ExtractLogs" + (Get-Date).ToString("yyyyMMddHHmmssfff")
    $byIdentity = @{}
    $resultCount = 0

    while ($true) {
        $page = @(Search-UnifiedAuditLog -StartDate $Start -EndDate $End -RecordType CopilotInteraction -SessionId $sessionId -SessionCommand ReturnLargeSet -ResultSize 5000 -ErrorAction Stop)
        if ($page.Count -eq 0) { break }
        if (@($page | Where-Object { $_.ResultIndex -lt 0 }).Count -gt 0) {
            throw "The audit search session returned an invalid result index (the session probably timed out)."
        }

        $resultCount = [int]$page[0].ResultCount
        if ($resultCount -ge $MaxRecordsPerWindow -and -not $IgnoreLimit) {
            return @{ TooLarge = $true; ResultCount = $resultCount; Records = @() }
        }

        foreach ($record in $page) { $byIdentity[[string]$record.Identity] = $record }
        $highestIndex = ($page | Measure-Object -Property ResultIndex -Maximum).Maximum
        Write-LogFile "INFO: Retrieved $($byIdentity.Count) audit records out of the total $resultCount"
        if ($highestIndex -ge $resultCount) { break }
    }

    return @{ TooLarge = $false; ResultCount = $resultCount; Records = @($byIdentity.Values) }
}

# Dot-source the script to load the functions above without running an export (used by the tests).
if ($MyInvocation.InvocationName -eq '.') { return }

#region Prepare output
$OutputFolder = $ExecutionContext.SessionState.Path.GetUnresolvedProviderPathFromPSPath($OutputFolder)
if (-not (Test-Path -LiteralPath $OutputFolder -PathType Container)) {
    New-Item -ItemType Directory -Path $OutputFolder -Force | Out-Null
}
$script:LogFile = Join-Path $OutputFolder 'AuditScriptLog.txt'
$outputFile = Join-Path $OutputFolder 'Copilot_Events.csv'
#endregion

#region Connect to Exchange Online
$connected = $false
if (-not $UseExistingSession) {
    if (-not (Get-Module -ListAvailable -Name ExchangeOnlineManagement)) {
        if (-not $InstallMissingModules) {
            Write-Host "The ExchangeOnlineManagement module is not installed. Install it with:" -ForegroundColor Yellow
            Write-Host "    Install-Module ExchangeOnlineManagement -Scope CurrentUser" -ForegroundColor Yellow
            Write-Host "or run this script again with -InstallMissingModules." -ForegroundColor Yellow
            exit 1
        }
        Write-Host "Installing module ExchangeOnlineManagement..."
        Install-Module -Name ExchangeOnlineManagement -Force -AllowClobber -Scope CurrentUser -ErrorAction Stop
    }
    Import-Module ExchangeOnlineManagement -ErrorAction Stop

    $connectParams = @{ ShowBanner = $false; ErrorAction = 'Stop' }
    if ($CloudProfile.ExchangeEnvironmentName) { $connectParams.ExchangeEnvironmentName = $CloudProfile.ExchangeEnvironmentName }
    if ($PSCmdlet.ParameterSetName -eq 'AppOnly') {
        $connectParams.AppId = $AppId
        $connectParams.Organization = $Organization
        $connectParams.CertificateThumbprint = $CertificateThumbprint
    } else {
        if ($UserPrincipalName) { $connectParams.UserPrincipalName = $UserPrincipalName }
        if ($DisableWAM) { $connectParams.DisableWAM = $true }
    }

    try {
        Connect-ExchangeOnline @connectParams
        $connected = $true
        Write-Host "Connected to Exchange Online ($($CloudProfile.Name))."
    } catch {
        Write-Host "Failed to connect to Exchange Online ($($CloudProfile.Name)): $_" -ForegroundColor Red
        Write-LogFile "ERROR: Failed to connect to Exchange Online ($($CloudProfile.Name)): $_"
        exit 1
    }
}
#endregion

try {
    #region Work out the date range
    [DateTime]$end = [DateTime]::UtcNow
    $existing = Get-ExistingEventState -Path $outputFile -OverlapHours $OverlapHours
    if ($null -ne $existing.NewestTimestamp) {
        [DateTime]$start = [DateTime]::SpecifyKind($existing.NewestTimestamp, [DateTimeKind]::Utc).AddHours(-$OverlapHours)
        Write-Host "Existing export found. Newest event: $($existing.NewestTimestamp.ToString('u')). Resuming from $($start.ToString('u'))."
    } else {
        [DateTime]$start = $end.AddDays(-$InitialLookbackDays)
    }
    $fileHasHeader = (Test-Path -LiteralPath $outputFile -PathType Leaf) -and ((Get-Item -LiteralPath $outputFile).Length -gt 0)
    #endregion

    Write-LogFile "BEGIN: Retrieving audit records between $($start) and $($end), RecordType=CopilotInteraction, Cloud=$($CloudProfile.Name)."
    Write-Host "Retrieving audit records for the date range between $($start) and $($end), RecordType=CopilotInteraction"

    $totalRetrieved = 0
    $totalWritten = 0
    $totalSkipped = 0
    $seenThisRun = New-Object 'System.Collections.Generic.HashSet[string]'
    $interval = $IntervalMinutes
    [DateTime]$currentStart = $start

    while ($currentStart -lt $end) {
        [DateTime]$currentEnd = $currentStart.AddMinutes($interval)
        if ($currentEnd -gt $end) { $currentEnd = $end }

        Write-LogFile "INFO: Retrieving audit records for activities performed between $($currentStart) and $($currentEnd)"
        Write-Host "Retrieving audit records for activities performed between $($currentStart) and $($currentEnd)"

        $window = $null
        for ($attempt = 1; $attempt -le $MaxWindowAttempts; $attempt++) {
            try {
                $window = Get-AuditWindowRecords -Start $currentStart -End $currentEnd -IgnoreLimit:($interval -le $MinIntervalMinutes)
                break
            } catch {
                Write-LogFile "WARN: Attempt $attempt of $MaxWindowAttempts failed for this time range: $_"
                if ($attempt -eq $MaxWindowAttempts) {
                    throw "Audit search failed $MaxWindowAttempts times between $currentStart and $currentEnd. Nothing after $currentStart was exported; run the script again to resume. Last error: $_"
                }
                Write-Host "Audit search failed (attempt $attempt of $MaxWindowAttempts). Retrying in $RetryDelaySeconds seconds..." -ForegroundColor Yellow
                Start-Sleep -Seconds $RetryDelaySeconds
            }
        }

        if ($window.TooLarge) {
            $interval = [Math]::Max($MinIntervalMinutes, [int][Math]::Floor($interval / 2))
            Write-LogFile "INFO: Time range holds $($window.ResultCount)+ records, more than one search can return. Reducing the interval to $interval minutes."
            Write-Host "More than $MaxRecordsPerWindow records in this time range. Reducing the interval to $interval minutes." -ForegroundColor Yellow
            continue
        }

        # A record on the boundary between two windows is returned by both; the second copy is dropped here.
        $records = @($window.Records | Where-Object { $seenThisRun.Add([string]$_.Identity) } | Sort-Object { $_.CreationDate -as [DateTime] })
        if (@($window.Records).Count -lt $window.ResultCount) {
            Write-LogFile "WARN: The service reported $($window.ResultCount) records for this time range but returned $(@($window.Records).Count)."
        }

        if ($records.Count -gt 0) {
            Write-Host ("{0} Copilot audit records found. Now analyzing the content" -f $records.Count)
            $newRows = New-Object 'System.Collections.Generic.List[object]'
            foreach ($row in @($records | ForEach-Object { ConvertTo-CopilotEventRow $_ })) {
                $key = Get-EventKey $row
                if ($existing.OverlapRows.ContainsKey($key) -and $existing.OverlapRows[$key] -gt 0) {
                    $existing.OverlapRows[$key]--
                    $totalSkipped++
                } else {
                    $newRows.Add($row)
                    $totalWritten++
                }
            }
            if ($newRows.Count -gt 0) {
                $csv = @($newRows | ConvertTo-Csv -NoTypeInformation)
                if ($fileHasHeader) { $csv = @($csv | Select-Object -Skip 1) } else { $fileHasHeader = $true }
                [System.IO.File]::AppendAllLines($outputFile, [string[]]$csv, $Utf8NoBom)
            }
            $totalRetrieved += $records.Count
        }

        Write-LogFile "INFO: Successfully retrieved $($records.Count) audit records for the current time range. Moving on!"
        Write-Host "Successfully retrieved $($records.Count) audit records for the current time range. Moving on to the next interval." -ForegroundColor Yellow

        # Grow the window back towards the requested size once the busy period has passed.
        if ($interval -lt $IntervalMinutes -and $records.Count -lt ($MaxRecordsPerWindow / 4)) {
            $interval = [Math]::Min($IntervalMinutes, $interval * 2)
        }
        $currentStart = $currentEnd
    }

    if ($script:AppHostSummary.Count -gt 0) {
        $summary = ($script:AppHostSummary.GetEnumerator() | Sort-Object Value -Descending | ForEach-Object { "$($_.Key)=$($_.Value)" }) -join ', '
        Write-LogFile "INFO: Apps by audit AppHost this run: $summary"
    }
    Write-LogFile "END: Retrieving audit records between $($start) and $($end). Retrieved: $totalRetrieved, written: $totalWritten, already exported: $totalSkipped."
    Write-Host "Script complete! Retrieved $totalRetrieved audit records between $($start) and $($end). New rows written: $totalWritten. Already exported (skipped): $totalSkipped." -ForegroundColor Green
    Write-Host "Output: $outputFile"
} catch {
    Write-LogFile "ERROR: $_"
    Write-Host "ERROR: $_" -ForegroundColor Red
    exit 1
} finally {
    if ($connected) { Disconnect-ExchangeOnline -Confirm:$false -ErrorAction SilentlyContinue | Out-Null }
}
