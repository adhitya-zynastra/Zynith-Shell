pragma Singleton

import QtQuick
import Quickshell
import Quickshell.Io
import Zynith.Native
import qs.Common

// Zynith's configuration: one TOML file per domain in ~/.config/zynith. Each file holds only what differs from
// the defaults below; edits on disk apply live, and every write from the UI goes through here.
Singleton {
    id: root

    readonly property bool loaded: experienceFile.loaded && barsFile.loaded && panelsFile.loaded && appearanceFile.loaded
        && animationFile.loaded && notificationsFile.loaded && wallpaperFile.loaded && windowFile.loaded
        && zynithFile.loaded

    // ── the shapes the rest of the UI reads ─────────────────────────────────
    readonly property var experience: ({
            profile: experienceFile.values.profile,
            adaptive: experienceFile.values.adaptive,
            overrides: experienceFile.values.overrides ?? {},
            reducedMotion: animationFile.values.reduced_motion
        })
    readonly property var appearance: appearanceFile.values
    readonly property var animation: animationFile.values
    readonly property var bars: barsFile.values.bar ?? []
    // named bar widgets ([widget.<name>] in bars.toml: type, settings, [widget.<name>.actions]) and capsule
    // groups ([[group]]: id, members, fill, opacity, padding, spacing, accordion, direction)
    readonly property var barWidgets: barsFile.values.widget ?? ({})
    readonly property var barGroups: barsFile.values.group ?? []
    // a bar list entry → what to draw: { name, type, settings, actions }
    function resolveBarWidget(name: string): var {
        const table = barWidgets[name] ?? {};
        const settings = Object.assign({}, table);
        delete settings.type;
        delete settings.actions;
        return {
            name: name,
            type: table.type ?? name,
            settings: settings,
            actions: table.actions ?? {}
        };
    }
    function setBarWidget(name: string, table: var): void {
        const all = Object.assign({}, barWidgets);
        all[name] = table;
        barsFile.set("widget", all);
    }
    function setBarGroups(list: var): void {
        barsFile.set("group", list);
    }
    readonly property var panels: panelsFile.values.panels
    readonly property var launcher: panelsFile.values.launcher
    readonly property var controlPanel: panelsFile.values.control_panel
    readonly property var osd: ({
            enabled: panelsFile.values.osd.enabled,
            durationMs: panelsFile.values.osd.duration_ms,
            margin: panelsFile.values.osd.margin,
            position: panelsFile.values.osd.position,
            hidden: panelsFile.values.osd.hidden ?? []
        })
    readonly property var notifications: ({
            server: notificationsFile.values.server,
            dnd: notificationsFile.values.dnd,
            popupMs: notificationsFile.values.popup_ms,
            maxPopups: notificationsFile.values.max_popups,
            historySize: notificationsFile.values.history_size,
            location: notificationsFile.values.location,
            density: notificationsFile.values.density,
            grouping: notificationsFile.values.grouping,
            lockRedaction: notificationsFile.values.lock_redaction,
            sound: notificationsFile.values.sound,
            soundVolume: notificationsFile.values.sound_volume,
            historyPersist: notificationsFile.values.history_persist,
            retentionHours: notificationsFile.values.history_retention_hours,
            showAppName: notificationsFile.values.show_app_name,
            showActions: notificationsFile.values.show_actions,
            monitor: notificationsFile.values.monitor,
            filters: notificationsFile.values.filter ?? []
        })
    readonly property var wallpaper: wallpaperFile.values
    readonly property var widgets: widgetsFile.values.widget ?? []
    readonly property var window: windowFile.values
    // which visible surfaces this UI draws instead of the native shell (the shell reads the same file)
    readonly property var surfaces: zynithFile.values.surfaces

    // ── writers ─────────────────────────────────────────────────────────────
    function setExperienceProfile(name: string): void {
        if (experienceFile.values.profile !== name)
            experienceFile.set("profile", name);
    }
    function setAdaptive(on: bool): void {
        experienceFile.set("adaptive", on);
    }
    function setReducedMotion(on: bool): void {
        animationFile.set("reduced_motion", on);
    }
    function setNotificationsDnd(on: bool): void {
        notificationsFile.set("dnd", on);
    }
    function setWindowBehaviour(behaviour: string): void {
        windowFile.set("behaviour", behaviour);
    }
    // one field of one bar; the list is written back whole
    function updateBar(index: int, key: string, value: var): void {
        const list = bars.slice();
        if (index < 0 || index >= list.length)
            return;
        list[index] = Object.assign({}, list[index], {
            [key]: value
        });
        barsFile.set("bar", list);
    }
    function setBars(list: var): void {
        barsFile.set("bar", list);
    }
    // one key of one bar back to its default
    function clearBarKey(index: int, key: string): void {
        const list = bars.slice();
        if (index < 0 || index >= list.length)
            return;
        const b = Object.assign({}, list[index]);
        delete b[key];
        list[index] = b;
        barsFile.set("bar", list);
    }
    function setBarWidgetKey(name: string, key: string, value: var): void {
        const table = Object.assign({}, barWidgets[name] ?? {});
        if (value === undefined)
            delete table[key];
        else
            table[key] = value;
        setBarWidget(name, table);
    }
    function setBarWidgetAction(name: string, gesture: string, action: var): void {
        const table = Object.assign({}, barWidgets[name] ?? {});
        const actions = Object.assign({}, table.actions ?? {});
        if (action === undefined)
            delete actions[gesture];
        else
            actions[gesture] = action;
        table.actions = actions;
        setBarWidget(name, table);
    }
    function setWidgets(list: var): void {
        widgetsFile.set("widget", list);
    }
    // generic: Config.write("appearance", "glass.opacity", 0.8)
    function write(domain: string, key: string, value: var): void {
        const file = files[domain];
        if (file)
            file.set(key, value);
    }
    function reset(domain: string, key: string): void {
        const file = files[domain];
        if (file)
            file.reset(key);
    }
    readonly property var files: ({
            experience: experienceFile,
            appearance: appearanceFile,
            animation: animationFile,
            bars: barsFile,
            panels: panelsFile,
            notifications: notificationsFile,
            wallpaper: wallpaperFile,
            window: windowFile,
            widgets: widgetsFile,
            zynith: zynithFile
        })

    // ── files and defaults ──────────────────────────────────────────────────
    ConfigFile {
        id: zynithFile
        path: Paths.config + "/zynith.toml"
        header: "Zynith. Which visible surfaces the Zynith UI draws (\"zynith\") and which the native shell still does\n(\"native\"). The native shell reads [surfaces] when it starts."
        defaults: ({
                surfaces: {
                    bar: "native",
                    launcher: "native",
                    notifications: "native",
                    osd: "native",
                    control_center: "native",
                    desktop_widgets: "native"
                }
            })
    }

    ConfigFile {
        id: experienceFile
        path: Paths.config + "/experience.toml"
        header: "Experience profile: auto (hardware recommendation, easing off on battery) or performance | balanced |\nenhanced | max. [overrides] changes single knobs, e.g. blurQuality = \"off\"."
        defaults: ({
                profile: "auto",
                adaptive: true,
                overrides: {}
            })
    }

    ConfigFile {
        id: appearanceFile
        path: Paths.config + "/appearance.toml"
        header: "Appearance. Surfaces follow the wallpaper palette; these adjust how."
        defaults: ({
                // 0 = the Experience profile decides; otherwise 0.4 – 1.0
                surface_opacity: 0,
                // profile | on | off
                blur: "profile",
                // none | subtle | defined
                border: "subtle",
                // multiplies every corner radius
                radius: 1.0,
                // standard | high
                contrast: "standard",
                // wallpaper, or a fixed colour such as "#b4c5ff"
                accent: "wallpaper",
                // how much of the wallpaper's colour tints surfaces, 0 – 1
                tint: 0.35,
                // multiplies every text size
                font_scale: 1.0
            })
    }

    ConfigFile {
        id: animationFile
        path: Paths.config + "/animation.toml"
        header: "Animation. speed multiplies every duration (0.5 = twice as fast); style picks the easing family."
        defaults: ({
                speed: 1.0,
                // fluid | crisp | calm
                style: "fluid",
                reduced_motion: false
            })
    }

    ConfigFile {
        id: barsFile
        path: Paths.config + "/bars.toml"
        header: "Bars. Each [[bar]] is one bar: edge top | bottom | left | right, anchor start | center | end | fill,\noffset/margin/thickness/length in px (length 0 = fit the widgets), widgets per section.\nStyle keys left out follow appearance.toml."
        defaults: ({
                bar: [
                    {
                        id: "main",
                        edge: "top",
                        anchor: "fill",
                        offset: 0,
                        margin: 6,
                        thickness: 34,
                        length: 0,
                        reserve: true,
                        layer: "top",
                        visibility: "always",
                        screens: ["*"],
                        widgets: {
                            start: ["workspaces", "media"],
                            center: ["clock"],
                            end: ["visualizer", "audio", "network", "battery", "quick"]
                        }
                    }
                ]
            })
    }

    ConfigFile {
        id: panelsFile
        path: Paths.config + "/panels.toml"
        header: "Panels: the launcher, the Control Panel and the OSD."
        defaults: ({
                panels: {
                    width: 400
                },
                launcher: {
                    // command prefix for apps that run in a terminal; empty: $TERMINAL -e, else kitty
                    terminal: [],
                    width: 600,
                    rows: 8,
                    // center | top
                    position: "center",
                    // comfortable | compact
                    density: "comfortable",
                    // list | grid (apps as an icon grid when nothing is typed)
                    layout: "list",
                    // category chips under the search line
                    categories: true,
                    // an app's actions (New Window, Private Window…) under it, and in search
                    actions: true,
                    // copied results (calculator, emoji) are pasted into the window beneath
                    auto_paste: true
                },
                control_panel: {
                    modules: ["header", "levels", "connectivity", "toggles", "media", "power", "system"],
                    width: 420
                },
                osd: {
                    enabled: false,
                    duration_ms: 1400,
                    margin: 72,
                    // bottom | top
                    position: "bottom",
                    // kinds never shown: volume microphone brightness keyboard-layout wifi bluetooth
                    // power-profile caffeine nightlight dnd lock-keys media privacy keyboard-backlight
                    hidden: []
                }
            })
    }

    ConfigFile {
        id: notificationsFile
        path: Paths.config + "/notifications.toml"
        header: "Notifications. The server runs only when this UI owns notifications (zynith.toml [surfaces])\nor `server = true`, and never takes the bus name from another process. max_popups show at once;\nthe rest wait their turn."
        defaults: ({
                server: false,
                dnd: false,
                popup_ms: 6000,
                max_popups: 4,
                // kept in memory only
                history_size: 100,
                // top-right | top-left | top-center | bottom-right | bottom-left | bottom-center
                location: "top-right",
                // comfortable | compact
                density: "comfortable",
                grouping: true,
                // hide notification text on the lock screen
                lock_redaction: true,
                sound: true,
                sound_volume: 0.6,
                // keep the history across restarts (~/.local/state/zynith/notifications.json, mode 0600)
                history_persist: true,
                // drop history older than this many hours (0 = only history_size limits it)
                history_retention_hours: 0,
                show_app_name: true,
                show_actions: true,
                // which screen popups use: focused, or an output name
                monitor: "focused",
                // per-app rules, as the native shell had them. Each [[filter]]: match (app name, desktop entry
                // or category, case-insensitive substring), match_content (a regex on summary/body),
                // show_popup, save_history, play_sound, bypass_dnd, timeout_ms, urgencies (low normal critical)
                filter: []
            })
    }

    ConfigFile {
        id: wallpaperFile
        path: Paths.config + "/wallpaper.toml"
        header: "Wallpaper. The native shell keeps the one WallpaperState; this file is about how the UI shows it."
        defaults: ({
                // where the Wallpaper panel looks for images ("" = ~/Pictures/wallpapers)
                directory: "",
                // carousel: a cinematic band over the dimmed desktop · grid: a panel with a hero and a grid
                layout: "carousel",
                // the focused carousel card's width in px (0 = 40 % of the screen, at most 760)
                card_width: 0,
                // live: the running live wallpaper behind niri's overview; poster: its still image
                overview: "poster",
                lock: "poster"
            })
    }

    ConfigFile {
        id: widgetsFile
        path: Paths.config + "/widgets.toml"
        header: "Desktop widgets. Each [[widget]]: type (clock label sticker audio_visualizer weather media_player calendar\nsysmon volume session_actions button), output, the centre (cx, cy) and box (width, height) in the reference\nresolution, rotation in radians, flip, hidden, settings. Edit them on the desktop: Mod+Alt+W."
        defaults: ({
                widget: []
            })
    }

    // the native shell's widget layout, read once to seed widgets.toml (never written: the Settings GUI owns it)
    ConfigFile {
        id: nativeLayout
        path: widgetsFile.loaded && !widgetsFile.exists ? Paths.home + "/.local/state/noctalia/settings.toml" : ""
        onLoadedChanged: {
            const dw = values.desktop_widgets;
            if (!loaded || !dw || widgetsFile.exists)
                return;
            const list = [];
            for (const id of dw.widget_order ?? []) {
                const w = (dw.widget ?? {})[id];
                if (!w)
                    continue;
                list.push({
                    id: id.replace("desktop-widget-", ""),
                    type: w.type,
                    output: w.output ?? "",
                    cx: w.cx ?? 0,
                    cy: w.cy ?? 0,
                    width: w.box_width ?? 0,
                    height: w.box_height ?? 0,
                    rotation: w.rotation ?? 0,
                    flip: w.flip_x ?? false,
                    reference: [w.placement_width ?? 1920, w.placement_height ?? 1080],
                    settings: w.settings ?? {}
                });
            }
            if (list.length > 0)
                widgetsFile.create({
                    widget: list
                });
        }
    }

    ConfigFile {
        id: windowFile
        path: Paths.config + "/window.toml"
        header: "Window behaviour: config (niri's layout block as written) | scrolling | tiling-like.\nWritten to ~/.config/niri/rice/layout.kdl after niri validates it."
        defaults: ({
                behaviour: "config"
            })
    }

    // one-time move from the Stage 1 shell.json: each file is created only if it does not exist yet
    FileView {
        path: Paths.config + "/shell.json"
        printErrors: false
        onLoaded: {
            let old;
            try {
                old = JSON.parse(text());
            } catch (e) {
                return;
            }
            if (old.bars)
                barsFile.create({
                    bar: old.bars
                });
            if (old.experience)
                experienceFile.create({
                    profile: old.experience.profile ?? "auto",
                    adaptive: old.experience.adaptive ?? true,
                    overrides: old.experience.overrides ?? {}
                });
            if (old.window)
                windowFile.create({
                    behaviour: old.window.behaviour ?? "config"
                });
        }
    }
}
