#pragma once

#include <array>
#include <cmath>
#include <cstdint>

// Jeden głos instrumentu melodycznego (Pianino, Klawisze elektryczne, Pad, Pluck, Dzwonki, Lead) — próbka po próbce.
// Ten sam kod liczy nuty ścieżek Akordy/Melodia (poza czasem rzeczywistym) i gra na żywo z klawiatury
// (w wątku audio: bez alokacji, cały stan w obiekcie). Nuta brzmi, dopóki nie przyjdzie release(),
// potem wycisza się w czasie właściwym instrumentowi.
class SynthVoice
{
public:
    enum Inst { Piano, EPiano, Pad, Pluck, Bells, Lead };
    static constexpr int MaxString = 4096;            // najniższy dźwięk struny Pluck: rate / MaxString (~12 Hz)

    void start(Inst inst, double freq, int rate, uint32_t seed, float gain = 1.f)
    {
        m_inst = inst;
        m_f = freq;
        m_rate = rate;
        m_gain = gain;
        m_seed = seed ? seed : 1;
        m_i = 0;
        m_relAt = -1;
        m_ph = m_ph2 = m_ph3 = m_lp = 0;
        m_rel = inst == Pad ? 0.45 : (inst == Bells || inst == Pluck) ? 1.2 : 0.25;
        m_active = true;
        if (inst == Pluck) {
            m_ksLen = int(std::clamp(rate / freq, 2.0, double(MaxString)));
            for (int i = 0; i < m_ksLen; ++i)
                m_ks[size_t(i)] = noise();
            m_ksPos = 0;
        }
    }
    void release()
    {
        if (m_active && m_relAt < 0)
            m_relAt = m_i;
    }
    bool active() const { return m_active; }
    bool released() const { return m_relAt >= 0; }
    double releaseSeconds() const { return m_rel; }

    float next()
    {
        if (!m_active)
            return 0.f;
        const double rate = m_rate, f = m_f, dt = f / rate;
        const double t = double(m_i) / rate;
        double off = 1;
        if (m_relAt >= 0) {
            const double since = double(m_i - m_relAt) / rate;
            off = std::exp(-since * (3.0 / m_rel) * 2.3);
            if (since > m_rel * 1.5)
                m_active = false;
        } else if (t > 12 && m_inst != Pad && m_inst != Lead) {
            m_active = false;                          // instrumenty gasnące same — po 12 s już nic nie słychać
        }
        double y = 0;
        switch (m_inst) {
        case Piano:
            for (int h = 1; h <= 8; ++h) {
                const double hf = h * std::sqrt(1 + 0.0004 * h * h);
                y += std::sin(2 * M_PI * f * hf * t) * std::pow(h, -1.1) * std::exp(-t * (0.7 + 0.55 * h));
            }
            y *= 0.55 * std::min(1.0, t / 0.002);
            y += noise() * std::exp(-t * 300) * 0.05;
            break;
        case EPiano: {
            const double index = 1.6 * std::exp(-t * 4) + 0.25;
            y = std::sin(2 * M_PI * f * t + index * std::sin(2 * M_PI * f * t)) * std::exp(-t * 0.9);
            y += 0.12 * std::sin(2 * M_PI * f * 7.0 * t) * std::exp(-t * 14);
            y *= 0.6 * std::min(1.0, t / 0.003);
            break;
        }
        case Pad: {
            // Trzy rozstrojone piły przez łagodny filtr; powolne narastanie
            const double d2 = dt * 1.0046, d3 = dt * 0.9954;
            m_ph += dt; m_ph -= std::floor(m_ph);
            m_ph2 += d2; m_ph2 -= std::floor(m_ph2);
            m_ph3 += d3; m_ph3 -= std::floor(m_ph3);
            const double saw = (2 * m_ph - 1 - blep(m_ph, dt)) + (2 * m_ph2 - 1 - blep(m_ph2, d2)) + (2 * m_ph3 - 1 - blep(m_ph3, d3));
            const double cutoff = 900 + 900 * std::min(1.0, t / 1.5);
            m_lp += (1 - std::exp(-2 * M_PI * cutoff / rate)) * (saw / 3 - m_lp);
            y = m_lp * 0.9 * std::min(1.0, t / 0.35);
            break;
        }
        case Pluck: {
            // Karplus–Strong: szum w pętli opóźniającej z uśrednianiem — szarpana struna
            const float a = m_ks[size_t(m_ksPos)], b = m_ks[size_t((m_ksPos + 1) % m_ksLen)];
            m_ks[size_t(m_ksPos)] = 0.5f * (a + b) * 0.996f;
            m_ksPos = (m_ksPos + 1) % m_ksLen;
            y = a * 0.7;
            break;
        }
        case Bells: {
            const double index = 2.4 * std::exp(-t * 2.2);
            y = std::sin(2 * M_PI * f * t + index * std::sin(2 * M_PI * f * 3.5 * t)) * std::exp(-t * 1.6) * 0.6;
            y += 0.2 * std::sin(2 * M_PI * f * 2 * t) * std::exp(-t * 3);
            break;
        }
        case Lead: {
            const double vib = t > 0.2 ? 1 + 0.005 * std::sin(2 * M_PI * 5.2 * t) : 1;
            const double d = dt * vib;
            m_ph += d; m_ph -= std::floor(m_ph);
            double q = m_ph < 0.5 ? 1 : -1;
            q += blep(m_ph, d);
            double p2 = m_ph + 0.5; p2 -= std::floor(p2);
            q -= blep(p2, d);
            m_lp += (1 - std::exp(-2 * M_PI * 2600 / rate)) * (q - m_lp);
            y = m_lp * 0.4 * std::min(1.0, t / 0.01);
            break;
        }
        }
        ++m_i;
        return float(y * off) * m_gain;
    }

private:
    // Piła i prostokąt z wygładzonymi skokami (PolyBLEP) — bez „cyfrowego” aliasingu
    static double blep(double t, double dt)
    {
        if (t < dt) {
            t /= dt;
            return t + t - t * t - 1;
        }
        if (t > 1 - dt) {
            t = (t - 1) / dt;
            return t * t + t + t + 1;
        }
        return 0;
    }
    float noise()
    {
        m_seed = m_seed * 1664525u + 1013904223u;
        return float(int32_t(m_seed)) / 2147483648.f;
    }

    Inst m_inst = Piano;
    double m_f = 440;
    int m_rate = 48000;
    float m_gain = 1.f;
    uint32_t m_seed = 1;
    long long m_i = 0, m_relAt = -1;
    double m_rel = 0.25, m_ph = 0, m_ph2 = 0, m_ph3 = 0, m_lp = 0;
    bool m_active = false;
    std::array<float, MaxString> m_ks{};
    int m_ksLen = 2, m_ksPos = 0;
};

// Głosy grane na żywo, każdy przypisany do ścieżki — mikser dokłada je do ścieżki przed jej efektami
// (autotune, korektor, kompresor, pogłos, echo…), więc granie brzmi jak gotowa ścieżka. Tylko wątek audio.
class LivePool
{
public:
    static constexpr int Voices = 16;

    void noteOn(int id, int track, SynthVoice::Inst inst, double freq, int rate, float gain)
    {
        // Wolny głos, a gdy brak — najstarszy (zwykle już cichnący)
        int slot = 0;
        for (int i = 0; i < Voices; ++i) {
            if (!m_v[i].active()) {
                slot = i;
                break;
            }
            if (m_age[i] < m_age[slot])
                slot = i;
        }
        m_seed = m_seed * 1664525u + 1013904223u;
        m_v[slot].start(inst, freq, rate, m_seed, gain);
        m_id[slot] = id;
        m_track[slot] = track;
        m_age[slot] = ++m_clock;
    }
    void noteOff(int id)
    {
        for (int i = 0; i < Voices; ++i)
            if (m_id[i] == id && m_v[i].active() && !m_v[i].released())
                m_v[i].release();
    }
    bool any(int track) const
    {
        for (int i = 0; i < Voices; ++i)
            if (m_track[i] == track && m_v[i].active())
                return true;
        return false;
    }
    void render(int track, float *l, float *r, int n)
    {
        for (int i = 0; i < Voices; ++i) {
            if (m_track[i] != track || !m_v[i].active())
                continue;
            for (int k = 0; k < n; ++k) {
                const float y = m_v[i].next();
                l[k] += y;
                r[k] += y;
            }
        }
    }
    // Głosy ścieżek, których już nie ma w miksie (usunięte) — wyciszamy, żeby nie wisiały
    void dropFrom(int trackCount)
    {
        for (int i = 0; i < Voices; ++i)
            if (m_track[i] >= trackCount && m_v[i].active())
                m_v[i] = SynthVoice();
    }

private:
    SynthVoice m_v[Voices];
    int m_id[Voices] = {}, m_track[Voices] = {};
    long long m_age[Voices] = {}, m_clock = 0;
    uint32_t m_seed = 12345;
};
