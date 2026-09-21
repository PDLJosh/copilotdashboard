<#
.SYNOPSIS
    Generates the per-cloud scripts (commercial/, gcc/, gcch/) from the templates in src/.

.DESCRIPTION
    The three cloud editions differ only in their cloud profile: endpoints, known Copilot
    product IDs and example values. To keep them in step, edit src/*.template.ps1 or
    src/clouds.psd1 and run this script; do not edit the generated scripts by hand.

.PARAMETER Check
    Do not write anything. Exit with code 1 if any generated script is missing or out of date.

.EXAMPLE
    .\tools\Build-CloudScripts.ps1

.EXAMPLE
    .\tools\Build-CloudScripts.ps1 -Check
#>
[CmdletBinding()]
param(
    [switch]$Check
)

$ErrorActionPreference = 'Stop'
$repoRoot = Split-Path -Parent $PSScriptRoot
$srcFolder = Join-Path $repoRoot 'src'
$clouds = Import-PowerShellDataFile -Path (Join-Path $srcFolder 'clouds.psd1')
$utf8NoBom = New-Object System.Text.UTF8Encoding($false)

function Format-CloudProfile ([hashtable]$Cloud) {
    $skuIds = @($Cloud.KnownCopilotSkuIds | ForEach-Object { "'$_'" }) -join ', '
    $worldwide = '   # empty = worldwide endpoints, parameter is omitted'
    @(
        "#region Cloud profile: $($Cloud.Name)"
        "# Generated from src/clouds.psd1 by tools/Build-CloudScripts.ps1. Do not edit by hand."
        "`$CloudProfile = @{"
        "    Name                    = '$($Cloud.Name)'"
        "    ExchangeEnvironmentName = '$($Cloud.ExchangeEnvironmentName)'$(if (-not $Cloud.ExchangeEnvironmentName) { $worldwide })"
        "    GraphEnvironment        = '$($Cloud.GraphEnvironment)'$(if (-not $Cloud.GraphEnvironment) { $worldwide })"
        "    KnownCopilotSkuIds      = @($skuIds)"
        "}"
        "#endregion"
    ) -join "`r`n"
}

$stale = @()
foreach ($key in ($clouds.Keys | Sort-Object)) {
    $cloud = $clouds[$key]
    $targetFolder = Join-Path $repoRoot $cloud.Folder

    foreach ($template in (Get-ChildItem -Path $srcFolder -Filter '*.template.ps1')) {
        $content = [System.IO.File]::ReadAllText($template.FullName)
        $content = $content.Replace('# {{CLOUD_PROFILE}}', (Format-CloudProfile $cloud))
        $content = $content.Replace('{{CLOUD_NAME}}', $cloud.Name)
        $content = $content.Replace('{{CLOUD_DESCRIPTION}}', $cloud.Description)
        $content = $content.Replace('{{ORGANIZATION_EXAMPLE}}', $cloud.OrganizationExample)
        if ($content -match '\{\{[A-Z_]+\}\}') { throw "Unresolved token $($Matches[0]) in $($template.Name)" }
        $content = ($content -replace "`r?`n", "`r`n")

        $targetPath = Join-Path $targetFolder ($template.Name -replace '\.template\.ps1$', '.ps1')
        $current = if (Test-Path -LiteralPath $targetPath) { [System.IO.File]::ReadAllText($targetPath) -replace "`r?`n", "`r`n" } else { $null }

        if ($current -ceq $content) { continue }
        if ($Check) {
            $stale += $targetPath
        } else {
            if (-not (Test-Path -LiteralPath $targetFolder)) { New-Item -ItemType Directory -Path $targetFolder | Out-Null }
            [System.IO.File]::WriteAllText($targetPath, $content, $utf8NoBom)
            Write-Host "Wrote $targetPath"
        }
    }
}

if ($Check) {
    if ($stale.Count -gt 0) {
        Write-Host "Out of date - run tools/Build-CloudScripts.ps1:" -ForegroundColor Red
        $stale | ForEach-Object { Write-Host "    $_" -ForegroundColor Red }
        exit 1
    }
    Write-Host "Generated scripts are up to date."
    exit 0
}
