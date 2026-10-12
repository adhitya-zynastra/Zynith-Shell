#!/usr/bin/env python3
"""A virtual absolute pointer for live UI tests: exact screen coordinates, presses and drags.

wlrctl moves the pointer relatively, through pointer acceleration, so it cannot land on a given pixel and cannot
press-and-hold. This makes a uinput absolute pointer (like a VM's tablet), which the compositor maps onto the
output, so (x, y) is a screen pixel. It needs write access to /dev/uinput (the `input` group or a uaccess ACL).

  vpointer.py move X Y
  vpointer.py click X Y [left|right|middle]
  vpointer.py drag X1 Y1 X2 Y2 [STEPS]      (absolute: the compositor treats it as a tablet)
  vpointer.py mdrag X Y DX DY             (a mouse drag: placed absolutely, then pressed and moved by a
                                           relative mouse, as a real one; DX/DY pass pointer acceleration)
  vpointer.py hover X Y SECONDS

Screen size defaults to 1920x1200; set VPOINTER_SIZE=WxH otherwise.
"""
import os
import sys
import time

from evdev import AbsInfo, UInput, ecodes as e

W, H = (int(v) for v in os.environ.get("VPOINTER_SIZE", "1920x1200").split("x"))
BUTTONS = {"left": e.BTN_LEFT, "right": e.BTN_RIGHT, "middle": e.BTN_MIDDLE}


def device():
    caps = {
        e.EV_KEY: [e.BTN_LEFT, e.BTN_RIGHT, e.BTN_MIDDLE],
        e.EV_ABS: [
            (e.ABS_X, AbsInfo(value=0, min=0, max=W - 1, fuzz=0, flat=0, resolution=0)),
            (e.ABS_Y, AbsInfo(value=0, min=0, max=H - 1, fuzz=0, flat=0, resolution=0)),
        ],
    }
    ui = UInput(caps, name="zynith-test-pointer")
    time.sleep(0.6)  # let the compositor pick the new device up
    return ui


def move(ui, x, y):
    ui.write(e.EV_ABS, e.ABS_X, int(x))
    ui.write(e.EV_ABS, e.ABS_Y, int(y))
    ui.syn()


def settle(ui, x, y):
    # a new device's first position can arrive after the next press: place it, nudge it, place it again
    for dx in (0, 1, 0):
        move(ui, x + dx, y)
        time.sleep(0.12)


def mouse():
    caps = {e.EV_KEY: [e.BTN_LEFT, e.BTN_RIGHT, e.BTN_MIDDLE], e.EV_REL: [e.REL_X, e.REL_Y]}
    m = UInput(caps, name="zynith-test-mouse")
    time.sleep(0.6)
    return m


def button(ui, name, down):
    ui.write(e.EV_KEY, BUTTONS[name], 1 if down else 0)
    ui.syn()


def main(argv):
    if len(argv) < 2:
        print(__doc__)
        return 2
    cmd, args = argv[1], argv[2:]
    with device() as ui:
        if cmd == "move":
            settle(ui, *map(float, args[:2]))
        elif cmd == "click":
            x, y = map(float, args[:2])
            name = args[2] if len(args) > 2 else "left"
            settle(ui, x, y)
            button(ui, name, True)
            time.sleep(0.06)
            button(ui, name, False)
        elif cmd == "drag":
            x1, y1, x2, y2 = map(float, args[:4])
            steps = int(args[4]) if len(args) > 4 else 30
            settle(ui, x1, y1)
            button(ui, "left", True)
            time.sleep(0.12)
            for i in range(1, steps + 1):
                move(ui, x1 + (x2 - x1) * i / steps, y1 + (y2 - y1) * i / steps)
                time.sleep(0.016)
            time.sleep(0.12)
            button(ui, "left", False)
        elif cmd == "mdrag":
            x, y, dx, dy = map(float, args[:4])
            settle(ui, x, y)
            with mouse() as m:
                # the tablet placed the cursor, but the client's mouse position is set only by mouse motion:
                # a step there and back, so the press lands where the cursor is
                for step in (1, -1):
                    m.write(e.EV_REL, e.REL_X, step)
                    m.syn()
                    time.sleep(0.08)
                button(m, "left", True)
                time.sleep(0.12)
                steps = max(1, int(max(abs(dx), abs(dy)) / 2))
                for _ in range(steps):
                    m.write(e.EV_REL, e.REL_X, int(round(dx / steps)))
                    m.write(e.EV_REL, e.REL_Y, int(round(dy / steps)))
                    m.syn()
                    time.sleep(0.012)
                time.sleep(0.12)
                button(m, "left", False)
        elif cmd == "hover":
            x, y, secs = float(args[0]), float(args[1]), float(args[2])
            move(ui, x, y)
            time.sleep(secs)
        else:
            print(__doc__)
            return 2
        time.sleep(0.15)
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv))
