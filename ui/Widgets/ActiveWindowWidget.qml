import QtQuick
import Quickshell
import qs.Common
import qs.Components
import qs.Services

// The focused window: its app icon and title (or one of the two), clipped and scrolling as asked.
BarItem {
    id: root
    readonly property var win: Workspaces.focusedWindow
    readonly property bool has: (win?.id ?? 0) !== 0 || (win?.title ?? "") !== ""
    readonly property string display: opt("display") ?? "icon_and_text"
    shown: has || opt("show_empty_label") === true
    spacing: Metrics.s2
    readonly property string iconSource: {
        const app = win?.appId ?? win?.app_id ?? "";
        const entry = app !== "" ? DesktopEntries.heuristicLookup(app) : null;
        return Quickshell.iconPath(entry?.icon ?? app, true);
    }
    Image {
        visible: root.display !== "text_only" && root.has && root.iconSource !== ""
        width: root.opt("icon_size") ?? 13
        height: width
        sourceSize.width: width * 2
        sourceSize.height: height * 2
        source: root.iconSource
        asynchronous: true
    }
    Item {
        id: viewport
        visible: root.display !== "icon_only" && !root.vertical
        readonly property real natural: label.implicitWidth
        width: Math.max(root.opt("min_length") ?? 80, Math.min(root.opt("max_length") ?? 260, natural))
        height: label.implicitHeight
        clip: true
        readonly property bool scrolls: natural > width && (root.opt("title_scroll") === "always" || root.opt("title_scroll") === "on_hover" && root.hovered)
        BarText {
            id: label
            item: root
            elide: viewport.scrolls ? Text.ElideNone : Text.ElideRight
            width: viewport.scrolls ? implicitWidth : viewport.width
            text: root.has ? (root.win.title || root.win.appId || "") : "Desktop"
            muted: !root.has
            NumberAnimation on x {
                running: viewport.scrolls
                loops: Animation.Infinite
                from: 0
                to: -(label.implicitWidth - viewport.width + 24)
                duration: Math.max(2000, (label.implicitWidth - viewport.width) * 40)
                easing.type: Easing.InOutSine
                onStopped: label.x = 0
            }
        }
    }
}
