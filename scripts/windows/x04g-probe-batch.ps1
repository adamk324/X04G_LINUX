<#
.SYNOPSIS
  Unattended batch of RAM-boot probes: for every image, wait for LK fastboot, `fastboot boot` it,
  and measure the time until the board resets (MediaTek preloader 0E8D:2000 re-appears).

.DESCRIPTION
  Reading the result: reset within ~1-6 s  -> the probe's trigger point was reached
                      reset at ~60 s       -> it was not reached (LK's watchdog fired)
                      no reset in -Timeout -> the image kept running (e.g. Linux up)
  Nothing is written to the device. Results: logs\batch-<time>.csv (+ console table).

.EXAMPLE
  PS> .\scripts\windows\x04g-probe-batch.ps1 -Images .\build\ckpt\*.img
#>
[CmdletBinding()]
param(
    [Parameter(Mandatory)][string[]]$Images,
    [string]$PlatformTools = "F:\platform-tools-latest-windows\platform-tools",
    [int]$Timeout = 75,
    [string]$LogDir = (Join-Path $PSScriptRoot "..\..\logs")
)
$ErrorActionPreference = "Stop"
$fastboot = Join-Path $PlatformTools "fastboot.exe"
$adb = Join-Path $PlatformTools "adb.exe"
New-Item -ItemType Directory -Force -Path $LogDir | Out-Null
$csv = Join-Path $LogDir ("batch-" + (Get-Date -Format "yyyyMMdd-HHmmss") + ".csv")

function Test-Usb([string]$pattern) {
    [bool](Get-CimInstance Win32_PnPEntity -Filter "PNPDeviceID LIKE 'USB%'" -ErrorAction SilentlyContinue |
        Where-Object { $_.PNPDeviceID -match $pattern })
}
function Wait-Fastboot([int]$seconds = 120) {
    $sw = [Diagnostics.Stopwatch]::StartNew(); $kicked = $false
    while ($sw.Elapsed.TotalSeconds -lt $seconds) {
        if (Test-Usb "VID_0E8D&PID_201C") { return $true }
        if (-not $kicked -and (Test-Usb "VID_18D1|VID_0E8D&PID_2008")) {
            & $adb reboot bootloader 2>$null | Out-Null; $kicked = $true   # Android is up: go to LK fastboot
        }
        Start-Sleep -Milliseconds 500
    }
    return $false
}
function Invoke-FastbootBoot([string]$img) {
    $psi = New-Object Diagnostics.ProcessStartInfo $fastboot, "boot `"$img`""
    $psi.UseShellExecute = $false; $psi.RedirectStandardOutput = $true
    $psi.RedirectStandardError = $true; $psi.CreateNoWindow = $true
    $p = [Diagnostics.Process]::Start($psi)
    $e = $p.StandardError.ReadToEndAsync(); $o = $p.StandardOutput.ReadToEnd(); $p.WaitForExit()
    return ($o + $e.Result)
}

$files = foreach ($i in $Images) { Get-ChildItem $i }
$files = $files | Sort-Object Name
"image,booting_okay,reset_s,verdict" | Set-Content $csv
$rows = @()
foreach ($f in $files) {
    Write-Host "== $($f.Name): waiting for LK fastboot..." -ForegroundColor Cyan
    if (-not (Wait-Fastboot)) { Write-Host "   clock not in fastboot mode, skipping" -ForegroundColor Red; continue }
    Start-Sleep -Seconds 1
    $out = Invoke-FastbootBoot $f.FullName
    $ok = $out -match "Booting\s+OKAY"
    $sw = [Diagnostics.Stopwatch]::StartNew()
    $reset = $null
    # LK fastboot (201C) disappears at boot; the next 0E8D:2000 is the reset
    while ($ok -and $sw.Elapsed.TotalSeconds -lt $Timeout) {
        if (Test-Usb "VID_0E8D&PID_2000") { $reset = [math]::Round($sw.Elapsed.TotalSeconds, 1); break }
        Start-Sleep -Milliseconds 250
    }
    $verdict = if (-not $ok) { "fastboot failed" }
               elseif ($null -eq $reset) { "no reset within $Timeout s (still running)" }
               elseif ($reset -lt 15) { "REACHED (fast reset)" }
               else { "not reached (watchdog)" }
    $color = if ($verdict -like "REACHED*") { "Green" } elseif ($verdict -like "not reached*") { "Yellow" } else { "Magenta" }
    Write-Host ("   reset after {0} s -> {1}" -f $reset, $verdict) -ForegroundColor $color
    "$($f.Name),$ok,$reset,$verdict" | Add-Content $csv
    $rows += [pscustomobject]@{ Image = $f.Name; ResetSeconds = $reset; Verdict = $verdict }
}
$rows | Format-Table -AutoSize
Write-Host "summary saved: $csv" -ForegroundColor Green
