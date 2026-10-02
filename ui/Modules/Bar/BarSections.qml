import QtQuick
import qs.Common
import qs.Widgets

// start / center / end. In a fitted bar the three sit next to each other with a quiet divider between
// non-empty sections; in a "fill" bar they pin to the ends and the middle.
Item {
    id: root

    required property var bar
    property bool fill: false

    readonly property var widgets: bar.spec.widgets ?? ({})
    readonly property bool vertical: bar.vertical
    readonly property var parts: [startSection, centerSection, endSection].filter(s => s.count > 0)
    readonly property int gap: Metrics.s3

    implicitWidth: vertical ? bar.thickness : parts.reduce((a, s) => a + s.implicitWidth, 0) + Math.max(0, parts.length - 1) * gap
    implicitHeight: vertical ? parts.reduce((a, s) => a + s.implicitHeight, 0) + Math.max(0, parts.length - 1) * gap : bar.thickness

    function place(section: Item, index: int): real {
        if (root.fill) {
            const span = root.vertical ? root.height : root.width;
            const size = root.vertical ? section.implicitHeight : section.implicitWidth;
            return index === 0 ? Metrics.s2 : index === 1 ? (span - size) / 2 : span - size - Metrics.s2;
        }
        let at = (root.vertical ? (root.height - root.implicitHeight) : (root.width - root.implicitWidth)) / 2;
        for (const s of root.parts) {
            if (s === section)
                return at;
            at += (root.vertical ? s.implicitHeight : s.implicitWidth) + root.gap;
        }
        return at;
    }

    BarSection {
        id: startSection
        bar: root.bar
        types: root.widgets.start ?? []
        x: root.vertical ? (root.width - width) / 2 : root.place(this, 0)
        y: root.vertical ? root.place(this, 0) : (root.height - height) / 2
    }
    BarSection {
        id: centerSection
        bar: root.bar
        types: root.widgets.center ?? []
        x: root.vertical ? (root.width - width) / 2 : root.place(this, 1)
        y: root.vertical ? root.place(this, 1) : (root.height - height) / 2
    }
    BarSection {
        id: endSection
        bar: root.bar
        types: root.widgets.end ?? []
        x: root.vertical ? (root.width - width) / 2 : root.place(this, 2)
        y: root.vertical ? root.place(this, 2) : (root.height - height) / 2
    }
}
