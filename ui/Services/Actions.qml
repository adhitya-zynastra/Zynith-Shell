pragma Singleton

import QtQuick
import Quickshell
import Zynith.Native
import qs.Common

// One vocabulary for "do something": what a bar widget's gesture, a keybinding or a desktop button asks for.
// It is the native shell's (noctalia msg ...) so bars and bindings carry over unchanged; what the Zynith UI
// draws is answered here, everything else goes on to the native shell as the command it already is.
// Zynith adds: exec <shell command> · panel <id> [context] · launcher-mode <prefix> · desktop-edit
//
// origin: { screen, item, bar, widget } — where it came from, so a panel opens beside the widget
Singleton {
    id: root

    // the native Control Center's tabs, and the Zynith panel that answers each

    // options: { open: open rather than toggle, history: where back goes }
    function openPanel(id: string, context: string, origin: var, options: var): void {
        const screen = origin?.screen?.name ?? Workspaces.focusedOutput ?? Quickshell.screens[0]?.name ?? "";
        if (origin?.bar && origin?.item) {
            origin.bar.openPanel(id, origin.item, context, options);
            return;
        }
        if (options?.transient) {
            const t = options.transient;
            PanelRouter.peek(id, screen, { context: context, history: options?.history ?? [], focused: options?.focused ?? false }, t.owner, t.closeDelay, t.closeOnLeave);
            return;
        }
        const where = ["launcher", "clipboard", "wallpaper", "session"].includes(id) ? { edge: "center", context: context } : { context: context };
        where.history = options?.history ?? [];
        where.focused = options?.focused ?? false;
        if (options?.open)
            PanelRouter.open(id, screen, where);
        else
            PanelRouter.toggle(id, screen, where);
    }

    function run(action: string, origin: var): void {
        const line = (action ?? "").trim();
        if (line === "" || line === "none")
            return;
        const space = line.indexOf(" ");
        const verb = space < 0 ? line : line.slice(0, space);
        const args = space < 0 ? "" : line.slice(space + 1).trim();
        const words = args === "" ? [] : args.split(/\s+/);

        switch (verb) {
        case "exec":
            Quickshell.execDetached(["sh", "-c", args]);
            return;
        case "panel":
            if ((Config.surfaces?.[words[0] ?? ""] ?? "zynith") === "native") {
                CoreClient.call("panel-toggle " + words.join(" "), () => {});
                return;
            }
            openPanel(words[0] ?? "control", words.slice(1).join(" "), origin, {});
            return;
        case "panel-toggle":
        case "panel-open":
            {
                const id = words[0] ?? "";
                // a surface zynith.toml [surfaces] leaves with the native shell is the native shell's to open
                // (the session menu: its own sleek floating one)
                const owner = ({ "control-center": "control_center" })[id] ?? id;
                if ((Config.surfaces?.[owner] ?? "zynith") === "native")
                    break;
                const options = {
                    open: verb === "panel-open",
                    transient: origin?.transient ?? null
                };
                if (id === "control-center") {
                    const tab = words[1] ?? "home";
                    const page = PanelCatalog.isPage(tab) ? tab : "control";
                    // a tab is a page within the Control Panel: back goes there
                    if (page !== "control")
                        options.history = ["control"];
                    openPanel(page, tab, origin, options);
                } else if (id === "launcher") {
                    openPanel("launcher", words.slice(1).join(" "), origin, options);
                } else if (PanelCatalog.opensAlone(id)) {
                    // a Control Panel page named on its own opens focused: by itself, sized to its content,
                    // without the Control Panel's hero and tabs (Sound from the volume icon, like Wi-Fi's)
                    options.focused = PanelCatalog.isPage(id);
                    openPanel(PanelCatalog.aliases[id] ?? id, words.slice(1).join(" "), origin, options);
                } else {
                    break; // a panel this UI does not draw: the native shell's
                }
                return;
            }
        case "launcher-mode":
            openPanel("launcher", args, origin, {});
            return;
        case "desktop-edit":
            Desktop.toggleEditing();
            return;
        case "volume-up":
            Audio.nudge(0.05);
            return;
        case "volume-down":
            Audio.nudge(-0.05);
            return;
        case "volume-mute":
            Audio.toggleMute();
            return;
        case "mic-volume-up":
            Audio.setMicVolume(Audio.micVolume + 0.05);
            return;
        case "mic-volume-down":
            Audio.setMicVolume(Audio.micVolume - 0.05);
            return;
        case "mic-mute":
            Audio.toggleMicMute();
            return;
        case "brightness-up":
            Backlight.set(Backlight.value + 0.05);
            return;
        case "brightness-down":
            Backlight.set(Backlight.value - 0.05);
            return;
        case "media":
            {
                const what = words[0] ?? "toggle";
                if (what === "next")
                    Media.next();
                else if (what === "previous" || what === "prev")
                    Media.previous();
                else
                    Media.toggle();
                return;
            }
        case "notification-dnd-toggle":
            if (Notifications.serving) {
                Notifications.setDnd(!Notifications.dnd);
                return;
            }
            break;
        case "workspace-switch":
            {
                const dir = words[0] ?? "next";
                NiriState.action({
                    [dir === "prev" || dir === "up" ? "FocusWorkspaceUp" : "FocusWorkspaceDown"]: {}
                });
                return;
            }
        case "taskbar-cycle":
            NiriState.action({
                [words[0] === "prev" ? "FocusWindowUpOrColumnLeft" : "FocusWindowDownOrColumnRight"]: {}
            });
            return;
        case "settings-open":
            Quickshell.execDetached([Paths.uiScript, "settings", words[0] ?? "home"]);
            return;
        case "settings-open-widget":
            Quickshell.execDetached([Paths.uiScript, "settings", "bars"]);
            return;
        }
        // everything else is a native shell command, as it always was
        CoreClient.call(line, reply => {
            if (reply.startsWith("error"))
                console.warn("zynith: action", line, "→", reply.trim());
        });
    }
}
