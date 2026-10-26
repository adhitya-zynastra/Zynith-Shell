#!/usr/bin/env python3
"""iso/vmctl.py — drive a test VM started by iso/test-vm.sh: its QMP monitor and its serial console.

  vmctl.py screendump <qmp.sock> <out.png>        the VM's screen, as a PNG
  vmctl.py key <qmp.sock> <combo> [<combo> …]     key presses, QEMU names joined by '-' (e.g. meta_l-ret, ctrl-alt-f3)
  vmctl.py type <qmp.sock> <text>                 type text (US layout)
  vmctl.py powerdown <qmp.sock>                   ACPI power button
  vmctl.py run <serial.sock> <command> [--user U] [--password P] [--timeout S]
                                                  run a shell command on the serial console (logging in as U,
                                                  default liveuser, when a login prompt is showing); prints its
                                                  output and exits with its status
  vmctl.py wait <serial.sock> <text> [--timeout S]
                                                  wait until the console prints <text>

Only for the disposable VMs of iso/test-vm.sh: it talks to the sockets it is given and to nothing else.
"""
import json
import os
import re
import socket
import subprocess
import sys
import tempfile
import time


def qmp(path, *commands):
    s = socket.socket(socket.AF_UNIX)
    s.connect(path)
    f = s.makefile("rw")
    json.loads(f.readline())  # greeting
    replies = []
    for cmd in ({"execute": "qmp_capabilities"},) + commands:
        f.write(json.dumps(cmd) + "\n")
        f.flush()
        while True:
            msg = json.loads(f.readline())
            if "event" in msg:
                continue
            if "error" in msg:
                raise SystemExit(f"qmp: {cmd['execute']}: {msg['error'].get('desc')}")
            replies.append(msg.get("return"))
            break
    s.close()
    return replies[1:]


SHIFTED = {
    '!': '1', '@': '2', '#': '3', '$': '4', '%': '5', '^': '6', '&': '7', '*': '8', '(': '9', ')': '0',
    '_': 'minus', '+': 'equal', '{': 'bracket_left', '}': 'bracket_right', '|': 'backslash', ':': 'semicolon',
    '"': 'apostrophe', '<': 'comma', '>': 'dot', '?': 'slash', '~': 'grave_accent',
}
PLAIN = {
    ' ': 'spc', '-': 'minus', '=': 'equal', '[': 'bracket_left', ']': 'bracket_right', '\\': 'backslash',
    ';': 'semicolon', "'": 'apostrophe', ',': 'comma', '.': 'dot', '/': 'slash', '`': 'grave_accent',
    '\n': 'ret', '\t': 'tab',
}


def keys_for(ch):
    if ch.isalpha() and ch.isascii():
        return ['shift', ch.lower()] if ch.isupper() else [ch]
    if ch.isdigit():
        return [ch]
    if ch in PLAIN:
        return [PLAIN[ch]]
    if ch in SHIFTED:
        return ['shift', SHIFTED[ch]]
    raise SystemExit(f"type: no key for {ch!r}")


def send_keys(path, combos):
    cmds = []
    for combo in combos:
        keys = combo if isinstance(combo, list) else combo.split('-')
        cmds.append({"execute": "send-key",
                     "arguments": {"keys": [{"type": "qcode", "data": k} for k in keys], "hold-time": 40}})
    # one connection; a short pause between presses so the guest sees each one
    s = socket.socket(socket.AF_UNIX)
    s.connect(path)
    f = s.makefile("rw")
    json.loads(f.readline())
    for cmd in [{"execute": "qmp_capabilities"}] + cmds:
        f.write(json.dumps(cmd) + "\n")
        f.flush()
        while "event" in (msg := json.loads(f.readline())):
            pass
        if "error" in msg:
            raise SystemExit(f"send-key: {msg['error'].get('desc')}")
        time.sleep(0.03)
    s.close()


class Console:
    def __init__(self, path):
        self.s = socket.socket(socket.AF_UNIX)
        self.s.connect(path)
        self.s.settimeout(0.5)
        self.buf = ""

    def send(self, text):
        self.s.sendall(text.encode())

    def read_until(self, pattern, timeout):
        deadline = time.time() + timeout
        rx = re.compile(pattern)
        while time.time() < deadline:
            m = rx.search(self.buf)
            if m:
                return m
            try:
                data = self.s.recv(65536)
            except socket.timeout:
                continue
            if not data:
                break
            self.buf += data.decode(errors="replace").replace("\r", "")
        return None


def run(path, command, user, password, timeout):
    c = Console(path)
    c.send("\n")
    m = c.read_until(r"(login: $|[$#] $)", 30)
    if m is None:
        raise SystemExit("run: no login prompt or shell prompt on the console")
    if m.group(1) == "login: ":
        c.buf = ""
        c.send(user + "\n")
        m = c.read_until(r"(Password: $|[$#] $)", 30)
        if m is None:
            raise SystemExit("run: login did not complete")
        if m.group(1) == "Password: ":
            if password is None:
                raise SystemExit(f"run: {user} needs a password on this console (--password)")
            c.buf = ""
            c.send(password + "\n")
            if c.read_until(r"[$#] $", 30) is None:
                raise SystemExit("run: the password was not accepted")
        # a quiet shell for the markers below
        c.send("stty -echo; PS1='$ '\n")
        c.read_until(r"\$ $", 10)
    c.buf = ""
    tag = f"V{os.getpid()}"
    c.send(f"echo {tag}-B; ( {command} ) 2>&1; echo {tag}-E $?\n")
    m = c.read_until(rf"(?s){tag}-B\n(.*?){tag}-E (\d+)", timeout)
    if m is None:
        sys.stdout.write(c.buf)
        raise SystemExit(f"run: timed out after {timeout}s")
    sys.stdout.write(m.group(1))
    return int(m.group(2))


def main(argv):
    if len(argv) < 3:
        print(__doc__)
        return 2
    op, sock = argv[1], argv[2]
    rest = argv[3:]
    opt = lambda name, default: (rest[rest.index(name) + 1] if name in rest else default)
    if op == "screendump":
        with tempfile.TemporaryDirectory() as d:
            ppm = os.path.join(d, "screen.ppm")
            qmp(sock, {"execute": "screendump", "arguments": {"filename": ppm}})
            subprocess.run(["magick", ppm, rest[0]], check=True)
        return 0
    if op == "key":
        send_keys(sock, rest)
        return 0
    if op == "type":
        send_keys(sock, [keys_for(ch) for ch in " ".join(rest)])
        return 0
    if op == "powerdown":
        qmp(sock, {"execute": "system_powerdown"})
        return 0
    if op == "run":
        return run(sock, rest[0], opt("--user", "liveuser"), opt("--password", None), float(opt("--timeout", "120")))
    if op == "wait":
        c = Console(sock)
        if c.read_until(re.escape(rest[0]), float(opt("--timeout", "600"))) is None:
            print(c.buf[-2000:])
            return 1
        return 0
    print(__doc__)
    return 2


if __name__ == "__main__":
    sys.exit(main(sys.argv))
