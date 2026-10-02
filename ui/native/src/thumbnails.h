#pragma once

#include <QObject>
#include <QColor>
#include <QString>

#include <memory>
#include <QtQml/qqmlregistration.h>

class QQmlEngine;
class QJSEngine;

// Small images of large ones, for browsers: image://zthumb/<width>/<percent-encoded absolute path>. Decoded
// off the UI thread at the size asked for (JPEG decodes scaled, so a 4K photo never exists at full size here)
// and kept in ~/.cache/zynith/thumbnails, keyed by path, modification time and width. Two decoders at most,
// so opening a browser over hundreds of wallpapers never takes every core.
class Thumbnails : public QObject {
    Q_OBJECT
    QML_ELEMENT
    QML_SINGLETON

public:
    explicit Thumbnails(QQmlEngine* engine);
    static Thumbnails* create(QQmlEngine* engine, QJSEngine*);

    // the image source for a thumbnail `width` pixels wide
    Q_INVOKABLE QString url(const QString& path, int width) const;
};

// The colour a wallpaper leans towards: the average of its more saturated pixels, from a 64 px thumbnail
// (the same cache), worked out off the UI thread. For tinting things after what is being looked at.
class Tone : public QObject {
    Q_OBJECT
    QML_ELEMENT

    Q_PROPERTY(QString path READ path WRITE setPath NOTIFY pathChanged)
    Q_PROPERTY(QColor color READ color NOTIFY colorChanged)
    Q_PROPERTY(bool ready READ ready NOTIFY colorChanged)

public:
    explicit Tone(QObject* parent = nullptr);
    ~Tone() override;

    QString path() const { return m_path; }
    void setPath(const QString& path);
    QColor color() const { return m_color; }
    bool ready() const { return m_ready; }

signals:
    void pathChanged();
    void colorChanged();

private:
    QString m_path;
    QColor m_color;
    bool m_ready = false;
    quint64 m_request = 0;
    std::shared_ptr<bool> m_alive = std::make_shared<bool>(true);
};
