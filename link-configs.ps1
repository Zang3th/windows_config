<#
.SYNOPSIS
    Links config files that apps expect outside of ~/.config to their versioned copy in this repo.

.DESCRIPTION
    Each live file becomes a symlink to the repo file, so edits from either side (including
    settings UIs like Windows Terminal's) land in the repo. Needs Developer Mode or admin.

    -Check  only reports the state, changes nothing (exit code 1 on drift).
    -Force  replaces a live file whose content differs from the repo (a .bak copy is kept).
#>
param(
    [switch]$Check,
    [switch]$Force
)

$repo = $PSScriptRoot

$links = @(
    @{
        Live = "$env:LOCALAPPDATA\Packages\Microsoft.WindowsTerminal_8wekyb3d8bbwe\LocalState\settings.json"
        Repo = "$repo\Microsoft.WindowsTerminal_8wekyb3d8bbwe\LocalState\settings.json"
    }
    @{
        Live = $PROFILE.CurrentUserCurrentHost
        Repo = "$repo\PowerShell\Microsoft.PowerShell_profile.ps1"
    }
)

$drift = $false

foreach ($l in $links) {
    $live = Get-Item $l.Live -ErrorAction SilentlyContinue

    if ($live -and $live.LinkType -eq 'SymbolicLink' -and $live.Target -eq $l.Repo) {
        Write-Host "[ok]      $($l.Live)" -ForegroundColor Green
        continue
    }

    $drift = $true
    $state = if (-not $live) { 'missing' }
             elseif ($live.LinkType) { "wrong link -> $($live.Target)" }
             elseif ((Get-FileHash $l.Live).Hash -eq (Get-FileHash $l.Repo).Hash) { 'copy (identical)' }
             else { 'copy (DIFFERS)' }

    if ($Check) {
        Write-Host "[drift]   $($l.Live): $state" -ForegroundColor Yellow
        continue
    }

    if ($state -eq 'copy (DIFFERS)' -and -not $Force) {
        Write-Host "[skipped] $($l.Live): content differs from repo - merge it, then rerun with -Force" -ForegroundColor Red
        Write-Host "          git diff --no-index `"$($l.Repo)`" `"$($l.Live)`""
        continue
    }

    if ($live) {
        if (-not $live.LinkType) {
            Copy-Item $l.Live "$($l.Live).bak" -Force
        }
        Remove-Item $l.Live -Force
    }
    New-Item -ItemType Directory -Force (Split-Path $l.Live) | Out-Null
    New-Item -ItemType SymbolicLink -Path $l.Live -Target $l.Repo | Out-Null
    Write-Host "[linked]  $($l.Live) -> $($l.Repo)" -ForegroundColor Cyan
}

if ($Check -and $drift) { exit 1 }
