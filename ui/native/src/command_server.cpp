#include "command_server.h"

#include <QCoreApplication>
#include <QDir>
#include <QFile>
#include <QLocalSocket>

#include <atomic>
#include <cstdio>
#include <sys/stat.h>
#include <unistd.h>

namespace {
quint64 inodeOf(const QString& path) {
    struct stat st{};
    return ::stat(QFile::encodeName(path).constData(), &st) == 0 ? quint64(st.st_ino) : 0;
}
} // namespace

CommandServer::CommandServer(QObject* parent)
    : QObject(parent) {
    const QByteArray runtime = qgetenv("XDG_RUNTIME_DIR");
    if (runtime.isEmpty())
        return;
    const QString dir = QString::fromUtf8(runtime) + QStringLiteral("/zynith");
    QDir().mkpath(dir);
    QFile::setPermissions(dir, QFileDevice::ReadOwner | QFileDevice::WriteOwner | QFileDevice::ExeOwner);
    m_path = dir + QStringLiteral("/ui.sock");
    // Qt unlinks a server's path when it closes. Listening on a private name and renaming it into place
    // means the instance a reload replaces only ever unlinks its own, already moved, name.
    static std::atomic<int> generation{0};
    const QString staging = m_path + QStringLiteral(".%1.%2").arg(QCoreApplication::applicationPid()).arg(generation++);
    QLocalServer::removeServer(staging);
    m_server.setSocketOptions(QLocalServer::UserAccessOption);
    if (!m_server.listen(staging)) {
        qWarning("zynith: command socket unavailable: %s", qPrintable(m_server.errorString()));
        return;
    }
    if (::rename(QFile::encodeName(staging).constData(), QFile::encodeName(m_path).constData()) != 0) {
        qWarning("zynith: command socket not moved into place");
        m_server.close();
        return;
    }
    m_inode = inodeOf(m_path);
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
    if (m_inode != 0 && inodeOf(m_path) == m_inode)
        QFile::remove(m_path);
}
