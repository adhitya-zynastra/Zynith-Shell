#include "core_client.h"

#include <QSocketNotifier>

#include <cerrno>
#include <cstring>
#include <fcntl.h>
#include <sys/socket.h>
#include <sys/un.h>
#include <unistd.h>

namespace {

// one request in flight; owns its socket and deletes itself when the reply is complete
class Request : public QObject {
public:
    Request(int fd, QJSValue callback, QObject* parent)
        : QObject(parent)
        , m_fd(fd)
        , m_callback(std::move(callback))
        , m_notifier(fd, QSocketNotifier::Read, this) {
        connect(&m_notifier, &QSocketNotifier::activated, this, [this] { readMore(); });
    }

    ~Request() override {
        m_notifier.setEnabled(false);
        if (m_fd >= 0)
            ::close(m_fd);
    }

    void finish() {
        m_notifier.setEnabled(false);
        if (m_callback.isCallable())
            m_callback.call({QJSValue(QString::fromUtf8(m_reply))});
        deleteLater();
    }

private:
    void readMore() {
        char buf[8192];
        for (;;) {
            const ssize_t n = ::read(m_fd, buf, sizeof buf);
            if (n > 0) {
                m_reply.append(buf, n);
                continue;
            }
            if (n < 0 && (errno == EAGAIN || errno == EINTR))
                return; // more later
            finish(); // EOF or error
            return;
        }
    }

    int m_fd;
    QJSValue m_callback;
    QByteArray m_reply;
    QSocketNotifier m_notifier;
};

} // namespace

CoreClient::CoreClient(QObject* parent)
    : QObject(parent) {
    const QByteArray runtime = qgetenv("XDG_RUNTIME_DIR");
    const QByteArray display = qgetenv("WAYLAND_DISPLAY");
    m_path = QString::fromUtf8(runtime.isEmpty() ? QByteArray("/tmp") : runtime) + QStringLiteral("/zynith-shell-")
             + QString::fromUtf8(display.isEmpty() ? QByteArray("wayland-0") : display) + QStringLiteral(".sock");
}

void CoreClient::call(const QString& command, const QJSValue& callback) {
    const auto fail = [&] {
        if (callback.isCallable())
            QJSValue(callback).call({QJSValue(QString())});
    };
    const int fd = ::socket(AF_UNIX, SOCK_STREAM | SOCK_CLOEXEC, 0);
    if (fd < 0)
        return fail();
    sockaddr_un addr{};
    addr.sun_family = AF_UNIX;
    const QByteArray path = m_path.toLocal8Bit();
    if (path.size() >= qsizetype(sizeof addr.sun_path)) {
        ::close(fd);
        return fail();
    }
    std::memcpy(addr.sun_path, path.constData(), size_t(path.size()) + 1);
    // a local connect and a short write complete at once; the reply is read without blocking
    if (::connect(fd, reinterpret_cast<const sockaddr*>(&addr), sizeof addr) < 0) {
        ::close(fd);
        return fail();
    }
    const QByteArray line = command.toUtf8();
    qsizetype sent = 0;
    while (sent < line.size()) {
        const ssize_t n = ::send(fd, line.constData() + sent, size_t(line.size() - sent), MSG_NOSIGNAL);
        if (n <= 0) {
            ::close(fd);
            return fail();
        }
        sent += n;
    }
    // the shell reads to EOF: without this half-close it would wait out its receive timeout
    ::shutdown(fd, SHUT_WR);
    ::fcntl(fd, F_SETFL, ::fcntl(fd, F_GETFL) | O_NONBLOCK);
    new Request(fd, callback, this);
}
