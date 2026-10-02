import QtQuick
import qs.Common

// A quiet search line: glyph, text, a clear button once there is text. Up and Down, Tab, Enter and Escape on
// an empty field are reported, so the list it filters can be driven from here.
Item {
    id: root

    property alias text: input.text
    property string placeholder: "Search"
    readonly property bool editing: input.activeFocus
    signal accepted
    signal escaped
    signal moved(int delta)
    signal tabbed(bool back)

    function focusField(): void {
        input.forceActiveFocus();
    }
    function append(s: string): void {
        input.insert(input.cursorPosition, s);
        input.forceActiveFocus();
    }

    implicitHeight: 34
    implicitWidth: 240

    Rectangle {
        anchors.fill: parent
        radius: height / 2
        color: Theme.well
        border.width: Metrics.hairline
        border.color: input.activeFocus ? Theme.accentLine : Theme.hairline

        Behavior on border.color {
            ColorAnimation {
                duration: Motion.focus
            }
        }
    }

    Icon {
        id: glyph
        anchors.left: parent.left
        anchors.leftMargin: Metrics.s3
        anchors.verticalCenter: parent.verticalCenter
        name: "search"
        size: 15
        tone: input.activeFocus ? "accent" : "faint"
    }

    TextInput {
        id: input
        anchors.left: glyph.right
        anchors.leftMargin: Metrics.s2
        anchors.right: clear.left
        anchors.rightMargin: Metrics.s1
        anchors.verticalCenter: parent.verticalCenter
        color: Theme.ink
        selectionColor: Theme.accentSoft
        selectedTextColor: Theme.ink
        font.family: Type.ui
        font.pixelSize: Type.body
        clip: true

        Keys.onReturnPressed: root.accepted()
        Keys.onEnterPressed: root.accepted()
        Keys.onEscapePressed: event => {
            if (text !== "")
                text = "";
            else
                root.escaped();
        }
        Keys.onUpPressed: root.moved(-1)
        Keys.onDownPressed: root.moved(1)
        Keys.onTabPressed: root.tabbed(false)
        Keys.onBacktabPressed: root.tabbed(true)

        Label {
            visible: input.text === ""
            anchors.verticalCenter: parent.verticalCenter
            role: "body"
            tone: "faint"
            text: root.placeholder
        }
    }

    IconButton {
        id: clear
        anchors.right: parent.right
        anchors.rightMargin: 3
        anchors.verticalCenter: parent.verticalCenter
        visible: input.text !== ""
        size: 26
        iconSize: 13
        icon: "x"
        tone: "faint"
        onClicked: input.text = ""
    }
}
