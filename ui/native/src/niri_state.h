#pragma once

#include <QHash>
#include <QJsonObject>
#include <QLocalSocket>
#include <QObject>
#include <QTimer>
#include <QVariantList>
#include <QVariantMap>
#include <QtQml/qqmlregistration.h>

// niri's state as the UI needs it, from one event-stream connection. Properties change only when their
// value changes, so bindings wake for real changes only.
class NiriState : public QObject {
    Q_OBJECT
    QML_ELEMENT
    QML_SINGLETON

    Q_PROPERTY(bool connected READ connected NOTIFY connectedChanged)
    Q_PROPERTY(bool overviewOpen READ overviewOpen NOTIFY overviewOpenChanged)
    Q_PROPERTY(QVariantList workspaces READ workspaces NOTIFY workspacesChanged)
    Q_PROPERTY(QVariantMap focusedWindow READ focusedWindow NOTIFY focusedWindowChanged)
    Q_PROPERTY(QString keyboardLayout READ keyboardLayout NOTIFY keyboardLayoutChanged)
    // every configured layout, so a single one can be told apart
    Q_PROPERTY(QStringList keyboardLayouts READ keyboardLayouts NOTIFY keyboardLayoutChanged)

public:
    explicit NiriState(QObject* parent = nullptr);
    ~NiriState() override;

    bool connected() const { return m_connected; }
    bool overviewOpen() const { return m_overviewOpen; }
    QVariantList workspaces() const { return m_workspacesOut; }
    QVariantMap focusedWindow() const { return m_focusedOut; }
    QString keyboardLayout() const { return m_layoutOut; }
    QStringList keyboardLayouts() const { return m_layoutNames; }

    // true when the active workspace on `output` has at least one window
    Q_INVOKABLE bool activeWorkspaceOccupied(const QString& output) const;
    Q_INVOKABLE void focusWorkspace(qulonglong id);
    // every open window, most recently focused first: [{ id, title, appId, workspaceId, focused }]; built on
    // request so window titles changing all day cost nothing
    Q_INVOKABLE QVariantList windowList() const;
    Q_INVOKABLE void focusWindow(qulonglong id);
    // `action` is one niri Action object, e.g. {"FocusWorkspace": {"reference": {"Id": 3}}}
    Q_INVOKABLE void action(const QVariantMap& action);

signals:
    void connectedChanged();
    void overviewOpenChanged();
    void workspacesChanged();
    void focusedWindowChanged();
    void keyboardLayoutChanged();

private:
    void connectStream();
    void onReadyRead();
    void onDisconnected();
    void handleEvent(const QJsonObject& event);
    void publish();
    void setConnected(bool connected);

    QLocalSocket m_stream;
    QTimer m_retry;
    int m_retryMs = 500;
    QByteArray m_buffer;
    bool m_replied = false;

    QHash<qulonglong, QJsonObject> m_workspaces;
    QHash<qulonglong, QJsonObject> m_windows;
    QStringList m_layoutNames;
    int m_layoutIdx = 0;

    bool m_connected = false;
    bool m_overviewOpen = false;
    QVariantList m_workspacesOut;
    QVariantMap m_focusedOut;
    QString m_layoutOut;
};
