<#
.SYNOPSIS
  READ-ONLY identification and full backup of a Xiaomi Mi Smart Clock (X04G/LX04)
  with MTKClient. Never writes, erases or unlocks anything.

.DESCRIPTION
  Steps (run them one at a time, each needs a fresh BootROM connection):
    identify   - print GPT + target config (SBC/SLA/DAA) -> backups\<ts>\identify\
    partitions - read every GPT partition into backups\<ts>\partitions\  (rl)
    boot       - read eMMC boot1 + boot2 hardware partitions (preloader lives in boot1)
    full       - read whole eMMC user area as a single image (rf)  ~3.7 GB
    verify     - SHA-256 every file, cross-check partition sizes vs GPT, write MANIFEST

  How to connect (every step):
    1. Unplug the clock.
    2. Start the step in PowerShell; wait for "Waiting for device".
    3. Hold VOL+ and plug the micro-USB cable in. Keep holding until MTKClient
       reports the device (BootROM 0E8D:0003).

  Every command passes --noreconnect so MTKClient does not try to re-enumerate
  the device on Windows after a USB drop.

.EXAMPLE
  PS> .\scripts\windows\backup-x04g.ps1 -Step identify
  PS> .\scripts\windows\backup-x04g.ps1 -Step partitions -Session 20261108-1530
#>
[CmdletBinding()]
param(
    [Parameter(Mandatory)][ValidateSet("identify", "partitions", "boot", "full", "verify")]
    [string]$Step,
    # Re-use one session folder across steps
    [string]$Session = (Get-Date -Format "yyyyMMdd-HHmm"),
    [string]$BackupRoot = (Join-Path $PSScriptRoot "..\..\backups"),
    [string]$MtkDir = (Join-Path $PSScriptRoot "..\..\tools\mtkclient")
)
$ErrorActionPreference = "Stop"
$py = Join-Path $MtkDir ".venv\Scripts\python.exe"
$mtk = Join-Path $MtkDir "mtk.py"
if (-not (Test-Path $py)) { throw "Run setup-mtkclient.ps1 first" }

$dir = Join-Path $BackupRoot $Session
New-Item -ItemType Directory -Force -Path $dir | Out-Null
$log = Join-Path $dir "mtkclient-$Step.log"

function Invoke-Mtk([string[]]$MtkArgs) {
    Write-Host ">> python mtk.py $($MtkArgs -join ' ')" -ForegroundColor Cyan
    & $py $mtk @MtkArgs 2>&1 | Tee-Object -FilePath $log -Append
    if ($LASTEXITCODE -ne 0) { throw "mtkclient failed (exit $LASTEXITCODE), see $log" }
}

# Works in Windows PowerShell 5.1 and PowerShell 7
function Test-NonZeroHead([string]$Path) {
    $fs = [System.IO.File]::OpenRead($Path)
    try {
        $buf = New-Object byte[] 4096
        $n = $fs.Read($buf, 0, $buf.Length)
        for ($i = 0; $i -lt $n; $i++) { if ($buf[$i] -ne 0) { return $true } }
        return $false
    } finally { $fs.Dispose() }
}

switch ($Step) {
    "identify" {
        $id = Join-Path $dir "identify"; New-Item -ItemType Directory -Force $id | Out-Null
        Invoke-Mtk @("printgpt", "--noreconnect")
        Write-Host "Replug with VOL+ held for the next query..." -ForegroundColor Yellow
        Invoke-Mtk @("gettargetconfig", "--noreconnect")
        Write-Host "Replug with VOL+ held to save GPT copies..." -ForegroundColor Yellow
        Invoke-Mtk @("gpt", $id, "--noreconnect")
        Copy-Item $log (Join-Path $id "identify.log")
    }
    "partitions" {
        Invoke-Mtk @("rl", (Join-Path $dir "partitions"), "--noreconnect")
    }
    "boot" {
        Invoke-Mtk @("r", "preloader", (Join-Path $dir "emmc_boot1.bin"), "--parttype", "boot1", "--noreconnect")
        Write-Host "Replug with VOL+ held for boot2..." -ForegroundColor Yellow
        Invoke-Mtk @("r", "preloader", (Join-Path $dir "emmc_boot2.bin"), "--parttype", "boot2", "--noreconnect")
    }
    "full" {
        Invoke-Mtk @("rf", (Join-Path $dir "emmc_user_full.bin"), "--noreconnect")
    }
    "verify" {
        $manifest = Join-Path $dir "MANIFEST.sha256"
        Get-ChildItem $dir -Recurse -File | Where-Object { $_.Extension -in ".bin", ".img" } |
            Sort-Object FullName | ForEach-Object {
                $h = (Get-FileHash $_.FullName -Algorithm SHA256).Hash.ToLower()
                "{0}  {1}  {2}" -f $h, $_.Length, $_.FullName.Substring($dir.Length + 1)
            } | Tee-Object -FilePath $manifest
        $parts = Join-Path $dir "partitions"
        if (Test-Path $parts) {
            $sum = (Get-ChildItem $parts -File -Filter *.bin | Measure-Object Length -Sum).Sum
            Write-Host ("partitions total: {0:N0} bytes ({1:N2} GiB)" -f $sum, ($sum / 1GB))
            foreach ($must in "seccfg", "lk", "lk2", "boot", "recovery", "vbmeta", "nvram", "proinfo", "persist", "nvdata") {
                $f = Get-ChildItem $parts -File | Where-Object { $_.BaseName -eq $must }
                if (-not $f) { Write-Warning "missing critical partition dump: $must" }
                elseif (-not (Test-NonZeroHead $f.FullName)) {
                    Write-Warning "$must dump starts with 4 KiB of zeros - inspect manually"
                }
            }
        }
        $full = Join-Path $dir "emmc_user_full.bin"
        if ((Test-Path $full) -and (Test-Path $parts)) {
            # GPT CRC check + byte-compare every partition dump against the full image
            & $py (Join-Path $PSScriptRoot "..\verify_backup.py") $dir
            if ($LASTEXITCODE -ne 0) { throw "Backup NOT verified - do not modify the device" }
        } else {
            Write-Warning "Need both 'full' and 'partitions' steps before the backup counts as verified."
        }
        Write-Host "Manifest written: $manifest" -ForegroundColor Green
        Write-Host "Copy the whole $dir folder to a SECOND disk. It contains device-unique IDs (MACs, serial) - do not publish it."
    }
}
