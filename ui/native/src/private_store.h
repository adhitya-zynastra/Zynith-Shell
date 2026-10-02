#pragma once

#include <QObject>
#include <QString>
#include <QtQml/qqmlregistration.h>

// A file only its owner can read: written whole and atomically with mode 0600 in a 0700 directory, read once
// when the path is set. For state that may hold private text (notification history) — never for secrets.
class PrivateStore : public QObject {
    Q_OBJECT
    QML_ELEMENT

    Q_PROPERTY(QString path READ path WRITE setPath NOTIFY pathChanged)
    Q_PROPERTY(QString text READ text NOTIFY loaded)
    Q_PROPERTY(bool ready READ ready NOTIFY loaded)

public:
    explicit PrivateStore(QObject* parent = nullptr);

    QString path() const { return m_path; }
    void setPath(const QString& path);
    QString text() const { return m_text; }
    bool ready() const { return m_ready; }

    Q_INVOKABLE bool save(const QString& text);
    Q_INVOKABLE void remove();

signals:
    void pathChanged();
    void loaded();

private:
    QString m_path;
    QString m_text;
    bool m_ready = false;
};
