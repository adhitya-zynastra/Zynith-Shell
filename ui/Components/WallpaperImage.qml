import QtQuick
import qs.Common
import qs.Services

// The current wallpaper as a picture inside the shell (the Control Panel's hero, Settings' scene and previews).
// A new wallpaper comes in as the palette does: the old picture stays until the new one has loaded, then the two
// cross-fade over the palette's own blend ([animation] palette_ms), so the picture and every colour around it change
// together. A plain Image dropped to its backing (a grey) while the new file loaded and then cut in, ~250 ms out of
// step with the colours. Reduced motion: the new picture at once, once it is ready.
Item {
    id: root

    // the picture: a path or a URL; the wallpaper (Scheme.image) unless told otherwise
    property string source: Scheme.image
    property real decodeWidth: width * 1.5
    property int fillMode: Image.PreserveAspectCrop
    readonly property bool ready: front.status === Image.Ready
    readonly property int fadeMs: Motion.reduced ? 0 : Math.round((Config.animation?.palette_ms ?? 650) * Motion.scale)

    function url(s: string): string {
        return s === "" ? "" : s.startsWith("/") ? "file://" + s : s;
    }
    property Image front: a
    readonly property Image back: front === a ? b : a
    onSourceChanged: {
        const next = url(source);
        if (next === front.source.toString() && back.source.toString() === "")
            return;
        fade.stop();
        // nothing shown yet: straight in
        if (front.status !== Image.Ready || next === "") {
            back.source = "";
            front.source = next;
            front.opacity = 1;
            return;
        }
        back.opacity = 0;
        back.z = 1;
        front.z = 0;
        back.source = next;
    }
    Component.onCompleted: {
        a.source = url(source);
        a.opacity = 1;
    }

    Image {
        id: a
        anchors.fill: parent
        sourceSize.width: root.decodeWidth
        fillMode: root.fillMode
        asynchronous: true
        opacity: 0
        onStatusChanged: root.arrived(a)
    }
    Image {
        id: b
        anchors.fill: parent
        sourceSize.width: root.decodeWidth
        fillMode: root.fillMode
        asynchronous: true
        opacity: 0
        onStatusChanged: root.arrived(b)
    }
    function arrived(img: Image): void {
        if (img === front || img.status !== Image.Ready || img.source.toString() === "")
            return;
        if (fadeMs <= 0) {
            finish(img);
            return;
        }
        fade.target = img;
        fade.duration = fadeMs;
        fade.restart();
    }
    function finish(img: Image): void {
        const old = front;
        img.opacity = 1;
        front = img;
        // the old decode is let go once it is covered
        old.opacity = 0;
        old.source = "";
    }
    NumberAnimation {
        id: fade
        property: "opacity"
        from: 0
        to: 1
        easing.type: Easing.InOutCubic
        onFinished: root.finish(target)
    }
}
