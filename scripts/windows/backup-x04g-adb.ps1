<#
.SYNOPSIS
  READ-ONLY partition backup of a rooted X04G over ADB (Magisk `su`).
  Every image is streamed with `adb exec-out` and checked against a SHA-256
  computed on the device itself.

.DESCRIPTION
  Use this when the clock already boots Android with root + ADB (verified on the
  user's unit, 2026-11-08). Unlike the MTKClient backup it needs no BootROM mode,
  and it is a good way to get boot/lk/dtbo quickly.

  It does NOT replace the MTKClient full-eMMC backup (backup-x04g.ps1):
    * partitions mounted read-write while Android runs (userdata, metadata, cache,
      nvdata, persist) can change during the read, so those copies may be inconsistent;
    * a restore still needs MTKClient (BootROM) if Android stops booting.

  Partitions are streamed straight to the PC. Nothing is written on the clock.

.EXAMPLE
  PS> .\scripts\windows\backup-x04g-adb.ps1                    # all except userdata
  PS> .\scripts\windows\backup-x04g-adb.ps1 -Only boot,lk,dtbo,vbmeta,recovery
#>
[CmdletBinding()]
param(
    [string]$Adb = "adb",
    [string]$Session = ("adb-" + (Get-Date -Format "yyyyMMdd-HHmm")),
    [string]$BackupRoot = (Join-Path $PSScriptRoot "..\..\backups"),
    [string[]]$Only,
    [switch]$IncludeUserdata
)
$ErrorActionPreference = "Stop"
function Su([string]$cmd) {
    $out = & $Adb shell "su -c '$cmd'" 2>&1
    if ($LASTEXITCODE -ne 0) { throw "adb/su failed: $cmd`n$out" }
    return ($out | Out-String).Trim()
}

# Binary-safe capture of adb stdout. PowerShell '>' re-encodes bytes as text, so the raw
# stream is copied from a .NET Process instead.
function Save-AdbStream([string]$Arguments, [string]$OutFile) {
    $exe = (Get-Command $Adb).Source
    $psi = New-Object System.Diagnostics.ProcessStartInfo $exe, $Arguments
    $psi.UseShellExecute = $false
    $psi.RedirectStandardOutput = $true
    $psi.CreateNoWindow = $true
    $proc = [System.Diagnostics.Process]::Start($psi)
    $fs = [System.IO.File]::Create($OutFile)
    try { $proc.StandardOutput.BaseStream.CopyTo($fs) } finally { $fs.Dispose() }
    $proc.WaitForExit()
    if ($proc.ExitCode -ne 0) { throw "adb $Arguments exited $($proc.ExitCode)" }
}

# On the user's unit (Magisk su, 2026-11-08) the stream comes back with every 0x0A expanded
# to 0x0D 0x0A: the su session runs behind a terminal with ONLCR output translation. The
# mapping is reversible (each original LF gained exactly one CR), so when the raw copy does
# not match the device hash we undo it and verify again. Nothing is trusted without a match.
Add-Type -TypeDefinition @"
using System.IO;
public static class X04gOnlcr {
    public static void Undo(string inPath, string outPath) {
        using (var i = File.OpenRead(inPath))
        using (var o = new BufferedStream(File.Create(outPath), 1 << 20)) {
            var buf = new byte[1 << 20]; int n; bool pendingCr = false;
            while ((n = i.Read(buf, 0, buf.Length)) > 0) {
                for (int k = 0; k < n; k++) {
                    byte b = buf[k];
                    if (pendingCr) {
                        pendingCr = false;
                        if (b == 10) { o.WriteByte(10); continue; }
                        o.WriteByte(13);
                    }
                    if (b == 13) { pendingCr = true; continue; }
                    o.WriteByte(b);
                }
            }
            if (pendingCr) o.WriteByte(13);
        }
    }
}
"@

& $Adb get-state | Out-Null
if ($LASTEXITCODE -ne 0) { throw "No ADB device" }
if ((Su "id -u") -ne "0") { throw "su did not give uid 0" }

$dir = Join-Path $BackupRoot $Session
$pdir = Join-Path $dir "partitions"
New-Item -ItemType Directory -Force -Path $pdir | Out-Null

# Device facts that are useful for the port (serial numbers are deliberately not saved)
Su "getprop ro.build.fingerprint; getprop ro.product.device; uname -a" |
    Set-Content (Join-Path $dir "device-info.txt")
Su "cat /proc/partitions" | Set-Content (Join-Path $dir "proc-partitions.txt")

$byname = $null
foreach ($p in "/dev/block/by-name", "/dev/block/platform/bootdevice/by-name") {
    $r = & $Adb shell "su -c 'ls $p'" 2>$null
    if ($LASTEXITCODE -eq 0 -and $r) { $byname = $p; break }
}
if (-not $byname) { throw "by-name directory not found" }
$names = (Su "ls $byname") -split "\s+" | Where-Object { $_ }
$items = @()
foreach ($n in $names) {
    if ($Only -and ($Only -notcontains $n)) { continue }
    if ($n -eq "userdata" -and -not $IncludeUserdata) { Write-Host "skip userdata (use -IncludeUserdata)"; continue }
    $items += [pscustomobject]@{ Name = $n; Dev = "$byname/$n"; Out = (Join-Path $pdir "$n.bin") }
}
# eMMC hardware boot partitions (preloader is in boot0 = MTKClient's "boot1")
if (-not $Only -or $Only -contains "preloader") {
    foreach ($b in @(@("mmcblk0boot0", "emmc_boot1.bin"), @("mmcblk0boot1", "emmc_boot2.bin"))) {
        $items += [pscustomobject]@{ Name = $b[0]; Dev = "/dev/block/$($b[0])"; Out = (Join-Path $dir $b[1]) }
    }
}

$manifest = Join-Path $dir "MANIFEST.sha256"
$bad = 0
foreach ($it in $items) {
    Write-Host ("reading {0,-16} " -f $it.Name) -NoNewline
    Save-AdbStream "exec-out su -c `"cat $($it.Dev)`"" $it.Out
    $devHash = ((Su "sha256sum $($it.Dev)") -split "\s+")[0].ToLower()
    $pcHash = (Get-FileHash $it.Out -Algorithm SHA256).Hash.ToLower()
    $note = "OK"
    if ($devHash -ne $pcHash) {
        $raw = "$($it.Out).crlf"
        Move-Item -Force $it.Out $raw
        [X04gOnlcr]::Undo($raw, $it.Out)
        $pcHash = (Get-FileHash $it.Out -Algorithm SHA256).Hash.ToLower()
        if ($devHash -eq $pcHash) { Remove-Item $raw; $note = "OK (undid tty LF->CRLF)" }
        else { Move-Item -Force $raw $it.Out; $note = "HASH MISMATCH (device $devHash)" }
    }
    $size = (Get-Item $it.Out).Length
    $ok = $devHash -eq $pcHash
    if (-not $ok) { $bad++ }
    Write-Host ("{0,12:N0} bytes  {1}" -f $size, $note)
    "{0}  {1}  {2}" -f $pcHash, $size, $it.Out.Substring($dir.Length + 1) | Add-Content $manifest
}
if ($bad) { throw "$bad image(s) differ from the device - backup NOT verified" }
Write-Host "All $($items.Count) images match the device-side SHA-256. Manifest: $manifest" -ForegroundColor Green
Write-Host "Note: rw-mounted partitions (metadata, nvdata, persist, cache) were read live; use the MTKClient backup as the restore source."
