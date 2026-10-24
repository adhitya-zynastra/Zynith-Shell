#pragma once

#include <QElapsedTimer>
#include <QList>
#include <QMutex>
#include <QObject>
#include <QQuickItem>
#include <QPointer>
#include <QString>
#include <QTimer>
#include <QVector>
#include <QtQml/qqmlregistration.h>

class QQuickWindow;

// Where a frame's time goes, for diagnostics. Disarmed (the default) it holds no connections and costs nothing.
// Armed for a bounded time, it stamps each watched window's frame phases on one monotonic clock — the GUI thread's
// (afterAnimating: animations advanced, polish next; beforeSynchronizing: the GUI thread blocks) and the render
// thread's (sync, render, frame end, swap) — with labelled marks from QML (a switch, a page built), into a fixed
// buffer read once at the end (`ipc frameDump`). A slow frame can then be put down to the GUI thread (QML, layout,
// page builds), to synchronisation, or to rendering and presenting (uploads, a resized surface).
class FrameProbe : public QObject {
    Q_OBJECT
    QML_ELEMENT
    QML_SINGLETON

    Q_PROPERTY(bool armed READ armed NOTIFY armedChanged)

public:
    explicit FrameProbe(QObject* parent = nullptr);

    bool armed() const { return m_armed; }

    // the window an item is in, under a name; followed if the item moves to another window
    Q_INVOKABLE void watch(QQuickItem* item, const QString& name);
    // record for ms (at most 60 s), from now; a new arm starts a new recording
    Q_INVOKABLE void arm(int ms);
    // a labelled moment on the GUI thread (only while armed)
    Q_INVOKABLE void mark(const QString& label);
    // the recording as JSON: {"events": [[t_us, thread, window, kind], ...], "dropped": n}; clears it
    Q_INVOKABLE QString dump();

signals:
    void armedChanged();

private:
    struct Watched {
        QPointer<QQuickItem> item;
        QPointer<QQuickWindow> window;
        QString name;
        QList<QMetaObject::Connection> connections;
    };
    void attach(Watched& w);
    void detach(Watched& w);
    void record(const QString& window, const char* kind, bool renderThread);
    void disarm();

    QElapsedTimer m_clock;
    QTimer m_stop;
    bool m_armed = false;
    QList<Watched> m_watched;

    struct Event {
        qint64 us;
        bool renderThread;
        QString window;
        QString kind;
    };
    QMutex m_lock;
    QVector<Event> m_events;
    int m_dropped = 0;
    static constexpr int kCapacity = 20000;
};
