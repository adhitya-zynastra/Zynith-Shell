import QtQuick
import Zynith.Native
import qs.Services

// Keeps a demand-counted service awake while `when` holds, and lets go when it stops or this goes away.
// service: weather · system · screen_time · backlight · network
QtObject {
    id: root

    property string service: ""
    property bool when: true
    property bool held: false

    function take(on: bool): void {
        const s = service;
        if (s === "weather")
            on ? Weather.retain() : Weather.release();
        else if (s === "system")
            on ? System.retain() : System.release();
        else if (s === "screen_time")
            on ? ScreenTime.retain() : ScreenTime.release();
        else if (s === "backlight")
            on ? Backlight.retain() : Backlight.release();
        else if (s === "network")
            on ? Network.retain() : Network.release();
    }
    function sync(): void {
        const want = when && service !== "";
        if (want !== held) {
            take(want);
            held = want;
        }
    }
    onWhenChanged: sync()
    Component.onCompleted: sync()
    Component.onDestruction: if (held)
        take(false)
}
