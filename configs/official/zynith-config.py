#!/usr/bin/env python3
"""configs/official/zynith-config.py — apply, preview, validate and undo Zynith's official configurations.

  zynith-config.py list                    the official configurations
  zynith-config.py show <name>             what applying <name> would change in your files (nothing is written)
  zynith-config.py apply <name>            apply it: only the keys it sets change; each file is backed up first
  zynith-config.py restore                 put back the files as they were before the last apply
  zynith-config.py validate                check every official configuration against the options Zynith knows

A configuration is a folder of small TOML files (appearance.toml, experience.toml, animation.toml) that set some keys
of the files of the same name in ~/.config/zynith. Keys a configuration does not set, comments, and every other file
are left as they are. The running UI picks the change up on its own. Backups go to
~/.local/state/zynith/config-backups.
"""
import datetime
import os
import pathlib
import re
import shutil
import sys
import tomllib

HERE = pathlib.Path(__file__).resolve().parent
CONFIG = pathlib.Path(os.environ.get("XDG_CONFIG_HOME") or pathlib.Path.home() / ".config") / "zynith"
BACKUPS = pathlib.Path(os.environ.get("XDG_STATE_HOME") or pathlib.Path.home() / ".local/state") / "zynith" / "config-backups"

# The options a configuration may set, as the UI defines them (ui/Services/Config.qml): a type, or the allowed values,
# or a numeric range.
SCHEMA = {
    "appearance.toml": {
        "surface_style": {"glass", "solid", "blur"},
        "glass_strength": (0.0, 1.0),
        "blur_strength": (0.0, 1.0),
        "border": {"none", "subtle", "defined"},
        "radius": (0.5, 1.5),
        "contrast": {"standard", "high"},
        "accent": str,
        "tint": (0.0, 1.0),
        "font_scale": (0.85, 1.3),
    },
    "experience.toml": {
        "efficiency": {"auto", "save"},
        "ease_effects": bool,
    },
    # speed and reduced_motion are kept in step with the native shell by Settings, so a configuration leaves them alone
    "animation.toml": {
        "style": {"fluid", "crisp", "calm"},
    },
}


def configurations():
    return sorted(p.name for p in HERE.iterdir() if p.is_dir() and any(p.glob("*.toml")))


def check_value(rule, value):
    if isinstance(rule, set):
        return isinstance(value, str) and value in rule
    if isinstance(rule, tuple):
        return isinstance(value, (int, float)) and not isinstance(value, bool) and rule[0] <= value <= rule[1]
    if rule is bool:
        return isinstance(value, bool)
    return isinstance(value, rule)


def load(name):
    folder = HERE / name
    if not folder.is_dir():
        raise SystemExit(f"no official configuration named {name!r} (see: list)")
    out = {}
    for f in sorted(folder.glob("*.toml")):
        with open(f, "rb") as fh:
            out[f.name] = tomllib.load(fh)
    return out


def problems(name):
    errs = []
    for fname, keys in load(name).items():
        schema = SCHEMA.get(fname)
        if schema is None:
            errs.append(f"{name}/{fname}: not a file a configuration may set")
            continue
        for key, value in keys.items():
            if key not in schema:
                errs.append(f"{name}/{fname}: unknown option {key}")
            elif not check_value(schema[key], value):
                errs.append(f"{name}/{fname}: {key} = {value!r} is not allowed")
    return errs


def toml_value(v):
    if isinstance(v, bool):
        return "true" if v else "false"
    if isinstance(v, (int, float)):
        return repr(v)
    return '"' + str(v).replace("\\", "\\\\").replace('"', '\\"') + '"'


def merged_text(text, keys):
    """Set top-level keys in a flat TOML text, keeping comments, order and every other key."""
    lines = text.splitlines()
    first_table = next((i for i, l in enumerate(lines) if re.match(r"\s*\[", l)), len(lines))
    pending = dict(keys)
    for i in range(first_table):
        m = re.match(r"\s*([A-Za-z0-9_-]+)\s*=", lines[i])
        if m and m.group(1) in pending:
            lines[i] = f"{m.group(1)} = {toml_value(pending.pop(m.group(1)))}"
    added = [f"{k} = {toml_value(v)}" for k, v in pending.items()]
    lines[first_table:first_table] = added
    out = "\n".join(lines) + "\n"
    tomllib.loads(out)  # never write something the UI could not read
    return out


def plan(name):
    changes = []
    for fname, keys in load(name).items():
        target = CONFIG / fname
        old = target.read_text() if target.exists() else ""
        if old:
            tomllib.loads(old)  # an unreadable file is reported, never replaced
        changes.append((target, old, merged_text(old, keys)))
    return changes


def main(argv):
    cmd = argv[1] if len(argv) > 1 else "list"
    if cmd == "list":
        for n in configurations():
            first = next((HERE / n).glob("appearance.toml"), None)
            line = first.read_text().splitlines()[0].lstrip("# ") if first else ""
            print(f"{n:16} {line}")
        return 0
    if cmd == "validate":
        errs = [e for n in configurations() for e in problems(n)]
        for e in errs:
            print(e)
        print("valid" if not errs else f"{len(errs)} problem(s)")
        return 1 if errs else 0
    if cmd in ("show", "apply"):
        if len(argv) < 3:
            raise SystemExit(f"usage: {argv[0]} {cmd} <name>")
        name = argv[2]
        errs = problems(name)
        if errs:
            raise SystemExit("\n".join(errs))
        changes = plan(name)
        for target, old, new in changes:
            print(f"{target}: {'unchanged' if old == new else 'changes'}")
            if cmd == "show":
                for line in new.splitlines():
                    if line not in old.splitlines():
                        print(f"  + {line}")
        if cmd == "apply":
            stamp = datetime.datetime.now().strftime("%Y%m%d-%H%M%S")
            backup = BACKUPS / f"{stamp}-before-{name}"
            backup.mkdir(parents=True, exist_ok=True)
            for target, old, new in changes:
                if target.exists():
                    shutil.copy2(target, backup / target.name)
                else:
                    (backup / (target.name + ".absent")).touch()
            for target, old, new in changes:
                target.parent.mkdir(parents=True, exist_ok=True)
                tmp = target.with_suffix(".toml.tmp")
                tmp.write_text(new)
                os.replace(tmp, target)
            print(f"applied {name}; the files as they were are in {backup}")
        return 0
    if cmd == "restore":
        if not BACKUPS.is_dir() or not any(BACKUPS.iterdir()):
            raise SystemExit("nothing to restore")
        last = sorted(BACKUPS.iterdir())[-1]
        for f in last.iterdir():
            if f.name.endswith(".absent"):
                (CONFIG / f.name[: -len(".absent")]).unlink(missing_ok=True)
            else:
                shutil.copy2(f, CONFIG / f.name)
        shutil.rmtree(last)
        print(f"restored the files from {last.name}")
        return 0
    print(__doc__)
    return 2


if __name__ == "__main__":
    sys.exit(main(sys.argv))
