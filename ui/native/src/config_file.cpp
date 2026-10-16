#include "config_file.h"

#include <QCryptographicHash>
#include <QDateTime>
#include <QDir>
#include <QFile>
#include <QFileInfo>
#include <QJSValue>
#include <QSaveFile>

#pragma GCC diagnostic push
#pragma GCC diagnostic ignored "-Wshadow"
#include <toml++/toml.hpp>
#pragma GCC diagnostic pop

#include <cmath>
#include <sstream>

namespace {

QVariant fromNode(const toml::node& node);

QVariantMap fromTable(const toml::table& table) {
    QVariantMap out;
    for (const auto& [key, value] : table)
        out.insert(QString::fromUtf8(key.str().data(), qsizetype(key.str().size())), fromNode(value));
    return out;
}

QVariant fromNode(const toml::node& node) {
    if (const auto* t = node.as_table())
        return fromTable(*t);
    if (const auto* a = node.as_array()) {
        QVariantList list;
        for (const auto& item : *a)
            list.append(fromNode(item));
        return list;
    }
    if (const auto* s = node.as_string())
        return QString::fromStdString(s->get());
    if (const auto* i = node.as_integer())
        return QVariant::fromValue(qint64(i->get()));
    if (const auto* d = node.as_floating_point())
        return d->get();
    if (const auto* b = node.as_boolean())
        return b->get();
    // dates and times come back as their TOML text
    std::ostringstream text;
    if (const auto* dt = node.as_date_time())
        text << *dt;
    else if (const auto* d = node.as_date())
        text << *d;
    else if (const auto* t = node.as_time())
        text << *t;
    return QString::fromStdString(text.str());
}

void insertValue(toml::table& table, const std::string& key, const QVariant& value);

toml::array toArray(const QVariantList& list) {
    toml::array out;
    for (const QVariant& v : list) {
        const QVariant item = v.canConvert<QJSValue>() ? v.value<QJSValue>().toVariant() : v;
        if (item.typeId() == QMetaType::QVariantMap) {
            toml::table t;
            const QVariantMap map = item.toMap();
            for (auto it = map.cbegin(); it != map.cend(); ++it)
                insertValue(t, it.key().toStdString(), it.value());
            out.push_back(std::move(t));
        } else if (item.typeId() == QMetaType::QVariantList || item.typeId() == QMetaType::QStringList) {
            out.push_back(toArray(item.toList()));
        } else if (item.typeId() == QMetaType::Bool) {
            out.push_back(item.toBool());
        } else if (item.typeId() == QMetaType::Double || item.typeId() == QMetaType::Float) {
            const double d = item.toDouble();
            if (std::trunc(d) == d && std::abs(d) < 1e15)
                out.push_back(int64_t(d));
            else
                out.push_back(d);
        } else if (item.canConvert<qint64>() && item.typeId() != QMetaType::QString) {
            out.push_back(int64_t(item.toLongLong()));
        } else {
            out.push_back(item.toString().toStdString());
        }
    }
    return out;
}

void insertValue(toml::table& table, const std::string& key, const QVariant& raw) {
    const QVariant value = raw.canConvert<QJSValue>() ? raw.value<QJSValue>().toVariant() : raw;
    switch (value.typeId()) {
    case QMetaType::QVariantMap: {
        toml::table t;
        const QVariantMap map = value.toMap();
        for (auto it = map.cbegin(); it != map.cend(); ++it)
            insertValue(t, it.key().toStdString(), it.value());
        table.insert_or_assign(key, std::move(t));
        break;
    }
    case QMetaType::QVariantList:
    case QMetaType::QStringList:
        table.insert_or_assign(key, toArray(value.toList()));
        break;
    case QMetaType::Bool:
        table.insert_or_assign(key, value.toBool());
        break;
    case QMetaType::Double:
    case QMetaType::Float: {
        const double d = value.toDouble();
        // QML hands every number over as a double; whole numbers stay integers in the file
        if (std::trunc(d) == d && std::abs(d) < 1e15)
            table.insert_or_assign(key, int64_t(d));
        else
            table.insert_or_assign(key, d);
        break;
    }
    case QMetaType::Int:
    case QMetaType::LongLong:
    case QMetaType::UInt:
    case QMetaType::ULongLong:
        table.insert_or_assign(key, int64_t(value.toLongLong()));
        break;
    default:
        table.insert_or_assign(key, value.toString().toStdString());
    }
}

QVariantMap merged(const QVariantMap& base, const QVariantMap& over) {
    QVariantMap out = base;
    for (auto it = over.cbegin(); it != over.cend(); ++it) {
        const QVariant& o = it.value();
        const auto b = out.constFind(it.key());
        if (b != out.cend() && b->typeId() == QMetaType::QVariantMap && o.typeId() == QMetaType::QVariantMap)
            out.insert(it.key(), merged(b->toMap(), o.toMap()));
        else
            out.insert(it.key(), o);
    }
    return out;
}

QVariantMap withKey(QVariantMap map, const QStringList& path, const QVariant& value, bool remove) {
    if (path.isEmpty())
        return map;
    if (path.size() == 1) {
        if (remove)
            map.remove(path.first());
        else
            map.insert(path.first(), value.canConvert<QJSValue>() ? value.value<QJSValue>().toVariant() : value);
        return map;
    }
    // removing from a table that is not there changes nothing; removing its last key removes the table too, so
    // a value set and then reset leaves the file as it was (no empty [table] behind)
    if (remove && !map.contains(path.first()))
        return map;
    const QVariantMap inner = map.value(path.first()).toMap();
    const QVariantMap next = withKey(inner, path.mid(1), value, remove);
    if (remove && next.isEmpty())
        map.remove(path.first());
    else
        map.insert(path.first(), next);
    return map;
}

} // namespace

ConfigFile::ConfigFile(QObject* parent)
    : QObject(parent) {
    m_reload.setSingleShot(true);
    m_reload.setInterval(60);
    connect(&m_reload, &QTimer::timeout, this, &ConfigFile::load);
    connect(&m_watcher, &QFileSystemWatcher::fileChanged, this, [this] { m_reload.start(); });
    connect(&m_watcher, &QFileSystemWatcher::directoryChanged, this, [this] { m_reload.start(); });
}

void ConfigFile::setPath(const QString& path) {
    if (path == m_path)
        return;
    m_path = path;
    emit pathChanged();
    if (m_complete)
        load();
}

void ConfigFile::setDefaults(const QVariantMap& defaults) {
    m_defaults = defaults;
    emit defaultsChanged();
    rebuild();
}

void ConfigFile::setHeader(const QString& header) {
    m_header = header;
    emit headerChanged();
}

void ConfigFile::componentComplete() {
    m_complete = true;
    load();
}

void ConfigFile::watch() {
    // an atomic save replaces the file, so the directory is watched as well
    const QFileInfo info(m_path);
    QDir().mkpath(info.absolutePath());
    if (!m_watcher.directories().contains(info.absolutePath()))
        m_watcher.addPath(info.absolutePath());
    if (info.exists() && !m_watcher.files().contains(m_path))
        m_watcher.addPath(m_path);
}

void ConfigFile::load() {
    if (m_path.isEmpty())
        return;
    watch();
    QFile file(m_path);
    const bool existed = file.exists();
    QVariantMap contents;
    QString error;
    if (existed && file.open(QIODevice::ReadOnly)) {
        const QByteArray bytes = file.readAll();
        if (!m_lastWritten.isEmpty() && bytes == m_lastWritten && m_loaded)
            return; // our own write coming back
        try {
            const auto table = toml::parse(std::string_view(bytes.constData(), size_t(bytes.size())));
            contents = fromTable(table);
        } catch (const toml::parse_error& e) {
            // keep the last good values rather than falling back to defaults mid-session
            error = QStringLiteral("%1:%2: %3")
                        .arg(m_path)
                        .arg(e.source().begin.line)
                        .arg(QString::fromStdString(std::string(e.description())));
            qWarning("zynith: %s", qPrintable(error));
            contents = m_file;
        }
    }
    if (error != m_error) {
        m_error = error;
        emit errorChanged();
    }
    m_file = contents;
    m_exists = existed;
    rebuild();
    if (!m_loaded) {
        m_loaded = true;
    }
    emit loadedChanged();
}

void ConfigFile::rebuild() {
    const QVariantMap values = merged(m_defaults, m_file);
    if (values != m_values) {
        m_values = values;
        emit valuesChanged();
    }
}

bool ConfigFile::write(const QVariantMap& contents) {
    toml::table table;
    for (auto it = contents.cbegin(); it != contents.cend(); ++it)
        insertValue(table, it.key().toStdString(), it.value());
    std::ostringstream text;
    text << table;
    QByteArray bytes;
    if (!m_header.isEmpty()) {
        for (const QString& line : m_header.split(QLatin1Char('\n')))
            bytes += (line.isEmpty() ? QByteArray("#") : "# " + line.toUtf8()) + '\n';
        bytes += '\n';
    }
    bytes += QByteArray::fromStdString(text.str());
    if (!bytes.endsWith('\n'))
        bytes += '\n';
    QDir().mkpath(QFileInfo(m_path).absolutePath());
    QSaveFile file(m_path);
    if (!file.open(QIODevice::WriteOnly)) {
        qWarning("zynith: cannot write %s", qPrintable(m_path));
        return false;
    }
    file.write(bytes);
    if (!file.commit()) {
        qWarning("zynith: cannot replace %s", qPrintable(m_path));
        return false;
    }
    m_lastWritten = bytes;
    m_file = contents;
    m_exists = true;
    watch();
    rebuild();
    return true;
}

void ConfigFile::set(const QString& keyPath, const QVariant& value) {
    if (!m_error.isEmpty()) {
        qWarning("zynith: not writing %s while it has an error (%s)", qPrintable(m_path), qPrintable(m_error));
        return;
    }
    write(withKey(m_file, keyPath.split(QLatin1Char('.')), value, false));
}

void ConfigFile::reset(const QString& keyPath) {
    if (!m_error.isEmpty()) {
        qWarning("zynith: not writing %s while it has an error (%s)", qPrintable(m_path), qPrintable(m_error));
        return;
    }
    write(withKey(m_file, keyPath.split(QLatin1Char('.')), QVariant(), true));
}

bool ConfigFile::assign(const QVariantMap& changes) {
    if (!m_error.isEmpty()) {
        qWarning("zynith: not writing %s while it has an error (%s)", qPrintable(m_path), qPrintable(m_error));
        return false;
    }
    QVariantMap next = m_file;
    for (auto it = changes.cbegin(); it != changes.cend(); ++it) {
        if (it.value().isNull() || !it.value().isValid())
            next.remove(it.key());
        else
            next.insert(it.key(), it.value());
    }
    return write(next);
}

QString ConfigFile::backup(const QString& tag) {
    if (m_path.isEmpty() || !QFile::exists(m_path) || tag.isEmpty() || tag.contains(QLatin1Char('/')))
        return {};
    const QString to = m_path + QLatin1Char('.') + tag;
    if (QFile::exists(to))
        return to; // the first copy under a tag is the one kept
    return QFile::copy(m_path, to) ? to : QString();
}

QString ConfigFile::recover(const QVariantMap& contents) {
    if (m_error.isEmpty() || m_path.isEmpty())
        return {};
    const QString aside = m_path + QStringLiteral(".broken-") + QDateTime::currentDateTime().toString(QStringLiteral("yyyyMMdd-HHmmss"));
    if (!QFile::rename(m_path, aside))
        return {};
    m_error.clear();
    emit errorChanged();
    m_file.clear();
    return write(contents) ? aside : QString();
}

bool ConfigFile::has(const QString& keyPath) const {
    QVariant node = m_file;
    for (const QString& part : keyPath.split(QLatin1Char('.'))) {
        const QVariantMap map = node.toMap();
        if (!map.contains(part))
            return false;
        node = map.value(part);
    }
    return true;
}

QVariant ConfigFile::get(const QString& keyPath, const QVariant& fallback) const {
    QVariant node = m_values;
    for (const QString& part : keyPath.split(QLatin1Char('.'))) {
        const QVariantMap map = node.toMap();
        if (!map.contains(part))
            return fallback;
        node = map.value(part);
    }
    return node;
}

bool ConfigFile::create(const QVariantMap& contents) {
    if (QFile::exists(m_path))
        return false;
    return write(contents);
}
