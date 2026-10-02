#include "niri_config.h"

#include <QDir>
#include <QFile>
#include <QRegularExpression>
#include <QSaveFile>
#include <QStandardPaths>

#include <cstdio>

namespace {

bool validName(const QString& name) {
    static const QRegularExpression re(QStringLiteral("^[a-z][a-z0-9-]{0,31}$"));
    return re.match(name).hasMatch();
}

QString includeLine(const QString& name) { return QStringLiteral("include \"rice/%1.kdl\"").arg(name); }

QString readFile(const QString& path) {
    QFile f(path);
    return f.open(QIODevice::ReadOnly) ? QString::fromUtf8(f.readAll()) : QString();
}

// niri explains a rejection in a drawn diagnostic; the last line that still has words after the box
// drawing and colour codes removed is the specific complaint ("unexpected node `x`")
QString reason(const QString& output) {
    static const QRegularExpression ansi(QStringLiteral("\x1b\\[[0-9;]*m"));
    static const QRegularExpression decoration(QStringLiteral("^[\\s│├╰╭─▶×·┬┴:0-9]*"));
    const QStringList lines = QString(output).remove(ansi).split(QLatin1Char('\n'));
    for (auto it = lines.crbegin(); it != lines.crend(); ++it) {
        const QString text = QString(*it).remove(decoration).trimmed();
        if (text.contains(QRegularExpression(QStringLiteral("[A-Za-z]{2}"))) && !text.contains(QStringLiteral("INFO")))
            return text;
    }
    return QStringLiteral("niri rejected the configuration");
}

bool writeFile(const QString& path, const QString& text) {
    QSaveFile f(path);
    if (!f.open(QIODevice::WriteOnly))
        return false;
    f.write(text.toUtf8());
    return f.commit();
}

} // namespace

NiriConfig::NiriConfig(QObject* parent)
    : QObject(parent)
    , m_dir(QStandardPaths::writableLocation(QStandardPaths::GenericConfigLocation) + QStringLiteral("/niri")) {}

NiriConfig::~NiriConfig() {
    if (m_process) {
        m_process->disconnect(this);
        m_process->kill();
        m_process->waitForFinished(500);
        QFile::remove(m_staged);
        QFile::remove(m_probe);
    }
}

bool NiriConfig::isIncluded(const QString& name) const {
    return validName(name) && readFile(m_dir + QStringLiteral("/config.kdl")).contains(includeLine(name));
}

QString NiriConfig::read(const QString& name) const {
    return validName(name) ? readFile(QStringLiteral("%1/rice/%2.kdl").arg(m_dir, name)) : QString();
}

void NiriConfig::apply(const QString& name, const QString& text) {
    if (!validName(name)) {
        emit applied(name, false, QStringLiteral("invalid fragment name"));
        return;
    }
    m_pendingName = name;
    m_pendingText = text;
    m_hasPending = true;
    if (!m_process)
        startNext();
}

void NiriConfig::startNext() {
    if (!m_hasPending)
        return;
    m_hasPending = false;
    m_name = m_pendingName;
    const QString text = m_pendingText;

    if (read(m_name) == text) {
        emit applied(m_name, true, QStringLiteral("unchanged"));
        return startNext();
    }

    // Validate the real configuration with the new fragment substituted for the old one. The probe sits next
    // to config.kdl so its relative includes resolve the same way.
    const QString config = readFile(m_dir + QStringLiteral("/config.kdl"));
    if (config.isEmpty()) {
        emit applied(m_name, false, QStringLiteral("no niri config.kdl"));
        return startNext();
    }
    const QString stagedRel = QStringLiteral("rice/%1.kdl.zynith-new").arg(m_name);
    m_staged = m_dir + QLatin1Char('/') + stagedRel;
    m_probe = m_dir + QStringLiteral("/.zynith-validate.kdl");
    QString probe = config;
    if (probe.contains(includeLine(m_name)))
        probe.replace(includeLine(m_name), QStringLiteral("include \"%1\"").arg(stagedRel));
    else
        probe += QStringLiteral("\ninclude \"%1\"\n").arg(stagedRel);

    QDir().mkpath(m_dir + QStringLiteral("/rice"));
    if (!writeFile(m_staged, text) || !writeFile(m_probe, probe)) {
        QFile::remove(m_staged);
        QFile::remove(m_probe);
        emit applied(m_name, false, QStringLiteral("could not write to %1").arg(m_dir));
        return startNext();
    }

    m_process = new QProcess(this);
    m_process->setProcessChannelMode(QProcess::MergedChannels);
    connect(m_process, &QProcess::finished, this, [this](int code, QProcess::ExitStatus status) {
        const QString output = QString::fromUtf8(m_process->readAll());
        if (status != QProcess::NormalExit || code != 0) {
            finish(false, reason(output));
            return;
        }
        const QString target = QStringLiteral("%1/rice/%2.kdl").arg(m_dir, m_name);
        // rename(2) replaces the target atomically; niri sees either the old or the new fragment
        if (std::rename(m_staged.toLocal8Bit().constData(), target.toLocal8Bit().constData()) != 0) {
            finish(false, QStringLiteral("could not replace %1").arg(target));
            return;
        }
        finish(true, QStringLiteral("applied"));
    });
    connect(m_process, &QProcess::errorOccurred, this, [this](QProcess::ProcessError error) {
        if (error == QProcess::FailedToStart)
            finish(false, QStringLiteral("niri is not available to validate the configuration"));
    });
    emit busyChanged();
    m_process->start(QStringLiteral("niri"), {QStringLiteral("validate"), QStringLiteral("-c"), m_probe});
}

void NiriConfig::finish(bool ok, const QString& message) {
    if (!m_process)
        return;
    m_process->deleteLater();
    m_process = nullptr;
    QFile::remove(m_staged);
    QFile::remove(m_probe);
    setError(ok ? QString() : message);
    emit busyChanged();
    emit applied(m_name, ok, message);
    startNext();
}

void NiriConfig::setError(const QString& error) {
    if (error == m_lastError)
        return;
    m_lastError = error;
    emit lastErrorChanged();
}
