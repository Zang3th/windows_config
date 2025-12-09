oh-my-posh init pwsh --config 'C:/Users/Zangeth/.config/Posh/config.json' | Invoke-Expression

$MSYS_BASH = "$env:USERPROFILE\scoop\apps\msys2\current\usr\bin\bash.exe"
function bash { & $MSYS_BASH -li @args }
function bsh  { & $MSYS_BASH -c @args }

# Fuck python paths
$PY_HOME = "$env:LOCALAPPDATA\Programs\Python\Python313"
$paths = ($env:Path -split ';' | ForEach-Object { $_.Trim() }) | Where-Object { $_ -and $_ -ne "$PY_HOME" -and $_ -ne "$PY_HOME\Scripts" }
$env:Path = "$PY_HOME;$PY_HOME\Scripts;" + ($paths -join ';')

function python { & "$PY_HOME\python.exe" @args }
function pip    { & "$PY_HOME\python.exe" -m pip @args }

# Visual Studio Developer PowerShell
$vsDevShell = "C:\Program Files (x86)\Microsoft Visual Studio\18\BuildTools\Common7\Tools\Launch-VsDevShell.ps1"
if (Test-Path $vsDevShell) {
    & $vsDevShell -Arch amd64
}
