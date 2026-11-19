<#
.SYNOPSIS
    Starts (or restarts) the desktop: komorebi + whkd + yasb.

.DESCRIPTION
    Anything already running is stopped first, so the script doubles as a
    "reset" when komorebi or the bar get stuck.

    -InstallShortcut  creates "Tiling WM" in the Start Menu (pin it from there).
    -Stop             only stops komorebi, whkd and yasb.
#>
param(
    [switch]$InstallShortcut,
    [switch]$Stop
)

$ErrorActionPreference = 'Stop'

if ($InstallShortcut) {
    $lnkPath = Join-Path ([Environment]::GetFolderPath('Programs')) 'Tiling WM.lnk'
    $shell   = New-Object -ComObject WScript.Shell
    $lnk     = $shell.CreateShortcut($lnkPath)
    # conhost --headless runs pwsh without flashing a console window
    $lnk.TargetPath       = "$env:SystemRoot\System32\conhost.exe"
    $lnk.Arguments        = "--headless pwsh.exe -NoProfile -ExecutionPolicy Bypass -File `"$PSCommandPath`""
    $lnk.WorkingDirectory = $PSScriptRoot
    # komorebi's executables ship without an icon resource
    $lnk.IconLocation     = "$PSScriptRoot\komorebi\tiling-wm.ico,0"
    $lnk.Description      = 'Start or restart komorebi, whkd and yasb'
    $lnk.Save()
    Write-Host "Shortcut created: $lnkPath"
    return
}

# Processes started from the Start Menu inherit Explorer's environment, which
# can be older than the user variable; fall back to the stored value.
if (-not $env:KOMOREBI_CONFIG_HOME) {
    $env:KOMOREBI_CONFIG_HOME =
        [Environment]::GetEnvironmentVariable('KOMOREBI_CONFIG_HOME', 'User') ??
        "$HOME\.config\komorebi"
}

# Everything started here inherits this environment. When the script runs from a terminal,
# drop that terminal's oh-my-posh session, or new shells inherit a foreign one.
Get-ChildItem env: | Where-Object Name -like 'POSH_*' |
    ForEach-Object { Remove-Item "env:$($_.Name)" }

# Prefer the nightly build (komorebi/install-nightly.ps1) over the Scoop one.
# whkd inherits this PATH, so every `komorebic` in whkdrc talks to the same
# version as the running komorebi.
$nightly = "$env:LOCALAPPDATA\Programs\komorebi-nightly"
if (Test-Path "$nightly\komorebi.exe") {
    $env:PATH = "$nightly;$env:PATH"
}

# --- Stop whatever is running ---
if (Get-Process yasb -ErrorAction SilentlyContinue) {
    yasbc stop | Out-Null
}
if (Get-Process komorebi -ErrorAction SilentlyContinue) {
    komorebic stop --whkd | Out-Null
}
# Leftovers if the graceful stops failed
Get-Process yasb, komorebi, whkd -ErrorAction SilentlyContinue | Stop-Process -Force

if ($Stop) { return }

# --- Start ---
# Started directly instead of via `komorebic start`, which may pick the Scoop
# binary regardless of PATH.
Start-Process (Get-Command komorebi.exe).Source -WindowStyle Hidden `
    -ArgumentList "--config=`"$env:KOMOREBI_CONFIG_HOME\komorebi.json`""

# Wait until komorebi answers, so whkd and yasb find it on their first connect.
$deadline = (Get-Date).AddSeconds(15)
do {
    Start-Sleep -Milliseconds 200
    komorebic query version 2>$null | Out-Null
} until ($LASTEXITCODE -eq 0 -or (Get-Date) -gt $deadline)

Start-Process (Get-Command whkd.exe).Source -WindowStyle Hidden

$yasb = "$HOME\scoop\apps\yasb\current\yasb.exe"
if (-not (Test-Path $yasb)) { $yasb = (Get-Command yasb).Source }
Start-Process $yasb
