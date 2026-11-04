#include "denoise.h"
#include "fft.h"

#include <QFile>
#include <algorithm>
#include <cmath>
#include <numeric>
#include <sndfile.h>

namespace Denoise {

namespace {

constexpr int N = 2048;          // 43 ms przy 48 kHz — rozdzielczość ok. 23 Hz
constexpr int Hop = N / 4;
constexpr int Bins = N / 2 + 1;

void channel(const AudioSource &src, int ch, int level, std::vector<float> &out)
{
    const long long frames = src.frames;
    const int count = int((frames + Hop - 1) / Hop) + 3;
    // Okno sqrt-Hann na wejściu i wyjściu: razem Hann, przy zakładce 75% suma = 2
    std::vector<float> win(N);
    for (int i = 0; i < N; ++i)
        win[size_t(i)] = std::sqrt(0.5f - 0.5f * std::cos(2.f * float(M_PI) * float(i) / float(N)));
    auto sample = [&](long long i) { return i >= 0 && i < frames ? src.at(i, ch) : 0.f; };

    // 1. Energia ramek (widma nie są trzymane — 3 minuty to setki MB; liczymy je jeszcze raz)
    std::vector<std::complex<float>> b(N);
    auto spectrum = [&](int f) {
        const long long start = (long long)(f - 3) * Hop;
        for (int i = 0; i < N; ++i)
            b[size_t(i)] = sample(start + i) * win[size_t(i)];
        fft(b);
    };
    std::vector<float> energy(size_t(count), 0.f);
    for (int f = 0; f < count; ++f) {
        spectrum(f);
        float e = 0;
        for (int k = 1; k < Bins; ++k)
            e += std::norm(b[size_t(k)]);
        energy[size_t(f)] = e;
    }

    // 2. Profil szumu: średnia mocy w 10% najcichszych ramek (bez zupełnej ciszy przed i po nagraniu)
    std::vector<int> order;
    for (int f = 0; f < count; ++f)
        if (energy[size_t(f)] > 1e-12f)
            order.push_back(f);
    if (order.size() < 8)
        return;
    std::sort(order.begin(), order.end(), [&](int a, int b) { return energy[size_t(a)] < energy[size_t(b)]; });
    const size_t take = std::max<size_t>(8, order.size() / 10);
    std::vector<float> noise(Bins, 0.f);
    for (size_t j = 0; j < take; ++j) {
        spectrum(order[j]);
        for (int k = 0; k < Bins; ++k)
            noise[size_t(k)] += std::norm(b[size_t(k)]);
    }
    for (float &v : noise)
        v /= float(take);

    // 3. Wzmocnienie w każdym paśmie: ile wystaje ponad szum (odejmowanie widmowe, nadmiar `over`),
    //    nie mniej niż `floor`; wygładzone w częstotliwości (3 pasma) i w czasie (szybko w górę, wolno w dół)
    const float over = level == 1 ? 2.2f : level == 2 ? 3.f : 4.f;
    const float floor = std::pow(10.f, (level == 1 ? -10.f : level == 2 ? -16.f : -24.f) / 20.f);
    std::vector<float> g(Bins), gs(Bins, 1.f), tmp(Bins);
    std::vector<float> acc(size_t((long long)count * Hop + N), 0.f);
    for (int f = 0; f < count; ++f) {
        spectrum(f);
        for (int k = 0; k < Bins; ++k) {
            const float p = std::norm(b[size_t(k)]) + 1e-20f;
            g[size_t(k)] = std::clamp(1.f - over * noise[size_t(k)] / p, 0.f, 1.f);
        }
        for (int k = 0; k < Bins; ++k)
            tmp[size_t(k)] = (g[size_t(std::max(0, k - 1))] + 2 * g[size_t(k)] + g[size_t(std::min(Bins - 1, k + 1))]) / 4;
        for (int k = 0; k < Bins; ++k) {
            const float t = tmp[size_t(k)];
            gs[size_t(k)] = t > gs[size_t(k)] ? 0.7f * t + 0.3f * gs[size_t(k)] : 0.35f * t + 0.65f * gs[size_t(k)];
            const float gain = floor + (1.f - floor) * gs[size_t(k)];
            b[size_t(k)] *= gain;
            if (k > 0 && k < N / 2)
                b[size_t(N - k)] *= gain;
        }
        fft(b, true);
        const long long at = (long long)f * Hop;
        for (int i = 0; i < N; ++i)
            acc[size_t(at + i)] += b[size_t(i)].real() * win[size_t(i)] / 2.f;
    }
    // acc[0] odpowiada próbce −3·Hop
    for (long long i = 0; i < frames; ++i)
        out[size_t(i * src.channels + ch)] = acc[size_t(i + 3 * Hop)];
}

}

std::shared_ptr<AudioSource> process(const AudioSource &src, int level)
{
    if (src.frames < N * 4)
        return {};
    auto out = std::make_shared<AudioSource>();
    out->channels = src.channels;
    out->frames = src.frames;
    out->data.assign(src.data.size(), 0.f);
    for (int ch = 0; ch < src.channels; ++ch)
        channel(src, ch, std::clamp(level, 1, 3), out->data);
    out->computePeaks();
    return out;
}

bool saveWav(const AudioSource &src, const QString &path)
{
    SF_INFO info{};
    info.samplerate = 48000;
    info.channels = src.channels;
    info.format = SF_FORMAT_WAV | SF_FORMAT_PCM_24;
    SNDFILE *sf = sf_open(QFile::encodeName(path).constData(), SFM_WRITE, &info);
    if (!sf)
        return false;
    const bool ok = sf_writef_float(sf, src.data.data(), src.frames) == src.frames;
    sf_close(sf);
    return ok;
}

}
