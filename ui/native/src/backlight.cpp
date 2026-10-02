#include "backlight.h"

#include <QDBusConnection>
#include <QDBusMessage>
#include <QDBusPendingCallWatcher>
#include <QDir>
#include <QFile>

#include <algorithm>

namespace {

int readInt(const QString& path) {
    QFile f(path);
    return f.open(QIODevice::ReadOnly) ? f.readAll().trimmed().toInt() : 0;
}

// firmware interfaces know the panel best, raw ones least (the order systemd-backlight uses)
int rank(const QString& dir) {
    QFile f(dir + QStringLiteral("/type"));
    const QByteArray type = f.open(QIODevice::ReadOnly) ? f.readAll().trimmed() : QByteArray();
    return type == "firmware" ? 3 : type == "platform" ? 2 : type == "raw" ? 1 : 0;
}

} // namespace

Backlight::Backlight(QObject* parent)
    : QObject(parent) {
    const QDir base(QStringLiteral("/sys/class/backlight"));
    int best = -1;
    for (const QString& name : base.entryList(QDir::Dirs | QDir::NoDotAndDotDot | QDir::System)) {
        const QString dir = base.filePath(name);
        if (rank(dir) > best && readInt(dir + QStringLiteral("/max_brightness")) > 0) {
            best = rank(dir);
            m_device = name;
            m_dir = dir;
        }
    }
    if (!m_dir.isEmpty()) {
        m_max = readInt(m_dir + QStringLiteral("/max_brightness"));
        m_current = readInt(m_dir + QStringLiteral("/brightness"));
    }
    m_poll.setInterval(1000);
    connect(&m_poll, &QTimer::timeout, this, &Backlight::read);
}

Backlight::~Backlight() { m_poll.stop(); }

void Backlight::retain() {
    if (++m_consumers == 1 && available()) {
        read();
        m_poll.start();
    }
}

void Backlight::release() {
    if (m_consumers > 0 && --m_consumers == 0)
        m_poll.stop();
}

void Backlight::read() {
    const int current = readInt(m_dir + QStringLiteral("/brightness"));
    if (current != m_current && !m_inFlight && m_wanted < 0) {
        m_current = current;
        emit valueChanged();
    }
}

void Backlight::set(qreal value) {
    if (!available())
        return;
    const int raw = std::clamp(int(value * m_max + 0.5), std::max(1, m_max / 100), m_max);
    if (raw == m_current && m_wanted < 0)
        return;
    m_current = raw;
    emit valueChanged();
    m_wanted = raw;
    if (!m_inFlight)
        send();
}

// one call in flight at a time; a drag sends its latest position, not every step
void Backlight::send() {
    if (m_wanted < 0)
        return;
    const uint raw = uint(m_wanted);
    m_wanted = -1;
    m_inFlight = true;
    QDBusMessage message = QDBusMessage::createMethodCall(
        QStringLiteral("org.freedesktop.login1"), QStringLiteral("/org/freedesktop/login1/session/auto"),
        QStringLiteral("org.freedesktop.login1.Session"), QStringLiteral("SetBrightness"));
    message.setArguments({QStringLiteral("backlight"), m_device, raw});
    auto* watcher = new QDBusPendingCallWatcher(QDBusConnection::systemBus().asyncCall(message), this);
    connect(watcher, &QDBusPendingCallWatcher::finished, this, [this](QDBusPendingCallWatcher* w) {
        w->deleteLater();
        if (w->isError())
            qWarning("zynith: brightness not set: %s", qPrintable(w->error().message()));
        m_inFlight = false;
        send();
    });
}
