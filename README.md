# PC → RG35XX (GarlicOS) wired game streaming

Streams a game window (or your primary monitor) from Windows to an
original RG35XX over the USB-C cable, with the handheld's buttons
acting as a virtual Xbox 360 controller on the PC. No WiFi, no extra
firmware — works on stock GarlicOS via adb.

## How it works

Video: ffmpeg on the PC captures the window (gdigrab), encodes H.264
(ultrafast/zerolatency), and sends MPEG-TS over TCP through `adb
forward`. A static armhf ffmpeg on the handheld (installed once to
`/mnt/SDCARD/.pcstream/`) decodes straight into the framebuffer
(`/dev/fb0`, 640x480 RGB565). The GarlicOS UI process is paused
(SIGSTOP) during the stream and restored afterward.

Input: the handheld pipes `/dev/input/event1` through busybox `nc` over
a second forwarded port. `input_bridge.py` parses the raw events and
drives a virtual Xbox 360 pad via ViGEmBus (analog L2/R2 included).

## Requirements

- adb and ffmpeg in PATH (PC side)
- Python 3 with `vgamepad` (`pip install vgamepad`) + ViGEmBus driver
- RG35XX connected over USB, visible in `adb devices`

## Usage

```powershell
.\stream.ps1                          # stream primary monitor
.\stream.ps1 -WindowTitle "Celeste"   # stream one window (exact title)
.\stream.ps1 -ListWindows             # list capturable window titles
.\stream.ps1 -Fps 30 -BitrateM 3      # tuning (defaults shown)
.\stream.ps1 -NoInput                 # video only
.\stream.ps1 -DurationSec 60          # auto-stop (otherwise Ctrl+C)
.\stream.ps1 -WindowTitle "X" -NoInput; # keyboard instead of gamepad:
python input_bridge.py --keyboard     # run bridge manually
```

Stop with Ctrl+C — cleanup restores the GarlicOS UI automatically.
First run installs ffmpeg to the handheld's SD card (~32 MB, one time).

## Button mapping (virtual Xbox 360 pad)

D-pad → D-pad, A/B/X/Y → A/B/X/Y, L1/R1 → shoulders,
L2/R2 → analog triggers, Start → Start, Select → Back, Menu → Guide.
Keyboard fallback mapping is in `KeyboardOut.KEYMAP` in
`input_bridge.py`.

## Notes & limits

- Latency is roughly 100–250 ms — fine for slower games, not for
  twitch-action titles.
- No audio (plays on the PC). Adding it would need another
  stream + ALSA on the device; the decoder CPU budget is tight.
- Window capture requires the window to be unminimized; title must
  match exactly (`-ListWindows` helps).
- 16:9 sources are letterboxed onto the 4:3 screen.
- If a stream dies unexpectedly and the GarlicOS menu looks frozen,
  run: `adb shell "busybox fbset -fb /dev/fb0 -g 640 480 640 1440 16"`
  and `adb shell "busybox pkill -CONT main"` (or just reboot the
  handheld).

## Device facts (discovered during setup)

- Original RG35XX, GarlicOS kernel 3.10.37 (Actions GS705A, 4x
  Cortex-A9, 237 MB RAM), Android-style init with adbd as root
- Display: `/dev/fb0`, 640x480 RGB565; virtual height must equal 480
  during streaming (GarlicOS uses 1440 = triple buffer)
- Gamepad: `/dev/input/event1`; A/B/X/Y=0x130/131/133/134,
  L1/R1=0x136/137, Select/Start/Menu=0x13A/13B/13C, D-pad=ABS_HAT0X/Y,
  L2/R2=ABS_Z/ABS_RZ (0–255)
- adbd too old for `exec-out`/`reverse`; busybox 1.14 `nc -e` broken,
  pipe form works
