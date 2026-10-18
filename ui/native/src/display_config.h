#pragma once

#include <QObject>
#include <functional>
#include <memory>
#include <QTimer>
#include <QVariantList>
#include <QtQml/qqmlregistration.h>

// Output orientation, owned by niri. This only asks niri and edits niri's own configuration; it keeps no display
// state of its own beyond a change waiting to be confirmed.
//
//   outputs        what niri reports (name, make, model, logical size, transform), refreshed on request
//   setTransform   applies a transform for the session only (niri IPC "Output"), and arms the rollback: a timer here
//                  and a detached watchdog process that restores the old transform even if this UI dies or freezes
//   confirm        persists it: the output block niri actually uses (the first for that name, following includes)
//                  gets the transform line, after a backup to ~/.config/rice-backups and a `niri validate` of the
//                  whole configuration with the change in place; then the watchdog is disarmed
//   revert         restores the old transform at once
//
// Transforms are niri's names: normal, 90, 180, 270 (counter-clockwise), and the flipped variants.
class DisplayConfig : public QObject {
    Q_OBJECT
    QML_ELEMENT
    QML_SINGLETON

    Q_PROPERTY(QVariantList outputs READ outputs NOTIFY outputsChanged)
    Q_PROPERTY(bool pending READ pending NOTIFY pendingChanged)
    Q_PROPERTY(QString pendingOutput READ pendingOutput NOTIFY pendingChanged)
    Q_PROPERTY(QString pendingTransform READ pendingTransform NOTIFY pendingChanged)
    Q_PROPERTY(QString previousTransform READ previousTransform NOTIFY pendingChanged)
    Q_PROPERTY(int secondsLeft READ secondsLeft NOTIFY secondsLeftChanged)
    Q_PROPERTY(QString lastError READ lastError NOTIFY lastErrorChanged)
    Q_PROPERTY(QString lastBackup READ lastBackup NOTIFY lastBackupChanged)

public:
    explicit DisplayConfig(QObject* parent = nullptr);
    ~DisplayConfig() override;

    QVariantList outputs() const { return m_outputs; }
    bool pending() const { return !m_pendingOutput.isEmpty(); }
    QString pendingOutput() const { return m_pendingOutput; }
    QString pendingTransform() const { return m_pendingTransform; }
    QString previousTransform() const { return m_previousTransform; }
    int secondsLeft() const { return m_secondsLeft; }
    QString lastError() const { return m_lastError; }
    QString lastBackup() const { return m_lastBackup; }

    Q_INVOKABLE void refresh();
    // seconds: how long the change waits for confirmation before it is undone (clamped to 5..60)
    Q_INVOKABLE void setTransform(const QString& output, const QString& transform, int seconds = 15);
    Q_INVOKABLE void confirm();
    Q_INVOKABLE void revert();

    // pure, for tests: `text` with the transform of the first top-level `output "<name>"` block set (a `normal`
    // transform removes the line), or a new block appended when there is none. `found` reports which.
    Q_INVOKABLE static QString withTransform(const QString& text, const QString& output, const QString& transform);
    Q_INVOKABLE static bool hasOutputBlock(const QString& text, const QString& output);
    // niri's IPC spelling ("Normal", "_90"…) or the CLI's ("normal", "90"…) → the CLI's
    Q_INVOKABLE static QString canonical(const QString& transform);

signals:
    void outputsChanged();
    void pendingChanged();
    void secondsLeftChanged();
    void lastErrorChanged();
    void lastBackupChanged();
    // the session change took (or not); the change was kept (persisted) or rolled back
    void applied(const QString& output, bool ok, const QString& message);
    void finished(const QString& output, bool kept, const QString& message);

private:
    void request(const QByteArray& json, std::function<void(const QJsonObject&)> done);
    void runtimeTransform(const QString& output, const QString& transform, std::function<void(bool, QString)> done);
    void armWatchdog(const QString& output, const QString& transform, int seconds);
    void disarmWatchdog();
    void clearPending();
    void setError(const QString& error);
    QString transformOf(const QString& output) const;
    // the file holding the block niri uses for `output`, following includes in order; "" when none
    QString blockFile(const QString& file, const QString& output, int depth) const;
    bool persist(const QString& output, const QString& transform, QString* message);

    QVariantList m_outputs;
    QString m_pendingOutput, m_pendingTransform, m_previousTransform;
    int m_secondsLeft = 0;
    QTimer m_tick;
    qint64 m_watchdog = 0;
    QString m_lastError, m_lastBackup;
};
