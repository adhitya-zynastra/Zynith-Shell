#pragma once

#include <QObject>
#include <QString>
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
