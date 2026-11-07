"""Drive real MATLAB startup/file-picker windows on Mercury's X11 display."""

import ctypes as C
import os
from pathlib import Path
import re
import subprocess
import sys
import time

root = Path(sys.argv[1])
root.mkdir(exist_ok=True, parents=True)
# shortcut: this Mercury GUI harness types lower-case ASCII paths; extend key mapping for other paths.
assert re.fullmatch(
    r"[a-z0-9/.-]+", str(root)
), "Use a lower-case ASCII test directory without spaces or underscores."
display = os.environ.get("DISPLAY", ":1")
env = dict(os.environ, DISPLAY=display)
x = C.CDLL("libX11.so.6")
t = C.CDLL("libXtst.so.6")
x.XOpenDisplay.argtypes = [C.c_char_p]
x.XOpenDisplay.restype = C.c_void_p
d = x.XOpenDisplay(display.encode())
assert d
x.XKeysymToKeycode.argtypes = [C.c_void_p, C.c_ulong]
x.XKeysymToKeycode.restype = C.c_uint
x.XSetInputFocus.argtypes = [C.c_void_p, C.c_ulong, C.c_int, C.c_ulong]
x.XRaiseWindow.argtypes = [C.c_void_p, C.c_ulong]
x.XFlush.argtypes = [C.c_void_p]
t.XTestFakeKeyEvent.argtypes = [C.c_void_p, C.c_uint, C.c_int, C.c_ulong]
t.XTestFakeMotionEvent.argtypes = [C.c_void_p, C.c_int, C.c_int, C.c_int, C.c_ulong]
t.XTestFakeButtonEvent.argtypes = [C.c_void_p, C.c_uint, C.c_int, C.c_ulong]


def window(title):
    for _ in range(500):
        tree = subprocess.check_output(
            ["xwininfo", "-root", "-tree"], env=env, text=True
        )
        match = re.search(r'(0x[0-9a-f]+) "' + re.escape(title) + '"', tree)
        if match:
            details = subprocess.check_output(
                ["xwininfo", "-id", match.group(1)], env=env, text=True
            )
            if "Map State: IsViewable" in details:

                def number(label):
                    return int(re.search(label + r":\s*(-?\d+)", details).group(1))

                wid = int(match.group(1), 16)
                x.XRaiseWindow(d, wid)
                x.XSetInputFocus(d, wid, 2, 0)
                x.XFlush(d)
                time.sleep(0.3)
                return (
                    match.group(1),
                    number("Absolute upper-left X"),
                    number("Absolute upper-left Y"),
                    number("Width"),
                    number("Height"),
                )
        time.sleep(0.1)
    raise RuntimeError("Native window not found: " + title)


def click(w, px, py):
    _, left, top, _, _ = w
    t.XTestFakeMotionEvent(d, 0, left + int(px), top + int(py), 0)
    x.XFlush(d)
    time.sleep(0.1)
    t.XTestFakeButtonEvent(d, 1, 1, 0)
    t.XTestFakeButtonEvent(d, 1, 0, 0)
    x.XFlush(d)
    time.sleep(0.4)


def key(symbol, down):
    t.XTestFakeKeyEvent(d, x.XKeysymToKeycode(d, symbol), down, 0)


def stroke(symbol):
    key(symbol, 1)
    key(symbol, 0)
    x.XFlush(d)


startup = window("VisualTask")
subprocess.run(["import", "-window", startup[0], str(root / "startup-before.png")])
print("STARTUP", startup, flush=True)
click(startup, startup[3] * 0.5, startup[4] * 0.708)
chooser = window("Select the labcams config file.")
click(chooser, chooser[3] * 0.6, chooser[4] * 0.73)
key(0xFFE3, 1)
stroke(ord("a"))
key(0xFFE3, 0)
x.XFlush(d)
time.sleep(0.1)
for ch in str(root / "picked.json"):
    stroke(ord(ch))
    time.sleep(0.006)
subprocess.run(["import", "-window", chooser[0], str(root / "picker-entry.png")])
click(chooser, chooser[3] - 132, chooser[4] - 26)
print("NATIVE_OPEN_CLICKED", flush=True)
time.sleep(0.5)
startup = window("VisualTask")
click(startup, startup[3] * 0.5, startup[4] * 0.708)
chooser = window("Select the labcams config file.")
subprocess.run(["import", "-window", chooser[0], str(root / "picker-cancel.png")])
click(chooser, chooser[3] - 51, chooser[4] - 26)
print("NATIVE_CANCEL_CLICKED", flush=True)
startup = window("VisualTask")
subprocess.run(["import", "-window", startup[0], str(root / "startup-picked.png")])
click(startup, startup[3] * 0.833, startup[4] * 0.87)
print("INITIALIZE_CLICKED", flush=True)
