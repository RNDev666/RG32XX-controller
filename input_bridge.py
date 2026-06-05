"""RG35XX -> PC input bridge.

Reads raw Linux input_event structs from the handheld (forwarded over
adb TCP) and presents them to Windows as a virtual Xbox 360 controller
(via ViGEmBus + vgamepad). Use --keyboard to inject keystrokes instead.

Run with --debug to log every button event.
"""

import argparse
import socket
import struct
import sys
import time

# Captured from this device (GarlicOS RG35XX, /dev/input/event1)
CODE_BTN = {
    0x130: "A", 0x131: "B", 0x133: "X", 0x134: "Y",
    0x136: "L1", 0x137: "R1",
    0x13A: "SELECT", 0x13B: "START", 0x13C: "MENU",
}
ABS_HAT0X, ABS_HAT0Y = 0x10, 0x11   # D-pad
ABS_Z, ABS_RZ = 0x02, 0x05          # L2 / R2 analog triggers (0..255)

EV_KEY, EV_ABS = 1, 3
EVENT_FMT = "<llHHi"  # 32-bit ARM: tv_sec, tv_usec, type, code, value
EVENT_SIZE = struct.calcsize(EVENT_FMT)


# ---------------------------------------------------------------- backends
class GamepadOut:
    """Virtual Xbox 360 controller (ViGEmBus)."""

    def __init__(self):
        import vgamepad as vg
        self._vg = vg
        self.pad = vg.VX360Gamepad()
        B = vg.XUSB_BUTTON
        self.btn = {
            "A": B.XUSB_GAMEPAD_A, "B": B.XUSB_GAMEPAD_B,
            "X": B.XUSB_GAMEPAD_X, "Y": B.XUSB_GAMEPAD_Y,
            "L1": B.XUSB_GAMEPAD_LEFT_SHOULDER,
            "R1": B.XUSB_GAMEPAD_RIGHT_SHOULDER,
            "START": B.XUSB_GAMEPAD_START, "SELECT": B.XUSB_GAMEPAD_BACK,
            "MENU": B.XUSB_GAMEPAD_GUIDE,
            "UP": B.XUSB_GAMEPAD_DPAD_UP, "DOWN": B.XUSB_GAMEPAD_DPAD_DOWN,
            "LEFT": B.XUSB_GAMEPAD_DPAD_LEFT,
            "RIGHT": B.XUSB_GAMEPAD_DPAD_RIGHT,
        }

    def button(self, name, down):
        b = self.btn.get(name)
        if b is None:
            return
        (self.pad.press_button if down else self.pad.release_button)(b)
        self.pad.update()

    def trigger(self, name, value):  # value 0..255
        (self.pad.left_trigger if name == "L2"
         else self.pad.right_trigger)(value=value)
        self.pad.update()

    def reset(self):
        self.pad.reset()
        self.pad.update()


class KeyboardOut:
    """SendInput scancode fallback. Edit KEYMAP to taste."""

    KEYMAP = {
        "UP": "UP", "DOWN": "DOWN", "LEFT": "LEFT", "RIGHT": "RIGHT",
        "A": "X", "B": "Z", "X": "S", "Y": "A",
        "L1": "Q", "R1": "W", "L2": "E", "R2": "R",
        "START": "RETURN", "SELECT": "RSHIFT", "MENU": "ESCAPE",
    }
    VK = {"RETURN": 0x0D, "RSHIFT": 0xA1, "ESCAPE": 0x1B, "SPACE": 0x20,
          "TAB": 0x09, "UP": 0x26, "DOWN": 0x28, "LEFT": 0x25,
          "RIGHT": 0x27}
    for _c in "ABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789":
        VK[_c] = ord(_c)
    EXTENDED = {0x26, 0x28, 0x25, 0x27}

    def __init__(self):
        import ctypes
        self.ctypes = ctypes
        self.user32 = ctypes.windll.user32
        ULONG_PTR = ctypes.c_size_t

        class KEYBDINPUT(ctypes.Structure):
            _fields_ = [("wVk", ctypes.c_ushort), ("wScan", ctypes.c_ushort),
                        ("dwFlags", ctypes.c_ulong), ("time", ctypes.c_ulong),
                        ("dwExtraInfo", ULONG_PTR)]

        class _U(ctypes.Union):
            _fields_ = [("ki", KEYBDINPUT), ("pad", ctypes.c_byte * 32)]

        class INPUT(ctypes.Structure):
            _fields_ = [("type", ctypes.c_ulong), ("u", _U)]

        self.KEYBDINPUT, self.INPUT = KEYBDINPUT, INPUT
        self._trig_state = {"L2": False, "R2": False}

    def _send(self, vk, down):
        scan = self.user32.MapVirtualKeyW(vk, 0)
        flags = 0x0008  # SCANCODE
        if vk in self.EXTENDED:
            flags |= 0x0001
        if not down:
            flags |= 0x0002
        inp = self.INPUT(type=1)
        inp.u.ki = self.KEYBDINPUT(0, scan, flags, 0, 0)
        self.user32.SendInput(1, self.ctypes.byref(inp),
                              self.ctypes.sizeof(self.INPUT))

    def button(self, name, down):
        key = self.KEYMAP.get(name)
        if key and key in self.VK:
            self._send(self.VK[key], down)

    def trigger(self, name, value):
        down = value > 127
        if down != self._trig_state[name]:
            self._trig_state[name] = down
            self.button(name, down)

    def reset(self):
        for name in list(self.KEYMAP):
            self.button(name, False)


# ---------------------------------------------------------------- bridge
class Bridge:
    def __init__(self, out, debug=False):
        self.out = out
        self.debug = debug
        self.held = set()

    def _emit(self, name, down):
        if down == (name in self.held):
            return
        (self.held.add if down else self.held.discard)(name)
        self.out.button(name, down)
        if self.debug:
            print(f"{name:>7} {'DOWN' if down else 'UP'}")

    def handle(self, etype, code, value):
        if etype == EV_KEY and code in CODE_BTN and value in (0, 1):
            self._emit(CODE_BTN[code], value == 1)
        elif etype == EV_ABS:
            if code == ABS_HAT0X:
                self._emit("LEFT", value < 0)
                self._emit("RIGHT", value > 0)
            elif code == ABS_HAT0Y:
                self._emit("UP", value < 0)
                self._emit("DOWN", value > 0)
            elif code == ABS_Z:
                self.out.trigger("L2", max(0, min(255, value)))
                if self.debug:
                    print(f"     L2 {value}")
            elif code == ABS_RZ:
                self.out.trigger("R2", max(0, min(255, value)))
                if self.debug:
                    print(f"     R2 {value}")

    def reset(self):
        self.held.clear()
        self.out.reset()


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--host", default="127.0.0.1")
    ap.add_argument("--port", type=int, default=35001)
    ap.add_argument("--keyboard", action="store_true",
                    help="inject keystrokes instead of virtual gamepad")
    ap.add_argument("--debug", action="store_true")
    args = ap.parse_args()

    if args.keyboard:
        out = KeyboardOut()
        print("output: keyboard (SendInput)")
    else:
        try:
            out = GamepadOut()
            print("output: virtual Xbox 360 controller (ViGEm)")
        except Exception as exc:
            print(f"vgamepad unavailable ({exc}); falling back to keyboard",
                  file=sys.stderr)
            out = KeyboardOut()

    bridge = Bridge(out, debug=args.debug)
    buf = b""
    while True:
        try:
            with socket.create_connection((args.host, args.port),
                                          timeout=5) as s:
                s.settimeout(None)
                print(f"input bridge connected ({args.host}:{args.port})")
                while True:
                    chunk = s.recv(4096)
                    if not chunk:
                        raise ConnectionError("stream closed")
                    buf += chunk
                    while len(buf) >= EVENT_SIZE:
                        _, _, etype, code, value = struct.unpack(
                            EVENT_FMT, buf[:EVENT_SIZE])
                        buf = buf[EVENT_SIZE:]
                        bridge.handle(etype, code, value)
        except (ConnectionError, OSError, socket.timeout) as exc:
            bridge.reset()
            buf = b""
            print(f"input bridge: {exc}; retrying in 2s", file=sys.stderr)
            time.sleep(2)


if __name__ == "__main__":
    main()
