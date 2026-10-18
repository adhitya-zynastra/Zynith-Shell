#include "display_config.h"

#include <QDateTime>
#include <QDir>
#include <QFile>
#include <QFileInfo>
#include <QJsonArray>
#include <QJsonDocument>
#include <QJsonObject>
#include <QLocalSocket>
#include <QProcess>
#include <QRegularExpression>
#include <QSaveFile>
#include <QStandardPaths>

#include <csignal>

namespace {

QString socketPath() { return qEnvironmentVariable("NIRI_SOCKET"); }
QString niriDir() { return QStandardPaths::writableLocation(QStandardPaths::GenericConfigLocation) + QStringLiteral("/niri"); }

QString readFile(const QString& path) {
    QFile f(path);
    return f.open(QIODevice::ReadOnly) ? QString::fromUtf8(f.readAll()) : QString();
}

const QStringList kTransforms = {QStringLiteral("normal"), QStringLiteral("90"), QStringLiteral("180"), QStringLiteral("270"),
                                 QStringLiteral("flipped"), QStringLiteral("flipped-90"), QStringLiteral("flipped-180"),
                                 QStringLiteral("flipped-270")};

// a top-level line, outside comments: strips `//` comments (KDL strings in these lines hold no `//`)
QString code(const QString& line) {
    const int c = line.indexOf(QStringLiteral("//"));
    return c >= 0 ? line.left(c) : line;
}

// [start, end] line indices of the first top-level `output "<name>" { … }` block, or {-1, -1}
std::pair<int, int> findBlock(const QStringList& lines, const QString& output) {
    const QRegularExpression head(QStringLiteral("^\\s*output\\s+\"%1\"\\s*\\{").arg(QRegularExpression::escape(output)));
    int depth = 0;
    for (int i = 0; i < lines.size(); ++i) {
        const QString c = code(lines[i]);
        if (depth == 0 && head.match(c).hasMatch()) {
            int d = 0;
            for (int j = i; j < lines.size(); ++j) {
                const QString cj = code(lines[j]);
                d += cj.count('{') - cj.count('}');
                if (d <= 0)
                    return {i, j};
            }
            return {i, int(lines.size()) - 1};
        }
        depth += c.count('{') - c.count('}');
    }
    return {-1, -1};
}

// niri's IPC spelling of a transform (serde of niri_ipc::Transform): "Normal", "90", "Flipped", "Flipped90"… The CLI's
// lowercase names are refused by the IPC ("error parsing request") — the first hardware test reverted to "normal",
// was refused, and stayed rotated.
QString ipcName(const QString& canonicalName) {
    if (canonicalName == QStringLiteral("normal"))
        return QStringLiteral("Normal");
    if (canonicalName == QStringLiteral("flipped"))
        return QStringLiteral("Flipped");
    if (canonicalName.startsWith(QStringLiteral("flipped-")))
        return QStringLiteral("Flipped") + canonicalName.mid(8);
    return canonicalName;
}

} // namespace

DisplayConfig::DisplayConfig(QObject* parent)
    : QObject(parent) {
    m_tick.setInterval(1000);
    connect(&m_tick, &QTimer::timeout, this, [this] {
        if (m_secondsLeft > 0) {
            --m_secondsLeft;
            emit secondsLeftChanged();
        }
        if (m_secondsLeft <= 0)
            revert();
    });
    refresh();
}

DisplayConfig::~DisplayConfig() {
    // a change still waiting is undone with the UI: the watchdog would do it anyway, a moment later
    if (pending())
        revert();
}

QString DisplayConfig::canonical(const QString& t) {
    QString s = t.trimmed().toLower();
    if (s.startsWith('_'))
        s.remove(0, 1);
    s.replace(QStringLiteral("flipped"), QStringLiteral("flipped-"));
    s.replace(QStringLiteral("--"), QStringLiteral("-"));
    if (s.endsWith('-'))
        s.chop(1);
    return kTransforms.contains(s) ? s : QString();
}

void DisplayConfig::setError(const QString& error) {
    if (error == m_lastError)
        return;
    m_lastError = error;
    emit lastErrorChanged();
}

void DisplayConfig::request(const QByteArray& json, std::function<void(const QJsonObject&)> done) {
    const QString path = socketPath();
    if (path.isEmpty()) {
        done(QJsonObject{{"Err", QStringLiteral("not a niri session")}});
        return;
    }
    auto* socket = new QLocalSocket(this);
    auto buffer = std::make_shared<QByteArray>();
    connect(socket, &QLocalSocket::connected, socket, [socket, json] { socket->write(json + '\n'); });
    connect(socket, &QLocalSocket::readyRead, socket, [socket, buffer, done] {
        buffer->append(socket->readAll());
        if (!buffer->contains('\n'))
            return;
        done(QJsonDocument::fromJson(buffer->left(buffer->indexOf('\n'))).object());
        socket->disconnectFromServer();
    });
    connect(socket, &QLocalSocket::disconnected, socket, &QObject::deleteLater);
    connect(socket, &QLocalSocket::errorOccurred, socket, [socket, done](QLocalSocket::LocalSocketError) {
        done(QJsonObject{{"Err", socket->errorString()}});
        socket->deleteLater();
    });
    socket->connectToServer(path);
}

void DisplayConfig::refresh() {
    request(QByteArrayLiteral("\"Outputs\""), [this](const QJsonObject& reply) {
        const QJsonObject outputs = reply.value("Ok").toObject().value("Outputs").toObject();
        QVariantList list;
        for (auto it = outputs.begin(); it != outputs.end(); ++it) {
            const QJsonObject o = it.value().toObject();
            const QJsonObject logical = o.value("logical").toObject();
            const QJsonArray modes = o.value("modes").toArray();
            const int current = o.value("current_mode").toInt(-1);
            const QJsonObject mode = current >= 0 && current < modes.size() ? modes[current].toObject() : QJsonObject();
            list.append(QVariantMap{
                {"name", it.key()},
                {"make", o.value("make").toString()},
                {"model", o.value("model").toString()},
                {"enabled", !logical.isEmpty()},
                {"x", logical.value("x").toInt()},
                {"y", logical.value("y").toInt()},
                {"width", logical.value("width").toInt()},
                {"height", logical.value("height").toInt()},
                {"scale", logical.value("scale").toDouble(1)},
                {"transform", canonical(logical.value("transform").toString())},
                {"modeWidth", mode.value("width").toInt()},
                {"modeHeight", mode.value("height").toInt()},
            });
        }
        m_outputs = list;
        emit outputsChanged();
    });
}

QString DisplayConfig::transformOf(const QString& output) const {
    for (const QVariant& v : m_outputs) {
        const QVariantMap o = v.toMap();
        if (o.value("name").toString() == output)
            return o.value("transform").toString();
    }
    return QString();
}

void DisplayConfig::runtimeTransform(const QString& output, const QString& transform, std::function<void(bool, QString)> done) {
    const QJsonObject req{{"Output", QJsonObject{{"output", output}, {"action", QJsonObject{{"Transform", QJsonObject{{"transform", ipcName(transform)}}}}}}}};
    request(QJsonDocument(req).toJson(QJsonDocument::Compact), [done](const QJsonObject& reply) {
        const QString changed = reply.value("Ok").toObject().value("OutputConfigChanged").toString();
        if (changed == QStringLiteral("Applied"))
            done(true, QString());
        else if (changed == QStringLiteral("OutputWasMissing"))
            done(false, QStringLiteral("That display is no longer connected"));
        else
            done(false, reply.value("Err").toString(QStringLiteral("niri refused the change")));
    });
}

void DisplayConfig::armWatchdog(const QString& output, const QString& transform, int seconds) {
    disarmWatchdog();
    // its own session: it outlives this process (a crash, a freeze ended by a restart) and puts the old transform back
    const QString script = QStringLiteral("sleep %1; niri msg output '%2' transform '%3'").arg(seconds).arg(output, transform);
    QProcess::startDetached(QStringLiteral("setsid"), {QStringLiteral("sh"), QStringLiteral("-c"), script}, QString(), &m_watchdog);
}

void DisplayConfig::disarmWatchdog() {
    if (m_watchdog > 0)
        ::kill(pid_t(m_watchdog), SIGTERM);
    m_watchdog = 0;
}

void DisplayConfig::clearPending() {
    m_tick.stop();
    m_pendingOutput.clear();
    m_pendingTransform.clear();
    m_previousTransform.clear();
    m_secondsLeft = 0;
    emit pendingChanged();
    emit secondsLeftChanged();
}

void DisplayConfig::setTransform(const QString& output, const QString& transform, int seconds) {
    const QString t = canonical(transform);
    if (t.isEmpty()) {
        setError(QStringLiteral("Unknown orientation: %1").arg(transform));
        emit applied(output, false, m_lastError);
        return;
    }
    // a change already waiting: the new one starts from the orientation that was confirmed, not the trial
    const QString previous = pending() && m_pendingOutput == output ? m_previousTransform : transformOf(output);
    if (pending() && m_pendingOutput != output)
        revert();
    if (previous.isEmpty()) {
        setError(QStringLiteral("No display called %1").arg(output));
        emit applied(output, false, m_lastError);
        return;
    }
    const int secs = qBound(5, seconds, 60);
    // the rollback is armed before the change, so there is no moment where a change exists without one
    armWatchdog(output, previous, secs + 3);
    runtimeTransform(output, t, [this, output, t, previous, secs](bool ok, const QString& message) {
        refresh();
        if (!ok) {
            disarmWatchdog();
            setError(message);
            emit applied(output, false, message);
            return;
        }
        setError(QString());
        m_pendingOutput = output;
        m_pendingTransform = t;
        m_previousTransform = previous;
        m_secondsLeft = secs;
        emit pendingChanged();
        emit secondsLeftChanged();
        m_tick.start();
        emit applied(output, true, QString());
    });
}

void DisplayConfig::revert() {
    if (!pending())
        return;
    const QString output = m_pendingOutput, previous = m_previousTransform;
    clearPending();
    runtimeTransform(output, previous, [this, output, previous](bool ok, const QString& message) {
        refresh();
        if (ok) {
            // only a restore that took lets the watchdog go: it is the net under exactly this step
            disarmWatchdog();
            emit finished(output, false, QStringLiteral("Orientation restored"));
            return;
        }
        // the IPC refused: the CLI next, and the watchdog stays armed in case that fails too
        QProcess::startDetached(QStringLiteral("niri"), {QStringLiteral("msg"), QStringLiteral("output"), output, QStringLiteral("transform"), previous});
        setError(QStringLiteral("niri refused the restore (%1); retried, and the fallback still runs").arg(message));
        emit finished(output, false, m_lastError);
    });
}

void DisplayConfig::confirm() {
    if (!pending())
        return;
    const QString output = m_pendingOutput, t = m_pendingTransform;
    m_tick.stop();
    QString message;
    if (!persist(output, t, &message)) {
        // the session keeps the new orientation until it is undone, but nothing was written: say so, and roll back
        setError(message);
        revert();
        return;
    }
    disarmWatchdog();
    clearPending();
    setError(QString());
    refresh();
    emit finished(output, true, message);
}

bool DisplayConfig::hasOutputBlock(const QString& text, const QString& output) {
    return findBlock(text.split('\n'), output).first >= 0;
}

QString DisplayConfig::withTransform(const QString& text, const QString& output, const QString& transform) {
    const QString t = canonical(transform);
    if (t.isEmpty())
        return text;
    QStringList lines = text.split('\n');
    const auto [start, end] = findBlock(lines, output);
    if (start < 0) {
        if (t == QStringLiteral("normal"))
            return text;
        QString out = text;
        if (!out.endsWith('\n'))
            out += '\n';
        out += QStringLiteral("\n// Orientation, from Zynith Settings → Displays\noutput \"%1\" {\n    transform \"%2\"\n}\n").arg(output, t);
        return out;
    }
    const QRegularExpression line(QStringLiteral("^(\\s*)transform\\s+\"[^\"]*\""));
    // the block's own transform line (depth 1 inside the block)
    int depth = 0;
    for (int i = start; i <= end; ++i) {
        const QString c = code(lines[i]);
        if (i > start && depth == 1) {
            const auto m = line.match(c);
            if (m.hasMatch()) {
                if (t == QStringLiteral("normal"))
                    lines.removeAt(i);
                else
                    lines[i] = QStringLiteral("%1transform \"%2\"").arg(m.captured(1), t);
                return lines.join('\n');
            }
        }
        depth += c.count('{') - c.count('}');
    }
    if (t == QStringLiteral("normal"))
        return text;
    // none yet: after the opening line, indented as the block's first property is (or four spaces)
    QString indent = QStringLiteral("    ");
    if (start + 1 <= end) {
        const auto m = QRegularExpression(QStringLiteral("^(\\s+)\\S")).match(lines[start + 1]);
        if (m.hasMatch() && start + 1 < end)
            indent = m.captured(1);
    }
    lines.insert(start + 1, QStringLiteral("%1transform \"%2\"").arg(indent, t));
    return lines.join('\n');
}

QString DisplayConfig::blockFile(const QString& file, const QString& output, int depth) const {
    if (depth > 8)
        return QString();
    const QStringList lines = readFile(file).split('\n');
    const auto block = findBlock(lines, output).first;
    const QRegularExpression include(QStringLiteral("^\\s*include\\s+\"([^\"]+)\""));
    int nesting = 0;
    for (int i = 0; i < lines.size(); ++i) {
        if (i == block)
            return file;
        const QString c = code(lines[i]);
        if (nesting == 0) {
            const auto m = include.match(c);
            if (m.hasMatch()) {
                QString path = m.captured(1);
                if (path.startsWith(QStringLiteral("~/")))
                    path = QDir::homePath() + path.mid(1);
                else if (!QFileInfo(path).isAbsolute())
                    path = QFileInfo(file).absolutePath() + '/' + path;
                const QString found = blockFile(path, output, depth + 1);
                if (!found.isEmpty())
                    return found;
            }
        }
        nesting += c.count('{') - c.count('}');
    }
    return QString();
}

bool DisplayConfig::persist(const QString& output, const QString& transform, QString* message) {
    const QString config = niriDir() + QStringLiteral("/config.kdl");
    if (!QFileInfo::exists(config)) {
        *message = QStringLiteral("niri's config.kdl was not found");
        return false;
    }
    QString target = blockFile(config, output, 0);
    if (target.isEmpty())
        target = config; // no block anywhere: a new one goes at the end of config.kdl
    const QString before = readFile(target);
    const QString after = withTransform(before, output, transform);
    if (after == before) {
        *message = QStringLiteral("Already saved");
        return true;
    }
    // validate the whole configuration with the change in place, from a probe beside config.kdl (relative includes
    // resolve the same way); a block in an included file is checked through a probe of that file named in place
    const QString dir = niriDir();
    const QString staged = target + QStringLiteral(".zynith-staged");
    const QString probe = dir + QStringLiteral("/.zynith-validate-displays.kdl");
    QString probeText;
    if (target == config) {
        probeText = after;
    } else {
        {
            QSaveFile f(staged);
            if (!f.open(QIODevice::WriteOnly) || f.write(after.toUtf8()) < 0 || !f.commit()) {
                *message = QStringLiteral("Could not stage the change");
                return false;
            }
        }
        probeText = readFile(config);
        const QString rel = QDir(dir).relativeFilePath(target);
        if (!probeText.contains(QStringLiteral("\"%1\"").arg(rel))) {
            QFile::remove(staged);
            *message = QStringLiteral("The block for %1 is in a nested include (%2); change it there by hand").arg(output, rel);
            return false;
        }
        probeText.replace(QStringLiteral("\"%1\"").arg(rel), QStringLiteral("\"%1\"").arg(QDir(dir).relativeFilePath(staged)));
    }
    {
        QSaveFile f(probe);
        if (!f.open(QIODevice::WriteOnly) || f.write(probeText.toUtf8()) < 0 || !f.commit()) {
            QFile::remove(staged);
            *message = QStringLiteral("Could not write the validation probe");
            return false;
        }
    }
    QProcess validate;
    validate.setProcessChannelMode(QProcess::MergedChannels);
    validate.start(QStringLiteral("niri"), {QStringLiteral("validate"), QStringLiteral("-c"), probe});
    const bool ran = validate.waitForFinished(10000);
    const QString out = QString::fromUtf8(validate.readAll());
    QFile::remove(probe);
    QFile::remove(staged);
    if (!ran || validate.exitStatus() != QProcess::NormalExit || validate.exitCode() != 0) {
        *message = QStringLiteral("niri rejected the change: %1").arg(out.trimmed().split('\n').last());
        return false;
    }
    // a backup of the file as it was, in the session's backup place
    const QString backupDir = QDir::homePath() + QStringLiteral("/.config/rice-backups/%1-zynith-displays")
                                                     .arg(QDateTime::currentDateTime().toString(QStringLiteral("yyyyMMdd-HHmmss")));
    if (!QDir().mkpath(backupDir) || !QFile::copy(target, backupDir + '/' + QFileInfo(target).fileName())) {
        *message = QStringLiteral("Could not back up %1, so it was not changed").arg(QFileInfo(target).fileName());
        return false;
    }
    m_lastBackup = backupDir;
    emit lastBackupChanged();
    QSaveFile f(target);
    if (!f.open(QIODevice::WriteOnly) || f.write(after.toUtf8()) < 0 || !f.commit()) {
        *message = QStringLiteral("Could not write %1").arg(target);
        return false;
    }
    *message = QStringLiteral("Saved to %1 (backup in %2)").arg(QDir(dir).relativeFilePath(target), backupDir);
    return true;
}
