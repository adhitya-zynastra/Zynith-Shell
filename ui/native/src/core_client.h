#pragma once

#include <QJSValue>
#include <QObject>
#include <QString>
#include <QtQml/qqmlregistration.h>

class QSocketNotifier;

// Talks to the native shell's IPC socket directly: one connection per call, the command written and the write
// side closed, the reply read to EOF, all on the event loop. Replaces spawning `noctalia msg` for each call
// (a process start per panel open) until the helper protocol exists.
class CoreClient : public QObject {
    Q_OBJECT
    QML_ELEMENT
    QML_SINGLETON

    Q_PROPERTY(QString socketPath READ socketPath CONSTANT)

public:
    explicit CoreClient(QObject* parent = nullptr);

    QString socketPath() const { return m_path; }

    // `callback(reply)` runs with the reply text ("" when the shell could not be reached)
    Q_INVOKABLE void call(const QString& command, const QJSValue& callback = QJSValue());

private:
    QString m_path;
};
