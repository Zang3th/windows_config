$CONFIG_HOME = if ($env:XDG_CONFIG_HOME) { $env:XDG_CONFIG_HOME } else { "$HOME\.config" }
$VS_ROOT     = "C:\Program Files (x86)\Microsoft Visual Studio\18\BuildTools"
$LLVM_BIN    = "C:\Program Files\LLVM\bin"
$WINGET_LINKS = "$env:LOCALAPPDATA\Microsoft\WinGet\Links"

oh-my-posh init pwsh --config "$CONFIG_HOME\posh\config.json" | Invoke-Expression

$env:EDITOR = 'nvim'
$env:VISUAL = 'nvim'

$MSYS_BASH = "$env:USERPROFILE\scoop\apps\msys2\current\usr\bin\bash.exe"
function bash { & $MSYS_BASH -li @args }
function bsh  { & $MSYS_BASH -c @args }

# Fuck python paths
$PY_HOME = "$env:LOCALAPPDATA\Programs\Python\Python313"
$paths = ($env:Path -split ';' | ForEach-Object { $_.Trim() }) | Where-Object {
    $_ -and
    $_ -ne "$PY_HOME" -and
    $_ -ne "$PY_HOME\Scripts"
}
$env:Path = "$PY_HOME;$PY_HOME\Scripts;" + ($paths -join ';')

function python { & "$PY_HOME\python.exe" @args }
function pip    { & "$PY_HOME\python.exe" -m pip @args }

# Prefer the standalone CMake
$env:Path = "$WINGET_LINKS;$env:Path"

# Visual Studio Developer PowerShell, loaded on demand
function vsdev {
    if ($env:VSCMD_VER) { Write-Host "VS dev environment already loaded ($env:VSCMD_VER)"; return }
    & "$VS_ROOT\Common7\Tools\Launch-VsDevShell.ps1" -Arch amd64 -HostArch amd64 -SkipAutomaticLocation
    # The dev shell prepends its own CMake and LLVM; keep the standalone ones in front
    $env:Path = "$WINGET_LINKS;$LLVM_BIN;$env:Path"
}

# Interactive line editing, skipped in non-interactive hosts (scripts, tools)
if ($Host.Name -eq 'ConsoleHost' -and -not [Console]::IsOutputRedirected) {
    Set-PSReadLineOption -EditMode Vi
    Set-PSReadLineOption -ViModeIndicator Cursor
    Set-PSReadLineOption -HistoryNoDuplicates
    Set-PSReadLineOption -PredictionSource History -PredictionViewStyle InlineView
    Set-PSReadLineKeyHandler -Key Tab       -Function MenuComplete
    Set-PSReadLineKeyHandler -Key UpArrow   -Function HistorySearchBackward
    Set-PSReadLineKeyHandler -Key DownArrow -Function HistorySearchForward
    Set-PSReadLineKeyHandler -Key Ctrl+f    -Function AcceptSuggestion -ViMode Insert

    # fzf: Ctrl+r history search, Ctrl+t file picker
    if ((Get-Command fzf -ErrorAction SilentlyContinue) -and (Get-Module -ListAvailable PSFzf)) {
        Import-Module PSFzf
        Set-PsFzfOption -PSReadlineChordProvider 'Ctrl+t' -PSReadlineChordReverseHistory 'Ctrl+r'
    }
}
