pragma Singleton

import QtQuick
import Quickshell
import Quickshell.Io
import Zynith.Native
import qs.Common

// `quickshell -p <ui>/shell.qml ipc call zynith <method> [args]`
Singleton {
    id: root

    // diagnostics: a test OSD on request, and where each reporting surface put its window (layer-shell anchors,
    // margins, size), which no capture of the surface's own pixels shows
    signal osdProbe(string kind)
    property var surfaceStates: ({})
    // the last frame-probe recording, read out by frameChunk
    property string frameRecording: ""
    function report(name: string, state: var): void {
        const next = Object.assign({}, surfaceStates);
        next[name] = state;
        surfaceStates = next;
    }

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

        // an id no panel answers to opens nothing (it made an empty card, which the next panel then grew out of)
        function panel(id: string): string {
            if (!PanelCatalog.byId(id))
                return "unknown panel: " + id;
            PanelRouter.toggle(id, root.focusedScreen(), null);
            return "ok";
        }
        // a panel shown beside Settings while its settings change (no catcher, no keys); again to hide it
        function previewPanel(id: string): void {
            PanelRouter.preview(id, root.focusedScreen());
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
        // diagnostics: the launcher's own search for each prefix of a query, as typed — ms per keystroke (median of 9)
        function benchSearch(query: string): string {
            const out = [];
            for (let n = 1; n <= query.length; n++) {
                const q = query.slice(0, n), t = [];
                for (let i = 0; i < 9; i++) {
                    const t0 = Date.now();
                    Launcher.search(q, 60, "");
                    t.push(Date.now() - t0);
                }
                t.sort((x, y) => x - y);
                out.push(q + " " + t[4]);
            }
            const t0 = Date.now();
            Launcher.search("", 100000, "");
            return out.join(", ") + " | browse(all) " + (Date.now() - t0);
        }
        // what the launcher would list for a query, best first
        function apps(query: string): string {
            return Apps.search(query, 8).map(e => e.name + "  [" + e.id + "]").join("\n");
        }
        // every notification from one app gone from the history (as the centre's "clear this app")
        function notificationsClearApp(app: string): string {
            const before = Notifications.history.length;
            Notifications.removeApp(app);
            return String(before - Notifications.history.length);
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
        // the surface style (glass | solid | blur) and its strength (subtle | balanced | strong)
        function surface(style: string): string {
            Material.setStyle(style);
            return Material.style;
        }
        function surfaceStrength(level: string): string {
            const v = Material.levels[level];
            if (v === undefined)
                return "subtle | balanced | strong";
            if (Material.style === "blur")
                Material.setBlurStrength(v);
            else
                Material.setGlassStrength(v);
            return level;
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
        // diagnostics: each component of a bar ("<bar id>@<output>") and where it is on the screen, for driving the
        // real pointer to it (testing): [{ name, type, x, y, w, h }]
        function barWidgets(key: string): string {
            const scene = PanelRouter.barItems[key];
            const at = PanelRouter.bars[key]?.win;
            if (!scene || !at)
                return "[]";
            const out = [];
            const walk = item => {
                for (const c of item.children) {
                    if (c.ownerKey !== undefined && c.type !== undefined && c.visible && c.width > 0) {
                        const p = c.mapToItem(scene, 0, 0);
                        out.push({ name: c.name, type: c.type, x: Math.round(at[0] + p.x), y: Math.round(at[1] + p.y), w: Math.round(c.width), h: Math.round(c.height) });
                    }
                    walk(c);
                }
            };
            walk(scene);
            return JSON.stringify(out);
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
        // the open launcher's state, for tests: { text, current, shown, rows, height }
        function launcherState(): string {
            const page = PanelRouter.livePages[root.focusedScreen()] ?? null;
            if (!page || page.results === undefined)
                return "no launcher";
            return JSON.stringify({ text: page.text, current: page.current, shown: page.shown.length, rows: page.rows, height: page.implicitHeight });
        }
        // a key, by name (down up left right tab backtab enter escape), to the open panel's page as its own key
        // handler takes it: the keyboard through a page on a desktop that takes no injected keys (test harness)
        function panelKey(name: string): string {
            const page = PanelRouter.livePages[root.focusedScreen()] ?? null;
            if (!page || typeof page.handleKey !== "function")
                return "no keyboard here";
            return page.handleKey(name) ? "ok" : "not taken";
        }
        function panelRect(): string {
            const r = PanelRouter.rects[root.focusedScreen()] ?? null;
            return JSON.stringify(r ? Object.assign({ window: PanelRouter.windowSizes[root.focusedScreen()] ?? null }, r) : null);
        }
        function osd(kind: string): string {
            root.osdProbe(kind);
            return "ok";
        }
        function surfaceState(name: string): string {
            return JSON.stringify(root.surfaceStates[name] ?? null);
        }
        // the durations the motion style and speed resolve to (what a style change does, which no capture shows)
        function motion(): string {
            return JSON.stringify({ style: Motion.style, spatialFast: Motion.spatialFast, spatial: Motion.spatial, spatialSlow: Motion.spatialSlow, effects: Motion.effects, enter: Motion.enter, exit: Motion.exit });
        }
        function stats(): string {
            return JSON.stringify(Diagnostics.summary());
        }
        // frame phases of the panel window and marks, recorded for ms (bounded), then read once
        function frameArm(ms: int): void {
            FrameProbe.arm(ms);
        }
        // read out in pieces: one reply of the whole recording is too large for the IPC socket
        function frameDump(): int {
            root.frameRecording = FrameProbe.dump();
            return root.frameRecording.length;
        }
        function frameChunk(i: int): string {
            const piece = root.frameRecording.substr(i * 65536, 65536);
            // the last piece read: the recording is not kept
            if ((i + 1) * 65536 >= root.frameRecording.length)
                root.frameRecording = "";
            return piece;
        }
        function resetStats(): void {
            Diagnostics.reset();
        }
        function status(): string {
            return JSON.stringify({
                material: { style: Material.style, glassStrength: Material.glassStrength, blurStrength: Material.blurStrength, blur: Material.blur, blurAvailable: Material.blurAvailable, fillAlpha: Number(Material.fillAlpha.toFixed(3)), shadows: Material.shadows, paused: Material.paused },
                efficiency: ExperiencePolicy.efficiency,
                // how many on-screen things ask the shared clock for seconds (0: it ticks once a minute)
                secondsDemand: Time.secondsDemand,
                level: ExperiencePolicy.level,
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
                scheme: { image: Scheme.image, primary: String(Scheme.target.primary ?? ""), blend: Number(Scheme.blend.toFixed(2)), wallpaper: Wallpapers.current },
                core: { known: Core.known, clipboardEntries: Clipboard.entries.length, wallpaperMode: Wallpapers.mode, liveItems: Object.keys(Wallpapers.liveItems).length, staticKnown: Wallpapers.current !== "" },
                notifications: { serving: Notifications.serving, wanted: Notifications.wanted, history: Notifications.history.length, popups: Notifications.popups.length, dnd: Notifications.dnd },
                windowBehaviour: { value: Config.window.behaviour, included: WindowBehaviour.included, error: WindowBehaviour.status },
                launchTime: Quickshell.launchTime
            });
        }
    }
}
