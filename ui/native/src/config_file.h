#pragma once

#include <QFileSystemWatcher>
#include <QObject>
#include <QQmlParserStatus>
#include <QTimer>
#include <QVariantMap>
#include <QtQml/qqmlregistration.h>

// One TOML file under ~/.config/zynith as a QML value: `values` is the file laid over `defaults` (tables merged,
// everything else replaced), and changes on disk arrive by themselves. set() changes one key and rewrites the
// file atomically, keeping its leading comment block; keys it does not touch keep their values.
class ConfigFile : public QObject, public QQmlParserStatus {
    Q_OBJECT
    QML_ELEMENT
    Q_INTERFACES(QQmlParserStatus)

    Q_PROPERTY(QString path READ path WRITE setPath NOTIFY pathChanged)
    Q_PROPERTY(QVariantMap defaults READ defaults WRITE setDefaults NOTIFY defaultsChanged)
    Q_PROPERTY(QString header READ header WRITE setHeader NOTIFY headerChanged)
    Q_PROPERTY(QVariantMap values READ values NOTIFY valuesChanged)
    Q_PROPERTY(bool loaded READ loaded NOTIFY loadedChanged)
    Q_PROPERTY(bool exists READ exists NOTIFY loadedChanged)
    Q_PROPERTY(QString error READ error NOTIFY errorChanged)

public:
    explicit ConfigFile(QObject* parent = nullptr);

    QString path() const { return m_path; }
    void setPath(const QString& path);
    QVariantMap defaults() const { return m_defaults; }
    void setDefaults(const QVariantMap& defaults);
    QString header() const { return m_header; }
    void setHeader(const QString& header);
    QVariantMap values() const { return m_values; }
    bool loaded() const { return m_loaded; }
    bool exists() const { return m_exists; }
    QString error() const { return m_error; }

    // "glass.opacity" → 0.8; a list of maps becomes an array of tables
    Q_INVOKABLE void set(const QString& keyPath, const QVariant& value);
    // removes the key, so the default shows through again
    Q_INVOKABLE void reset(const QString& keyPath);
    // value at a dotted path in `values`, or `fallback`
    Q_INVOKABLE QVariant get(const QString& keyPath, const QVariant& fallback = QVariant()) const;
    // writes the file with `contents` (a map) when it does not exist yet; used for one-time migrations
    Q_INVOKABLE bool create(const QVariantMap& contents);
    // several top-level keys in one atomic write (a null value removes its key): a change that spans keys (a bar
    // and the component tables it names) never lands half-written
    Q_INVOKABLE bool assign(const QVariantMap& changes);
    // a copy of the file as it is now, beside it: <path>.<tag>; returns the copy's path ("" when it failed)
    Q_INVOKABLE QString backup(const QString& tag);
    // when the file on disk cannot be parsed, nothing is written over it (the values in memory are the defaults
    // or the last good ones, not the user's file). recover() moves the broken file aside (<path>.broken-<time>)
    // and writes `contents`; returns the path the broken file went to
    Q_INVOKABLE QString recover(const QVariantMap& contents);

    void classBegin() override {}
    void componentComplete() override;

signals:
    void pathChanged();
    void defaultsChanged();
    void headerChanged();
    void valuesChanged();
    void loadedChanged();
    void errorChanged();

private:
    void load();
    void rebuild();
    bool write(const QVariantMap& contents);
    void watch();

    QString m_path;
    QVariantMap m_defaults;
    QString m_header;
    QVariantMap m_file;   // what the file holds
    QVariantMap m_values; // m_file over m_defaults
    QByteArray m_lastWritten;
    bool m_complete = false;
    bool m_loaded = false;
    bool m_exists = false;
    QString m_error;
    QFileSystemWatcher m_watcher;
    QTimer m_reload;
};
