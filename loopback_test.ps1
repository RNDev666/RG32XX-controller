# loopback_test.ps1 - measure the PC-only half of the video latency.
#
# Captures the MSCLOCK window, runs it through the SAME encoder settings as
# stream.ps1, and decodes it locally with ffplay (low-latency) into a window
# titled LOOPBACK. No device, no USB, no adb involved.
#
# Usage:
#   1. .\latency_clock.ps1                 # window titled MSCLOCK
#   2. .\loopback_test.ps1                 # window titled LOOPBACK (decoded)
#   3. Photograph both windows together. The delta is the PC-side latency
#      (capture + encode + mpegts + decode + ffplay display).
#
# Compare against the full glass-to-glass number from the real device stream:
#   full_path - loopback  ~=  USB/adb transport + device swscale/fbdev + LCD
#
# Ctrl+C to stop.

$ErrorActionPreference = 'Stop'
$Port = 35050   # separate from the device stream port (35000)

# ffplay listens; the encoder connects to it.
$playArgs = @(
    '-hide_banner', '-loglevel', 'warning',
    '-fflags', 'nobuffer', '-flags', 'low_delay', '-framedrop',
    '-probesize', '32', '-analyzeduration', '0',
    '-window_title', 'LOOPBACK',
    '-i', "tcp://127.0.0.1:${Port}?listen"
)
$play = Start-Process ffplay -ArgumentList $playArgs -PassThru
Start-Sleep -Milliseconds 800

try {
    ffmpeg -hide_banner -loglevel warning -f gdigrab -framerate 30 -i "title=MSCLOCK" `
        -vf "scale=640:480:force_original_aspect_ratio=decrease,pad=640:480:(ow-iw)/2:(oh-ih)/2" `
        -c:v libx264 -preset ultrafast -tune zerolatency -pix_fmt yuv420p `
        -b:v 3M -maxrate 3M -bufsize 200k -g 60 `
        -muxdelay 0 -muxpreload 0 -flush_packets 1 `
        -f mpegts "tcp://127.0.0.1:$Port"
}
finally {
    if ($play -and -not $play.HasExited) { Stop-Process -Id $play.Id -Force -ErrorAction SilentlyContinue }
}
