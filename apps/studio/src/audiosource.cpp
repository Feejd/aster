#include "audiosource.h"

#include <QFile>
#include <QFileInfo>
#include <algorithm>
#include <samplerate.h>
#include <sndfile.h>

void AudioSource::computePeaks()
{
    const long long blocks = (frames + PeakStep - 1) / PeakStep;
    peaks.assign(size_t(blocks * 2), 0.f);
    for (long long b = 0; b < blocks; ++b) {
        float lo = 0.f, hi = 0.f;
        const long long end = std::min(frames, (b + 1) * PeakStep);
        for (long long f = b * PeakStep; f < end; ++f) {
            float v = data[size_t(f * channels)];
            if (channels > 1)
                v = 0.5f * (v + data[size_t(f * channels + 1)]);
            lo = std::min(lo, v);
            hi = std::max(hi, v);
        }
        peaks[size_t(b * 2)] = lo;
        peaks[size_t(b * 2 + 1)] = hi;
    }
}

std::shared_ptr<AudioSource> loadAudio(const QString &path, int rate, QString *error)
{
    SF_INFO info{};
    SNDFILE *sf = sf_open(QFile::encodeName(path).constData(), SFM_READ, &info);
    if (!sf) {
        if (error)
            *error = QStringLiteral("Nie udało się otworzyć pliku „%1”: %2").arg(QFileInfo(path).fileName(), QString::fromUtf8(sf_strerror(nullptr)));
        return {};
    }
    // Więcej niż dwa kanały: zostają pierwsze dwa
    const int inCh = info.channels;
    const int ch = std::min(inCh, 2);
    std::vector<float> raw;
    raw.reserve(size_t(std::max<sf_count_t>(info.frames, 0) * ch));
    std::vector<float> buf(size_t(4096 * inCh));
    for (;;) {
        const sf_count_t n = sf_readf_float(sf, buf.data(), 4096);
        if (n <= 0)
            break;
        for (sf_count_t f = 0; f < n; ++f)
            for (int c = 0; c < ch; ++c)
                raw.push_back(buf[size_t(f * inCh + c)]);
    }
    sf_close(sf);
    if (raw.empty()) {
        if (error)
            *error = QStringLiteral("Plik „%1” nie zawiera dźwięku.").arg(QFileInfo(path).fileName());
        return {};
    }

    auto src = std::make_shared<AudioSource>();
    src->file = QFileInfo(path).fileName();
    src->channels = ch;
    if (info.samplerate == rate) {
        src->data = std::move(raw);
    } else {
        const double ratio = double(rate) / info.samplerate;
        const long long inFrames = (long long)raw.size() / ch;
        src->data.resize(size_t((inFrames * ratio + 64) * ch));
        SRC_DATA d{};
        d.data_in = raw.data();
        d.input_frames = long(inFrames);
        d.data_out = src->data.data();
        d.output_frames = long(src->data.size() / ch);
        d.src_ratio = ratio;
        const int err = src_simple(&d, SRC_SINC_MEDIUM_QUALITY, ch);
        if (err) {
            if (error)
                *error = QString::fromUtf8(src_strerror(err));
            return {};
        }
        src->data.resize(size_t(d.output_frames_gen * ch));
    }
    src->frames = (long long)src->data.size() / ch;
    src->computePeaks();
    return src;
}
