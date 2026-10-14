pragma Singleton

import QtQuick
import Quickshell
import Quickshell.Io
import Zynith.Native

// `quickshell -p <ui>/shell.qml ipc call zynith <method> [args]`
Singleton {
    id: root

    // the output with keyboard focus under niri, else the first one
    function focusedScreen(): string {
        const focused = Workspaces.focusedOutput;
        if (focused && Quickshell.screens.some(s => s.name === focused))
            return focused;
        return Quickshell.screens.length > 0 ? Quickshell.screens[0].name : "";
    }

    // the keybinding socket (zynith-ui cmd …): the same actions, without a client process per key
    readonly property Connections commands: Connections {
        target: CommandServer
        function onCommand(name: string, args: string): void {
            const screen = root.focusedScreen();
            switch (name) {
            case "launcher":
                if (args !== "") {
                    if (PanelRouter.isOpen("launcher", screen) && (PanelRouter.current(screen)?.context ?? "") === args)
                        PanelRouter.close(screen);
                    else
                        PanelRouter.open("launcher", screen, { edge: "center", context: args });
                } else {
                    PanelRouter.toggle("launcher", screen, { edge: "center" });
                }
                break;
            case "clipboard":
            case "wallpaper":
            case "session":
                // an argument picks what the panel opens on, e.g. wallpaper live
                PanelRouter.toggle(name, screen, { edge: "center", context: args });
                break;
            case "control":
            case "notifications":
                PanelRouter.toggle(name, screen, null);
                break;
            case "panel":
                PanelRouter.toggle(args, screen, null);
                break;
            case "close":
                PanelRouter.closeAll();
                break;
            case "open-from": {
                // diagnostics: open a panel as a bar would, from that bar's middle: <bar id> <panel id> [focused]
                const [barId, id, how] = args.split(" ");
                const at = PanelRouter.bars[barId + "@" + screen];
                if (!at) {
                    console.warn("zynith: open-from: no bar", barId, "on", screen);
                    break;
                }
                PanelRouter.open(id, screen, Object.assign({}, at, { focused: how === "focused", history: [], context: "" }));
                break;
            }
            case "action":
                // any action a bar gesture can name: panel-toggle control-center audio, media next, exec …
                Actions.run(args, {
                    screen: Quickshell.screens.find(s => s.name === screen) ?? null
                });
                break;
            case "event":
                Events.dispatch(args);
                break;
            case "desktop-edit":
                Desktop.toggleEditing();
                break;
            case "brightness":
                // up | down | <0-100>
                if (args === "up")
                    Backlight.set(Backlight.value + 0.05);
                else if (args === "down")
                    Backlight.set(Backlight.value - 0.05);
                else if (!isNaN(parseFloat(args)))
                    Backlight.set(parseFloat(args) / 100);
                break;
            default:
                console.warn("zynith: unknown command", name);
            }
        }
    }

    IpcHandler {
        target: "zynith"

        function panel(id: string): void {
            PanelRouter.toggle(id, root.focusedScreen(), null);
        }
        // the desktop widget editor
        function desktopEdit(): void {
            Desktop.toggleEditing();
        }
        // select the n-th widget (from 0) in the editor and show its settings
        function desktopInspect(n: int): void {
            Desktop.setEditing(true);
            const w = Config.widgets[n];
            if (w) {
                Desktop.selection = [w.id];
                Desktop.inspecting = true;
            }
        }
        // the editor's own operations, by widget id (persisted, undoable): show or hide one, set one setting
        // (value as JSON: 96, true, "right")
        function desktopWidgets(): string {
            return JSON.stringify(Config.widgets.map(w => ({ id: w.id, type: w.type, hidden: w.hidden === true, settings: w.settings ?? {} })));
        }
        function desktopSetHidden(id: string, hidden: bool): string {
            const w = Desktop.byId(id);
            if (!w)
                return "no such widget";
            if ((w.hidden === true) !== hidden)
                Desktop.toggleHidden([id]);
            return "ok";
        }
        function desktopSetting(id: string, key: string, json: string): string {
            if (!Desktop.byId(id))
                return "no such widget";
            Desktop.setSetting(id, key, JSON.parse(json));
            return "ok";
        }
        // for diagnostics, no input made: which widget the open editor would hand a press at (x, y) of the output
        // to (its own hit area, as the pointer delivery asks it), or "desktop" (the selection lasso's)
        function editorHit(x: real, y: real): string {
            const slots = PanelRouter.barItems["editor-slots@" + root.focusedScreen()];
            if (!slots)
                return "editor not open";
            const kids = slots.children.filter(c => c.entry !== undefined).sort((a, b) => b.z - a.z);
            for (const s of kids) {
                const p = s.mapFromItem(null, x, y);
                if (s.visible && s.contains(p))
                    return JSON.stringify({ id: s.entry.id, type: s.entry.type, local: [Math.round(p.x), Math.round(p.y)] });
            }
            return "desktop";
        }
        // read-only: at (x, y) of the output, is the press the editor's own panels' (inspector, toolbar, frame buttons)
        // or the canvas's, and what would the canvas do; and where the inspector card is
        function editorProbe(x: real, y: real): string {
            const ed = PanelRouter.barItems["editor-root@" + root.focusedScreen()];
            if (!ed || !ed.slotAt)
                return "editor not open";
            const p = Qt.point(x, y);
            const card = ed.inspectorCard;
            const s = ed.overlayAt(p) ? null : ed.slotAt(p);
            return JSON.stringify({
                overlay: ed.overlayAt(p),
                canvas: ed.overlayAt(p) ? "none" : s ? "move/select " + s.entry.type : "lasso/clear",
                card: card ? [Math.round(card.mapToItem(null, 0, 0).x), Math.round(card.mapToItem(null, 0, 0).y), Math.round(card.width), Math.round(card.height)] : null
            });
        }
        function editorTrace(on: bool): string {
            Desktop.traceInput = on;
            return on ? "editor input trace on (in the UI log)" : "off";
        }
        // like editorHit, through the editor's own decision (what a press at x, y would grab)
        function editorGrab(x: real, y: real): string {
            const ed = PanelRouter.barItems["editor-root@" + root.focusedScreen()];
            if (!ed || !ed.slotAt)
                return "editor not open";
            const s = ed.slotAt(Qt.point(x, y));
            return s ? "move " + s.entry.id + " (" + s.entry.type + ")" : "lasso";
        }
        function desktopPick(): void {
            Desktop.setEditing(true);
            Desktop.picking = true;
        }
        function launcher(): void {
            PanelRouter.toggle("launcher", root.focusedScreen(), { edge: "center" });
        }
        // opens the launcher in a mode: = > @ : !
        function launcherMode(prefix: string): void {
            const screen = root.focusedScreen();
            if (PanelRouter.isOpen("launcher", screen) && (PanelRouter.current(screen)?.context ?? "") === prefix)
                PanelRouter.close(screen);
            else
                PanelRouter.open("launcher", screen, { edge: "center", context: prefix });
        }
        function wallpaper(): void {
            PanelRouter.toggle("wallpaper", root.focusedScreen(), { edge: "center" });
        }
        function quick(): void {
            PanelRouter.toggle("quick", root.focusedScreen(), null);
        }
        function clipboard(): void {
            PanelRouter.toggle("clipboard", root.focusedScreen(), { edge: "center" });
        }
        // what the launcher would list for a query, best first
        function apps(query: string): string {
            return Apps.search(query, 8).map(e => e.name + "  [" + e.id + "]").join("\n");
        }
        function dnd(on: string): string {
            Notifications.setDnd(on === "on" || on === "true" || (on === "toggle" && !Notifications.dnd));
            return Notifications.dnd ? "on" : "off";
        }
        // config | scrolling | tiling-like
        function behaviour(name: string): string {
            Config.setWindowBehaviour(name);
            return Config.window.behaviour;
        }
        function close(): void {
            PanelRouter.closeAll();
        }
        function profile(name: string): string {
            ExperiencePolicy.select(name);
            return ExperiencePolicy.profile;
        }
        function captureBar(key: string, path: string): string {
            const item = PanelRouter.barItems[key];
            // an entry outlives its item when the surface is gone (a destroyed item has no grabToImage)
            if (!item || typeof item.grabToImage !== "function")
                return "no such bar";
            item.grabToImage(r => r.saveToFile(path));
            return "ok";
        }
        // for diagnostics: apply a wallpaper as the browser would, the reveal growing from (x, y)
        function applyWallpaper(path: string, x: int, y: int): void {
            Wallpapers.applyImage(path, { x: x, y: y });
        }
        function bars(): string {
            return JSON.stringify(PanelRouter.bars);
        }
        // diagnostics: each registered surface's window (to match render-loop logs)
        function windows(): string {
            const out = {};
            for (const k in PanelRouter.barItems) {
                const it = PanelRouter.barItems[k];
                out[k] = it && it.Window ? String(it.Window.window) : "";
            }
            return JSON.stringify(out);
        }
        // the bars, from a terminal (zynith-ui ipc barsDo "<command>"; and for tests): the Bar Manager's operations
        // through BarEdits
        //   list | create <edge> <anchor> [name] | preset <key> add|replace | rename <id> <name> | duplicate <id>
        //   remove <id> | show <id> | hide <id> | place <id> <edge> <anchor> | move <id> <-1|1>
        //   add <id> <start|center|end> <kind> | set <id> <key> <json> | component <instance> <key> <json> | undo
        function barsDo(args: string): string {
            const a = args.trim().split(/\s+/);
            const rest = n => a.slice(n).join(" ");
            const out = v => JSON.stringify(v);
            switch (a[0] ?? "list") {
            case "list":
                return out(Config.bars.map(b => ({ id: b.id, name: b.name, edge: b.edge, anchor: b.anchor, enabled: b.enabled !== false, widgets: b.widgets })));
            case "create":
                return out(BarEdits.create({ edge: a[1], anchor: a[2] }, rest(3)));
            case "preset":
                return out(BarEdits.applyPreset(a[1], a[2] ?? "add"));
            case "rename":
                BarEdits.rename(a[1], rest(2));
                break;
            case "duplicate":
                return out(BarEdits.duplicate(a[1]));
            case "remove":
                BarEdits.remove(a[1]);
                break;
            case "show":
            case "hide":
                BarEdits.setEnabled(a[1], a[0] === "show");
                break;
            case "place":
                BarEdits.place(a[1], a[2], a[3]);
                break;
            case "move":
                BarEdits.move(a[1], parseInt(a[2]));
                break;
            case "add":
                BarEdits.addComponent(a[1], a[2], a[3]);
                break;
            case "set":
                BarEdits.setKey(a[1], a[2], JSON.parse(rest(3)));
                break;
            case "component":
                // component <instance> <key> <json>: one setting of one component instance
                BarEdits.setComponentKey(a[1], a[2], JSON.parse(rest(3)));
                break;
            case "undo":
                return out(BarEdits.undo());
            default:
                return "unknown: " + a[0];
            }
            return out(BarEdits.lastLabel);
        }
        function panelRect(): string {
            const r = PanelRouter.rects[root.focusedScreen()] ?? null;
            return JSON.stringify(r ? Object.assign({ window: PanelRouter.windowSizes[root.focusedScreen()] ?? null }, r) : null);
        }
        function stats(): string {
            return JSON.stringify(Diagnostics.summary());
        }
        function resetStats(): void {
            Diagnostics.reset();
        }
        function status(): string {
            return JSON.stringify({
                profile: ExperiencePolicy.profile,
                selected: ExperiencePolicy.selected,
                recommended: ExperiencePolicy.recommended,
                hardwareProfile: ExperiencePolicy.hardwareProfile,
                limitedBy: ExperiencePolicy.limitedBy,
                power: { onBattery: Power.onBattery, level: Number(Power.level.toFixed(2)), low: Power.low, powerSaver: Power.powerSaver },
                tier: Hardware.tier,
                cpu: Hardware.cpuModel,
                threads: Hardware.cpuThreads,
                memGiB: Number(Hardware.memGiB.toFixed(1)),
                gpus: Hardware.gpus.map(g => g.label),
                palette: Scheme.live ? "theme" : "fallback",
                niri: Workspaces.niri,
                overview: Workspaces.overviewOpen,
                workspaces: Workspaces.forScreen(Quickshell.screens[0]).map(w => (w.active ? "*" : "") + w.windows),
                focused: Workspaces.focusedWindow.appId ?? "",
                spectrum: { consumers: Spectrum.consumers, active: Spectrum.active, bands: Spectrum.values.length },
                panels: PanelRouter.openPanels,
                network: { connected: Network.connected, kind: NetworkState.kind, strength: Number(Network.strength.toFixed(2)), wifi: Network.wifiEnabled, listed: Network.networks.length, consumers: NetworkState.consumers, nameLength: Network.name.length, nativeNameLength: NetworkState.name.length, vpn: Network.vpn !== "" },
                core: { known: Core.known, clipboardEntries: Clipboard.entries.length, wallpaperMode: Wallpapers.mode, liveItems: Object.keys(Wallpapers.liveItems).length, staticKnown: Wallpapers.current !== "" },
                notifications: { serving: Notifications.serving, wanted: Notifications.wanted, history: Notifications.history.length, popups: Notifications.popups.length, dnd: Notifications.dnd },
                windowBehaviour: { value: Config.window.behaviour, included: WindowBehaviour.included, error: WindowBehaviour.status },
                launchTime: Quickshell.launchTime
            });
        }
    }
}
