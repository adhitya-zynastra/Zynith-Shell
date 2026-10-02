#pragma once

#include <QObject>
#include <QString>
#include <QTimer>
#include <QtQml/qqmlregistration.h>

// Screen brightness. Read from sysfs, written through logind (Session.SetBrightness), so no privileges and
// no helper process. The kernel does not announce changes made elsewhere (brightness keys), so while
// something shows the value (retain) it is re-read once a second; otherwise nothing runs.
class Backlight : public QObject {
    Q_OBJECT
    QML_ELEMENT
    QML_SINGLETON

    Q_PROPERTY(bool available READ available CONSTANT)
    Q_PROPERTY(QString device READ device CONSTANT)
    Q_PROPERTY(qreal value READ value NOTIFY valueChanged)

public:
    explicit Backlight(QObject* parent = nullptr);
    ~Backlight() override;

    bool available() const { return m_max > 0; }
    QString device() const { return m_device; }
    qreal value() const { return m_max > 0 ? qreal(m_current) / m_max : 0; }

    Q_INVOKABLE void retain();
    Q_INVOKABLE void release();
    // 0..1; never fully dark, so the screen cannot be turned off by accident
    Q_INVOKABLE void set(qreal value);

signals:
    void valueChanged();

private:
    void read();
    void send();

    QString m_device;
    QString m_dir;
    int m_max = 0;
    int m_current = 0;
    int m_consumers = 0;
    int m_wanted = -1;   // the latest requested raw value not yet sent
    bool m_inFlight = false;
    QTimer m_poll;
};
