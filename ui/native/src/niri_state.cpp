#include "niri_state.h"

#include <QJsonArray>
#include <QJsonDocument>
#include <algorithm>

namespace {

QString socketPath() { return qEnvironmentVariable("NIRI_SOCKET"); }

qulonglong idOf(const QJsonValue& v) { return static_cast<qulonglong>(v.toInteger(-1)); }

} // namespace

NiriState::NiriState(QObject* parent)
    : QObject(parent) {
    m_retry.setSingleShot(true);
    connect(&m_retry, &QTimer::timeout, this, &NiriState::connectStream);
    connect(&m_stream, &QLocalSocket::connected, this, [this] {
        m_retryMs = 500;
        m_buffer.clear();
        m_replied = false;
        m_stream.write("\"EventStream\"\n");
        setConnected(true);
    });
    connect(&m_stream, &QLocalSocket::readyRead, this, &NiriState::onReadyRead);
    connect(&m_stream, &QLocalSocket::disconnected, this, &NiriState::onDisconnected);
    connect(&m_stream, &QLocalSocket::errorOccurred, this, [this](QLocalSocket::LocalSocketError) { onDisconnected(); });
    connectStream();
}

void NiriState::connectStream() {
    const QString path = socketPath();
    if (path.isEmpty())
        return; // not a niri session
    if (m_stream.state() != QLocalSocket::UnconnectedState)
        m_stream.abort();
    m_stream.connectToServer(path);
}

void NiriState::onDisconnected() {
    setConnected(false);
    if (m_retry.isActive())
        return;
    // back off: a restarting compositor should not be hammered, a brief hiccup should recover quickly
    m_retry.start(m_retryMs);
    m_retryMs = std::min(m_retryMs * 2, 30000);
}

void NiriState::onReadyRead() {
    m_buffer += m_stream.readAll();
    qsizetype nl;
    while ((nl = m_buffer.indexOf('\n')) >= 0) {
        const QByteArray line = m_buffer.left(nl);
        m_buffer.remove(0, nl + 1);
        const QJsonDocument doc = QJsonDocument::fromJson(line);
        if (!doc.isObject())
            continue;
        if (!m_replied) {
            m_replied = true; // {"Ok":"Handled"}
            continue;
        }
        handleEvent(doc.object());
    }
    publish();
}

void NiriState::handleEvent(const QJsonObject& event) {
    if (event.isEmpty())
        return;
    const QString kind = event.begin().key();
    const QJsonObject body = event.begin().value().toObject();

    if (kind == QLatin1String("WorkspacesChanged")) {
        m_workspaces.clear();
        for (const QJsonValue& w : body.value("workspaces").toArray())
            m_workspaces.insert(idOf(w.toObject().value("id")), w.toObject());
    } else if (kind == QLatin1String("WorkspaceActivated")) {
        const qulonglong id = idOf(body.value("id"));
        const bool focused = body.value("focused").toBool();
        const QString output = m_workspaces.value(id).value("output").toString();
        for (auto it = m_workspaces.begin(); it != m_workspaces.end(); ++it) {
            if (it.value().value("output").toString() == output)
                it.value()["is_active"] = it.key() == id;
            if (focused)
                it.value()["is_focused"] = it.key() == id;
        }
    } else if (kind == QLatin1String("WorkspaceActiveWindowChanged")) {
        const qulonglong id = idOf(body.value("workspace_id"));
        if (m_workspaces.contains(id))
            m_workspaces[id]["active_window_id"] = body.value("active_window_id");
    } else if (kind == QLatin1String("WorkspaceUrgencyChanged")) {
        const qulonglong id = idOf(body.value("id"));
        if (m_workspaces.contains(id))
            m_workspaces[id]["is_urgent"] = body.value("urgent");
    } else if (kind == QLatin1String("WindowsChanged")) {
        m_windows.clear();
        for (const QJsonValue& w : body.value("windows").toArray())
            m_windows.insert(idOf(w.toObject().value("id")), w.toObject());
    } else if (kind == QLatin1String("WindowOpenedOrChanged")) {
        const QJsonObject window = body.value("window").toObject();
        const qulonglong id = idOf(window.value("id"));
        if (window.value("is_focused").toBool()) {
            for (auto it = m_windows.begin(); it != m_windows.end(); ++it)
                it.value()["is_focused"] = false;
        }
        m_windows.insert(id, window);
    } else if (kind == QLatin1String("WindowClosed")) {
        m_windows.remove(idOf(body.value("id")));
    } else if (kind == QLatin1String("WindowFocusChanged")) {
        const qulonglong id = body.value("id").isNull() ? qulonglong(-1) : idOf(body.value("id"));
        for (auto it = m_windows.begin(); it != m_windows.end(); ++it)
            it.value()["is_focused"] = it.key() == id;
    } else if (kind == QLatin1String("WindowUrgencyChanged")) {
        const qulonglong id = idOf(body.value("id"));
        if (m_windows.contains(id))
            m_windows[id]["is_urgent"] = body.value("urgent");
    } else if (kind == QLatin1String("OverviewOpenedOrClosed")) {
        const bool open = body.value("is_open").toBool();
        if (open != m_overviewOpen) {
            m_overviewOpen = open;
            emit overviewOpenChanged();
        }
    } else if (kind == QLatin1String("KeyboardLayoutsChanged")) {
        const QJsonObject layouts = body.value("keyboard_layouts").toObject();
        m_layoutNames.clear();
        for (const QJsonValue& n : layouts.value("names").toArray())
            m_layoutNames << n.toString();
        m_layoutIdx = layouts.value("current_idx").toInt();
    } else if (kind == QLatin1String("KeyboardLayoutSwitched")) {
        m_layoutIdx = body.value("idx").toInt();
    }
    // WindowLayoutsChanged, ConfigLoaded, CastsChanged, … are not used by the UI yet
}

void NiriState::publish() {
    QHash<qulonglong, int> counts;
    for (const QJsonObject& w : std::as_const(m_windows)) {
        const QJsonValue ws = w.value("workspace_id");
        if (!ws.isNull())
            counts[idOf(ws)]++;
    }

    QList<QJsonObject> sorted = m_workspaces.values();
    std::sort(sorted.begin(), sorted.end(), [](const QJsonObject& a, const QJsonObject& b) {
        const QString oa = a.value("output").toString(), ob = b.value("output").toString();
        return oa != ob ? oa < ob : a.value("idx").toInt() < b.value("idx").toInt();
    });

    QVariantList out;
    out.reserve(sorted.size());
    for (const QJsonObject& w : sorted) {
        const qulonglong id = idOf(w.value("id"));
        out.append(QVariantMap{
            {"id", id},
            {"idx", w.value("idx").toInt()},
            {"name", w.value("name").toString()},
            {"output", w.value("output").toString()},
            {"active", w.value("is_active").toBool()},
            {"focused", w.value("is_focused").toBool()},
            {"urgent", w.value("is_urgent").toBool()},
            {"windows", counts.value(id)},
        });
    }
    if (out != m_workspacesOut) {
        m_workspacesOut = out;
        emit workspacesChanged();
    }

    QVariantMap focused;
    for (const QJsonObject& w : std::as_const(m_windows)) {
        if (w.value("is_focused").toBool()) {
            focused = QVariantMap{
                {"id", idOf(w.value("id"))},
                {"title", w.value("title").toString()},
                {"appId", w.value("app_id").toString()},
                {"workspaceId", idOf(w.value("workspace_id"))},
                {"floating", w.value("is_floating").toBool()},
            };
            break;
        }
    }
    if (focused != m_focusedOut) {
        m_focusedOut = focused;
        emit focusedWindowChanged();
    }

    const QString layout = m_layoutIdx >= 0 && m_layoutIdx < m_layoutNames.size() ? m_layoutNames.at(m_layoutIdx) : QString();
    if (layout != m_layoutOut) {
        m_layoutOut = layout;
        emit keyboardLayoutChanged();
    }
}

bool NiriState::activeWorkspaceOccupied(const QString& output) const {
    for (const QVariant& v : m_workspacesOut) {
        const QVariantMap w = v.toMap();
        if (w.value("output").toString() == output && w.value("active").toBool())
            return w.value("windows").toInt() > 0;
    }
    return false;
}

void NiriState::focusWorkspace(qulonglong id) {
    action(QVariantMap{{"FocusWorkspace", QVariantMap{{"reference", QVariantMap{{"Id", id}}}}}});
}

void NiriState::action(const QVariantMap& action) {
    const QString path = socketPath();
    if (path.isEmpty())
        return;
    // niri answers one request per connection; the socket deletes itself when niri closes it
    auto* socket = new QLocalSocket(this);
    const QByteArray request = QJsonDocument(QJsonObject{{"Action", QJsonObject::fromVariantMap(action)}}).toJson(QJsonDocument::Compact) + '\n';
    connect(socket, &QLocalSocket::connected, socket, [socket, request] { socket->write(request); });
    connect(socket, &QLocalSocket::readyRead, socket, [socket] {
        const QByteArray reply = socket->readAll();
        if (!reply.contains("\"Ok\""))
            qWarning("zynith: niri refused an action: %s", reply.constData());
        socket->disconnectFromServer();
    });
    connect(socket, &QLocalSocket::disconnected, socket, &QObject::deleteLater);
    connect(socket, &QLocalSocket::errorOccurred, socket, [socket](QLocalSocket::LocalSocketError) { socket->deleteLater(); });
    socket->connectToServer(path);
}

void NiriState::setConnected(bool connected) {
    if (connected == m_connected)
        return;
    m_connected = connected;
    emit connectedChanged();
}
