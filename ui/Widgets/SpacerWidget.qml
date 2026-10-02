import QtQuick
import Quickshell
import qs.Common
import qs.Components
import qs.Services

// Room between widgets.
BarItem {
    id: root
    interactive: false
    pad: 0
    Item {
        width: root.vertical ? 1 : root.opt("length") ?? 20
        height: root.vertical ? root.opt("length") ?? 20 : 1
    }
}
