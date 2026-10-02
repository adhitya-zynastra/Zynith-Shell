pragma Singleton

import QtQuick
import Quickshell

// One clock for every surface. Minute precision unless a consumer asks for seconds.
Singleton {
    id: root

    property int secondsDemand: 0
    readonly property date now: clock.date

    function retainSeconds(): void {
        secondsDemand++;
    }
    function releaseSeconds(): void {
        secondsDemand = Math.max(0, secondsDemand - 1);
    }

    SystemClock {
        id: clock
        precision: root.secondsDemand > 0 ? SystemClock.Seconds : SystemClock.Minutes
    }
}
