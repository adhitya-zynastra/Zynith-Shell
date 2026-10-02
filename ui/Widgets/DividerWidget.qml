import QtQuick
import qs.Common
import qs.Components
import qs.Services

// A quiet line between groups of widgets.
BarItem {
    id: root
    interactive: false
    pad: Metrics.s2
    Rectangle {
        width: root.vertical ? root.cross * 0.5 : 1
        height: root.vertical ? 1 : root.cross * 0.5
        color: Theme.alpha(root.ink, 0.18)
    }
}
