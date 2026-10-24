#include "frame_probe.h"

#include <QJsonArray>
#include <QJsonDocument>
#include <QJsonObject>
#include <QMutexLocker>
#include <QQuickItem>
#include <QQuickWindow>

FrameProbe::FrameProbe(QObject* parent)
    : QObject(parent) {
    m_clock.start();
    m_stop.setSingleShot(true);
    connect(&m_stop, &QTimer::timeout, this, &FrameProbe::disarm);
}

void FrameProbe::watch(QQuickItem* item, const QString& name) {
    if (!item)
        return;
    for (auto& w : m_watched)
        if (w.item == item)
            return;
    m_watched.append({item, nullptr, name, {}});
    connect(item, &QQuickItem::windowChanged, this, [this, item](QQuickWindow*) {
        for (auto& w : m_watched)
            if (w.item == item && m_armed) {
                detach(w);
                attach(w);
            }
    });
    connect(item, &QObject::destroyed, this, [this, item]() {
        for (int i = 0; i < m_watched.size(); ++i)
            if (m_watched[i].item == item || m_watched[i].item.isNull()) {
                detach(m_watched[i]);
                m_watched.removeAt(i--);
            }
    });
    if (m_armed)
        attach(m_watched.last());
}

void FrameProbe::attach(Watched& w) {
    QQuickWindow* win = w.item ? w.item->window() : nullptr;
    w.window = win;
    if (!win)
        return;
    const QString name = w.name;
    // direct: stamped on the thread that does the work, not when a queued call gets round to it
    auto gui = [this, name](const char* kind) { return [this, name, kind]() { record(name, kind, false); }; };
    auto rt = [this, name](const char* kind) { return [this, name, kind]() { record(name, kind, true); }; };
    w.connections << connect(win, &QQuickWindow::afterAnimating, this, gui("animated"), Qt::DirectConnection)
                  << connect(win, &QQuickWindow::beforeSynchronizing, this, rt("syncBegin"), Qt::DirectConnection)
                  << connect(win, &QQuickWindow::afterSynchronizing, this, rt("syncEnd"), Qt::DirectConnection)
                  << connect(win, &QQuickWindow::beforeRendering, this, rt("renderBegin"), Qt::DirectConnection)
                  << connect(win, &QQuickWindow::afterRendering, this, rt("renderEnd"), Qt::DirectConnection)
                  << connect(win, &QQuickWindow::frameSwapped, this, rt("swapped"), Qt::DirectConnection)
                  << connect(win, &QWindow::widthChanged, this, gui("resized"), Qt::DirectConnection)
                  << connect(win, &QWindow::heightChanged, this, gui("resized"), Qt::DirectConnection)
                  << connect(win, &QWindow::visibleChanged, this, gui("visibility"), Qt::DirectConnection);
}

void FrameProbe::detach(Watched& w) {
    for (const auto& c : w.connections)
        disconnect(c);
    w.connections.clear();
    w.window = nullptr;
}

void FrameProbe::arm(int ms) {
    {
        QMutexLocker lock(&m_lock);
        m_events.clear();
        m_events.reserve(kCapacity);
        m_dropped = 0;
    }
    if (!m_armed) {
        m_armed = true;
        for (auto& w : m_watched)
            attach(w);
        emit armedChanged();
    }
    m_stop.start(qBound(1, ms, 60000));
}

void FrameProbe::disarm() {
    if (!m_armed)
        return;
    m_armed = false;
    for (auto& w : m_watched)
        detach(w);
    emit armedChanged();
}

void FrameProbe::mark(const QString& label) {
    if (m_armed)
        record(QStringLiteral("-"), label.toUtf8().constData(), false);
}

void FrameProbe::record(const QString& window, const char* kind, bool renderThread) {
    const qint64 us = m_clock.nsecsElapsed() / 1000;
    QMutexLocker lock(&m_lock);
    if (m_events.size() >= kCapacity) {
        ++m_dropped;
        return;
    }
    m_events.append({us, renderThread, window, QString::fromUtf8(kind)});
}

QString FrameProbe::dump() {
    QJsonArray events;
    int dropped;
    {
        QMutexLocker lock(&m_lock);
        for (const auto& e : m_events)
            events.append(QJsonArray{double(e.us), e.renderThread ? QStringLiteral("rt") : QStringLiteral("gui"), e.window, e.kind});
        dropped = m_dropped;
        m_events.clear();
        m_dropped = 0;
    }
    return QString::fromUtf8(QJsonDocument(QJsonObject{{"events", events}, {"dropped", dropped}}).toJson(QJsonDocument::Compact));
}
