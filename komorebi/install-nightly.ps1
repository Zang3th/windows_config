<#
.SYNOPSIS
    Installs or updates the komorebi nightly build.

.DESCRIPTION
    Downloads the latest nightly from GitHub, verifies its SHA-256 checksum
    and unpacks it to %LOCALAPPDATA%\Programs\komorebi-nightly. The Scoop
    install (stable) stays untouched as a fallback; start-wm.ps1 prefers the
    nightly whenever this folder exists.

    Running komorebi is stopped first because its executables are locked;
    start it again afterwards with start-wm.ps1.

    To go back to stable: delete the folder and run start-wm.ps1.
#>

$ErrorActionPreference = 'Stop'

$target = "$env:LOCALAPPDATA\Programs\komorebi-nightly"
$base   = 'https://github.com/LGUG2Z/komorebi/releases/download/nightly'
$zip    = 'komorebi-nightly-x86_64-pc-windows-msvc.zip'

$tmp = Join-Path ([IO.Path]::GetTempPath()) "komorebi-nightly-$([guid]::NewGuid())"
New-Item -ItemType Directory $tmp | Out-Null

try {
    Invoke-WebRequest "$base/$zip"           -OutFile "$tmp\$zip"
    Invoke-WebRequest "$base/checksums.txt"  -OutFile "$tmp\checksums.txt"

    $expected = (Get-Content "$tmp\checksums.txt" |
        Where-Object { $_ -match [regex]::Escape($zip) } |
        Select-Object -First 1).Split(' ')[0]
    $actual = (Get-FileHash "$tmp\$zip" -Algorithm SHA256).Hash
    if (-not $expected -or $actual -ne $expected.ToUpper()) {
        throw "Checksum mismatch for $zip (expected $expected, got $actual)"
    }

    if (Get-Process komorebi -ErrorAction SilentlyContinue) {
        komorebic stop | Out-Null
        Start-Sleep -Seconds 1
        Get-Process komorebi, komorebi-bar -ErrorAction SilentlyContinue | Stop-Process -Force
    }

    if (Test-Path $target) { Remove-Item $target -Recurse -Force }
    Expand-Archive "$tmp\$zip" -DestinationPath $target

    Write-Host "Installed: $(& "$target\komorebic.exe" --version | Select-Object -First 1)"
    Write-Host "Start it with start-wm.ps1"
}
finally {
    Remove-Item $tmp -Recurse -Force -ErrorAction SilentlyContinue
}
