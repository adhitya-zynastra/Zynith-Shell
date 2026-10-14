import QtQuick
import qs.Common

// The Zynith mark, assembled block by block: the image cut into a grid whose blocks settle into place in a
// diagonal wave, then the whole mark resolves crisp. Restrained (about 0.7 s), played once per process, skipped by
// a click, shown at once with reduced motion. Every block shows the same decoded image, so it costs one decode.
Item {
    id: root

    property url source: Paths.asset("brand/zynith-mark.png")
    property int blocks: 8
    // 0 → 1; playing drives it, a click or reduced motion jumps to 1
    property real progress: Motion.reduced || played ? 1 : 0
    // the wave's length relative to one block's own settling
    readonly property real span: 0.55
    property bool played: false

    implicitWidth: 128
    implicitHeight: 128

    function play(): void {
        if (Motion.reduced || played) {
            progress = 1;
            return;
        }
        run.restart();
    }
    function skip(): void {
        run.stop();
        progress = 1;
        played = true;
    }
    Component.onCompleted: play()

    NumberAnimation {
        id: run
        target: root
        property: "progress"
        from: 0
        to: 1
        duration: Math.max(1, Motion.ms(700))
        easing.type: Easing.Linear
        onFinished: root.played = true
    }

    readonly property real cell: width / blocks

    Repeater {
        model: root.blocks * root.blocks
        delegate: Item {
            id: block
            required property int index
            readonly property int row: Math.floor(index / root.blocks)
            readonly property int col: index % root.blocks
            // the wave runs from the top left; each block settles over the rest of the time
            readonly property real start: (row + col) / (2 * (root.blocks - 1)) * root.span
            readonly property real t: Math.max(0, Math.min(1, (root.progress - start) / (1 - root.span)))
            readonly property real e: 1 - Math.pow(1 - t, 3)
            x: col * root.cell + (1 - e) * (col - root.blocks / 2) * root.cell * 0.18
            y: row * root.cell + (1 - e) * (row - root.blocks / 2) * root.cell * 0.18
            width: root.cell
            height: root.cell
            clip: true
            opacity: e * (1 - crisp.opacity)
            scale: 0.6 + 0.4 * e
            visible: opacity > 0.01
            Image {
                x: -block.col * root.cell
                y: -block.row * root.cell
                width: root.width
                height: root.height
                source: root.source
                sourceSize.width: 256
                smooth: true
                mipmap: true
            }
        }
    }
    // the mark itself once every block has landed (no seams)
    Image {
        id: crisp
        anchors.fill: parent
        source: root.source
        sourceSize.width: 256
        smooth: true
        mipmap: true
        opacity: Math.max(0, Math.min(1, (root.progress - 0.92) / 0.08))
    }
    MouseArea {
        anchors.fill: parent
        enabled: root.progress < 1
        cursorShape: Qt.PointingHandCursor
        onClicked: root.skip()
    }
}
