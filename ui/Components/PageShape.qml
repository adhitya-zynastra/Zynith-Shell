import QtQuick
import QtQuick.Shapes
import qs.Common

// The page and its tab as one outline: a sheet whose top edge rises into a tab between tabLeft and tabRight,
// meeting the sheet in concave fillets. One path, so the fill has no seam and the contour runs unbroken from
// the sheet up around the tab and back. The tab's edges move (PanelTabs animates them); the path follows.
Item {
    id: root

    // the sheet, in this item's coordinates
    property real sheetX: 0
    property real sheetY: 0
    property real sheetWidth: width
    property real sheetHeight: height
    property real radius: Metrics.radiusPlate
    // the tab: its horizontal extent and its top (above sheetY); no tab when tabRight <= tabLeft
    property real tabLeft: 0
    property real tabRight: 0
    property real tabTop: sheetY
    property real tabRadius: Metrics.radiusPlate
    property real fillet: Metrics.radiusPlate
    property color fill: Theme.well
    // the contour: a hairline in the material's edge colour (transparent: none)
    property color edge: "transparent"
    property real edgeWidth: Metrics.hairline

    function f(n: real): string {
        return Number(n).toFixed(2);
    }
    function arc(r: real, sweep: int, x: real, y: real): string {
        return r > 0.01 ? " A " + f(r) + " " + f(r) + " 0 0 " + sweep + " " + f(x) + " " + f(y) : " L " + f(x) + " " + f(y);
    }
    readonly property string outline: {
        const L = sheetX, T = sheetY, Rt = sheetX + sheetWidth, B = sheetY + sheetHeight;
        if (sheetWidth <= 0 || sheetHeight <= 0)
            return "";
        const R = Math.min(radius, sheetWidth / 2, sheetHeight / 2);
        const hasTab = tabRight - tabLeft > 1 && tabTop < T - 0.5;
        if (!hasTab)
            return "M " + f(L) + " " + f(T + R) + arc(R, 1, L + R, T) + " L " + f(Rt - R) + " " + f(T) + arc(R, 1, Rt, T + R)
                + " L " + f(Rt) + " " + f(B - R) + arc(R, 1, Rt - R, B) + " L " + f(L + R) + " " + f(B) + arc(R, 1, L, B - R) + " Z";
        const a = Math.max(L, tabLeft), b = Math.min(Rt, tabRight);
        const rt = Math.min(tabRadius, (b - a) / 2, (T - tabTop) / 2);
        // the fillets give way where the tab reaches the sheet's corner; the corner itself gives way after
        const fl = Math.max(0, Math.min(fillet, a - L - R, (T - tabTop) - rt));
        const fr = Math.max(0, Math.min(fillet, Rt - b - R, (T - tabTop) - rt));
        const rl = fl > 0 || a - L >= R ? R : Math.max(0, a - L);
        const rr = fr > 0 || Rt - b >= R ? R : Math.max(0, Rt - b);
        let p = "M " + f(L) + " " + f(T + rl) + arc(rl, 1, L + rl, T);
        p += " L " + f(a - fl) + " " + f(T) + arc(fl, 0, a, T - fl);
        p += " L " + f(a) + " " + f(tabTop + rt) + arc(rt, 1, a + rt, tabTop);
        p += " L " + f(b - rt) + " " + f(tabTop) + arc(rt, 1, b, tabTop + rt);
        p += " L " + f(b) + " " + f(T - fr) + arc(fr, 0, b + fr, T);
        p += " L " + f(Rt - rr) + " " + f(T) + arc(rr, 1, Rt, T + rr);
        p += " L " + f(Rt) + " " + f(B - R) + arc(R, 1, Rt - R, B) + " L " + f(L + R) + " " + f(B) + arc(R, 1, L, B - R) + " Z";
        return p;
    }

    // the fill: drawn opaque inside a layer that takes the colour's alpha, so a translucent tone stays even
    // where the path's own antialiased edges would otherwise double
    Shape {
        anchors.fill: parent
        visible: root.outline !== ""
        preferredRendererType: Shape.CurveRenderer
        layer.enabled: root.fill.a < 1 && visible
        opacity: root.fill.a < 1 ? root.fill.a : 1
        ShapePath {
            strokeWidth: 0
            strokeColor: "transparent"
            fillColor: Qt.rgba(root.fill.r, root.fill.g, root.fill.b, 1)
            PathSvg {
                path: root.outline
            }
        }
    }
    Shape {
        anchors.fill: parent
        visible: root.outline !== "" && root.edge.a > 0 && root.edgeWidth > 0
        preferredRendererType: Shape.CurveRenderer
        ShapePath {
            strokeWidth: root.edgeWidth
            strokeColor: root.edge
            fillColor: "transparent"
            PathSvg {
                path: root.outline
            }
        }
    }
}
