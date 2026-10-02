#include "audio_spectrum.h"

#include <QMutexLocker>
#include <algorithm>
#include <cmath>
#include <numbers>

#include <pipewire/pipewire.h>
#include <spa/param/audio/format-utils.h>
#include <spa/pod/builder.h>

namespace {

constexpr float kLowHz = 20.0F;
constexpr float kHighHz = 20000.0F;
constexpr float kNoiseReduction = 0.77F;
constexpr float kMaxLevel = 0.9F;
constexpr float kMinSensitivity = 0.001F;
constexpr float kMaxSensitivity = 30.0F;
// below this (after gain) a band counts as silent; a frame of all-silent bands for a second → idle
constexpr float kSilence = 0.01F;
// a buffer whose peak is under this wakes nothing
constexpr float kWakePeak = 0.0005F;

void fft(std::complex<float>* data, int n) {
    for (int i = 1, j = 0; i < n; ++i) {
        int bit = n >> 1;
        for (; j & bit; bit >>= 1)
            j ^= bit;
        j ^= bit;
        if (i < j)
            std::swap(data[i], data[j]);
    }
    for (int len = 2; len <= n; len <<= 1) {
        const float angle = -2.0F * std::numbers::pi_v<float> / static_cast<float>(len);
        const std::complex<float> wn(std::cos(angle), std::sin(angle));
        for (int i = 0; i < n; i += len) {
            std::complex<float> w(1.0F, 0.0F);
            for (int j = 0; j < len / 2; ++j) {
                const auto u = data[i + j];
                const auto v = data[i + j + len / 2] * w;
                data[i + j] = u + v;
                data[i + j + len / 2] = u - v;
                w *= wn;
            }
        }
    }
}

void onProcessCb(void* data) { static_cast<AudioSpectrum*>(data)->onProcess(); }

void onParamChangedCb(void* data, uint32_t id, const spa_pod* param) {
    if (param == nullptr || id != SPA_PARAM_Format)
        return;
    spa_audio_info_raw raw{};
    uint32_t mediaType = 0, mediaSubtype = 0;
    if (spa_format_parse(param, &mediaType, &mediaSubtype) < 0 || mediaType != SPA_MEDIA_TYPE_audio
        || mediaSubtype != SPA_MEDIA_SUBTYPE_raw)
        return;
    if (spa_format_audio_raw_parse(param, &raw) < 0 || raw.format != SPA_AUDIO_FORMAT_F32)
        return;
    static_cast<AudioSpectrum*>(data)->onFormat(static_cast<int>(raw.rate), static_cast<int>(raw.channels));
}

pw_stream_events makeStreamEvents() {
    pw_stream_events events{};
    events.version = PW_VERSION_STREAM_EVENTS;
    events.param_changed = onParamChangedCb;
    events.process = onProcessCb;
    return events;
}

const pw_stream_events kStreamEvents = makeStreamEvents();

} // namespace

AudioSpectrum::AudioSpectrum(QObject* parent)
    : QObject(parent) {
    pw_init(nullptr, nullptr);
    m_timer.setTimerType(Qt::PreciseTimer);
    connect(&m_timer, &QTimer::timeout, this, &AudioSpectrum::tick);
    m_window.resize(kFftSize);
    for (int i = 0; i < kFftSize; ++i)
        m_window[i] = 0.5F * (1.0F - std::cos(2.0F * std::numbers::pi_v<float> * i / (kFftSize - 1)));
    m_fft.resize(kFftSize);
    m_ring.assign(kFftSize, 0.0F);
    resetState();
}

AudioSpectrum::~AudioSpectrum() { stopStream(); }

void AudioSpectrum::setBands(int bands) {
    bands = std::clamp(bands, 1, 256);
    if (bands == m_bands)
        return;
    m_bands = bands;
    resetState();
    emit bandsChanged();
    emit valuesChanged();
}

void AudioSpectrum::setFps(int fps) {
    fps = std::clamp(fps, 1, 240);
    if (fps == m_fps)
        return;
    m_fps = fps;
    if (m_timer.isActive())
        m_timer.start(1000 / m_fps);
    emit fpsChanged();
}

void AudioSpectrum::retain() {
    if (++m_consumers == 1)
        startStream();
    emit consumersChanged();
}

void AudioSpectrum::release() {
    if (m_consumers == 0)
        return;
    if (--m_consumers == 0) {
        stopStream();
        m_timer.stop();
        resetState();
        setActive(false);
        emit valuesChanged();
    }
    emit consumersChanged();
}

void AudioSpectrum::startStream() {
    m_loop = pw_thread_loop_new("zynith-spectrum", nullptr);
    if (m_loop == nullptr)
        return;
    pw_thread_loop_lock(m_loop);
    // passive: the capture never keeps the output awake; no target: it follows the default output
    pw_properties* props = pw_properties_new(PW_KEY_MEDIA_TYPE, "Audio", PW_KEY_MEDIA_CATEGORY, "Capture",
        PW_KEY_MEDIA_NAME, "Zynith Spectrum", PW_KEY_APP_NAME, "Zynith", PW_KEY_STREAM_CAPTURE_SINK, "true",
        PW_KEY_NODE_PASSIVE, "true", nullptr);
    m_stream = pw_stream_new_simple(pw_thread_loop_get_loop(m_loop), "zynith-spectrum", props, &kStreamEvents, this);
    if (m_stream != nullptr) {
        uint8_t buffer[512];
        spa_pod_builder b = SPA_POD_BUILDER_INIT(buffer, sizeof(buffer));
        spa_audio_info_raw raw = SPA_AUDIO_INFO_RAW_INIT(.format = SPA_AUDIO_FORMAT_F32);
        const spa_pod* params[1] = {spa_format_audio_raw_build(&b, SPA_PARAM_EnumFormat, &raw)};
        pw_stream_connect(m_stream, PW_DIRECTION_INPUT, PW_ID_ANY,
            static_cast<pw_stream_flags>(PW_STREAM_FLAG_AUTOCONNECT | PW_STREAM_FLAG_MAP_BUFFERS), params, 1);
    }
    pw_thread_loop_unlock(m_loop);
    m_sleeping = true;
    pw_thread_loop_start(m_loop);
}

void AudioSpectrum::stopStream() {
    if (m_loop == nullptr)
        return;
    pw_thread_loop_stop(m_loop);
    if (m_stream != nullptr) {
        pw_stream_destroy(m_stream);
        m_stream = nullptr;
    }
    pw_thread_loop_destroy(m_loop);
    m_loop = nullptr;
}

void AudioSpectrum::onFormat(int rate, int channels) {
    m_rate = std::max(1, rate);
    m_channels = std::max(1, channels);
}

void AudioSpectrum::onProcess() {
    pw_buffer* b = pw_stream_dequeue_buffer(m_stream);
    if (b == nullptr)
        return;
    const spa_buffer* buf = b->buffer;
    if (buf != nullptr && buf->n_datas > 0 && buf->datas[0].data != nullptr && buf->datas[0].chunk != nullptr) {
        const spa_data& d = buf->datas[0];
        const int channels = m_channels.load();
        const auto* samples = reinterpret_cast<const float*>(static_cast<const uint8_t*>(d.data) + d.chunk->offset);
        const int frames = static_cast<int>(d.chunk->size / sizeof(float)) / channels;
        float peak = 0.0F;
        {
            QMutexLocker lock(&m_lock);
            for (int f = 0; f < frames; ++f) {
                float mono = 0.0F;
                for (int c = 0; c < channels; ++c)
                    mono += samples[f * channels + c];
                mono /= static_cast<float>(channels);
                peak = std::max(peak, std::abs(mono));
                m_ring[m_ringPos] = mono;
                m_ringPos = (m_ringPos + 1) % kFftSize;
                if (m_ringPos == 0)
                    m_ringFull = true;
            }
        }
        // the UI side sleeps through silence; sound wakes it once
        if (peak > kWakePeak && m_sleeping.exchange(false))
            QMetaObject::invokeMethod(this, "wake", Qt::QueuedConnection);
    }
    pw_stream_queue_buffer(m_stream, b);
}

void AudioSpectrum::wake() {
    if (m_consumers == 0)
        return;
    m_silentFrames = 0;
    if (!m_timer.isActive())
        m_timer.start(1000 / m_fps);
}

void AudioSpectrum::computeBins() {
    const int rate = m_rate.load();
    const float high = std::min(kHighHz, rate / 2.0F);
    const float ratio = high / kLowHz;
    m_bins.resize(m_bands);
    for (int i = 0; i < m_bands; ++i) {
        const float t = m_bands > 1 ? static_cast<float>(i) / (m_bands - 1) : 0.0F;
        m_bins[i] = std::clamp(kLowHz * std::pow(ratio, t) * kFftSize / rate, 1.0F, kFftSize / 2.0F);
    }
}

void AudioSpectrum::resetState() {
    m_work.assign(m_bands, 0.0F);
    m_prev.assign(m_bands, 0.0F);
    m_peak.assign(m_bands, 0.0F);
    m_fall.assign(m_bands, 0.0F);
    m_mem.assign(m_bands, 0.0F);
    m_values = QList<qreal>(m_bands, 0.0);
    m_sensitivity = 0.01F;
    m_sensInit = true;
    m_silentFrames = 0;
}

void AudioSpectrum::tick() {
    {
        QMutexLocker lock(&m_lock);
        if (!m_ringFull)
            return;
        for (int i = 0; i < kFftSize; ++i)
            m_fft[i] = {m_ring[(m_ringPos + i) % kFftSize] * m_window[i], 0.0F};
    }
    computeBins();
    fft(m_fft.data(), kFftSize);

    const float gate = kNoiseReduction * kFftSize * 0.00005F;
    bool silent = true;
    bool overshoot = false;
    for (int i = 0; i < m_bands; ++i) {
        const int lo = std::clamp(static_cast<int>(std::floor(m_bins[i])), 1, kFftSize / 2);
        const int hi = std::min(lo + 1, kFftSize / 2);
        const float t = std::clamp(m_bins[i] - lo, 0.0F, 1.0F);
        float v = std::abs(m_fft[lo]) + (std::abs(m_fft[hi]) - std::abs(m_fft[lo])) * t;
        v = std::max(0.0F, v - gate);
        // log compression keeps treble visible beside loud bass
        v = std::log1p(v * 0.15F) / 0.15F * m_sensitivity;
        if (v > kMaxLevel) {
            overshoot = true;
            v = kMaxLevel;
        }
        if (v > kSilence)
            silent = false;
        m_work[i] = v;
    }

    // automatic gain: back off on overshoot, creep up otherwise
    if (overshoot) {
        m_sensitivity *= 0.98F;
        m_sensInit = false;
    } else if (!silent) {
        m_sensitivity *= m_sensInit ? 1.1F : 1.001F;
    }
    m_sensitivity = std::clamp(m_sensitivity, kMinSensitivity, kMaxSensitivity);

    if (silent) {
        if (++m_silentFrames >= m_fps) {
            m_timer.stop();
            m_sleeping = true;
            resetState();
            setActive(false);
            emit valuesChanged();
            return;
        }
    } else {
        m_silentFrames = 0;
        setActive(true);
    }

    // gravity fall-off, then integration
    const double gravity = std::max(1.0, 1.54 / std::max<double>(kNoiseReduction, 0.01)) * (60.0 / m_fps);
    for (int i = 0; i < m_bands; ++i) {
        float v = m_work[i];
        if (v < m_prev[i]) {
            v = std::max(0.0F, static_cast<float>(m_peak[i] * (1.0 - m_fall[i] * m_fall[i] * gravity)));
            m_fall[i] += 0.04F;
        } else {
            m_peak[i] = v;
            m_fall[i] = 0.0F;
        }
        m_prev[i] = v;
        v = std::clamp(m_mem[i] * kNoiseReduction + v * (1.0F - kNoiseReduction), 0.0F, kMaxLevel);
        m_mem[i] = v;
        m_work[i] = v;
    }

    // soft neighbours: each band lends a little height to the ones beside it
    for (int z = 0; z < m_bands; ++z) {
        float spread = m_work[z] / 1.5F;
        for (int m = z - 1; m >= 0 && spread > 0.01F; --m, spread /= 1.5F)
            m_work[m] = std::max(m_work[m], spread);
        spread = m_work[z] / 1.5F;
        for (int m = z + 1; m < m_bands && spread > 0.01F; ++m, spread /= 1.5F)
            m_work[m] = std::max(m_work[m], spread);
    }

    bool changed = false;
    for (int i = 0; i < m_bands; ++i) {
        const qreal v = std::round(m_work[i] / kMaxLevel * 1000.0) / 1000.0;
        if (m_values[i] != v) {
            m_values[i] = v;
            changed = true;
        }
    }
    if (changed)
        emit valuesChanged();
}

void AudioSpectrum::setActive(bool active) {
    if (active == m_active)
        return;
    m_active = active;
    emit activeChanged();
}
