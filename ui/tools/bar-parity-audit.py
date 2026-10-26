#!/usr/bin/env python3
"""Bar customizability parity: every native bar option and bar-widget option against the Zynith UI.

Native truth:
  * per-bar settings: `zynith-shell msg settings-schema bar` (the native settings registry)
  * per-widget options: the `.key = "..."` fields of the native widget definitions
    (wallpaper-state/src/shell/bar/widgets/*_definition.cpp)
  * capsule groups: the BarCapsuleGroupStyle fields of the native config schema

Zynith side, for each option:
  * exposed: present in Settings (BarsPage.qml for bars and groups, BarWidgetTypes.qml for widgets — per
    widget type, plus the common options every widget has)
  * read: referenced by the bar / widget QML

Prints the gaps; exit status 1 when there are any.
"""
import glob
import json
import os
import re
import subprocess
import sys

UI = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
NATIVE = os.path.join(UI, "..", "..", "wallpaper-state", "src")

# native per-bar key -> the Zynith bars.toml key
RENAMES = {
    "position": "edge", "auto_hide": "visibility", "show_on_workspace_switch": "reveal_on_switch",
    "reserve_space": "reserve", "margin_ends": "offset", "margin_edge": "margin",
    "margin_opposite_edge": "margin_opposite", "background_opacity": "opacity", "widget_spacing": "spacing",
    "start": "start", "center": "center", "end": "end",
}
GROUP_KEYS = ["id", "enabled", "members", "fill", "border", "foreground", "padding", "radius", "opacity",
              "accordion", "accordion_direction", "widget_spacing"]


def read(path):
    with open(path, encoding="utf-8") as f:
        return f.read()


def main():
    gaps = []
    bar_qml = "".join(read(p) for p in glob.glob(os.path.join(UI, "Modules/Bar/*.qml"))) + read(os.path.join(UI, "Widgets/BarItem.qml"))
    # Bars.qml filters the bar list by b.enabled (the bar spec under another name)
    bar_qml = bar_qml.replace("b.enabled", "spec.enabled")
    page = read(os.path.join(UI, "Modules/Settings/BarsPage.qml"))

    schema = json.loads(subprocess.run(["zynith-shell", "msg", "settings-schema", "bar"], capture_output=True, text=True, check=True).stdout)
    per_bar = sorted({".".join(e["path"][2:]) for e in schema["entries"] if e["path"][:2] == ["bar", "default"]})
    for key in per_bar:
        if key.startswith("dead_zone.actions."):
            # the bar's empty-space gestures: BarsPage edits all of BarWidgetTypes.gestures as `actions`
            ok = "BarWidgetTypes.gestures" in page and "actions" in bar_qml
            if not ok:
                gaps.append(f"bar  {key}: dead-zone gesture not editable")
            continue
        z = RENAMES.get(key, key)
        exposed = f'key: "{z}"' in page
        read_ = re.search(r"spec\??\.%s\b" % re.escape(z), bar_qml) is not None or z in ("start", "center", "end")
        if not exposed or not read_:
            gaps.append(f"bar  {key} -> {z}: exposed={exposed} read={read_}")

    group_qml = read(os.path.join(UI, "Modules/Bar/CapsuleGroup.qml")) + read(os.path.join(UI, "Widgets/BarItem.qml"))
    for key in GROUP_KEYS:
        if key == "id":
            continue
        exposed = f'key: "{key}"' in page
        read_ = re.search(r"group\??\.%s\b" % key, group_qml) is not None
        if not exposed or not read_:
            gaps.append(f"group  {key}: exposed={exposed} read={read_}")

    types = read(os.path.join(UI, "Services/BarWidgetTypes.qml"))
    common = re.search(r"readonly property var common: \[(.*?)\n    \]", types, re.S).group(1)
    blocks = {}
    for m in re.finditer(r'type: "([a-z_-]+)"', types):
        nxt = re.search(r'\n\s*\{\s*\n?\s*type: "', types[m.end():])
        blocks[m.group(1)] = blocks.get(m.group(1), "") + types[m.start(): m.end() + (nxt.start() if nxt else len(types))]
    widgets_qml = "".join(read(p) for p in glob.glob(os.path.join(UI, "Widgets/*.qml")) + glob.glob(os.path.join(UI, "Modules/Bar/*.qml")))
    aliases = {"notification": "notifications", "control_center": "control-center"}
    for path in sorted(glob.glob(os.path.join(NATIVE, "shell/bar/widgets/*_definition.cpp"))):
        name = os.path.basename(path).replace("_widget_definition.cpp", "").replace("_definition.cpp", "")
        if name == "test":
            continue
        keys = sorted(set(re.findall(r'\.key = "([a-z_0-9]+)"', read(path))))
        block = blocks.get(name) or blocks.get(aliases.get(name, ""), "")
        if not block:
            gaps.append(f"widget  {name}: no Zynith widget type")
            continue
        for key in keys:
            exposed = f'key: "{key}"' in block or f'key: "{key}"' in common or ("glyphButton" in block and key in ("glyph", "custom_image", "custom_image_colorize"))
            read_ = f'opt("{key}")' in widgets_qml or f"settings.{key}" in widgets_qml or f'"{key}"' in widgets_qml
            if not exposed or not read_:
                gaps.append(f"widget  {name}.{key}: exposed={exposed} read={read_}")

    for g in gaps:
        print(g)
    print(f"{len(per_bar)} bar keys, {len(GROUP_KEYS) - 1} group keys, widget options checked; {len(gaps)} gaps")
    return 1 if gaps else 0


if __name__ == "__main__":
    sys.exit(main())
