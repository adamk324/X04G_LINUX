<#
.SYNOPSIS
  Install MTKClient into tools\mtkclient (PowerShell, Windows 11).

.DESCRIPTION
  Read-only setup: clones bkerler/mtkclient, creates a Python venv and installs
  requirements. Does NOT talk to the device.

  Manual prerequisites (one-time, need admin, done by you):
    1. Python 3.10+ from python.org (tick "Add python.exe to PATH").
    2. Git for Windows.
    3. UsbDk 64-bit: https://github.com/daynix/UsbDk/releases  (install the .msi)
       -> required by MTKClient for BootROM (0E8D:0003) access via libusb.
    4. Optional: MediaTek USB VCOM driver, only if the device shows a yellow "!"
       in Device Manager when in preloader mode.

.EXAMPLE
  PS> Set-ExecutionPolicy -Scope Process Bypass
  PS> .\scripts\windows\setup-mtkclient.ps1
#>
[CmdletBinding()]
param(
    [string]$ToolsDir = (Join-Path $PSScriptRoot "..\..\tools"),
    # Pin a known commit for reproducibility (inspected 2026-11-08)
    [string]$MtkClientCommit = "118a000"
)
$ErrorActionPreference = "Stop"

foreach ($exe in "git", "python") {
    if (-not (Get-Command $exe -ErrorAction SilentlyContinue)) { throw "$exe not found in PATH" }
}
python --version

New-Item -ItemType Directory -Force -Path $ToolsDir | Out-Null
$mtk = Join-Path $ToolsDir "mtkclient"
if (-not (Test-Path (Join-Path $mtk ".git"))) {
    git clone https://github.com/bkerler/mtkclient $mtk
}
git -C $mtk fetch --quiet origin
git -C $mtk checkout --quiet $MtkClientCommit
Write-Host "mtkclient @ $(git -C $mtk rev-parse --short HEAD)"

$venv = Join-Path $mtk ".venv"
if (-not (Test-Path $venv)) { python -m venv $venv }
& (Join-Path $venv "Scripts\python.exe") -m pip install --upgrade pip
& (Join-Path $venv "Scripts\python.exe") -m pip install -r (Join-Path $mtk "requirements.txt")

# Verify the options this project relies on exist in this version
$help = & (Join-Path $venv "Scripts\python.exe") (Join-Path $mtk "mtk.py") rl --help 2>&1 | Out-String
foreach ($opt in "--noreconnect", "--parttype") {
    if ($help -notmatch [regex]::Escape($opt)) { Write-Warning "mtkclient does not list $opt - check scripts before use" }
    else { Write-Host "ok: $opt supported" }
}

if (Get-Command UsbDkController -ErrorAction SilentlyContinue) {
    Write-Host "UsbDk present."
} elseif (Test-Path "C:\Program Files\UsbDk Runtime Library\UsbDkController.exe") {
    Write-Host "UsbDk present."
} else {
    Write-Warning "UsbDk not detected. Install it before connecting the clock in BootROM mode."
}
Write-Host "Done. Next: .\scripts\windows\backup-x04g.ps1 -Step identify"
