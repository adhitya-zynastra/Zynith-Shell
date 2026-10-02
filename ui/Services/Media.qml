pragma Singleton

import QtQuick
import Quickshell
import Quickshell.Services.Mpris

// The player that matters right now: the one playing, else the last one that played.
Singleton {
    id: root

    readonly property var players: Mpris.players.values
    property MprisPlayer last: null

    readonly property MprisPlayer active: {
        const list = players;
        const playing = list.find(p => p.isPlaying);
        if (playing)
            return playing;
        if (last && list.includes(last))
            return last;
        return list.find(p => p.trackTitle) ?? null;
    }
    onActiveChanged: if (active && active.isPlaying)
        last = active

    readonly property bool present: active !== null && (active.trackTitle || "") !== ""
    readonly property bool playing: active?.isPlaying ?? false
    readonly property string title: active?.trackTitle ?? ""
    readonly property string artist: active?.trackArtist ?? ""
    readonly property string art: active?.trackArtUrl ?? ""
    readonly property string app: active?.identity ?? ""

    function toggle(): void {
        if (active?.canTogglePlaying)
            active.togglePlaying();
    }
    function next(): void {
        if (active?.canGoNext)
            active.next();
    }
    function previous(): void {
        if (active?.canGoPrevious)
            active.previous();
    }
}
