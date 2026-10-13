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
    function write(v: var): void {
        Config.write(domain, key, v);
    }

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
        Label {
            width: parent.width
            role: "body"
            text: root.title
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
