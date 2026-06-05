# stream.ps1 - stream a game window (or primary monitor) from this PC
# to an RG35XX running GarlicOS over the USB cable (adb).
#
# Usage:
#   .\stream.ps1                          # stream primary monitor
#   .\stream.ps1 -WindowTitle "Celeste"   # stream a specific window (exact title)
#   .\stream.ps1 -ListWindows             # show capturable window titles
#   .\stream.ps1 -Fps 30 -BitrateM 3 -NoInput
#
# Stop with Ctrl+C. Cleanup (restore GarlicOS UI) runs automatically.

param(
    [string]$WindowTitle = '',
    [int]$Fps = 30,
    [double]$BitrateM = 3,
    [int]$DurationSec = 0,   # 0 = run until Ctrl+C
    [switch]$NoInput,
    [switch]$ListWindows
)

$ErrorActionPreference = 'Stop'
$VideoPort = 35000
$InputPort = 35001
$DevFfmpeg = '/mnt/SDCARD/.pcstream/ffmpeg'
$FfmpegUrl = 'https://johnvansickle.com/ffmpeg/releases/ffmpeg-release-armhf-static.tar.xz'

if ($ListWindows) {
    Add-Type -AssemblyName System.Windows.Forms
    Get-Process | Where-Object { $_.MainWindowTitle } |
        Select-Object -ExpandProperty MainWindowTitle | Sort-Object -Unique
    exit 0
}

function Fail($msg) { Write-Host "ERROR: $msg" -ForegroundColor Red; exit 1 }

# --- preflight -----------------------------------------------------------
foreach ($tool in 'adb', 'ffmpeg') {
    if (-not (Get-Command $tool -ErrorAction SilentlyContinue)) { Fail "$tool not found in PATH" }
}
$state = (adb get-state 2>$null)
if ($state -ne 'device') { Fail 'no adb device connected (is the RG35XX plugged in and on?)' }

# --- ensure decoder binary on device ------------------------------------
$have = adb shell "ls $DevFfmpeg 2>/dev/null"
if (-not $have) {
    Write-Host 'Installing static ffmpeg onto the handheld SD card (one-time)...'
    $tmp = Join-Path $env:TEMP 'rg35xx-ffmpeg'
    New-Item -ItemType Directory -Force -Path $tmp | Out-Null
    $tarball = Join-Path $tmp 'ffmpeg-armhf.tar.xz'
    if (-not (Test-Path $tarball)) { curl.exe -sLo $tarball $FfmpegUrl }
    tar -xf $tarball -C $tmp
    $bin = Get-ChildItem -Path $tmp -Recurse -Filter ffmpeg | Select-Object -First 1
    if (-not $bin) { Fail 'could not extract armhf ffmpeg' }
    adb shell 'busybox mkdir -p /mnt/SDCARD/.pcstream' | Out-Null
    adb push $bin.FullName $DevFfmpeg | Out-Null
    adb shell "chmod 755 $DevFfmpeg" | Out-Null
}

# --- find GarlicOS UI process (paused during stream) ---------------------
$uiPid = $null
$psLine = adb shell ps | Select-String '\./main' | Select-Object -First 1
if ($psLine) { $uiPid = ($psLine.ToString() -split '\s+')[1] }

# --- capture source ------------------------------------------------------
if ($WindowTitle) {
    $grabArgs = @('-f', 'gdigrab', '-framerate', $Fps, '-i', "title=$WindowTitle")
} else {
    Add-Type -AssemblyName System.Windows.Forms
    $b = [System.Windows.Forms.Screen]::PrimaryScreen.Bounds
    $grabArgs = @('-f', 'gdigrab', '-framerate', $Fps,
                  '-offset_x', $b.X, '-offset_y', $b.Y,
                  '-video_size', "$($b.Width)x$($b.Height)", '-i', 'desktop')
}

$procs = @()
try {
    # --- port forwards ----------------------------------------------------
    adb forward "tcp:$VideoPort" "tcp:$VideoPort" | Out-Null
    if (-not $NoInput) { adb forward "tcp:$InputPort" "tcp:$InputPort" | Out-Null }

    # --- device decoder (adb shell session must stay open) ----------------
    $decCmd = "$DevFfmpeg -loglevel error -fflags nobuffer -flags low_delay " +
              "-probesize 32 -analyzeduration 0 -f mpegts " +
              "-i tcp://0.0.0.0:${VideoPort}?listen " +
              "-vf scale=640:480 -pix_fmt rgb565le -f fbdev /dev/fb0"
    $procs += Start-Process adb -ArgumentList 'shell', $decCmd -WindowStyle Hidden -PassThru

    # --- device input forwarder -------------------------------------------
    if (-not $NoInput) {
        $inpCmd = "while true; do busybox cat /dev/input/event1 | busybox nc -l -p $InputPort; done"
        $procs += Start-Process adb -ArgumentList 'shell', $inpCmd -WindowStyle Hidden -PassThru
    }

    Start-Sleep 2

    # --- take over the screen ---------------------------------------------
    adb shell 'busybox fbset -fb /dev/fb0 -g 640 480 640 480 16' | Out-Null
    if ($uiPid) { adb shell "kill -STOP $uiPid" | Out-Null }

    # --- PC input bridge ----------------------------------------------------
    if (-not $NoInput) {
        $bridge = Join-Path $PSScriptRoot 'input_bridge.py'
        $py = if (Get-Command python -ErrorAction SilentlyContinue) { 'python' } else { 'py' }
        $procs += Start-Process $py -ArgumentList '-u', "`"$bridge`"", '--port', $InputPort `
                      -WindowStyle Minimized -PassThru
    }

    # --- capture + encode (blocks until Ctrl+C or window closes) -----------
    Write-Host "Streaming$(if ($WindowTitle) { " '$WindowTitle'" } else { ' primary monitor' }) -> RG35XX. Ctrl+C to stop." -ForegroundColor Green
    $g = [Math]::Max(2 * $Fps, 30)
    $durArgs = @(); if ($DurationSec -gt 0) { $durArgs = @('-t', $DurationSec) }
    ffmpeg -hide_banner -loglevel warning @grabArgs @durArgs `
        -vf "scale=640:480:force_original_aspect_ratio=decrease,pad=640:480:(ow-iw)/2:(oh-ih)/2" `
        -c:v libx264 -preset ultrafast -tune zerolatency -pix_fmt yuv420p `
        -b:v "${BitrateM}M" -maxrate "${BitrateM}M" -bufsize 1M -g $g `
        -f mpegts "tcp://127.0.0.1:$VideoPort"
}
finally {
    Write-Host 'Cleaning up...'
    foreach ($p in $procs) { if ($p -and -not $p.HasExited) { Stop-Process -Id $p.Id -Force -ErrorAction SilentlyContinue } }
    adb shell 'busybox pkill -f pcstream/ffmpeg; busybox pkill -f "nc -l"; busybox pkill -f "input/event1"' 2>$null | Out-Null
    adb shell 'busybox fbset -fb /dev/fb0 -g 640 480 640 1440 16' | Out-Null
    if ($uiPid) { adb shell "kill -CONT $uiPid" | Out-Null }
    adb forward --remove "tcp:$VideoPort" 2>$null | Out-Null
    adb forward --remove "tcp:$InputPort" 2>$null | Out-Null
    Write-Host 'Done - GarlicOS UI restored.'
}
