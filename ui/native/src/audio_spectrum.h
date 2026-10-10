#pragma once

#include <QList>
#include <QMutex>
#include <QObject>
#include <QTimer>
#include <QtQml/qqmlregistration.h>
#include <atomic>
#include <complex>
#include <vector>

struct pw_thread_loop;
struct pw_stream;

// Spectrum of what the default output is playing. Costs nothing until a visible consumer calls retain():
// then a passive PipeWire monitor stream runs on its own thread and the bands are computed on the UI
// thread at `fps`. After a second of silence the analysis stops until sound returns; at zero consumers
// the stream and its thread are gone.
class AudioSpectrum : public QObject {
    Q_OBJECT
    QML_ELEMENT
    QML_SINGLETON

    Q_PROPERTY(QList<qreal> values READ values NOTIFY valuesChanged)
    Q_PROPERTY(bool active READ active NOTIFY activeChanged)
    Q_PROPERTY(int bands READ bands WRITE setBands NOTIFY bandsChanged)
    Q_PROPERTY(int fps READ fps WRITE setFps NOTIFY fpsChanged)
    Q_PROPERTY(int consumers READ consumers NOTIFY consumersChanged)

public:
    explicit AudioSpectrum(QObject* parent = nullptr);
    ~AudioSpectrum() override;

    QList<qreal> values() const { return m_values; }
    bool active() const { return m_active; }
    int bands() const { return m_bands; }
    int fps() const { return m_fps; }
    int consumers() const { return m_consumers; }
    void setBands(int bands);
    void setFps(int fps);

    Q_INVOKABLE void retain();
    Q_INVOKABLE void release();

    // called on the PipeWire thread
    void onProcess();
    void onFormat(int rate, int channels);

signals:
    void valuesChanged();
    void activeChanged();
    void bandsChanged();
    void fpsChanged();
    void consumersChanged();

private slots:
    void wake();

private:
    void startStream();
    void stopStream();
    void tick();
    void setActive(bool active);
    void computeBins();
    void resetState();

    static constexpr int kFftSize = 4096;

    int m_consumers = 0;
    int m_bands = 32;
    int m_fps = 60;
    bool m_active = false;
    QList<qreal> m_values;
    QTimer m_timer;

    pw_thread_loop* m_loop = nullptr;
    pw_stream* m_stream = nullptr;

    // written on the PipeWire thread, read on the UI thread under m_lock
    QMutex m_lock;
    std::vector<float> m_ring;
    int m_ringPos = 0;
    bool m_ringFull = false;
    std::atomic<int> m_rate{48000};
    std::atomic<int> m_channels{2};
    std::atomic<bool> m_sleeping{true};
    // a wake that finds only silence (a stream carrying a noise floor above kWakePeak) backs off before the
    // next one, so a quiet stream does not keep the UI thread analysing nothing; audible sound always wakes
    std::atomic<qint64> m_wakeNotBefore{0};
    // when the stream last delivered audio: a paused stream (its sink idle) delivers none, and the ring would
    // otherwise hold its last sound forever — the analysis never reads silence and never sleeps
    std::atomic<qint64> m_lastAudioMs{0};
    int m_fruitlessWakes = 0;
    bool m_heardSinceWake = false;

    // analysis (UI thread)
    std::vector<float> m_window;
    std::vector<std::complex<float>> m_fft;
    std::vector<float> m_bins;
    std::vector<float> m_work, m_prev, m_peak, m_fall, m_mem;
    float m_sensitivity = 0.01F;
    bool m_sensInit = true;
    int m_silentFrames = 0;
};
