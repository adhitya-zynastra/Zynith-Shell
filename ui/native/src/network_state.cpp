#include "network_state.h"

#include <QDBusArgument>
#include <QDBusMetaType>
#include <QDBusObjectPath>
#include <QDBusPendingCallWatcher>
#include <QDBusVariant>

#include <algorithm>

namespace {

const QString kService = QStringLiteral("org.freedesktop.NetworkManager");
const QString kPath = QStringLiteral("/org/freedesktop/NetworkManager");
const QString kManager = QStringLiteral("org.freedesktop.NetworkManager");
const QString kProps = QStringLiteral("org.freedesktop.DBus.Properties");
const QString kActive = QStringLiteral("org.freedesktop.NetworkManager.Connection.Active");
const QString kDevice = QStringLiteral("org.freedesktop.NetworkManager.Device");
const QString kWireless = QStringLiteral("org.freedesktop.NetworkManager.Device.Wireless");
const QString kAp = QStringLiteral("org.freedesktop.NetworkManager.AccessPoint");
const QString kApPrefix = QStringLiteral("/org/freedesktop/NetworkManager/AccessPoint/");
const QString kSettingsPath = QStringLiteral("/org/freedesktop/NetworkManager/Settings");
const QString kSettings = QStringLiteral("org.freedesktop.NetworkManager.Settings");
const QString kSaved = QStringLiteral("org.freedesktop.NetworkManager.Settings.Connection");

using NMSettings = QMap<QString, QVariantMap>;

QString pathOf(const QVariant& v) { return v.value<QDBusObjectPath>().path(); }

QList<QDBusObjectPath> pathsOf(const QVariant& v) { return qdbus_cast<QList<QDBusObjectPath>>(v); }

QString kindOf(const QString& type) {
    if (type.isEmpty())
        return {};
    if (type == QLatin1String("802-11-wireless"))
        return QStringLiteral("wifi");
    if (type == QLatin1String("802-3-ethernet"))
        return QStringLiteral("ethernet");
    return QStringLiteral("other");
}

QVariantMap apEntry(const QVariantMap& props) {
    const bool secured = (props.value("Flags").toUInt() & 0x1) || props.value("WpaFlags").toUInt() || props.value("RsnFlags").toUInt();
    return {
        {"ssid", QString::fromUtf8(props.value("Ssid").toByteArray())},
        {"strength", props.value("Strength").toUInt()},
        {"secured", secured},
    };
}

} // namespace

Q_DECLARE_METATYPE(NMSettings)

NetworkState::NetworkState(QObject* parent)
    : QObject(parent)
    , m_bus(QDBusConnection::systemBus())
    , m_watcher(kService, m_bus, QDBusServiceWatcher::WatchForOwnerChange) {
    qDBusRegisterMetaType<NMSettings>();
    m_publish.setSingleShot(true);
    m_publish.setInterval(250);
    connect(&m_publish, &QTimer::timeout, this, &NetworkState::publishNetworks);

    connect(&m_watcher, &QDBusServiceWatcher::serviceOwnerChanged, this, [this](const QString&, const QString&, const QString& owner) {
        if (owner.isEmpty()) {
            m_available = false;
            m_primary.clear();
            m_kind.clear();
            m_name.clear();
            m_wifiDevice.clear();
            watchActiveAp({});
            emit changed();
        } else {
            refreshManager();
        }
    });
    m_bus.connect(kService, kPath, kProps, QStringLiteral("PropertiesChanged"), this,
                  SLOT(onManagerProperties(QString, QVariantMap, QStringList)));
    refreshManager();
}

NetworkState::~NetworkState() { m_publish.stop(); }

void NetworkState::call(const QString& path, const QString& iface, const QString& method, const QVariantList& args, Reply reply) {
    QDBusMessage message = QDBusMessage::createMethodCall(kService, path, iface, method);
    message.setArguments(args);
    auto* watcher = new QDBusPendingCallWatcher(m_bus.asyncCall(message), this);
    connect(watcher, &QDBusPendingCallWatcher::finished, this, [reply](QDBusPendingCallWatcher* w) {
        w->deleteLater();
        const QDBusMessage result = w->reply();
        if (result.type() == QDBusMessage::ErrorMessage)
            qWarning("zynith: NetworkManager %s: %s", qPrintable(result.errorName()), qPrintable(result.errorMessage()));
        if (reply)
            reply(result);
    });
}

void NetworkState::getAll(const QString& path, const QString& iface, std::function<void(const QVariantMap&)> done) {
    call(path, kProps, QStringLiteral("GetAll"), {iface}, [done](const QDBusMessage& reply) {
        if (reply.type() == QDBusMessage::ReplyMessage && !reply.arguments().isEmpty())
            done(qdbus_cast<QVariantMap>(reply.arguments().constFirst()));
    });
}

// ── always on: the manager and the access point in use ──────────────────────

void NetworkState::refreshManager() {
    getAll(kPath, kManager, [this](const QVariantMap& props) {
        m_available = true;
        applyManager(props);
        findWifiDevice();
    });
}

void NetworkState::onManagerProperties(const QString& iface, const QVariantMap& changed, const QStringList&) {
    if (iface == kManager)
        applyManager(changed);
}

void NetworkState::applyManager(const QVariantMap& props) {
    bool primaryMoved = false;
    if (props.contains("WirelessEnabled"))
        m_wifiEnabled = props.value("WirelessEnabled").toBool();
    if (props.contains("PrimaryConnection")) {
        const QString primary = pathOf(props.value("PrimaryConnection"));
        primaryMoved = primary != m_primary;
        m_primary = primary;
    }
    if (props.contains("PrimaryConnectionType"))
        m_kind = kindOf(props.value("PrimaryConnectionType").toString());
    if (props.contains("Devices") && m_wifiDevice.isEmpty())
        findWifiDevice();
    if (primaryMoved)
        followPrimary();
    emit changed();
}

void NetworkState::followPrimary() {
    m_pendingSsid.clear();
    if (!connected()) {
        m_name.clear();
        m_activeConnection.clear();
        watchActiveAp({});
        emit changed();
        m_publish.start();
        return;
    }
    const QString primary = m_primary;
    getAll(primary, kActive, [this, primary](const QVariantMap& props) {
        if (primary != m_primary)
            return;
        m_activeConnection = primary;
        m_name = props.value("Id").toString();
        const bool wifi = props.value("Type").toString() == QLatin1String("802-11-wireless");
        watchActiveAp(wifi ? pathOf(props.value("SpecificObject")) : QString());
        emit changed();
        m_publish.start();
    });
}

void NetworkState::watchActiveAp(const QString& path) {
    const QString next = path == QLatin1String("/") ? QString() : path;
    if (next == m_activeAp)
        return;
    if (!m_activeAp.isEmpty())
        m_bus.disconnect(kService, m_activeAp, kProps, QStringLiteral("PropertiesChanged"), this,
                         SLOT(onActiveApProperties(QString, QVariantMap, QStringList)));
    m_activeAp = next;
    m_strength = 0;
    if (m_activeAp.isEmpty())
        return;
    m_bus.connect(kService, m_activeAp, kProps, QStringLiteral("PropertiesChanged"), this,
                  SLOT(onActiveApProperties(QString, QVariantMap, QStringList)));
    const QString ap = m_activeAp;
    getAll(ap, kAp, [this, ap](const QVariantMap& props) {
        if (ap != m_activeAp)
            return;
        m_strength = props.value("Strength").toInt();
        emit changed();
    });
}

void NetworkState::onActiveApProperties(const QString& iface, const QVariantMap& changed, const QStringList&) {
    if (iface != kAp || !changed.contains("Strength"))
        return;
    const int strength = changed.value("Strength").toInt();
    if (strength != m_strength) {
        m_strength = strength;
        emit this->changed();
    }
}

void NetworkState::findWifiDevice() {
    call(kPath, kManager, QStringLiteral("GetDevices"), {}, [this](const QDBusMessage& reply) {
        if (reply.type() != QDBusMessage::ReplyMessage || reply.arguments().isEmpty())
            return;
        for (const QDBusObjectPath& device : pathsOf(reply.arguments().constFirst())) {
            const QString path = device.path();
            call(path, kProps, QStringLiteral("Get"), {kDevice, QStringLiteral("DeviceType")}, [this, path](const QDBusMessage& r) {
                if (r.type() != QDBusMessage::ReplyMessage || !m_wifiDevice.isEmpty())
                    return;
                if (r.arguments().constFirst().value<QDBusVariant>().variant().toUInt() == 2) { // NM_DEVICE_TYPE_WIFI
                    m_wifiDevice = path;
                    emit changed();
                    if (m_consumers > 0)
                        startList();
                }
            });
        }
    });
}

// ── on demand: nearby networks ──────────────────────────────────────────────

void NetworkState::retain() {
    if (++m_consumers == 1)
        startList();
    emit consumersChanged();
}

void NetworkState::release() {
    if (m_consumers == 0)
        return;
    if (--m_consumers == 0)
        stopList();
    emit consumersChanged();
}

void NetworkState::startList() {
    if (m_listing || m_wifiDevice.isEmpty())
        return;
    m_listing = true;
    m_bus.connect(kService, m_wifiDevice, kWireless, QStringLiteral("AccessPointAdded"), this, SLOT(onAccessPointsChanged()));
    m_bus.connect(kService, m_wifiDevice, kWireless, QStringLiteral("AccessPointRemoved"), this, SLOT(onAccessPointsChanged()));
    // every access point's changes, only while someone looks at the list
    m_bus.connect(kService, QString(), kProps, QStringLiteral("PropertiesChanged"), this, SLOT(onAnyProperties(QDBusMessage)));
    m_bus.connect(kService, kSettingsPath, kSettings, QStringLiteral("NewConnection"), this, SLOT(onSavedConnectionsChanged()));
    m_bus.connect(kService, kSettingsPath, kSettings, QStringLiteral("ConnectionRemoved"), this, SLOT(onSavedConnectionsChanged()));
    loadSavedConnections();
    loadAccessPoints();
    scan();
}

void NetworkState::stopList() {
    if (!m_listing)
        return;
    m_listing = false;
    m_bus.disconnect(kService, m_wifiDevice, kWireless, QStringLiteral("AccessPointAdded"), this, SLOT(onAccessPointsChanged()));
    m_bus.disconnect(kService, m_wifiDevice, kWireless, QStringLiteral("AccessPointRemoved"), this, SLOT(onAccessPointsChanged()));
    m_bus.disconnect(kService, QString(), kProps, QStringLiteral("PropertiesChanged"), this, SLOT(onAnyProperties(QDBusMessage)));
    m_bus.disconnect(kService, kSettingsPath, kSettings, QStringLiteral("NewConnection"), this, SLOT(onSavedConnectionsChanged()));
    m_bus.disconnect(kService, kSettingsPath, kSettings, QStringLiteral("ConnectionRemoved"), this, SLOT(onSavedConnectionsChanged()));
    m_publish.stop();
    m_aps.clear();
    m_saved.clear();
    if (!m_networksOut.isEmpty()) {
        m_networksOut.clear();
        emit networksChanged();
    }
}

void NetworkState::onAccessPointsChanged() { loadAccessPoints(); }

void NetworkState::onSavedConnectionsChanged() { loadSavedConnections(); }

void NetworkState::onAnyProperties(const QDBusMessage& message) {
    const QString path = message.path();
    if (!m_listing || !path.startsWith(kApPrefix) || !m_aps.contains(path) || message.arguments().size() < 2)
        return;
    const QVariantMap changed = qdbus_cast<QVariantMap>(message.arguments().at(1));
    if (changed.contains("Strength")) {
        m_aps[path]["strength"] = changed.value("Strength").toUInt();
        m_publish.start();
    }
}

void NetworkState::loadAccessPoints() {
    if (m_wifiDevice.isEmpty())
        return;
    call(m_wifiDevice, kWireless, QStringLiteral("GetAllAccessPoints"), {}, [this](const QDBusMessage& reply) {
        if (!m_listing || reply.type() != QDBusMessage::ReplyMessage || reply.arguments().isEmpty())
            return;
        QSet<QString> present;
        for (const QDBusObjectPath& ap : pathsOf(reply.arguments().constFirst())) {
            const QString path = ap.path();
            present.insert(path);
            if (m_aps.contains(path))
                continue;
            getAll(path, kAp, [this, path](const QVariantMap& props) {
                if (!m_listing)
                    return;
                m_aps.insert(path, apEntry(props));
                m_publish.start();
            });
        }
        for (auto it = m_aps.begin(); it != m_aps.end();)
            it = present.contains(it.key()) ? std::next(it) : m_aps.erase(it);
        m_publish.start();
    });
}

void NetworkState::loadSavedConnections() {
    call(kSettingsPath, kSettings, QStringLiteral("ListConnections"), {}, [this](const QDBusMessage& reply) {
        if (!m_listing || reply.type() != QDBusMessage::ReplyMessage || reply.arguments().isEmpty())
            return;
        m_saved.clear();
        for (const QDBusObjectPath& connection : pathsOf(reply.arguments().constFirst())) {
            const QString path = connection.path();
            // GetSettings never includes secrets
            call(path, kSaved, QStringLiteral("GetSettings"), {}, [this, path](const QDBusMessage& r) {
                if (!m_listing || r.type() != QDBusMessage::ReplyMessage || r.arguments().isEmpty())
                    return;
                const NMSettings settings = qdbus_cast<NMSettings>(r.arguments().constFirst());
                const QByteArray ssid = settings.value(QStringLiteral("802-11-wireless")).value(QStringLiteral("ssid")).toByteArray();
                if (!ssid.isEmpty()) {
                    m_saved.insert(QString::fromUtf8(ssid), path);
                    m_publish.start();
                }
            });
        }
    });
}

void NetworkState::publishNetworks() {
    QString activeSsid;
    if (!m_activeAp.isEmpty() && m_aps.contains(m_activeAp))
        activeSsid = m_aps.value(m_activeAp).value("ssid").toString();
    else if (m_kind == QLatin1String("wifi"))
        activeSsid = m_name; // usually the SSID; good enough until the access point is listed

    // one row per network name, at its strongest access point
    QHash<QString, QVariantMap> best;
    for (const QVariantMap& ap : std::as_const(m_aps)) {
        const QString ssid = ap.value("ssid").toString();
        if (ssid.isEmpty())
            continue;
        if (!best.contains(ssid) || best[ssid].value("strength").toUInt() < ap.value("strength").toUInt())
            best.insert(ssid, ap);
    }
    QList<QVariantMap> rows;
    for (auto it = best.cbegin(); it != best.cend(); ++it) {
        QVariantMap row = it.value();
        row["strength"] = row.value("strength").toUInt() / 100.0;
        row["known"] = m_saved.contains(it.key());
        row["connected"] = it.key() == activeSsid;
        row["busy"] = it.key() == m_pendingSsid;
        rows.append(row);
    }
    std::sort(rows.begin(), rows.end(), [](const QVariantMap& a, const QVariantMap& b) {
        if (a.value("connected").toBool() != b.value("connected").toBool())
            return a.value("connected").toBool();
        if (a.value("known").toBool() != b.value("known").toBool())
            return a.value("known").toBool();
        return a.value("strength").toDouble() > b.value("strength").toDouble();
    });
    QVariantList out;
    for (qsizetype i = 0; i < std::min<qsizetype>(rows.size(), 30); ++i)
        out.append(rows.at(i));
    if (out != m_networksOut) {
        m_networksOut = out;
        emit networksChanged();
    }
}

// ── actions ─────────────────────────────────────────────────────────────────

void NetworkState::setWifiEnabled(bool on) {
    call(kPath, kProps, QStringLiteral("Set"),
         {kManager, QStringLiteral("WirelessEnabled"), QVariant::fromValue(QDBusVariant(on))});
}

void NetworkState::scan() {
    if (!m_wifiDevice.isEmpty())
        call(m_wifiDevice, kWireless, QStringLiteral("RequestScan"), {QVariantMap()});
}

void NetworkState::connectTo(const QString& ssid) {
    if (m_wifiDevice.isEmpty() || ssid.isEmpty())
        return;
    m_pendingSsid = ssid;
    m_publish.start();
    const auto failed = [this](const QDBusMessage& reply) {
        if (reply.type() == QDBusMessage::ErrorMessage) {
            m_pendingSsid.clear();
            m_publish.start();
        }
    };
    if (m_saved.contains(ssid)) {
        call(kPath, kManager, QStringLiteral("ActivateConnection"),
             {QVariant::fromValue(QDBusObjectPath(m_saved.value(ssid))), QVariant::fromValue(QDBusObjectPath(m_wifiDevice)),
              QVariant::fromValue(QDBusObjectPath(QStringLiteral("/")))},
             failed);
        return;
    }
    QString ap = QStringLiteral("/");
    uint strongest = 0;
    for (auto it = m_aps.cbegin(); it != m_aps.cend(); ++it) {
        if (it.value().value("ssid").toString() == ssid && it.value().value("strength").toUInt() >= strongest) {
            strongest = it.value().value("strength").toUInt();
            ap = it.key();
        }
    }
    call(kPath, kManager, QStringLiteral("AddAndActivateConnection"),
         {QVariant::fromValue(NMSettings()), QVariant::fromValue(QDBusObjectPath(m_wifiDevice)), QVariant::fromValue(QDBusObjectPath(ap))},
         failed);
}

void NetworkState::disconnectActive() {
    if (!m_activeConnection.isEmpty())
        call(kPath, kManager, QStringLiteral("DeactivateConnection"), {QVariant::fromValue(QDBusObjectPath(m_activeConnection))});
}
