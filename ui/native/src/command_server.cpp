#include "command_server.h"

#include <QDir>
#include <QFile>
#include <QLocalSocket>

CommandServer::CommandServer(QObject* parent)
    : QObject(parent) {
    const QByteArray runtime = qgetenv("XDG_RUNTIME_DIR");
    if (runtime.isEmpty())
        return;
    const QString dir = QString::fromUtf8(runtime) + QStringLiteral("/zynith");
    QDir().mkpath(dir);
    QFile::setPermissions(dir, QFileDevice::ReadOwner | QFileDevice::WriteOwner | QFileDevice::ExeOwner);
    m_path = dir + QStringLiteral("/ui.sock");
    QLocalServer::removeServer(m_path);
    m_server.setSocketOptions(QLocalServer::UserAccessOption);
    if (!m_server.listen(m_path)) {
        qWarning("zynith: command socket unavailable: %s", qPrintable(m_server.errorString()));
        return;
    }
    connect(&m_server, &QLocalServer::newConnection, this, [this] {
        while (QLocalSocket* socket = m_server.nextPendingConnection()) {
            connect(socket, &QLocalSocket::readyRead, socket, [this, socket] {
                if (!socket->canReadLine() && socket->bytesAvailable() < 4096)
                    return;
                const QString line = QString::fromUtf8(socket->readLine(4096)).trimmed();
                const qsizetype space = line.indexOf(QLatin1Char(' '));
                emit command(space < 0 ? line : line.left(space), space < 0 ? QString() : line.mid(space + 1));
                socket->write("ok\n");
                socket->disconnectFromServer();
            });
            connect(socket, &QLocalSocket::disconnected, socket, &QObject::deleteLater);
        }
    });
    emit listeningChanged();
}

CommandServer::~CommandServer() {
    m_server.close();
    if (!m_path.isEmpty())
        QLocalServer::removeServer(m_path);
}
