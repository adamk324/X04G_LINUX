<#
.SYNOPSIS
  USB-only debug monitor for the X04G (no UART needed). Optionally RAM-boots an image with
  `fastboot boot`, then records a timestamped timeline of everything the clock does on USB.

.DESCRIPTION
  Timeline entries (seconds since "Booting OKAY", or since start with -NoBoot):
    + / -  USB devices appearing / disappearing (MTK preloader, LK fastboot, Linux gadgets, Android)
    COM>   every line received on the clock's USB serial port (kernel log, stage lines, shell)
    NET    ping / telnet results for 172.16.42.1
  When the Linux composite gadget appears it automatically fetches /run/x04g-stages.txt and
  /run/x04g-report.txt over the serial shell, and saves them next to the log.

  Expected Windows enumeration (see docs/USB_DEBUGGING.md):
    0E8D:2000  MediaTek PreLoader USB VCOM     (power-on / reset, ~2 s)
    0E8D:201C  LK fastboot                     (before `fastboot boot`)
    0525:A4A7  "Gadget Serial" -> USB Serial Device (COMx)         kernel stage, legacy g_serial
    1D6B:0104  "Mi Smart Clock (Linux)" composite:
                 USB Serial Device (COMy)  + UsbNcm Host Device (network)   init stage
    0E8D:2008 / 18D1:*  Android again (MTP / ADB)

.EXAMPLE
  PS> .\scripts\windows\x04g-usb-monitor.ps1 -Image .\build\x04g-T4-usbdiag.img
  PS> .\scripts\windows\x04g-usb-monitor.ps1 -NoBoot -Minutes 5
#>
[CmdletBinding()]
param(
    [string]$Image,
    [string]$Fastboot = "F:\platform-tools-latest-windows\platform-tools\fastboot.exe",
    [switch]$NoBoot,
    [double]$Minutes = 3,
    [string]$LogDir = (Join-Path $PSScriptRoot "..\..\logs")
)
$ErrorActionPreference = "Stop"
New-Item -ItemType Directory -Force -Path $LogDir | Out-Null
$stamp = Get-Date -Format "yyyyMMdd-HHmmss"
$log = Join-Path $LogDir "usbdiag-$stamp.log"
$sw = [System.Diagnostics.Stopwatch]::new()

function T { "{0,7:N2}s" -f $sw.Elapsed.TotalSeconds }
function Log([string]$kind, [string]$msg, [string]$color = "Gray") {
    $line = "[{0}] {1,-4} {2}" -f (T), $kind, $msg
    Write-Host $line -ForegroundColor $color
    Add-Content -Path $log -Value $line
}

$known = @{
    "VID_0E8D&PID_2000" = "MTK preloader"
    "VID_0E8D&PID_0003" = "MTK BootROM"
    "VID_0E8D&PID_201C" = "LK fastboot"
    "VID_0E8D&PID_2008" = "Android (MTP)"
    "VID_18D1"          = "Android / fastbootd (Google VID)"
    "VID_0525&PID_A4A7" = "LINUX kernel stage: legacy g_serial"
    "VID_1D6B&PID_0104" = "LINUX init stage: ACM+NCM composite"
}
function Classify([string]$id) {
    foreach ($k in $known.Keys) { if ($id -match [regex]::Escape($k)) { return $known[$k] } }
    return $null
}
function Get-ClockDevices {
    Get-CimInstance Win32_PnPEntity -Filter "PNPDeviceID LIKE 'USB%'" -ErrorAction SilentlyContinue |
        Where-Object { $_.PNPDeviceID -match "VID_(0E8D|18D1|0525|1D6B)" } |
        Select-Object PNPDeviceID, Name, Status
}

# ---- optional RAM boot ------------------------------------------------------
if (-not $NoBoot) {
    if (-not $Image) { throw "-Image is required unless -NoBoot is given" }
    $Image = (Resolve-Path $Image).Path
    Write-Host "fastboot boot $Image" -ForegroundColor Cyan
    # fastboot prints progress on stderr. Run it as a .NET process so Windows PowerShell 5.1
    # does not turn stderr lines into terminating errors under ErrorActionPreference=Stop.
    $psi = New-Object System.Diagnostics.ProcessStartInfo
    $psi.FileName = $Fastboot
    $psi.Arguments = "boot `"$Image`""
    $psi.UseShellExecute = $false
    $psi.RedirectStandardOutput = $true
    $psi.RedirectStandardError = $true
    $psi.CreateNoWindow = $true
    $p = [System.Diagnostics.Process]::Start($psi)
    $errTask = $p.StandardError.ReadToEndAsync()
    $outText = $p.StandardOutput.ReadToEnd()
    $p.WaitForExit()
    $out = $outText + $errTask.Result
    $sw.Start()
    if ($p.ExitCode -ne 0) { Write-Host "fastboot exit code $($p.ExitCode)" -ForegroundColor Red }
    Add-Content $log "fastboot output:`n$out"
    Write-Host $out
    if ($out -notmatch "Booting\s+OKAY") { Log "ERR" "fastboot did not report Booting OKAY" "Red" }
    else { Log "BOOT" "fastboot: Booting OKAY (t=0)" "Cyan" }
} else { $sw.Start(); Log "INFO" "monitoring only" }

# ---- monitor loop -----------------------------------------------------------
$present = @{}
$port = $null; $portName = $null; $rx = ""
$pinged = $false; $fetched = $false; $compositeSeen = $null
$reportPath = Join-Path $LogDir "x04g-report-$stamp.txt"
$deadline = [TimeSpan]::FromMinutes($Minutes)

while ($sw.Elapsed -lt $deadline) {
    $now = @{}
    foreach ($d in Get-ClockDevices) { $now[$d.PNPDeviceID] = $d }
    foreach ($id in $now.Keys) {
        if (-not $present.ContainsKey($id)) {
            $c = Classify $id
            Log "+" ("{0}  [{1}]  {2}" -f $now[$id].Name, $(if ($c) { $c } else { "?" }), $id) "Green"
            if ($id -match "VID_1D6B&PID_0104" -and -not $compositeSeen) { $compositeSeen = $sw.Elapsed }
        }
    }
    foreach ($id in @($present.Keys)) {
        if (-not $now.ContainsKey($id)) { Log "-" ("{0}  {1}" -f $present[$id].Name, $id) "DarkYellow" }
    }
    $present = $now

    # Serial port of the clock (legacy or composite); prefer the composite one
    $com = $now.Values | Where-Object { $_.PNPDeviceID -match "VID_(1D6B|0525)" -and $_.Name -match "\((COM\d+)\)" } |
        Sort-Object { if ($_.PNPDeviceID -match "1D6B") { 0 } else { 1 } } | Select-Object -First 1
    $want = if ($com) { [regex]::Match($com.Name, "\((COM\d+)\)").Groups[1].Value } else { $null }
    if ($port -and ($want -ne $portName)) {
        try { $port.Close() } catch {}
        Log "COM" "$portName closed"; $port = $null; $portName = $null
    }
    if ($want -and -not $port) {
        try {
            $port = New-Object System.IO.Ports.SerialPort $want, 115200, "None", 8, "One"
            $port.DtrEnable = $true; $port.RtsEnable = $true; $port.ReadTimeout = 50
            $port.Open(); $portName = $want
            Log "COM" "$want opened ($($com.Name))" "Cyan"
        } catch { Log "COM" "cannot open ${want}: $($_.Exception.Message)" "Red"; $port = $null }
    }
    if ($port) {
        try { $rx += $port.ReadExisting() } catch { }
        while ($rx -match "^(.*?)\r?\n") {
            $l = $Matches[1]; $rx = $rx.Substring($Matches[0].Length)
            if ($l.Trim()) { Log "COM>" $l "White" }
        }
        # Once the composite shell is up, pull the stage log and the report
        if (-not $fetched -and $compositeSeen -and ($sw.Elapsed - $compositeSeen).TotalSeconds -gt 4 -and $portName) {
            $fetched = $true
            Log "INFO" "requesting stages + report over serial" "Cyan"
            # split markers ("===STA""GES===") so the shell's echo of this command line never matches
            $port.Write("`r`necho ""===STA""""GES===""; cat /run/x04g-stages.txt; echo ""===REP""""ORT===""; cat /run/x04g-report.txt; echo ""===E""""ND===""`r`n")
        }
    }

    # USB network
    if ($compositeSeen -and -not $pinged -and ($sw.Elapsed - $compositeSeen).TotalSeconds -gt 3) {
        if (Test-Connection -ComputerName 172.16.42.1 -Count 1 -Quiet -ErrorAction SilentlyContinue) {
            $pinged = $true; Log "NET" "172.16.42.1 answers ping (USB NCM network OK)" "Green"
        } elseif (($sw.Elapsed - $compositeSeen).TotalSeconds -gt 30) {
            $pinged = $true; Log "NET" "no ping reply from 172.16.42.1 after 30 s (check 'UsbNcm Host Device' in Device Manager)" "Red"
        }
    }
    Start-Sleep -Milliseconds 300
}

if ($port) { try { $port.Close() } catch {} }
# Extract the report from the log (between markers)
$txt = Get-Content $log -Raw
$m = [regex]::Match($txt, "(?s)===STAGES===(.*?)===END===")
if ($m.Success) {
    ($m.Groups[1].Value -split "`n" | ForEach-Object { $_ -replace "^\[\s*[\d.,]+s\]\s+COM>\s?", "" }) |
        Set-Content $reportPath
    Write-Host "report saved: $reportPath" -ForegroundColor Green
}
Write-Host "timeline saved: $log" -ForegroundColor Green
