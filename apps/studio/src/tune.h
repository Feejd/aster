#pragma once

#include <algorithm>
#include <cmath>
#include <cstdint>
#include <vector>

// Autotune: korekcja wysokości głosu do skali piosenki, w wątku audio bez alokacji (bufory przydzielane w konstruktorze).
//
// 1. Wykrywanie wysokości — YIN (de Cheveigné i Kawahara, 2002) na sygnale zmniejszonym 4× (12 kHz przy 48 kHz),
//    co 64 próbki zmniejszonego sygnału (~5 ms), zakres 70–1000 Hz.
// 2. Cel — najbliższa nuta dozwolona w tonacji (maska 12 klas wysokości). Szybkość dojścia zależy od „ile”:
//    mało — łagodnie i naturalnie, dużo — natychmiast (charakterystyczny „robotyczny” wokal z trapu).
// 3. Przesunięcie wysokości — linia opóźniająca z dwoma odczytami, przenikanie oknem Hanna. Odczyty są oddalone
//    o jeden okres głosu, więc dla dźwięków dźwięcznych sumują się w fazie (bez brzmienia „grzebienia”).
struct TuneParams
{
    bool on = false;
    float amount = 0;          // 0…1
    uint16_t scale = 0xFFF;    // bit n = klasa wysokości n (0 = C) dozwolona
};

class PitchCorrector
{
public:
    static constexpr int Down = 4, DetSize = 1024, Window = 384, Hop = 64;
    static constexpr int LineSize = 8192;

    PitchCorrector() : m_det(DetSize, 0.f), m_line(LineSize, 0.f), m_diff(Window, 0.f) {}

    // Przetwarza mono (l i r sumowane); wynik trafia do obu kanałów
    void process(float *l, float *r, int n, const TuneParams &p, int rate)
    {
        const int fsd = rate / Down;
        const int tauMin = std::max(2, fsd / 1000), tauMax = std::min(Window - 1, fsd / 70);
        // Szybkość: 1 → ~2 ms (natychmiast), 0,5 → ~40 ms, mało → ~150 ms
        const float a = std::clamp(p.amount, 0.f, 1.f);
        const float tau = 0.002f + 0.16f * (1 - a) * (1 - a);
        const float k = 1.f - std::exp(-1.f / (tau * rate));
        const float strength = std::min(1.f, a * 1.6f);       // przy małym „ile” poprawia tylko część odchyłki

        for (int i = 0; i < n; ++i) {
            const float x = 0.5f * (l[i] + r[i]);

            // ——— wykrywanie (co Down próbek jedna próbka zmniejszona, filtr: średnia) ———
            m_acc += x;
            if (++m_accN == Down) {
                m_det[size_t(m_detPos)] = m_acc / Down;
                m_detPos = (m_detPos + 1) % DetSize;
                m_acc = 0;
                m_accN = 0;
                if (++m_hopN == Hop) {
                    m_hopN = 0;
                    detect(fsd, tauMin, tauMax, p, strength);
                }
            }

            // ——— wygładzone przesunięcie ———
            m_ratio += (m_target - m_ratio) * k;

            // ——— przesuwanie (dwa odczyty z linii opóźniającej) ———
            m_line[size_t(m_w)] = x;
            m_win += (m_winTarget - m_win) * 0.002f;
            m_phase += (1.f - m_ratio) / m_win;
            if (m_phase >= 1.f)
                m_phase -= 1.f;
            else if (m_phase < 0.f)
                m_phase += 1.f;
            const float p2 = m_phase + 0.5f >= 1.f ? m_phase - 0.5f : m_phase + 0.5f;
            const float g1 = 0.5f - 0.5f * std::cos(6.2831853f * m_phase);
            const float y = g1 * read(MinDelay + m_phase * m_win) + (1.f - g1) * read(MinDelay + p2 * m_win);
            m_w = (m_w + 1) % LineSize;
            l[i] = y;
            r[i] = y;
        }
    }

    float detectedHz() const { return m_hz; }

private:
    static constexpr float MinDelay = 8.f;

    float read(float delay) const
    {
        float pos = float(m_w) - delay;
        while (pos < 0)
            pos += LineSize;
        const int i0 = int(pos);
        const float f = pos - float(i0);
        const float a = m_line[size_t(i0 % LineSize)], b = m_line[size_t((i0 + 1) % LineSize)];
        return a + (b - a) * f;
    }

    float det(int back) const      // próbka zmniejszona sprzed `back` kroków
    {
        int i = m_detPos - 1 - back;
        while (i < 0)
            i += DetSize;
        return m_det[size_t(i)];
    }

    void detect(int fsd, int tauMin, int tauMax, const TuneParams &p, float strength)
    {
        // Za cicho — bez korekty (oddech, cisza)
        float energy = 0;
        for (int j = 0; j < Window; ++j)
            energy += det(j) * det(j);
        if (energy / Window < 1e-6f) {
            m_target = 1.f;
            return;
        }
        // YIN: funkcja różnicowa i jej skumulowana średnia normalizowana
        float running = 0;
        int best = -1;
        for (int t = 1; t <= tauMax; ++t) {
            float d = 0;
            for (int j = 0; j < Window - tauMax; ++j) {
                const float diff = det(j) - det(j + t);
                d += diff * diff;
            }
            running += d;
            m_diff[size_t(t)] = running > 0 ? d * t / running : 1.f;
        }
        for (int t = tauMin; t < tauMax; ++t) {
            if (m_diff[size_t(t)] < 0.15f) {
                while (t + 1 < tauMax && m_diff[size_t(t + 1)] < m_diff[size_t(t)])
                    ++t;
                best = t;
                break;
            }
        }
        if (best < 0) {
            m_target = 1.f;           // bezdźwięczne (sz, s, f) — nie ruszamy
            return;
        }
        // Dokładniej: parabola przez trzy punkty wokół minimum
        float tauF = float(best);
        if (best > 1 && best + 1 <= tauMax) {
            const float a = m_diff[size_t(best - 1)], b = m_diff[size_t(best)], c = m_diff[size_t(best + 1)];
            const float den = a - 2 * b + c;
            if (std::fabs(den) > 1e-9f)
                tauF += 0.5f * (a - c) / den;
        }
        m_hz = float(fsd) / tauF;
        // Okno przesuwania = dwa okresy głosu (odczyty co jeden okres — w fazie)
        const float period = float(fsd * Down) / m_hz;
        m_winTarget = std::clamp(2.f * period, 300.f, 3000.f);

        const float midi = 69.f + 12.f * std::log2(m_hz / 440.f);
        float bestNote = std::round(midi), bestDist = 99.f;
        for (int c = -6; c <= 6; ++c) {
            const int note = int(std::round(midi)) + c;
            if (!(p.scale & (1u << (((note % 12) + 12) % 12))))
                continue;
            const float dist = std::fabs(float(note) - midi);
            if (dist < bestDist) {
                bestDist = dist;
                bestNote = float(note);
            }
        }
        m_target = std::pow(2.f, (bestNote - midi) * strength / 12.f);
    }

    std::vector<float> m_det, m_line, m_diff;
    int m_detPos = 0, m_accN = 0, m_hopN = 0, m_w = 0;
    float m_acc = 0;
    float m_ratio = 1.f, m_target = 1.f, m_phase = 0.f, m_win = 960.f, m_winTarget = 960.f, m_hz = 0;
};
