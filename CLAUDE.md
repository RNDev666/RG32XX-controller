# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## What this project is

Wired (USB/adb) game streaming from a Windows PC to an original Anbernic
RG35XX running stock GarlicOS, with the handheld acting as a virtual
Xbox 360 controller for the PC. No custom firmware on the device; all
device-side pieces run over adb. There is no build step, lint, or test
suite — everything is verified live against the connected handheld.

## Commands

```powershell
.\stream.ps1                          # stream primary monitor + input
.\stream.ps1 -WindowTitle "Celeste"   # stream one window (exact title)
.\stream.ps1 -ListWindows             # list capturable window titles
.\stream.ps1 -DurationSec 30          # auto-stop (used for testing)
.\stream.ps1 -NoInput                 # video only
python -u input_bridge.py --debug     # run input bridge alone, log events
python -u input_bridge.py --keyboard  # keystrokes instead of gamepad
```

Quick device sanity checks:

```powershell
adb get-state                                         # expect "device"
adb shell "busybox timeout -t 10 getevent -t /dev/input/event1"  # press buttons, see events
adb shell "ls /mnt/SDCARD/.pcstream/ffmpeg"           # decoder installed?
```

If a stream crashes without cleanup, restore the handheld with:

```powershell
adb shell "busybox fbset -fb /dev/fb0 -g 640 480 640 1440 16; busybox pkill -CONT main"
```

## Architecture

Two independent data paths, both tunneled through `adb forward` TCP
(the only transport this device supports — see constraints below):

- Video (PC → device, port 35000): ffmpeg gdigrab capture → libx264
  ultrafast/zerolatency → MPEG-TS over TCP → static armhf ffmpeg on the
  device (installed once to `/mnt/SDCARD/.pcstream/ffmpeg`) decodes to
  `/dev/fb0` (640x480 rgb565le).
- Input (device → PC, port 35001): `busybox cat /dev/input/event1 |
  busybox nc -l -p 35001` on the device; `input_bridge.py` connects
  through the forward, parses raw 16-byte `input_event` structs
  (`<llHHi`, 32-bit ARM), and drives a ViGEmBus virtual X360 pad
  (`vgamepad`). PC initiates both connections; data then flows both ways.

`stream.ps1` orchestrates everything: port forwards, launching the
device decoder (inside a `Start-Process adb shell` that must stay open
— backgrounded device processes die when the adb session closes),
pausing the GarlicOS UI, running capture in the foreground, and a
`finally` block that restores device state.

`btn_test.p8` / `btn_test.tic` are standalone PICO-8 / TIC-80 button
tester carts for running ON the handheld (fake-08 mapping: btn4=B,
btn5=A); unrelated to the streaming pipeline.

## Device constraints (hard-won; do not rediscover)

- Original RG35XX, GarlicOS kernel 3.10.37, Actions GS705A (4x
  Cortex-A9 + NEON), 237 MB RAM, Android-style init, adbd runs as root.
  Userspace is minimal: `/system/bin` toolbox + busybox 1.14 + curl.
- adbd is too old for `adb exec-out` and `adb reverse`; `adb shell`
  mangles binary output (pty). Binary data must go over forwarded TCP.
- busybox `nc -e` is broken; only the pipe form works
  (`cat FILE | nc -l -p PORT`). `nc` handles binary and trickle data fine.
- Framebuffer: `/dev/fb0` is the visible one (fb1 is not scanned out).
  Streaming requires virtual size == physical (`fbset -g 640 480 640 480
  16`); GarlicOS expects `640 480 640 1440` (triple buffer) — always
  restore it. Pixel format rgb565le; mismatched virtual geometry causes
  tiled/diagonal garbage.
- GarlicOS UI is the `./main` process; SIGSTOP it while streaming (it
  fights for the framebuffer and reacts to button presses), SIGCONT on
  cleanup.
- Gamepad is `/dev/input/event1` ("RG35XX Gamepad"): A/B/X/Y =
  0x130/0x131/0x133/0x134, L1/R1 = 0x136/0x137, Select/Start/Menu =
  0x13A/0x13B/0x13C, D-pad = ABS_HAT0X/HAT0Y (±1), L2/R2 = ABS_Z/ABS_RZ
  (0–255 analog).
- Device ffmpeg is John Van Sickle's static armhf build; it persists on
  the SD card (`/tmp` is ramdisk, wiped on reboot). `stream.ps1`
  re-installs it automatically if missing.
- Windows build 26200+ has no native RNDIS driver, so USB ethernet
  gadget networking was rejected in favor of pure adb TCP.
