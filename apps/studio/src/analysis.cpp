#include "analysis.h"
#include "fft.h"

#include <algorithm>
#include <array>
#include <cmath>
#include <complex>
#include <numeric>

namespace Analysis {

namespace {

constexpr int Down = 4;                 // 48 kHz → 12 kHz: wystarcza na rytm i wysokości do ~2 kHz

// Widma amplitudowe kolejnych ramek (okno Hanna)
template<typename F>
void frames(const std::vector<float> &x, int size, int hop, F &&each)
{
    std::vector<float> win(static_cast<size_t>(size));
    for (int i = 0; i < size; ++i)
        win[size_t(i)] = 0.5f - 0.5f * std::cos(2.f * float(M_PI) * float(i) / float(size));
    std::vector<std::complex<float>> buf(static_cast<size_t>(size));
    std::vector<float> mag(static_cast<size_t>(size / 2));
    for (size_t start = 0; start + size_t(size) <= x.size(); start += size_t(hop)) {
        for (int i = 0; i < size; ++i)
            buf[size_t(i)] = x[start + size_t(i)] * win[size_t(i)];
        fft(buf);
        for (int i = 0; i < size / 2; ++i)
            mag[size_t(i)] = std::abs(buf[size_t(i)]);
        each(mag);
    }
}

// Wartość ciągu w punkcie ułamkowym (interpolacja liniowa)
float at(const std::vector<float> &v, double i)
{
    if (i < 0 || i >= double(v.size() - 1))
        return 0.f;
    const size_t k = size_t(i);
    const float f = float(i - double(k));
    return v[k] + (v[k + 1] - v[k]) * f;
}

}

Result analyze(const AudioSource &src, int rate)
{
    Result r;
    const int fs = rate / Down;
    if (src.frames < rate * 4)
        return r;                                    // za krótki na rozpoznanie

    // Mono, zmniejszone 4× (średnia — dość jako filtr przed decymacją dla tych celów)
    std::vector<float> x(static_cast<size_t>(src.frames / Down));
    for (size_t i = 0; i < x.size(); ++i) {
        float s = 0;
        for (int k = 0; k < Down; ++k) {
            const long long f = (long long)(i) * Down + k;
            s += src.channels > 1 ? 0.5f * (src.at(f, 0) + src.at(f, 1)) : src.at(f, 0);
        }
        x[i] = s / Down;
    }

    // Cisza na początku (próg −40 dB względem szczytu)
    float peak = 0;
    for (float v : x)
        peak = std::max(peak, std::fabs(v));
    if (peak < 1e-4f)
        return r;
    size_t lead = 0;
    while (lead < x.size() && std::fabs(x[lead]) < peak * 0.01f)
        ++lead;
    r.leadIn = double(lead) / fs;

    // ——— Tempo ———
    constexpr int OnN = 512, OnHop = 128;
    const double fps = double(fs) / OnHop;            // ~94 ramki na sekundę
    std::vector<float> flux, fluxLow;              // całe pasmo (tempo) i do 1,5 kHz (faza: stopa, werbel)
    {
        const size_t lowBins = size_t(1500.0 * OnN / fs);
        std::vector<float> prev;
        frames(x, OnN, OnHop, [&](const std::vector<float> &mag) {
            std::vector<float> lm(mag.size());
            for (size_t i = 0; i < mag.size(); ++i)
                lm[i] = std::log1p(100.f * mag[i]);
            float f = 0, fl = 0;
            if (!prev.empty())
                for (size_t i = 1; i < lm.size(); ++i) {
                    const float d = std::max(0.f, lm[i] - prev[i]);
                    f += d;
                    if (i < lowBins)
                        fl += d;
                }
            flux.push_back(f);
            fluxLow.push_back(fl);
            prev.swap(lm);
        });
    }
    // Odjęcie średniej lokalnej (~0,5 s) — zostają same uderzenia
    auto onsets = [&](const std::vector<float> &in) {
        std::vector<float> out(in.size());
        const int w = int(fps * 0.25);
        std::vector<double> pre(in.size() + 1, 0);
        for (size_t i = 0; i < in.size(); ++i)
            pre[i + 1] = pre[i] + in[i];
        for (size_t i = 0; i < in.size(); ++i) {
            const size_t a = i >= size_t(w) ? i - size_t(w) : 0, b = std::min(in.size(), i + size_t(w) + 1);
            out[i] = std::max(0.f, in[i] - float((pre[b] - pre[a]) / double(b - a)));
        }
        return out;
    };
    const std::vector<float> env = onsets(flux), envLow = onsets(fluxLow);
    // Autokorelacja do 16 uderzeń przy 60 BPM — długie opóźnienia dają dokładne tempo
    const int maxLag = int(fps * 16) + 4;
    std::vector<float> ac(static_cast<size_t>(maxLag + 2), 0.f);
    {
        const double mean = std::accumulate(env.begin(), env.end(), 0.0) / std::max<size_t>(1, env.size());
        std::vector<float> e(env.size());
        for (size_t i = 0; i < env.size(); ++i)
            e[i] = env[i] - float(mean);
        for (int lag = 0; lag <= maxLag + 1 && size_t(lag) < e.size(); ++lag) {
            double s = 0;
            for (size_t i = size_t(lag); i < e.size(); ++i)
                s += double(e[i]) * e[i - size_t(lag)];
            ac[size_t(lag)] = float(s / double(e.size() - size_t(lag)));
        }
        if (ac[0] > 0)
            for (float &v : ac)
                v /= ac[0];
    }
    auto score = [&](double bpm) {
        const double lag = fps * 60.0 / bpm;
        // Okres, jego wielokrotności (takty) i połowa (ósemki) — prawdziwe tempo zgadza się ze wszystkimi
        const double s = at(ac, lag) + 0.5 * at(ac, 2 * lag) + 0.5 * at(ac, 4 * lag) + 0.25 * at(ac, lag / 2);
        const double oct = std::log2(bpm / 120.0) / 0.9;
        return s * std::exp(-0.5 * oct * oct);
    };
    double best = 0, bestScore = -1;
    for (double b = 60; b <= 190; b += 0.25) {
        const double s = score(b);
        if (s > bestScore) {
            bestScore = s;
            best = b;
        }
    }
    if (bestScore > 0) {
        // Dokładniej: szczyty autokorelacji przy 4, 8 i 16 uderzeniach (długie opóźnienie = mały błąd względny)
        double fine = best, fineScore = -1;
        for (double b = best - 1.0; b <= best + 1.0; b += 0.01) {
            const double lag = fps * 60.0 / b;
            const double s = at(ac, lag) + at(ac, 4 * lag) + at(ac, 8 * lag) + at(ac, 16 * lag);
            if (s > fineScore) {
                fineScore = s;
                fine = b;
            }
        }
        best = std::abs(fine - std::round(fine)) < 0.35 ? std::round(fine) : std::round(fine * 10) / 10;
        r.bpm = best;
        r.beatStrength = std::clamp(at(ac, fps * 60.0 / best) * 1.5, 0.0, 1.0);

        // Faza uderzeń: przesunięcie, przy którym stopa i werbel (pasmo do 1,5 kHz, bez hi-hatów na ósemkach)
        // wypadają najmocniej. Gotowe bity prawie zawsze zaczynają się na „raz”, więc jeśli pierwszy dźwięk
        // pliku pasuje do rytmu niewiele gorzej niż najlepsze przesunięcie — wygrywa on (synkopowana stopa
        // trapu potrafi przeważyć „i” nad „raz”).
        const double period = fps * 60.0 / best;
        auto phaseScore = [&](const std::vector<float> &e, double p) {
            double s = 0;
            for (double t = p; t < double(e.size()) - 1; t += period)
                s += at(e, t - 0.5) + at(e, t) + at(e, t + 0.5);
            return s;
        };
        // Klatka zgłasza uderzenie, gdy jego atak jest mniej więcej w środku okna: frame = (czas·fs − N/2) / hop
        auto frameOf = [&](double sec) { return std::fmod(std::fmod((sec * fs - OnN / 2.0) / OnHop, period) + period, period); };
        // Całe pasmo myli się, gdy hi-haty i synkopowana stopa przeważają „i”; samo dolne — gdy bas gra na „i” (house).
        // Pierwszy dźwięk wygrywa, jeśli pasuje w którymkolwiek; inaczej suma obu.
        double bestPhase = 0, topAll = -1, topLow = -1;
        for (double p = 0; p < period; p += 0.25) {
            topAll = std::max(topAll, phaseScore(env, p));
            topLow = std::max(topLow, phaseScore(envLow, p));
        }
        double sumBest = -1;
        for (double p = 0; p < period; p += 0.25) {
            const double v = phaseScore(env, p) / std::max(1e-9, topAll) + phaseScore(envLow, p) / std::max(1e-9, topLow);
            if (v > sumBest) {
                sumBest = v;
                bestPhase = p;
            }
        }
        const double leadPhase = frameOf(r.leadIn);
        if (phaseScore(env, leadPhase) >= 0.6 * topAll || phaseScore(envLow, leadPhase) >= 0.6 * topLow)
            bestPhase = leadPhase;
        const double beatSec = 60.0 / best;
        double t = std::fmod((bestPhase * OnHop + OnN / 2.0) / fs, beatSec);
        if (beatSec - t < 0.02)                     // tuż przed zerem = właściwie zero
            t = 0;
        r.firstBeat = t;
        // Pierwszy „raz”: pierwsze uderzenie siatki przy pierwszym dźwięku pliku
        r.firstBar = t + std::max(0.0, std::ceil((r.leadIn - 0.03 - t) / beatSec)) * beatSec;
    }

    // ——— Tonacja ———
    constexpr int KeyN = 8192, KeyHop = 4096;      // 0,68 s, rozdzielczość ~1,5 Hz — dość na basy
    std::array<double, 12> chroma{};
    frames(x, KeyN, KeyHop, [&](const std::vector<float> &mag) {
        // Tylko szczyty widma (dźwięki), nie szum perkusji; wysokość z paraboli przez trzy prążki
        const int lo = int(30.0 * KeyN / fs), hi = std::min(int(mag.size()) - 2, int(1000.0 * KeyN / fs));
        float top = 0;
        for (int k = lo; k <= hi; ++k)
            top = std::max(top, mag[size_t(k)]);
        if (top <= 1e-5f)
            return;
        std::array<double, 12> c{};
        double sum = 0;
        for (int k = std::max(lo, 1); k <= hi; ++k) {
            const float m = mag[size_t(k)];
            if (m < top * 0.05f || m <= mag[size_t(k - 1)] || m < mag[size_t(k + 1)])
                continue;
            const double a = mag[size_t(k - 1)], b = m, cc = mag[size_t(k + 1)];
            const double den = a - 2 * b + cc;
            const double shift = std::abs(den) > 1e-12 ? 0.5 * (a - cc) / den : 0.0;
            const double f = (k + shift) * fs / KeyN;
            const double midi = 69 + 12 * std::log2(f / 440.0);
            const int p = ((int(std::lround(midi)) % 12) + 12) % 12;
            const double w = double(m) * (f < 250 ? 1.5 : 1.0);
            c[size_t(p)] += w;
            sum += w;
        }
        if (sum <= 0)
            return;
        for (int i = 0; i < 12; ++i)
            chroma[size_t(i)] += c[size_t(i)] / sum;      // każda ramka waży tyle samo
    });
    // Profile Krumhansla–Kesslera (w próbach trafniejsze od profili Temperleya dla bitów)
    static const double major[12] = {6.35, 2.23, 3.48, 2.33, 4.38, 4.09, 2.52, 5.19, 2.39, 3.66, 2.29, 2.88};
    static const double minor[12] = {6.33, 2.68, 3.52, 5.38, 2.60, 3.53, 2.54, 4.75, 3.98, 2.69, 3.34, 3.17};
    auto corr = [&](const double *prof, int root) {
        double mx = 0, my = 0;
        for (int i = 0; i < 12; ++i) {
            mx += chroma[size_t((i + root) % 12)];
            my += prof[i];
        }
        mx /= 12;
        my /= 12;
        double sxy = 0, sxx = 0, syy = 0;
        for (int i = 0; i < 12; ++i) {
            const double a = chroma[size_t((i + root) % 12)] - mx, b = prof[i] - my;
            sxy += a * b;
            sxx += a * a;
            syy += b * b;
        }
        return sxx > 0 && syy > 0 ? sxy / std::sqrt(sxx * syy) : 0.0;
    };
    double first = -2, second = -2;
    for (int root = 0; root < 12; ++root) {
        for (int m = 0; m < 2; ++m) {
            // Rap i trap to głównie moll — mała premia rozstrzyga dwuznaczność z równoległym durem
            const double c = corr(m ? minor : major, root) + (m ? 0.02 : 0.0);
            if (c > first) {
                second = first;
                first = c;
                r.keyRoot = root;
                r.minor = m;
            } else if (c > second) {
                second = c;
            }
        }
    }
    if (first < 0.3)
        r.keyRoot = -1;
    r.keyConfidence = std::clamp((first - second) * 5.0, 0.0, 1.0);
    return r;
}

}
