import QtQuick
import Quickshell
import qs.Common
import qs.Components
import qs.Services

// Pick a wallpaper. Static images from the wallpaper folder, or live wallpapers from the collection; the
// desktop, overview, lock screen and palette all follow the choice. Thumbnails decode at the profile's size,
// and only the ones in view.
Column {
    id: root

    property var screen: null
    property real visibleProgress: 1
    property bool active: true
    readonly property int preferredWidth: 780

    property string tab: Wallpapers.mode
    onActiveChanged: if (active) {
        Wallpapers.refresh();
        tab = Wallpapers.mode;
    }
    Component.onCompleted: Wallpapers.refresh()

    padding: Metrics.s5
    spacing: Metrics.s4
    readonly property real inner: width - padding * 2

    Item {
        width: root.inner
        height: 36

        Label {
            anchors.verticalCenter: parent.verticalCenter
            role: "headline"
            text: "Wallpaper"
        }
        Segmented {
            anchors.right: parent.right
            anchors.verticalCenter: parent.verticalCenter
            width: 220
            current: root.tab
            options: [
                {
                    key: "static",
                    label: "Images"
                },
                {
                    key: "live",
                    label: "Live"
                }
            ]
            onPicked: key => root.tab = key
        }
    }

    GridView {
        id: grid
        width: root.inner
        readonly property int columns: 4
        cellWidth: Math.floor(width / columns)
        cellHeight: Math.round(cellWidth * 0.625) + (root.tab === "live" ? 22 : 0)
        height: Math.min(cellHeight * 3 + 4, Math.max(cellHeight, contentHeight))
        clip: true
        boundsBehavior: Flickable.StopAtBounds
        cacheBuffer: cellHeight
        Keys.onEscapePressed: PanelRouter.close(root.screen.name)
        focus: true

        model: ScriptModel {
            values: root.tab === "live" ? Wallpapers.live : Wallpapers.images.map(p => ({
                        path: p
                    }))
            objectProp: root.tab === "live" ? "id" : "path"
        }

        delegate: Item {
            id: cell
            required property var modelData
            readonly property bool live: root.tab === "live"
            readonly property string source: live ? (modelData.preview ?? "") : modelData.path
            readonly property bool current: live ? Wallpapers.mode === "live" && modelData.id === Wallpapers.liveCurrent : Wallpapers.mode === "static" && modelData.path === Wallpapers.current

            width: grid.cellWidth
            height: grid.cellHeight

            Rectangle {
                id: frame
                x: Metrics.s1
                y: Metrics.s1
                width: parent.width - Metrics.s1 * 2
                height: Math.round(width * 0.625)
                radius: Metrics.radiusMd
                color: Theme.hover
                border.width: cell.current ? 2 : 0
                border.color: Theme.accent
                scale: hover.containsMouse ? 1.025 : 1

                Behavior on scale {
                    NumberAnimation {
                        duration: Motion.focus
                        easing.type: Motion.standardEasing
                    }
                }

                Image {
                    anchors.fill: parent
                    anchors.margins: cell.current ? 3 : 0
                    source: cell.source !== "" ? "file://" + cell.source : ""
                    sourceSize.width: Math.min(ExperiencePolicy.thumbnailSize, Math.round(frame.width * 1.5))
                    fillMode: Image.PreserveAspectCrop
                    asynchronous: true
                    cache: true
                    smooth: true
                    opacity: status === Image.Ready ? 1 : 0

                    Behavior on opacity {
                        NumberAnimation {
                            duration: Motion.contentIn
                        }
                    }
                }

                MouseArea {
                    id: hover
                    anchors.fill: parent
                    hoverEnabled: true
                    cursorShape: Qt.PointingHandCursor
                    onClicked: cell.live ? Wallpapers.applyLive(cell.modelData.id) : Wallpapers.applyImage(cell.modelData.path)
                }
            }
            Label {
                visible: cell.live
                anchors.top: frame.bottom
                anchors.topMargin: 3
                x: Metrics.s1
                width: frame.width
                role: "caption"
                tone: cell.current ? "accent" : "muted"
                text: cell.modelData.title ?? ""
            }
        }
    }

    Label {
        visible: grid.count === 0
        width: root.inner
        height: 64
        horizontalAlignment: Text.AlignHCenter
        verticalAlignment: Text.AlignVCenter
        role: "label"
        tone: "faint"
        text: Wallpapers.loading ? "" : root.tab === "live" ? "No live wallpapers in the collection" : "No images in " + Wallpapers.directory
    }
}
