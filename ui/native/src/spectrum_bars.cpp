#include "spectrum_bars.h"

#include <QSGGeometryNode>
#include <QSGVertexColorMaterial>
#include <algorithm>
#include <cmath>
#include <numbers>

namespace {
// segments per rounded end: enough for a smooth cap at bar widths up to ~40 px
constexpr int kCapSegments = 6;
// the soft edge, in pixels
constexpr float kFeather = 0.9F;

using Vertex = QSGGeometry::ColoredPoint2D;

void put(Vertex*& v, float x, float y, const QColor& c, float alpha) {
    // premultiplied, as the vertex-colour material expects
    const float a = std::clamp(alpha, 0.0F, 1.0F) * static_cast<float>(c.alphaF());
    v->set(x, y, static_cast<uchar>(c.red() * a), static_cast<uchar>(c.green() * a), static_cast<uchar>(c.blue() * a),
           static_cast<uchar>(255 * a));
    ++v;
}

QColor mix(const QColor& a, const QColor& b, qreal t) {
    t = std::clamp(t, 0.0, 1.0);
    return QColor::fromRgbF(static_cast<float>(a.redF() + (b.redF() - a.redF()) * t), static_cast<float>(a.greenF() + (b.greenF() - a.greenF()) * t),
                            static_cast<float>(a.blueF() + (b.blueF() - a.blueF()) * t), static_cast<float>(a.alphaF() + (b.alphaF() - a.alphaF()) * t));
}
} // namespace

SpectrumBars::SpectrumBars(QQuickItem* parent) : QQuickItem(parent) { setFlag(ItemHasContents, true); }

void SpectrumBars::touch() {
    emit changed();
    update();
}

#define SETTER(name, member, type)                                                                                     \
    void SpectrumBars::name(type v) {                                                                                  \
        if (member == v)                                                                                               \
            return;                                                                                                    \
        member = v;                                                                                                    \
        touch();                                                                                                       \
    }
SETTER(setCount, m_count, int)
SETTER(setMirrored, m_mirrored, bool)
SETTER(setReversed, m_reversed, bool)
SETTER(setCentred, m_centred, bool)
SETTER(setVertical, m_vertical, bool)
SETTER(setEdge, m_edge, const QString&)
SETTER(setGain, m_gain, qreal)
SETTER(setGap, m_gap, qreal)
SETTER(setMinLength, m_minLength, qreal)
SETTER(setFloor, m_floor, qreal)
SETTER(setAlpha, m_alpha, qreal)
SETTER(setAlphaByLevel, m_alphaByLevel, qreal)
SETTER(setGradientFromCentre, m_gradientFromCentre, bool)
SETTER(setStill, m_still, bool)
#undef SETTER

void SpectrumBars::setValues(const QList<qreal>& v) {
    if (m_values == v)
        return;
    m_values = v;
    update(); // every frame: no changed() (nothing in QML needs to re-read it)
}
void SpectrumBars::setColorFrom(const QColor& v) {
    if (m_from == v)
        return;
    m_from = v;
    touch();
}
void SpectrumBars::setColorTo(const QColor& v) {
    if (m_to == v)
        return;
    m_to = v;
    touch();
}

// the analyser's bands, stretched to `count` positions (as the QML visualizers' level())
qreal SpectrumBars::level(int i) const {
    const int count = std::max(1, m_count);
    qreal t = m_mirrored ? std::abs((i + 0.5) / count * 2.0 - 1.0) : (i + 0.5) / count;
    if (m_reversed)
        t = 1.0 - t;
    if (m_still) {
        const qreal s = std::sin(t * 2.6 + 0.4);
        return 0.2 + 0.6 * s * s;
    }
    const int n = static_cast<int>(m_values.size());
    if (n == 0)
        return 0.0;
    const qreal x = t * (n - 1);
    const int a = static_cast<int>(std::floor(x));
    const int b = std::min(n - 1, a + 1);
    const qreal v = m_values.at(a) + (m_values.at(b) - m_values.at(a)) * (x - a);
    return std::clamp(v * m_gain, 0.0, 1.0);
}

QSGNode* SpectrumBars::updatePaintNode(QSGNode* old, UpdatePaintNodeData*) {
    const int count = std::max(1, m_count);
    enum class Edge { Bottom, Top, Left, Right };
    const Edge edge = m_edge == QLatin1String("top")      ? Edge::Top
                      : m_edge == QLatin1String("left")   ? Edge::Left
                      : m_edge == QLatin1String("right")  ? Edge::Right
                      : m_edge == QLatin1String("bottom") ? Edge::Bottom
                      : m_vertical                        ? Edge::Left
                                                          : Edge::Bottom;
    const bool alongHeight = edge == Edge::Left || edge == Edge::Right;
    const float along = static_cast<float>(alongHeight ? height() : width());
    const float across = static_cast<float>(alongHeight ? width() : height());
    if (along <= 0 || across <= 0) {
        delete old;
        return nullptr;
    }

    // per bar: the body (2 triangles) + two caps (kCapSegments triangles each), filled, plus the feathered
    // outline (one quad per outline edge)
    const int outlinePoints = 2 * (kCapSegments + 1);
    const int perBar = (2 + 2 * kCapSegments) * 3 + outlinePoints * 6;

    auto* node = static_cast<QSGGeometryNode*>(old);
    if (node == nullptr) {
        node = new QSGGeometryNode;
        auto* geometry = new QSGGeometry(QSGGeometry::defaultAttributes_ColoredPoint2D(), 0);
        geometry->setDrawingMode(QSGGeometry::DrawTriangles);
        node->setGeometry(geometry);
        node->setFlag(QSGNode::OwnsGeometry);
        auto* material = new QSGVertexColorMaterial;
        node->setMaterial(material);
        node->setFlag(QSGNode::OwnsMaterial);
    }
    QSGGeometry* geometry = node->geometry();
    geometry->allocate(count * perBar);
    Vertex* v = geometry->vertexDataAsColoredPoint2D();

    const float slot = along / count;
    const float thickness = std::max(1.0F, slot * static_cast<float>(1.0 - std::clamp(m_gap, 0.0, 0.9)));
    const float r = thickness / 2.0F;

    // a bar in local space — u along the edge, w away from it (0 = the baseline) — mapped to x/y
    auto map = [&](float u, float w, float& x, float& y) {
        switch (edge) {
        case Edge::Bottom:
            x = u;
            y = across - w;
            break;
        case Edge::Top:
            x = u;
            y = w;
            break;
        case Edge::Left:
            x = w;
            y = u;
            break;
        case Edge::Right:
            x = across - w;
            y = u;
            break;
        }
    };

    for (int i = 0; i < count; ++i) {
        const qreal lv = level(i);
        const float len = std::clamp(static_cast<float>(std::max<qreal>(m_minLength, std::max(m_floor, lv) * across)), thickness, across);
        const float u0 = slot * i + (slot - thickness) / 2.0F;
        const float uc = u0 + r; // the bar's centre line, along
        // across: from the edge, or centred
        const float w0 = m_centred ? (across - len) / 2.0F : 0.0F;
        const float w1 = w0 + len;
        const float capR = std::min(r, len / 2.0F);
        const float body0 = w0 + capR, body1 = w1 - capR;

        const qreal pos = m_gradientFromCentre ? std::abs((i + 0.5) / count * 2.0 - 1.0) : (i + 0.5) / count;
        const QColor c = mix(m_from, m_to, pos);
        const float a = static_cast<float>(m_alpha + m_alphaByLevel * lv);

        // the outline, counter-clockwise: the far cap (w1) then the near cap (w0)
        float ox[outlinePoints], oy[outlinePoints], nx[outlinePoints], ny[outlinePoints];
        for (int k = 0; k <= kCapSegments; ++k) {
            const float t = std::numbers::pi_v<float> * k / kCapSegments; // 0..pi
            const float du = -std::cos(t) * r, dw = std::sin(t) * capR;
            // far cap: from u0 side to u1 side over the top
            map(uc + du, body1 + dw, ox[k], oy[k]);
            float ex, ey, cx, cy;
            map(uc + du * 1.0F, body1 + dw, ex, ey);
            map(uc, body1, cx, cy);
            const float len2 = std::hypot(ex - cx, ey - cy);
            nx[k] = len2 > 0 ? (ex - cx) / len2 : 0;
            ny[k] = len2 > 0 ? (ey - cy) / len2 : 0;
        }
        for (int k = 0; k <= kCapSegments; ++k) {
            const float t = std::numbers::pi_v<float> * k / kCapSegments;
            const float du = std::cos(t) * r, dw = -std::sin(t) * capR;
            const int j = kCapSegments + 1 + k;
            map(uc + du, body0 + dw, ox[j], oy[j]);
            float ex, ey, cx, cy;
            map(uc + du, body0 + dw, ex, ey);
            map(uc, body0, cx, cy);
            const float len2 = std::hypot(ex - cx, ey - cy);
            nx[j] = len2 > 0 ? (ex - cx) / len2 : 0;
            ny[j] = len2 > 0 ? (ey - cy) / len2 : 0;
        }

        // fill: a fan from the bar's middle over the outline
        float mx, my;
        map(uc, (w0 + w1) / 2.0F, mx, my);
        const int fanTriangles = 2 + 2 * kCapSegments;
        for (int k = 0; k < fanTriangles; ++k) {
            const int p = k % outlinePoints, q = (k + 1) % outlinePoints;
            put(v, mx, my, c, a);
            put(v, ox[p], oy[p], c, a);
            put(v, ox[q], oy[q], c, a);
        }
        // the soft edge: a quad from each outline edge outwards, fading to clear
        for (int p = 0; p < outlinePoints; ++p) {
            const int q = (p + 1) % outlinePoints;
            const float px = ox[p] + nx[p] * kFeather, py = oy[p] + ny[p] * kFeather;
            const float qx = ox[q] + nx[q] * kFeather, qy = oy[q] + ny[q] * kFeather;
            put(v, ox[p], oy[p], c, a);
            put(v, ox[q], oy[q], c, a);
            put(v, px, py, c, 0);
            put(v, ox[q], oy[q], c, a);
            put(v, qx, qy, c, 0);
            put(v, px, py, c, 0);
        }
    }
    node->markDirty(QSGNode::DirtyGeometry);
    return node;
}
