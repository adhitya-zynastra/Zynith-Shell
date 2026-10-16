import QtQuick
import qs.Common
import qs.Components
import qs.Services

// One setting: what it is on the left, its control on the right. Bound to one key of one config file
// (domain = the file, e.g. "appearance"; key = a dotted path inside it).
Item {
    id: root

    property string title: ""
    property string detail: ""
    property string domain: ""
    property string key: ""
    // the control sits here
    default property alias control: slot.data
    property int controlWidth: 220

    readonly property var file: Config.files[domain] ?? null
    readonly property var value: {
        let node = file ? file.values : undefined;
        for (const part of key.split("."))
            node = node === undefined || node === null ? undefined : node[part];
        return node;
    }
    // through Config.change, so the Settings window can take it back
    function write(v: var): void {
        Config.change(domain, key, v, title);
    }
    readonly property var fallback: Config.defaultAt(domain, key)
    // a value of its own (not the default), which the row offers to put back
    readonly property bool changedFromDefault: fallback !== undefined && value !== undefined && !Config.same(value, fallback)

    // as tall as its text or its control, whichever is taller (a font list unfolds in place)
    implicitHeight: Math.max(48, text.implicitHeight + Metrics.s3 * 2, slot.height + Metrics.s3 * 2)
    width: parent ? parent.width : 400

    Column {
        id: text
        anchors.left: parent.left
        anchors.right: slot.left
        anchors.rightMargin: Metrics.s5
        anchors.verticalCenter: parent.verticalCenter
        spacing: 2
        Row {
            width: parent.width
            spacing: Metrics.s2
            Label {
                id: titleLabel
                width: Math.min(implicitWidth, parent.width - (reset.visible ? reset.width + parent.spacing : 0))
                role: "body"
                text: root.title
            }
            // set to something of its own: one click puts the default back (and can itself be undone)
            Item {
                id: reset
                visible: root.changedFromDefault && root.domain !== ""
                anchors.verticalCenter: titleLabel.verticalCenter
                width: 18
                height: 18
                Icon {
                    anchors.centerIn: parent
                    name: "arrow-back-up"
                    size: 14
                    color: resetArea.containsMouse ? Theme.accent : Theme.inkFaint
                }
                MouseArea {
                    id: resetArea
                    anchors.fill: parent
                    anchors.margins: -4
                    hoverEnabled: true
                    cursorShape: Qt.PointingHandCursor
                    onClicked: Config.change(root.domain, root.key, undefined, root.title)
                }
            }
        }
        Label {
            visible: root.detail !== ""
            width: parent.width
            role: "label"
            tone: "faint"
            wrapMode: Text.WordWrap
            elide: Text.ElideNone
            text: root.detail
        }
    }
    Item {
        id: slot
        anchors.right: parent.right
        anchors.top: parent.top
        anchors.topMargin: Math.max(Metrics.s3, (Math.max(48, text.implicitHeight + Metrics.s3 * 2) - Math.min(height, 48)) / 2)
        width: root.controlWidth
        height: childrenRect.height
    }
}
