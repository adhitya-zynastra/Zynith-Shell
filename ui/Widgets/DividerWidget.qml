import QtQuick
import qs.Common
import qs.Components

// A quiet point between groups.
BarItem {
    interactive: false
    pad: Metrics.s1

    Rectangle {
        width: 3
        height: 3
        radius: 1.5
        color: Theme.inkFaint
    }
}
