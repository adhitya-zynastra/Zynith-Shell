#pragma once

#include <QObject>
#include <QProcess>
#include <QString>
#include <QtQml/qqmlregistration.h>

// Writes generated niri config fragments (rice/<name>.kdl). A fragment is only installed after niri has
// validated the whole configuration with it in place, and it replaces the old one atomically; niri then
// reloads by itself. One write at a time; a newer request replaces a queued one.
class NiriConfig : public QObject {
    Q_OBJECT
    QML_ELEMENT
    QML_SINGLETON

    Q_PROPERTY(bool busy READ busy NOTIFY busyChanged)
    Q_PROPERTY(QString lastError READ lastError NOTIFY lastErrorChanged)

public:
    explicit NiriConfig(QObject* parent = nullptr);
    ~NiriConfig() override;

    bool busy() const { return m_process != nullptr; }
    QString lastError() const { return m_lastError; }

    // true when config.kdl includes rice/<name>.kdl
    Q_INVOKABLE bool isIncluded(const QString& name) const;
    // the fragment's current text, or "" when it does not exist
    Q_INVOKABLE QString read(const QString& name) const;
    // validate and install; `applied` reports the outcome. Unchanged text is a no-op that succeeds.
    Q_INVOKABLE void apply(const QString& name, const QString& text);

signals:
    void busyChanged();
    void lastErrorChanged();
    void applied(const QString& name, bool ok, const QString& message);

private:
    void startNext();
    void finish(bool ok, const QString& message);
    void setError(const QString& error);

    QString m_dir;
    QProcess* m_process = nullptr;
    QString m_name, m_staged, m_probe;
    bool m_hasPending = false;
    QString m_pendingName, m_pendingText;
    QString m_lastError;
};
