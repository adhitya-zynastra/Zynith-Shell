pragma Singleton

import Quickshell

Singleton {
    readonly property string home: Quickshell.env("HOME")
    readonly property string configHome: Quickshell.env("XDG_CONFIG_HOME") || home + "/.config"
    readonly property string stateHome: Quickshell.env("XDG_STATE_HOME") || home + "/.local/state"
    readonly property string cacheHome: Quickshell.env("XDG_CACHE_HOME") || home + "/.cache"

    // ZYNITH_CONFIG_DIR lets a test instance run on its own copy of shell.json
    readonly property string config: Quickshell.env("ZYNITH_CONFIG_DIR") || configHome + "/zynith"
    readonly property string state: stateHome + "/zynith"
    readonly property string cache: cacheHome + "/zynith"
    // per session, in memory (XDG_RUNTIME_DIR): transient state shared between the UI's processes
    readonly property string runtime: (Quickshell.env("XDG_RUNTIME_DIR") || "/tmp") + "/zynith"

    // the native shell, which holds the core services (clipboard history, wallpaper, lock) during migration.
    // zynith-ui says which one runs (ZYNITH_NATIVE): a user build in ~/.local/opt, or the installed /usr/bin/noctalia
    readonly property string core: Quickshell.env("ZYNITH_NATIVE") || home + "/.local/opt/noctalia/bin/noctalia"
    // UI sounds (notification, screenshot …): the user's own if zynith-ui found them, else the installed ones
    readonly property string sounds: Quickshell.env("ZYNITH_SOUNDS") || home + "/.local/share/zynith/sounds"

    // the UI's own script (start, settings, cmd), beside shell.qml
    readonly property string uiScript: Quickshell.shellPath("zynith-ui")

    // Quickshell serves QML from a virtual filesystem, so assets are addressed by real path.
    function asset(rel: string): string {
        return "file://" + Quickshell.shellPath("assets/" + rel);
    }

    function repoAsset(rel: string): string {
        return "file://" + Quickshell.shellPath("../assets/" + rel);
    }
}
