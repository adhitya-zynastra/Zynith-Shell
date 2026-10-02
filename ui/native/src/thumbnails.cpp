#include "thumbnails.h"

#include <QAtomicInteger>
#include <QCryptographicHash>
#include <QDir>
#include <QFileInfo>
#include <QImage>
#include <QImageReader>
#include <QQmlEngine>
#include <QQuickAsyncImageProvider>
#include <QQuickImageResponse>
#include <QQuickTextureFactory>
#include <QRunnable>
#include <QSaveFile>
#include <QStandardPaths>
#include <QThreadPool>
#include <QUrl>

namespace {

QString cacheDir() {
    static const QString dir = [] {
        QString base = qEnvironmentVariable("XDG_CACHE_HOME");
        if (!base.startsWith(QLatin1Char('/')))
            base = QDir::homePath() + QStringLiteral("/.cache");
        const QString path = base + QStringLiteral("/zynith/thumbnails");
        QDir().mkpath(path);
        return path;
    }();
    return dir;
}

QThreadPool* decoders() {
    static QThreadPool* pool = [] {
        auto* p = new QThreadPool;
        p->setMaxThreadCount(2);
        p->setThreadPriority(QThread::LowPriority);
        return p;
    }();
    return pool;
}

QImage makeThumbnail(const QString& path, int width) {
    const QFileInfo info(path);
    if (!info.isFile() || width <= 0)
        return {};
    const QByteArray key = QCryptographicHash::hash(
        (path + QLatin1Char('\n') + QString::number(info.lastModified().toMSecsSinceEpoch()) + QLatin1Char('\n')
         + QString::number(width))
            .toUtf8(),
        QCryptographicHash::Sha1);
    const QString stem = cacheDir() + QLatin1Char('/') + QString::fromLatin1(key.toHex());

    for (const char* ext : {".jpg", ".png"}) {
        QImage cached(stem + QLatin1String(ext));
        if (!cached.isNull())
            return cached;
    }

    QImageReader reader(path);
    reader.setAutoTransform(true);
    const QSize full = reader.size();
    if (full.isValid() && full.width() > width) {
        // scaled decode: JPEG skips most of the work, other formats scale after decoding
        reader.setScaledSize(QSize(width, qMax(1, int(qint64(full.height()) * width / full.width()))));
    }
    QImage image = reader.read();
    if (image.isNull())
        return {};
    if (image.width() > width)
        image = image.scaledToWidth(width, Qt::SmoothTransformation);

    const bool alpha = image.hasAlphaChannel();
    QSaveFile out(stem + (alpha ? QStringLiteral(".png") : QStringLiteral(".jpg")));
    if (out.open(QIODevice::WriteOnly) && image.save(&out, alpha ? "PNG" : "JPG", alpha ? -1 : 88))
        out.commit();
    return image;
}

class Response : public QQuickImageResponse {
public:
    Response(QString path, int width) {
        auto* job = QRunnable::create([this, path = std::move(path), width] {
            if (!m_cancelled.loadAcquire())
                m_image = makeThumbnail(path, width);
            emit finished();
        });
        decoders()->start(job);
    }
    QQuickTextureFactory* textureFactory() const override { return QQuickTextureFactory::textureFactoryForImage(m_image); }
    QString errorString() const override { return m_image.isNull() ? QStringLiteral("no thumbnail") : QString(); }
    void cancel() override { m_cancelled.storeRelease(1); }

private:
    QImage m_image;
    QAtomicInteger<int> m_cancelled = 0;
};

class Provider : public QQuickAsyncImageProvider {
public:
    QQuickImageResponse* requestImageResponse(const QString& id, const QSize&) override {
        // <width>/<percent-encoded path>
        const qsizetype slash = id.indexOf(QLatin1Char('/'));
        const int width = slash > 0 ? id.left(slash).toInt() : 0;
        const QString path = QUrl::fromPercentEncoding(id.mid(slash + 1).toUtf8());
        return new Response(path, qBound(16, width, 1600));
    }
};

} // namespace

Thumbnails::Thumbnails(QQmlEngine* engine)
    : QObject(nullptr) {
    if (engine->imageProvider(QStringLiteral("zthumb")) == nullptr)
        engine->addImageProvider(QStringLiteral("zthumb"), new Provider);
}

Thumbnails* Thumbnails::create(QQmlEngine* engine, QJSEngine*) {
    return new Thumbnails(engine);
}

QString Thumbnails::url(const QString& path, int width) const {
    if (path.isEmpty())
        return {};
    return QStringLiteral("image://zthumb/") + QString::number(width) + QLatin1Char('/')
        + QString::fromLatin1(QUrl::toPercentEncoding(path));
}
