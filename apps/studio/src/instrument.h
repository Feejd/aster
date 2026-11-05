#pragma once

#include "audiosource.h"
#include "synthvoice.h"
#include "vst3host.h"

#include <algorithm>
#include <cmath>
#include <memory>
#include <vector>

// Instrument kanału: dostaje nuty z dokładnością do próbki i gra stereo do l, r (wyzerowanych przez wołającego).
// process() i silence() woła wątek audio — bez alokacji i blokad. Każdy eksport ma własne kopie instrumentów.
class Instrument
{
public:
    virtual ~Instrument() = default;
    virtual void process(float *l, float *r, int n, const Vst3::Note *ev, int count, const Vst3::Transport &t) = 0;
    virtual void silence() = 0;                 // zatrzymanie, skok głowicy, zawrócenie pętli
};

// Sampler: dźwięk z pliku albo syntezy, wysokość przez szybkość odtwarzania.
// Jednostrzałowy (perkusja) gra do końca, inaczej puszczenie nuty wycisza w 12 ms.
class SamplerInstrument : public Instrument
{
public:
    SamplerInstrument(SourcePtr src, int root, bool oneShot, int rate) : m_src(std::move(src)), m_root(root), m_oneShot(oneShot), m_rate(rate) {}
    void process(float *l, float *r, int n, const Vst3::Note *ev, int count, const Vst3::Transport &) override
    {
        int done = 0;
        for (int e = 0; e <= count; ++e) {
            const int to = e < count ? std::clamp(ev[e].offset, done, n) : n;
            render(l + done, r + done, to - done);
            done = to;
            if (e < count) {
                if (ev[e].on)
                    start(ev[e].pitch, ev[e].velocity);
                else
                    stop(ev[e].pitch);
            }
        }
    }
    void silence() override
    {
        for (Voice &v : m_v)
            if (v.on)
                v.rel = std::min(v.rel, 1.f), v.falling = true;
    }

private:
    static constexpr int Voices = 32;
    struct Voice
    {
        bool on = false, falling = false;
        int pitch = 0;
        double pos = 0, step = 1;
        float gain = 1, rel = 1;
        long long age = 0;
    };
    void start(int pitch, float vel)
    {
        Voice *v = &m_v[0];
        for (Voice &o : m_v) {
            if (!o.on) {
                v = &o;
                break;
            }
            if (o.age < v->age)
                v = &o;
        }
        *v = Voice{};
        v->on = true;
        v->pitch = pitch;
        v->step = std::pow(2.0, (pitch - m_root) / 12.0);
        v->gain = 0.25f + 0.75f * vel * vel;
        v->age = ++m_clock;
    }
    void stop(int pitch)
    {
        if (m_oneShot)
            return;
        for (Voice &v : m_v)
            if (v.on && v.pitch == pitch)
                v.falling = true;
    }
    void render(float *l, float *r, int n)
    {
        if (n <= 0 || !m_src)
            return;
        const AudioSource &s = *m_src;
        const float fall = 1.f / (0.012f * float(m_rate));
        for (Voice &v : m_v) {
            if (!v.on)
                continue;
            for (int i = 0; i < n; ++i) {
                const long long a = (long long)v.pos;
                if (a + 1 >= s.frames || v.rel <= 0) {
                    v.on = false;
                    break;
                }
                const float f = float(v.pos - double(a));
                const float g = v.gain * v.rel;
                l[i] += (s.at(a, 0) + (s.at(a + 1, 0) - s.at(a, 0)) * f) * g;
                r[i] += (s.at(a, 1) + (s.at(a + 1, 1) - s.at(a, 1)) * f) * g;
                v.pos += v.step;
                if (v.falling)
                    v.rel -= fall;
            }
        }
    }
    SourcePtr m_src;
    int m_root, m_rate;
    bool m_oneShot;
    Voice m_v[Voices];
    long long m_clock = 0;
};

// Syntezator Studia (pianino, pad, dzwonki…)
class SynthInstrument : public Instrument
{
public:
    SynthInstrument(SynthVoice::Inst inst, int rate) : m_inst(inst), m_rate(rate), m_v(Voices), m_pitch(Voices, -1), m_age(Voices, 0) {}
    void process(float *l, float *r, int n, const Vst3::Note *ev, int count, const Vst3::Transport &) override
    {
        int done = 0;
        for (int e = 0; e <= count; ++e) {
            const int to = e < count ? std::clamp(ev[e].offset, done, n) : n;
            for (auto &v : m_v)
                if (v.active())
                    for (int i = done; i < to; ++i) {
                        const float y = v.next();
                        l[i] += y;
                        r[i] += y;
                    }
            done = to;
            if (e < count) {
                if (ev[e].on)
                    start(ev[e].pitch, ev[e].velocity);
                else
                    for (int i = 0; i < Voices; ++i)
                        if (m_pitch[size_t(i)] == ev[e].pitch)
                            m_v[size_t(i)].release();
            }
        }
    }
    void silence() override
    {
        for (auto &v : m_v)
            v.release();
    }

private:
    static constexpr int Voices = 16;
    void start(int pitch, float vel)
    {
        size_t slot = 0;
        for (size_t i = 0; i < size_t(Voices); ++i) {
            if (!m_v[i].active()) {
                slot = i;
                break;
            }
            if (m_age[i] < m_age[slot])
                slot = i;
        }
        m_seed = m_seed * 1664525u + 1013904223u;
        // Poziom jak w dawnych pętlach Beat Makera: akord nie przesterowuje sumy
        m_v[slot].start(m_inst, 440.0 * std::pow(2.0, (pitch - 69) / 12.0), m_rate, m_seed, 0.45f * vel);
        m_pitch[slot] = pitch;
        m_age[slot] = ++m_clock;
    }
    SynthVoice::Inst m_inst;
    int m_rate;
    std::vector<SynthVoice> m_v;
    std::vector<int> m_pitch;
    std::vector<long long> m_age;
    long long m_clock = 0;
    uint32_t m_seed = 22222;
};

// Bas 808: jeden głos ze ślizgiem do kolejnej nuty granej tuż po poprzedniej
class Bass808 : public Instrument
{
public:
    struct Params { double decay = 1.5, glide = 0.06, drive = 0.3; };
    Bass808(const Params &p, int rate) : m_p(p), m_rate(rate), m_decayK(std::exp(-3.0 / (p.decay * rate))) {}
    void process(float *l, float *r, int n, const Vst3::Note *ev, int count, const Vst3::Transport &t) override
    {
        const double slideWithin = 3 * 60.0 / std::max(t.bpm, 30.0) / 4 * m_rate;     // do 3 szesnastek
        const double drive = 1 + 4 * m_p.drive, norm = 1 / std::tanh(drive);
        int e = 0;
        for (int i = 0; i < n; ++i) {
            for (; e < count && ev[e].offset <= i; ++e) {
                if (!ev[e].on)
                    continue;
                const double f = 440.0 * std::pow(2.0, (ev[e].pitch - 69) / 12.0);
                if (m_p.glide > 0 && m_since < slideWithin && m_amp > 0.05) {
                    m_from = m_freq;
                    m_to = f;
                    m_slide = 0;
                } else {
                    m_freq = m_from = m_to = f;
                    m_trig = 0;
                    m_slide = 1e9;
                    m_amp = ev[e].velocity;
                }
                m_since = 0;
            }
            if (m_amp < 1e-4)
                continue;
            if (m_slide < m_p.glide * m_rate) {
                const double x = m_slide / (m_p.glide * m_rate);
                m_freq = m_from + (m_to - m_from) * (x * x * (3 - 2 * x));
            } else if (m_slide < 1e8) {
                m_freq = m_to;
            }
            m_ph += 2 * M_PI * m_freq * (1 + 0.6 * std::exp(-m_trig / m_rate * 60)) / m_rate;
            const double attack = std::min(1.0, m_trig / (0.003 * m_rate));
            const float y = float(std::tanh(std::sin(m_ph) * m_amp * attack * drive) * norm * m_stop);
            l[i] += y;
            r[i] += y;
            m_amp *= m_decayK;
            m_trig += 1;
            m_slide += 1;
            m_since += 1;
            if (m_falling) {
                m_stop -= float(1.0 / (0.01 * m_rate));
                if (m_stop <= 0) {
                    m_amp = 0;
                    m_stop = 1;
                    m_falling = false;
                }
            }
        }
    }
    void silence() override { m_falling = m_amp > 0; }

private:
    Params m_p;
    int m_rate;
    double m_decayK, m_ph = 0, m_freq = 55, m_from = 55, m_to = 55, m_amp = 0;
    double m_trig = 1e9, m_slide = 1e9, m_since = 1e9;
    float m_stop = 1;
    bool m_falling = false;
};

// Instrument VST3
class VstInstrument : public Instrument
{
public:
    explicit VstInstrument(std::shared_ptr<Vst3::Plugin> p) : m_plugin(std::move(p)) {}
    Vst3::Plugin *plugin() const { return m_plugin.get(); }
    void process(float *l, float *r, int n, const Vst3::Note *ev, int count, const Vst3::Transport &t) override
    {
        Vst3::Note all[MaxEvents];
        int k = 0;
        if (m_clear) {
            for (int p = 0; p < 128 && k < MaxEvents / 2; ++p)
                if (m_held[p]) {
                    all[k++] = Vst3::Note{0, false, p, 0};
                    m_held[p] = false;
                }
            m_clear = false;
        }
        for (int e = 0; e < count && k < MaxEvents; ++e) {
            all[k++] = ev[e];
            m_held[std::clamp(ev[e].pitch, 0, 127)] = ev[e].on;
        }
        m_plugin->process(l, r, n, all, k, t);
    }
    void silence() override { m_clear = true; }

private:
    static constexpr int MaxEvents = 512;
    std::shared_ptr<Vst3::Plugin> m_plugin;
    bool m_held[128] = {};
    bool m_clear = false;
};
