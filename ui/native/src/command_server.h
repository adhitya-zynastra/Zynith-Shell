#pragma once

#include <QLocalServer>
#include <QObject>
#include <QtQml/qqmlregistration.h>

// A line socket for keybindings: `echo "launcher :" | socat - UNIX-CONNECT:$XDG_RUNTIME_DIR/zynith/ui.sock`
// arrives as command("launcher", ":"). Answers "ok" or what the handler returned. The directory is the user's
// only (0700), so the socket is as private as the runtime directory itself.
class CommandServer : public QObject {
    Q_OBJECT
    QML_ELEMENT
    QML_SINGLETON

    Q_PROPERTY(QString path READ path CONSTANT)
    Q_PROPERTY(bool listening READ listening NOTIFY listeningChanged)

public:
    explicit CommandServer(QObject* parent = nullptr);
    ~CommandServer() override;

    QString path() const { return m_path; }
    bool listening() const { return m_server.isListening(); }

signals:
    void command(const QString& name, const QString& args);
    void listeningChanged();

private:
    QString m_path;
    QLocalServer m_server;
    // the socket file this instance put in place: a live reload starts the next instance before this one
    // goes, so this one may only remove the file while it is still its own
    quint64 m_inode = 0;
};
