pragma Singleton

import QtQuick
import Quickshell
import Quickshell.Io
import Zynith.Native
import qs.Common
import "../Common/BarModel.js" as BarModel
import "../Common/MaterialModel.js" as MaterialModel

// Zynith's configuration: one TOML file per domain in ~/.config/zynith. Each file holds only what differs from
// the defaults below; edits on disk apply live, and every write from the UI goes through here.
Singleton {
    id: root

    readonly property bool loaded: experienceFile.loaded && barsFile.loaded && panelsFile.loaded && appearanceFile.loaded
        && animationFile.loaded && notificationsFile.loaded && wallpaperFile.loaded && windowFile.loaded
        && zynithFile.loaded

    // ── the shapes the rest of the UI reads ─────────────────────────────────
    // what the UI may spend (ExperiencePolicy): efficiency "auto" | "save", whether blur and shadows pause under
    // real power pressure, single-knob overrides; how surfaces look is appearance.toml's (Material)
    readonly property var experience: ({
            efficiency: experienceFile.values.efficiency ?? "auto",
            easeEffects: experienceFile.values.ease_effects ?? true,
            overrides: experienceFile.values.overrides ?? {},
            reducedMotion: animationFile.values.reduced_motion
        })
    function setEfficiency(name: string): void {
        experienceFile.set("efficiency", name);
    }
    function setEaseEffects(on: bool): void {
        experienceFile.set("ease_effects", on);
    }
    function setAppearance(key: string, value: var): void {
        if (appearanceFile.values[key] !== value)
            appearanceFile.set(key, value);
    }
    // Settings shows its technical pages and native settings for surfaces Zynith draws only with this on
    readonly property bool settingsAdvanced: zynithFile.values.settings?.advanced === true
    function setSettingsAdvanced(on: bool): void {
        zynithFile.set("settings.advanced", on);
    }
    readonly property var appearance: appearanceFile.values
    readonly property var animation: animationFile.values
    // the bars as drawn: bars.toml's list made safe (BarModel.validate: each a table with a unique id and a name;
    // a wrong kind of value falls back and is reported once, unknown keys are kept)
    readonly property var barCheck: BarModel.validate({
        bars: barsFile.values.bar ?? [],
        widgets: savedBarWidgets
    })
    // A setting being dragged in Settings, shown before it is written: { id, key, value } from the preview file
    // (BarEdits.preview), laid over that one bar. Only its release writes bars.toml; the overlay goes once the
    // written value has come back (or after a moment), so the bar never springs back to the old value between.
    readonly property var bars: barPreview && barPreview.id !== undefined ? barCheck.state.bars.map(b => b.id === barPreview.id ? Object.assign({}, b, {
                [barPreview.key]: barPreview.value
            }) : b) : barCheck.state.bars
    property var barPreview: null
    property var barPreviewEnded: null
    FileView {
        id: barPreviewFile
        path: Paths.runtime + "/bar-preview.json"
        watchChanges: true
        printErrors: false
        // what was there before this process started is someone else's finished drag: only changes count
        property bool primed: false
        onLoaded: {
            if (!primed) {
                primed = true;
                return;
            }
            let p = null;
            try {
                p = JSON.parse(text());
            } catch (e) {
                return;
            }
            if (p && p.ended) {
                root.barPreviewEnded = p.ended;
                root.settlePreview();
                previewSettle.restart();
            } else if (p && (p.id !== undefined || p.widget !== undefined) && p.key !== undefined) {
                previewSettle.stop();
                root.barPreviewEnded = null;
                root.barPreview = p.widget !== undefined ? { widget: p.widget, key: p.key, value: p.value } : { id: p.id, key: p.key, value: p.value };
            }
        }
        onLoadFailed: primed = true
        onFileChanged: reload()
    }
    // the drag ended: the overlay goes as soon as bars.toml carries the value (or was given up on)
    function settlePreview(): void {
        const e = barPreviewEnded;
        if (!e || !barPreview)
            return;
        const b = e.widget !== undefined ? savedBarWidgets[e.widget] : barCheck.state.bars.find(x => x.id === e.id);
        if (!b || JSON.stringify(b[e.key]) === JSON.stringify(e.value) || e.cancel) {
            barPreview = null;
            barPreviewEnded = null;
        }
    }
    Timer {
        id: previewSettle
        interval: 1500
        onTriggered: {
            root.barPreview = null;
            root.barPreviewEnded = null;
        }
    }
    onBarCheckChanged: {
        for (const p of barCheck.problems)
            console.warn("zynith: bars.toml:", p);
        settlePreview();
    }
    // the bars and their component instances, as BarModel edits them: the saved ones, never a preview (an edit, and
    // the undo step it records, must start from what is in the file)
    readonly property var barState: ({
            bars: barCheck.state.bars,
            widgets: savedBarWidgets
        })
    // a whole edit (bars and the component tables they name) in one atomic write
    function applyBars(state: var): bool {
        return barsFile.assign({
            bar: state.bars,
            widget: state.widgets
        });
    }
    // bars.toml could not be read: nothing is written over it until it is fixed or recovered
    readonly property string barsError: barsFile.error
    // moves the broken file aside (bars.toml.broken-<time>) and starts again from the default bar; returns where
    // the broken file went
    function recoverBars(): string {
        return barsFile.recover({
            schema: BarModel.schemaVersion
        });
    }
    // the user's own presets ([[preset]] in bars.toml)
    readonly property var barPresets: barsFile.values.preset ?? []
    function setBarPresets(list: var): bool {
        return barsFile.assign({
            preset: list
        });
    }
    // named bar widgets ([widget.<name>] in bars.toml: type, settings, [widget.<name>.actions]) and capsule
    // groups ([[group]]: id, members, fill, opacity, padding, spacing, accordion, direction)
    readonly property var savedBarWidgets: barsFile.values.widget ?? ({})
    // a component setting being dragged, laid over its instance (as barPreview for a bar)
    readonly property var barWidgets: barPreview && barPreview.widget !== undefined ? Object.assign({}, savedBarWidgets, {
            [barPreview.widget]: Object.assign({}, savedBarWidgets[barPreview.widget] ?? {}, {
                [barPreview.key]: barPreview.value
            })
        }) : savedBarWidgets
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
        const all = Object.assign({}, savedBarWidgets);
        all[name] = table;
        barsFile.set("widget", all);
    }
    function setBarGroups(list: var): void {
        barsFile.set("group", list);
    }
    readonly property var panels: panelsFile.values.panels
    readonly property var launcher: panelsFile.values.launcher
    readonly property var controlPanel: panelsFile.values.control_panel
    readonly property var media: panelsFile.values.media
    readonly property var osd: ({
            enabled: panelsFile.values.osd.enabled,
            durationMs: panelsFile.values.osd.duration_ms,
            margin: panelsFile.values.osd.margin,
            position: panelsFile.values.osd.position,
            // left | center | right, and how far from that side
            align: panelsFile.values.osd.align ?? "center",
            sideMargin: panelsFile.values.osd.side_margin ?? 20,
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
            // the native offset_x / offset_y, layer, keep_dismissed_in_history
            marginX: notificationsFile.values.margin_x ?? 10,
            marginY: notificationsFile.values.margin_y ?? 6,
            layer: notificationsFile.values.layer ?? "overlay",
            keepDismissed: notificationsFile.values.keep_dismissed ?? true,
            filters: notificationsFile.values.filter ?? []
        })
    readonly property var wallpaper: wallpaperFile.values
    readonly property var widgets: widgetsFile.values.widget ?? []
    readonly property var window: windowFile.values
    // which visible surfaces this UI draws instead of the native shell (the shell reads the same file)
    readonly property var surfaces: zynithFile.values.surfaces
    // how Zynith shows its user: a name and a picture of Zynith's own (zynith.toml [profile]), apart from the
    // OS account and its authentication; empty keeps the account's
    readonly property var profile: zynithFile.values.profile ?? ({})
    function setProfile(key: string, value: string): void {
        const v = String(value ?? "").trim();
        if (v === "")
            zynithFile.reset("profile." + key);
        else
            zynithFile.set("profile." + key, v);
    }

    // ── writers ─────────────────────────────────────────────────────────────
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
        const table = Object.assign({}, savedBarWidgets[name] ?? {});
        if (value === undefined)
            delete table[key];
        else
            table[key] = value;
        setBarWidget(name, table);
    }
    function setBarWidgetAction(name: string, gesture: string, action: var): void {
        const table = Object.assign({}, savedBarWidgets[name] ?? {});
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

    // ── changes made by hand (Settings), so the last can be taken back ──
    function lookup(map: var, key: string): var {
        let node = map;
        for (const part of key.split("."))
            node = node === undefined || node === null ? undefined : node[part];
        return node;
    }
    function valueAt(domain: string, key: string): var {
        return lookup(files[domain]?.values, key);
    }
    function defaultAt(domain: string, key: string): var {
        return lookup(files[domain]?.defaults, key);
    }
    function same(a: var, b: var): bool {
        return JSON.stringify(a) === JSON.stringify(b);
    }
    // the changes, newest last: { domain, key, before, label, at }. A run of changes to one setting (a slider
    // being dragged) is one change: it keeps the value from before the run.
    property var history: []
    signal changed(string label)
    function change(domain: string, key: string, value: var, label: string): void {
        const before = valueAt(domain, key);
        if (value !== undefined && same(before, value))
            return;
        const last = history.length > 0 ? history[history.length - 1] : null;
        const now = Date.now();
        if (last && last.domain === domain && last.key === key && now - last.at < 1500) {
            const h = history.slice(0, -1);
            h.push(Object.assign({}, last, { at: now }));
            history = h;
        } else {
            // `present`: whether the file itself set it (then undo writes it back; else it removes the key again).
            // A plugin from before has() (a shell not restarted since) writes the old value back instead.
            history = history.concat([{ domain: domain, key: key, before: before, present: typeof files[domain]?.has === "function" ? files[domain].has(key) : true, label: label, at: now }]).slice(-30);
        }
        // undefined: back to the default (the key leaves the file)
        if (value === undefined)
            reset(domain, key);
        else
            write(domain, key, value);
        changed(label);
    }
    // put the last change back: the file ends as it was before it
    function undo(): string {
        if (history.length === 0)
            return "";
        const last = history[history.length - 1];
        history = history.slice(0, -1);
        if (last.present)
            write(last.domain, last.key, last.before);
        else
            reset(last.domain, last.key);
        return last.label;
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
                    desktop_widgets: "native",
                    wallpaper: "native",
                    clipboard: "native",
                    session: "native"
                }
            })
    }

    ConfigFile {
        id: experienceFile
        path: Paths.config + "/experience.toml"
        header: "What the UI may spend. efficiency: auto (follow power: less on battery, least with power saver) | save\n(spend little even when plugged in). ease_effects: pause blur and shadows while power saver is on or the\nbattery is low. [overrides] sets single knobs, e.g. visualizerBands = 64. How surfaces look is appearance.toml."
        defaults: ({
                efficiency: "auto",
                ease_effects: true,
                overrides: {}
            })
    }

    ConfigFile {
        id: appearanceFile
        path: Paths.config + "/appearance.toml"
        header: "Appearance. Surfaces follow the wallpaper palette; these adjust how."
        defaults: ({
                // what every surface is made of: glass (clear, tinted) | solid (opaque) | blur (frosted, niri blurs)
                surface_style: "glass",
                // 0 – 1: subtle 0.15, balanced 0.5, strong 0.85 (each style keeps its own)
                glass_strength: 0.5,
                blur_strength: 0.5,
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
                // the media module (the dashboard's and its page)
                media: {
                    // the words of the song from lrclib.net, asked only while lyrics are on screen (sends the
                    // artist, title, album and length); false never asks
                    lyrics: true,
                    // lrclib | none
                    lyrics_provider: "lrclib",
                    // lines of lyrics on the dashboard (the page shows the whole sheet, in a column this share wide)
                    lyrics_lines: 2,
                    lyrics_column: 0.36,
                    // the spectrum: ring (around the record) | bars (a strip under the controls) | both | and
                    // how far the ring reaches (px), how many bars, how tall, their second colour
                    visualizer: true,
                    visualizer_style: "both",
                    visualizer_reach: 18,
                    bars: 32,
                    bars_height: 26,
                    bars_color_2: "tertiary",
                    // the record turns while it plays
                    spin: true,
                    // seconds per turn
                    spin_seconds: 24,
                    // the record's size on the dashboard and on the page
                    art_size: 104,
                    page_art_size: 180,
                    // the art's colour washes the module's plate
                    art_tint: true,
                    // chips to pick among players when more than one is open
                    player_chips: true
                },
                panels: {
                    width: 400,
                    // a panel opened from a bar joins it: one surface in the bar's fill, growing out of its edge, with
                    // concave fillets where their outlines meet (false: panels float beside the bar)
                    attach: true,
                    // how a panel changes into another (another icon's, a tab, a page): morph (the card glides
                    // and resizes, contents cross-fade) | fade (contents cross-fade in place) | none
                    switch: "morph",
                    // liquid (a slight overshoot) | emphasized | smooth | style (the animation style's)
                    morph_curve: "liquid",
                    // the glide's length in ms; 0 follows the animation speed
                    morph_ms: 0,
                    // how far the outgoing and incoming contents shrink while they cross (1 = not at all)
                    content_scale: 0.94,
                    // the list panels (Wi‑Fi, Bluetooth): wide, their rows in columns
                    list_width: 440,
                    list_columns: 1,
                    // audio devices shown before their list scrolls
                    device_rows: 6,
                    // the session menu: orbs (round glyphs over the dimmed desktop, as the native modal menu) | card
                    session_style: "orbs",
                    session_actions: ["lock", "suspend", "logout", "reboot", "shutdown"]
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
                    // which sections show and where: `columns`, each a list of sections top to bottom (left out = the
                    // adaptive arrangement, Common/SectionLayout.js adaptive(): it leads with the player while something
                    // plays, else with the quick controls; the catalogue of sections is ControlSections.entries).
                    // dashboard (the columns side by side, wide and short) | column (the same sections, one tall column)
                    layout: "dashboard",
                    // where it opens: auto (beside the bar that opened it; by a key, beside anchor_bar, else the work
                    // area's top right) | follow (always beside what opened it last on that output) | top-left |
                    // top-center | top-right | middle-left | center | middle-right | bottom-left | bottom-center |
                    // bottom-right (that spot of the output's work area: the screen less the bars' reserved room)
                    position: "auto",
                    // the gap to the work area's edges when placed at a spot
                    position_margin: 12,
                    // the hero: the wallpaper across the top with you on it; hero_pages all (over every tab) |
                    // dashboard; its height, the picture's size, the shade under the type (0 – 1), and which
                    // pieces show
                    hero: true,
                    hero_pages: "all",
                    // card (an inset, rounded wallpaper card, clear but under the type) | band (full-bleed)
                    hero_style: "card",
                    hero_height: 150,
                    hero_avatar_size: 64,
                    hero_shade: 0.7,
                    hero_clock: true,
                    hero_weather: true,
                    hero_details: true,
                    hero_drift: true,
                    // the hero on a panel opened by hovering a bar icon (a quick look) too
                    hero_on_peek: false,
                    // the dashboard: its width and a weight per column of a written arrangement (1 each when left
                    // out; the adaptive arrangement has its own)
                    dashboard_width: 1080,
                    column_widths: [1.6, 1, 1],
                    // a row of tabs over the Control Panel and its pages; which, in order (control media audio
                    // power monitor calendar weather screen-time system network bluetooth notifications), and
                    // tab_labels / tab_icons to rename or re-icon one: { audio = "Sound" }
                    tab_bar: true,
                    // connected (the current tab is the page's sheet reaching up into the strip, stretching across on a
                    // switch) | inline (icon beside label, a sliding pill) | stacked (icon over label, an underline)
                    tab_style: "connected",
                    tabs: ["control", "media", "audio", "power", "weather", "calendar"],
                    tab_labels: {},
                    tab_icons: {},
                    // a tab's page: its width (0 = the dashboard's) and how many columns its module flows into
                    tab_page_width: 0,
                    page_columns: 2,
                    tab_icons_shown: true,
                    tab_labels_shown: true,
                    // (retired: `modules`, the column layout's own list; read as its columns until Settings first
                    // arranges the sections, which backs panels.toml up and moves it into `columns`)
                    width: 420,
                    // the bar (its id) a Control Panel opened by a key sits by; "" is the top right corner
                    anchor_bar: "",
                    // gap between modules
                    spacing: 16,
                    // auto (cards on the dashboard, plain in a column) | plain | cards (each module on its own
                    // soft card)
                    module_style: "auto",
                    // indexed heads over the modules: auto (in a column, not on the dashboard's cards) | true | false
                    section_heads: "auto",
                    // the session button in the header (the native Control Center's)
                    session_button: true,
                    // shortcut tiles, in order (ControlShortcuts holds the catalogue; custom:<name> are yours)
                    shortcuts: ["wifi", "bluetooth", "caffeine", "nightlight", "notification", "power_profile"],
                    // compact (round buttons) | regular (two-line tiles) | wide (one per row)
                    shortcut_size: "regular",
                    // the same on the dashboard (its columns are narrow)
                    dashboard_shortcut_size: "compact",
                    // tiles per row; 0 picks by size (compact 4, regular 2, wide 1)
                    shortcut_columns: 0,
                    shortcut_labels: true,
                    // a regular tile that spans the whole row: { wifi = "wide" }
                    tile_sizes: {},
                    // [control_panel.custom.<name>] icon, label, action, detail — a tile of your own
                    custom: {},
                    // the sliders in Levels, in order
                    levels: ["volume", "mic", "brightness"],
                    // apps shown in the Audio module's mixer (all in its own page)
                    mixer_apps: 3,
                    calendar_week_numbers: false,
                    calendar_events: true,
                    // monday | sunday
                    week_start: "monday",
                    // daily | hourly
                    weather_forecast: "daily",
                    // 1 | 3 | 14 days
                    screen_time_range: 1
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
        path: widgetsFile.loaded && !widgetsFile.exists ? Paths.home + "/.local/state/zynith-shell/settings.toml" : ""
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

    // bars.toml's schema, brought up to date once: a copy of the file as it was first (bars.toml.pre-schema-<n>),
    // then the migrated bars in one write. Only a file that exists and parses, and never while the session is
    // locked (a write to watched config while locked once took the shell down).
    Connections {
        target: barsFile
        function onValuesChanged(): void {
            root.migrateBars();
        }
        function onLoadedChanged(): void {
            root.migrateBars();
        }
    }
    // The four Experience Profiles decided appearance and spending together; now appearance.toml holds the surface
    // style and experience.toml only what to spend. Once: copies of both files first (*.pre-materials), then the
    // new keys and the old ones gone, so nothing old can override the style later. Never while locked.
    Connections {
        target: appearanceFile
        function onLoadedChanged(): void {
            root.migrateMaterials();
        }
    }
    Connections {
        target: experienceFile
        function onLoadedChanged(): void {
            root.migrateMaterials();
        }
    }
    function migrateMaterials(): void {
        if (!appearanceFile.loaded || !experienceFile.loaded || appearanceFile.error !== "" || experienceFile.error !== "" || Events.locked)
            return;
        // the old keys have no defaults any more: present means the file holds them, and a migration is due
        const oldBlur = appearanceFile.get("blur");
        const oldOpacity = appearanceFile.get("surface_opacity");
        const oldProfile = experienceFile.get("profile");
        if (oldBlur === undefined && oldOpacity === undefined && oldProfile === undefined)
            return;
        const m = MaterialModel.migrate({
            blur: oldBlur ?? "profile",
            surface_opacity: oldOpacity ?? 0
        }, {
            profile: oldProfile
        }, nativeBlurStrength >= 0 ? nativeBlurStrength : undefined);
        if (!m)
            return;
        if (appearanceFile.exists && appearanceFile.backup("pre-materials") === "")
            return;
        if (experienceFile.exists && experienceFile.backup("pre-materials") === "")
            return;
        const aChanges = Object.assign({}, m.appearance.set);
        for (const k of m.appearance.remove)
            aChanges[k] = null;
        const xChanges = Object.assign({}, m.experience.set);
        for (const k of m.experience.remove)
            xChanges[k] = null;
        if (appearanceFile.assign(aChanges) && experienceFile.assign(xChanges))
            console.info("zynith: surfaces are now " + m.appearance.set.surface_style + ", efficiency " + m.experience.set.efficiency + " (from the Experience Profiles; copies in *.pre-materials)");
    }

    // the native shell's niri blur strength as it stands (read only: the native shell owns settings.toml)
    property int nativeBlurStrength: -1
    FileView {
        path: Paths.stateHome + "/zynith-shell/settings.toml"
        printErrors: false
        onLoaded: {
            const m = text().match(/\[shell\.glass\][^\[]*?blur_strength\s*=\s*(\d+)/);
            root.nativeBlurStrength = m ? parseInt(m[1]) : -1;
        }
    }

    function migrateBars(): void {
        if (!barsFile.loaded || !barsFile.exists || barsFile.error !== "" || Events.locked)
            return;
        const m = BarModel.migrate({
            schema: barsFile.values.schema,
            bar: barsFile.values.bar ?? [],
            widget: barsFile.values.widget ?? {}
        });
        if (!m.changed)
            return;
        // a migration never drops a bar: anything else means the bars were misread, and nothing is written
        const raw = BarModel.list(barsFile.values.bar);
        if (m.file.bar.length !== raw.length) {
            console.warn("zynith: bars.toml: migration would turn " + raw.length + " bars into " + m.file.bar.length + "; not migrating");
            return;
        }
        const copy = barsFile.backup("pre-schema-" + BarModel.schemaVersion);
        if (copy === "") {
            console.warn("zynith: bars.toml: no backup could be made; not migrating");
            return;
        }
        if (barsFile.assign({
                schema: m.file.schema,
                bar: m.file.bar
            }))
            console.info("zynith: bars.toml migrated (" + m.notes.join("; ") + "); the old file is " + copy);
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
