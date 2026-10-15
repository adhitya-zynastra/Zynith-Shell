#!/usr/bin/env python3
# Wallpaper changes through the browser, with real keys (wtype): normal pick, rapid picks, an interrupted pick
# (Escape right after Return), a very large image, and one pick under each surface style. For each: time until the
# UI's palette is the new wallpaper's and its cross-fade has finished, and that the palette file names the image
# shown. Memory of the UI and the native shell before and after. Restores the wallpaper and appearance.toml.
import json, os, shutil, subprocess, sys, time

UI = os.path.expanduser("~/.local/src/noctalia-lockfade/zynith-ui/ui/zynith-ui")
WTYPE = os.environ.get("WTYPE", "wtype")
APPEAR = os.path.expanduser("~/.config/zynith/appearance.toml")
PAL = os.path.expanduser("~/.local/state/zynith/palette.json")
BIG = os.path.expanduser("~/Pictures/wallpapers/Default/1392833.jpg")
TMP = os.environ.get("XDG_RUNTIME_DIR", "/tmp") + "/zynith-wallpaper-test"
os.makedirs(TMP, exist_ok=True)

def ui(*a):
    return subprocess.run([UI, *a], capture_output=True, text=True).stdout.strip()

def status():
    return json.loads(ui("ipc", "status"))

def keys(*names):
    args = []
    for n in names:
        args += ["-k", n]
    subprocess.run([WTYPE, *args])

def locked():
    out = subprocess.run(["noctalia", "msg", "status"], capture_output=True, text=True).stdout
    return '"locked": false' not in out

def rss(pid):
    for l in open(f"/proc/{pid}/status"):
        if l.startswith("VmRSS"):
            return int(l.split()[1]) // 1024
    return -1

def pids():
    ui_pid = subprocess.run(["pgrep", "-f", "quickshell -p .*zynith-ui/ui/shell.qml"], capture_output=True, text=True).stdout.split()[0]
    nat = subprocess.run(["pgrep", "-x", "noctalia"], capture_output=True, text=True).stdout.split()[0]
    return int(ui_pid), int(nat)

def settle(t0, timeout=12):
    """until the UI shows a wallpaper, its palette is that wallpaper's, the file agrees and the blend is done"""
    while time.time() - t0 < timeout:
        s = status()["scheme"]
        if s["wallpaper"] and s["image"] == s["wallpaper"] and s["blend"] >= 1:
            pal = json.load(open(PAL))
            return time.time() - t0, s, pal["image"] == s["wallpaper"] and pal["colors"]["primary"].lower() == s["primary"].lower()[:7]
        time.sleep(0.05)
    return None, status()["scheme"], False

def report(tag, r):
    dt, s, match = r
    print(f"{tag:22s} settled {('%.2fs' % dt) if dt else 'NO':>6}  palette={'match' if match else 'MISMATCH'}  primary={s['primary']}  {os.path.basename(s['wallpaper'])}", flush=True)

if locked():
    sys.exit("session locked; not testing")

orig_wall = subprocess.run(["noctalia", "msg", "wallpaper-get"], capture_output=True, text=True).stdout.strip().splitlines()[0]
assert os.path.isfile(orig_wall), orig_wall
mode = status()["core"]["wallpaperMode"]
if mode != "static":
    sys.exit(f"wallpaper mode is {mode}; this test restores only a static wallpaper")
shutil.copy2(APPEAR, TMP + "/appearance.bak")
ui_pid, nat_pid = pids()
mem0 = (rss(ui_pid), rss(nat_pid))
print("start", os.path.basename(orig_wall), "rss ui/native MiB", mem0)

try:
    ui("cmd", "wallpaper"); time.sleep(1.4)
    ui("ipc", "captureBar", "panel@eDP-1", TMP + "/browser-before.png")

    # 1. one pick: the next wallpaper, Return
    keys("Right"); time.sleep(0.4)
    t0 = time.time(); keys("Return")
    report("single pick", settle(t0))
    time.sleep(0.6)
    ui("ipc", "captureBar", "panel@eDP-1", TMP + "/browser-after.png")

    # 2. rapid picks: five in about a second
    t0 = time.time()
    for _ in range(5):
        keys("Right", "Return"); time.sleep(0.18)
    report("rapid x5", settle(t0))

    # 3. interrupted: Return, then Escape at once (the browser closes mid-change)
    keys("Right"); time.sleep(0.3)
    t0 = time.time(); keys("Return", "Escape")
    report("pick + escape", settle(t0))

    # 4. very large image (8365x5582, 29 MB), through the browser's own apply path
    t0 = time.time(); ui("ipc", "applyWallpaper", BIG, "960", "540")
    report("large 8365x5582", settle(t0, 20))

    # 5. each surface style: one pick with the browser open
    for style in ("glass", "solid", "blur"):
        ui("ipc", "surface", style); time.sleep(1.0)
        ui("cmd", "wallpaper"); time.sleep(1.4)
        keys("Right"); time.sleep(0.3)
        t0 = time.time(); keys("Return")
        report("style " + style, settle(t0))
        ui("ipc", "captureBar", "panel@eDP-1", f"{TMP}/browser-{style}.png")
        keys("Escape"); time.sleep(0.8)
finally:
    ui("cmd", "close")
    tmp = APPEAR + ".wp-restore"
    shutil.copy2(TMP + "/appearance.bak", tmp)
    os.replace(tmp, APPEAR)
    time.sleep(1.0)
    ui("ipc", "applyWallpaper", orig_wall, "-1", "-1")
    report("restored", settle(time.time(), 20))
    time.sleep(3)
    mem1 = (rss(ui_pid), rss(nat_pid))
    print("end rss ui/native MiB", mem1, "delta", (mem1[0] - mem0[0], mem1[1] - mem0[1]))
    print("appearance identical:", open(APPEAR, "rb").read() == open(TMP + "/appearance.bak", "rb").read())
