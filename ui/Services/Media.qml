pragma Singleton

import QtQuick
import Quickshell
import Quickshell.Services.Mpris

// The player that matters right now: the one playing, else the last one that played.
Singleton {
    id: root

    readonly property var players: Mpris.players.values
    property MprisPlayer last: null

    // a player chosen by hand (the media module's player chips) wins while it is still there
    property MprisPlayer chosen: null
    function choose(p: var): void {
        chosen = p;
    }
    readonly property MprisPlayer active: {
        const list = players;
        if (chosen && list.includes(chosen))
            return chosen;
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
    readonly property string album: active?.trackAlbum ?? ""
    // seconds; MPRIS does not push position, so a view that shows it calls tick() while it is open
    readonly property real position: active?.position ?? 0
    readonly property real length: active?.length ?? 0
    // (Quickshell docs, MprisPlayer: position is writable only when canSeek and positionSupported)
    readonly property bool canSeek: (active?.canSeek ?? false) && (active?.positionSupported ?? false) && length > 0
    function tick(): void {
        if (active && active.isPlaying)
            active.positionChanged();
    }
    function seek(seconds: real): void {
        if (canSeek)
            active.position = Math.max(0, Math.min(length, seconds));
    }
    readonly property bool shuffle: active?.shuffle ?? false
    // shuffle and loopState are writable only with canControl as well
    readonly property bool canShuffle: (active?.shuffleSupported ?? false) && (active?.canControl ?? false)
    function toggleShuffle(): void {
        if (canShuffle)
            active.shuffle = !active.shuffle;
    }
    // none | track | playlist
    readonly property string loop: !active?.loopSupported ? "none" : active.loopState === MprisLoopState.Track ? "track" : active.loopState === MprisLoopState.Playlist ? "playlist" : "none"
    readonly property bool canLoop: (active?.loopSupported ?? false) && (active?.canControl ?? false)
    function cycleLoop(): void {
        if (!canLoop)
            return;
        active.loopState = active.loopState === MprisLoopState.None ? MprisLoopState.Playlist : active.loopState === MprisLoopState.Playlist ? MprisLoopState.Track : MprisLoopState.None;
    }
    function clock(s: real): string {
        if (!(s >= 0))
            return "0:00";
        const h = Math.floor(s / 3600), m = Math.floor(s % 3600 / 60), sec = String(Math.floor(s % 60)).padStart(2, "0");
        return h > 0 ? h + ":" + String(m).padStart(2, "0") + ":" + sec : m + ":" + sec;
    }

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
