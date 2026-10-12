#pragma once

#include <QColor>
#include <QString>
#include <QList>
#include <QElapsedTimer>
#include <QQuickItem>
#include <QtQml/qqmlregistration.h>

// The spectrum as bars, drawn by the scene graph in one node: every bar a rounded (stadium) quad with a
// one-pixel soft edge, vertex-coloured along the gradient. A QML Repeater of Rectangles costs a binding and
// a node per bar per frame on the GUI thread; this costs one geometry update.
//
// Bars stand along the item's width (or its height when `vertical`), each sampling the analyser's bands the
// way the QML visualizers did: mirrored around the middle or not, reversed, rising from the edge or centred.
class SpectrumBars : public QQuickItem {
    Q_OBJECT
    QML_ELEMENT

    Q_PROPERTY(QList<qreal> values READ values WRITE setValues NOTIFY changed)
    Q_PROPERTY(int count READ count WRITE setCount NOTIFY changed)
    Q_PROPERTY(bool mirrored READ mirrored WRITE setMirrored NOTIFY changed)
    Q_PROPERTY(bool reversed READ reversed WRITE setReversed NOTIFY changed)
    Q_PROPERTY(bool centred READ centred WRITE setCentred NOTIFY changed)
    Q_PROPERTY(bool vertical READ vertical WRITE setVertical NOTIFY changed)
    // the edge the bars stand on: "bottom" | "top" (bars along the width) | "left" | "right" (along the height).
    // Each bar's baseline is that edge and it grows away from it, into the item. Empty: left when `vertical`,
    // else bottom (as before the edge existed).
    Q_PROPERTY(QString edge READ edge WRITE setEdge NOTIFY changed)
    Q_PROPERTY(qreal gain READ gain WRITE setGain NOTIFY changed)
    // the share of each bar's slot left empty between bars (0..0.9)
    Q_PROPERTY(qreal gap READ gap WRITE setGap NOTIFY changed)
    // a bar never shrinks below this many pixels, nor below `floor` of its length
    Q_PROPERTY(qreal minLength READ minLength WRITE setMinLength NOTIFY changed)
    Q_PROPERTY(qreal floor READ floor WRITE setFloor NOTIFY changed)
    Q_PROPERTY(QColor colorFrom READ colorFrom WRITE setColorFrom NOTIFY changed)
    Q_PROPERTY(QColor colorTo READ colorTo WRITE setColorTo NOTIFY changed)
    // each bar's opacity: `alpha`, plus `alphaByLevel` × its level (louder bars stand out)
    Q_PROPERTY(qreal alpha READ alpha WRITE setAlpha NOTIFY changed)
    Q_PROPERTY(qreal alphaByLevel READ alphaByLevel WRITE setAlphaByLevel NOTIFY changed)
    // the gradient runs from the middle outwards (mirrored strips) rather than end to end
    Q_PROPERTY(bool gradientFromCentre READ gradientFromCentre WRITE setGradientFromCentre NOTIFY changed)
    // a still pattern instead of the values (previews)
    Q_PROPERTY(bool still READ still WRITE setStill NOTIFY changed)
    // square-ended, pixel-sharp bars (the native shell's) rather than rounded ones with a soft edge
    Q_PROPERTY(bool square READ square WRITE setSquare NOTIFY changed)
    // each bar eases toward the analyser's value with this time constant (ms) every frame, as the native shell's
    // visualizer does (60 ms); 0 shows the values as they come
    Q_PROPERTY(qreal smoothing READ smoothing WRITE setSmoothing NOTIFY changed)

public:
    explicit SpectrumBars(QQuickItem* parent = nullptr);

    QList<qreal> values() const { return m_values; }
    int count() const { return m_count; }
    bool mirrored() const { return m_mirrored; }
    bool reversed() const { return m_reversed; }
    bool centred() const { return m_centred; }
    bool vertical() const { return m_vertical; }
    QString edge() const { return m_edge; }
    qreal gain() const { return m_gain; }
    qreal gap() const { return m_gap; }
    qreal minLength() const { return m_minLength; }
    qreal floor() const { return m_floor; }
    QColor colorFrom() const { return m_from; }
    QColor colorTo() const { return m_to; }
    qreal alpha() const { return m_alpha; }
    qreal alphaByLevel() const { return m_alphaByLevel; }
    bool gradientFromCentre() const { return m_gradientFromCentre; }
    bool still() const { return m_still; }
    bool square() const { return m_square; }
    qreal smoothing() const { return m_smoothing; }

    void setValues(const QList<qreal>& v);
    void setCount(int v);
    void setMirrored(bool v);
    void setReversed(bool v);
    void setCentred(bool v);
    void setVertical(bool v);
    void setEdge(const QString& v);
    void setGain(qreal v);
    void setGap(qreal v);
    void setMinLength(qreal v);
    void setFloor(qreal v);
    void setColorFrom(const QColor& v);
    void setColorTo(const QColor& v);
    void setAlpha(qreal v);
    void setAlphaByLevel(qreal v);
    void setGradientFromCentre(bool v);
    void setStill(bool v);
    void setSquare(bool v);
    void setSmoothing(qreal v);

signals:
    void changed();

protected:
    QSGNode* updatePaintNode(QSGNode* old, UpdatePaintNodeData*) override;

private:
    qreal level(int i) const;
    void touch();

    QList<qreal> m_values;
    int m_count = 16;
    bool m_mirrored = true;
    bool m_reversed = false;
    bool m_centred = false;
    bool m_vertical = false;
    QString m_edge;
    qreal m_gain = 1.0;
    qreal m_gap = 0.3;
    qreal m_minLength = 2.0;
    qreal m_floor = 0.0;
    QColor m_from = Qt::white;
    QColor m_to = Qt::white;
    qreal m_alpha = 0.85;
    qreal m_alphaByLevel = 0.0;
    bool m_gradientFromCentre = false;
    bool m_still = false;
    bool m_square = false;
    qreal m_smoothing = 0.0;
    // what is drawn: the values, eased toward m_values frame by frame (render thread, during sync)
    QList<qreal> m_shown;
    QElapsedTimer m_frameClock;
    bool easeShown();
};
