import QtQuick
import qs.Common
import qs.Components

// A settings card: optional caption, then content.
Rectangle {
    id: root

    property string caption: ""
    default property alias content: body.data
    property alias spacing: body.spacing

    implicitHeight: body.implicitHeight + Metrics.s5 * 2 + (caption ? 22 : 0)
    // an Optics plate: a tone step, no edge
    radius: Metrics.radiusPlate
    color: Theme.plate

    Label {
        id: head
        visible: root.caption !== ""
        x: Metrics.s5
        y: Metrics.s5
        role: "data"
        tone: "faint"
        text: root.caption
    }

    Column {
        id: body
        x: Metrics.s5
        y: Metrics.s5 + (root.caption ? 22 : 0)
        width: root.width - Metrics.s5 * 2
        spacing: Metrics.s3
    }
}
