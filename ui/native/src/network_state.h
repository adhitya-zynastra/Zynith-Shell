#pragma once

#include <QDBusConnection>
#include <QDBusMessage>
#include <QDBusServiceWatcher>
#include <QHash>
#include <QObject>
#include <QTimer>
#include <QVariantList>
#include <QVariantMap>
#include <QtQml/qqmlregistration.h>

#include <functional>

// NetworkManager as the UI needs it. Always watched: NetworkManager's own object and the access point in
// use, which is a handful of signals a minute. The list of nearby networks (and the per-access-point signals
// behind it) exists only while something holds it (retain/release): in a dense Wi-Fi area following every
// access point costs tens of wakeups a second for nothing on screen.
class NetworkState : public QObject {
    Q_OBJECT
    QML_ELEMENT
    QML_SINGLETON

    Q_PROPERTY(bool available READ available NOTIFY changed)
    Q_PROPERTY(bool wifiEnabled READ wifiEnabled NOTIFY changed)
    Q_PROPERTY(bool connected READ connected NOTIFY changed)
    Q_PROPERTY(QString kind READ kind NOTIFY changed)       // "wifi" | "ethernet" | "other" | ""
    Q_PROPERTY(QString name READ name NOTIFY changed)       // active connection's name
    Q_PROPERTY(qreal strength READ strength NOTIFY changed) // 0..1, Wi-Fi only
    Q_PROPERTY(bool hasWifi READ hasWifi NOTIFY changed)
    // an active VPN (NetworkManager "vpn" or "wireguard" connection): its name, "" when none (the native
    // network widget's vpn_status / show_vpn_label)
    Q_PROPERTY(QString vpnName READ vpnName NOTIFY changed)
    // [{ ssid, strength, secured, known, connected, busy }], strongest first; empty unless retained
    Q_PROPERTY(QVariantList networks READ networks NOTIFY networksChanged)
    Q_PROPERTY(int consumers READ consumers NOTIFY consumersChanged)

public:
    explicit NetworkState(QObject* parent = nullptr);
    ~NetworkState() override;

    bool available() const { return m_available; }
    bool wifiEnabled() const { return m_wifiEnabled; }
    bool connected() const { return !m_primary.isEmpty() && m_primary != QLatin1String("/"); }
    QString kind() const { return m_kind; }
    QString name() const { return m_name; }
    qreal strength() const { return m_strength / 100.0; }
    bool hasWifi() const { return !m_wifiDevice.isEmpty(); }
    QString vpnName() const { return m_vpnName; }
    QVariantList networks() const { return m_networksOut; }
    int consumers() const { return m_consumers; }

    Q_INVOKABLE void retain();
    Q_INVOKABLE void release();
    Q_INVOKABLE void setWifiEnabled(bool on);
    Q_INVOKABLE void scan();
    // a saved network is activated as saved; a new one is added and NetworkManager asks the secret agent
    // (not this UI) for its password
    Q_INVOKABLE void connectTo(const QString& ssid);
    Q_INVOKABLE void disconnectActive();

signals:
    void changed();
    void networksChanged();
    void consumersChanged();

private slots:
    void onManagerProperties(const QString& iface, const QVariantMap& changed, const QStringList& invalidated);
    void onActiveApProperties(const QString& iface, const QVariantMap& changed, const QStringList& invalidated);
    void onAnyProperties(const QDBusMessage& message);
    void onAccessPointsChanged();
    void onSavedConnectionsChanged();

private:
    using Reply = std::function<void(const QDBusMessage&)>;
    void call(const QString& path, const QString& iface, const QString& method, const QVariantList& args, Reply reply = {});
    void getAll(const QString& path, const QString& iface, std::function<void(const QVariantMap&)> done);

    void refreshManager();
    void applyManager(const QVariantMap& props);
    void followPrimary();
    void followActive(const QVariantList& paths);
    void watchActiveAp(const QString& path);
    void findWifiDevice();

    void startList();
    void stopList();
    void loadAccessPoints();
    void loadSavedConnections();
    void publishNetworks();

    QDBusConnection m_bus;
    QDBusServiceWatcher m_watcher;

    bool m_available = false;
    bool m_wifiEnabled = false;
    QString m_primary;
    QString m_kind;
    QString m_name;
    int m_strength = 0;
    QString m_wifiDevice;
    QString m_activeAp;
    QString m_activeConnection;
    QString m_vpnName;
    int m_vpnQuery = 0;

    int m_consumers = 0;
    bool m_listing = false;
    QHash<QString, QVariantMap> m_aps;     // access point path -> { ssid, strength, secured }
    QHash<QString, QString> m_saved;       // ssid -> saved connection path
    QString m_pendingSsid;
    QTimer m_publish; // access points report in bursts; the list is rebuilt once per burst
    QVariantList m_networksOut;
};
