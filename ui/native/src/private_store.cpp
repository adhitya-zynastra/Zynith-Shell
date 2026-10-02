#include "private_store.h"

#include <QDir>
#include <QFile>
#include <QFileInfo>
#include <QSaveFile>

PrivateStore::PrivateStore(QObject* parent)
    : QObject(parent) {}

void PrivateStore::setPath(const QString& path) {
    if (path == m_path)
        return;
    m_path = path;
    emit pathChanged();
    m_text.clear();
    m_ready = false;
    if (!path.isEmpty()) {
        QFile file(path);
        if (file.open(QIODevice::ReadOnly))
            m_text = QString::fromUtf8(file.readAll());
    }
    m_ready = !path.isEmpty();
    emit loaded();
}

bool PrivateStore::save(const QString& text) {
    if (m_path.isEmpty())
        return false;
    const QString dir = QFileInfo(m_path).absolutePath();
    if (!QDir().mkpath(dir))
        return false;
    QFile::setPermissions(dir, QFileDevice::ReadOwner | QFileDevice::WriteOwner | QFileDevice::ExeOwner);
    QSaveFile out(m_path);
    if (!out.open(QIODevice::WriteOnly))
        return false;
    // the temporary file gets the mode before any content is in it
    out.setPermissions(QFileDevice::ReadOwner | QFileDevice::WriteOwner);
    out.write(text.toUtf8());
    if (!out.commit())
        return false;
    m_text = text;
    return true;
}

void PrivateStore::remove() {
    if (!m_path.isEmpty())
        QFile::remove(m_path);
    m_text.clear();
}
