#include "thumbnails.h"

#include <QAtomicInteger>
#include <QCoreApplication>
#include <QMetaObject>

#include <cmath>
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

Tone::Tone(QObject* parent)
    : QObject(parent) {}

Tone::~Tone() {
    *m_alive = false;
}

void Tone::setPath(const QString& path) {
    if (path == m_path)
        return;
    m_path = path;
    emit pathChanged();
    if (path.isEmpty())
        return;
    const quint64 request = ++m_request;
    std::weak_ptr<bool> alive = m_alive;
    decoders()->start(QRunnable::create([this, alive, path, request] {
        const QImage small = makeThumbnail(path, 64).convertToFormat(QImage::Format_RGB32);
        double r = 0, g = 0, b = 0, weight = 0, ar = 0, ag = 0, ab = 0;
        for (int y = 0; y < small.height(); ++y) {
            const QRgb* line = reinterpret_cast<const QRgb*>(small.constScanLine(y));
            for (int x = 0; x < small.width(); ++x) {
                const QColor c = QColor::fromRgb(line[x]);
                ar += c.redF();
                ag += c.greenF();
                ab += c.blueF();
                // saturated, mid-bright pixels say what the picture is about; greys and near-black do not
                const double w = c.hsvSaturationF() * c.hsvSaturationF() * (1.0 - std::abs(c.valueF() - 0.6));
                r += c.redF() * w;
                g += c.greenF() * w;
                b += c.blueF() * w;
                weight += w;
            }
        }
        const int n = qMax(1, small.width() * small.height());
        QColor tone = weight > 0.5 ? QColor::fromRgbF(r / weight, g / weight, b / weight)
                                   : QColor::fromRgbF(ar / n, ag / n, ab / n);
        QMetaObject::invokeMethod(
            qApp,
            [this, alive, request, tone] {
                if (alive.expired() || request != m_request)
                    return;
                m_color = tone;
                m_ready = true;
                emit colorChanged();
            },
            Qt::QueuedConnection);
    }));
}
