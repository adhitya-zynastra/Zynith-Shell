import QtQuick
import Quickshell
import qs.Common
import qs.Components
import qs.Services

// Words of your choosing.
BarItem {
    id: root
    shown: (opt("text") ?? "") !== ""
    BarText {
        item: root
        text: root.opt("text") ?? ""
    }
}
