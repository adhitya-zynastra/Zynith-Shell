pragma Singleton

import Quickshell

Singleton {
    readonly property string home: Quickshell.env("HOME")
    readonly property string configHome: Quickshell.env("XDG_CONFIG_HOME") || home + "/.config"
    readonly property string stateHome: Quickshell.env("XDG_STATE_HOME") || home + "/.local/state"
    readonly property string cacheHome: Quickshell.env("XDG_CACHE_HOME") || home + "/.cache"

    readonly property string config: configHome + "/zynith"
    readonly property string state: stateHome + "/zynith"
    readonly property string cache: cacheHome + "/zynith"

    // Quickshell serves QML from a virtual filesystem, so assets are addressed by real path.
    function asset(rel: string): string {
        return "file://" + Quickshell.shellPath("assets/" + rel);
    }

    function repoAsset(rel: string): string {
        return "file://" + Quickshell.shellPath("../assets/" + rel);
    }
}
