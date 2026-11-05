#pragma once

#include "audiosource.h"
#include "dsp.h"
#include "synthvoice.h"
#include "plugin.h"

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
    virtual void process(float *l, float *r, int n, const Plug::Note *ev, int count, const Plug::Transport &t) = 0;
    virtual void silence() = 0;                 // zatrzymanie, skok głowicy, zawrócenie pętli
};

// Sampler: dźwięk z pliku albo syntezy. Wysokość przez szybkość odtwarzania, obwiednia ADSR, zakres pliku,
// pętla, filtr. Pocięty na plasterki gra każdym klawiszem od podstawy inny kawałek, zawsze w oryginalnym tempie.
struct SamplerParams
{
    double attack = 0.001, decay = 0.1, sustain = 1, release = 0.012;   // sekundy, sustain 0…1
    long long from = 0, to = -1;          // zakres w ramkach (-1 — do końca)
    bool loop = false, oneShot = true;
    int root = 60;
    double tune = 0;                      // półtony
    double cutoff = 20000, resonance = 0.7;   // Hz, Q
    std::vector<long long> slices;        // początki plasterków
};

class SamplerInstrument : public Instrument
{
public:
    SamplerInstrument(SourcePtr src, const SamplerParams &p, int rate) : m_src(std::move(src)), m_p(p), m_rate(rate)
    {
        m_filter = p.cutoff < 19000;
        if (m_filter)
            m_lp = Biquad::lowPassQ(p.cutoff, p.resonance, rate);
    }
    void process(float *l, float *r, int n, const Plug::Note *ev, int count, const Plug::Transport &) override
    {
        int done = 0;
        for (int e = 0; e <= count; ++e) {
            const int to = e < count ? std::clamp(ev[e].offset, done, n) : n;
            render(l + done, r + done, to - done);
            done = to;
            if (e < count) {
                if (ev[e].pitch < 0)
                    choke();
                else if (ev[e].on)
                    start(ev[e].pitch, ev[e].velocity);
                else
                    stop(ev[e].pitch);
            }
        }
        if (m_filter)
            for (int i = 0; i < n; ++i) {
                l[i] = m_z[0].run(m_lp, l[i]);
                r[i] = m_z[1].run(m_lp, r[i]);
            }
    }
    void silence() override
    {
        for (Voice &v : m_v)
            if (v.on)
                v.stage = Release;
    }

private:
    static constexpr int Voices = 32;
    enum Stage { Attack, Decay, Sustain, Release, Choke };
    struct Voice
    {
        bool on = false;
        int pitch = 0;
        Stage stage = Attack;
        double pos = 0, step = 1;
        long long from = 0, to = 0;
        float gain = 1, env = 0;
        long long age = 0;
    };
    void start(int pitch, float vel)
    {
        if (!m_src)
            return;
        long long from = m_p.from, to = m_p.to < 0 ? m_src->frames : std::min(m_p.to, m_src->frames);
        double step = std::pow(2.0, (pitch - m_p.root + m_p.tune) / 12.0);
        if (!m_p.slices.empty()) {
            const int i = pitch - m_p.root;
            if (i < 0 || i >= int(m_p.slices.size()))
                return;
            from = m_p.slices[size_t(i)];
            to = size_t(i + 1) < m_p.slices.size() ? m_p.slices[size_t(i + 1)] : to;
            step = std::pow(2.0, m_p.tune / 12.0);
        }
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
        v->from = from;
        v->to = to;
        v->pos = double(from);
        v->step = step;
        v->gain = 0.25f + 0.75f * vel * vel;
        v->age = ++m_clock;
    }
    void stop(int pitch)
    {
        if (m_p.oneShot)
            return;
        for (Voice &v : m_v)
            if (v.on && v.pitch == pitch && v.stage < Release)
                v.stage = Release;
    }
    void choke()
    {
        for (Voice &v : m_v)
            if (v.on)
                v.stage = Choke;
    }
    void render(float *l, float *r, int n)
    {
        if (n <= 0 || !m_src)
            return;
        const AudioSource &s = *m_src;
        const float sr = float(m_rate);
        const float att = 1.f / std::max(1.f, float(m_p.attack) * sr), rel = 1.f / std::max(1.f, float(m_p.release) * sr);
        const float dec = (1.f - float(m_p.sustain)) / std::max(1.f, float(m_p.decay) * sr), ck = 1.f / (0.004f * sr);
        const float sus = float(m_p.sustain);
        for (Voice &v : m_v) {
            if (!v.on)
                continue;
            for (int i = 0; i < n; ++i) {
                long long a = (long long)v.pos;
                if (a + 1 >= v.to) {
                    if (!m_p.loop) {
                        v.on = false;
                        break;
                    }
                    v.pos -= double(v.to - v.from - 1);
                    a = (long long)v.pos;
                }
                switch (v.stage) {
                case Attack:
                    v.env += att;
                    if (v.env >= 1) {
                        v.env = 1;
                        v.stage = Decay;
                    }
                    break;
                case Decay:
                    v.env -= dec;
                    if (v.env <= sus) {
                        v.env = sus;
                        v.stage = Sustain;
                    }
                    break;
                case Sustain:
                    break;
                case Release:
                    v.env -= rel;
                    break;
                case Choke:
                    v.env -= ck;
                    break;
                }
                if (v.env <= 0 && v.stage >= Release) {
                    v.on = false;
                    break;
                }
                const float f = float(v.pos - double(a));
                const float g = v.gain * v.env;
                l[i] += (s.at(a, 0) + (s.at(a + 1, 0) - s.at(a, 0)) * f) * g;
                r[i] += (s.at(a, 1) + (s.at(a + 1, 1) - s.at(a, 1)) * f) * g;
                v.pos += v.step;
            }
        }
    }
    SourcePtr m_src;
    SamplerParams m_p;
    int m_rate;
    bool m_filter = false;
    Biquad m_lp;
    BiquadState m_z[2];
    Voice m_v[Voices];
    long long m_clock = 0;
};

// Syntezator Studia (pianino, pad, dzwonki…)
class SynthInstrument : public Instrument
{
public:
    SynthInstrument(SynthVoice::Inst inst, int rate) : m_inst(inst), m_rate(rate), m_v(Voices), m_pitch(Voices, -1), m_age(Voices, 0) {}
    void process(float *l, float *r, int n, const Plug::Note *ev, int count, const Plug::Transport &) override
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
    void process(float *l, float *r, int n, const Plug::Note *ev, int count, const Plug::Transport &t) override
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
    explicit VstInstrument(std::shared_ptr<Plug::Plugin> p) : m_plugin(std::move(p)) {}
    Plug::Plugin *plugin() const { return m_plugin.get(); }
    void process(float *l, float *r, int n, const Plug::Note *ev, int count, const Plug::Transport &t) override
    {
        Plug::Note all[MaxEvents];
        int k = 0;
        if (m_clear) {
            for (int p = 0; p < 128 && k < MaxEvents / 2; ++p)
                if (m_held[p]) {
                    all[k++] = Plug::Note{0, false, p, 0};
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
    std::shared_ptr<Plug::Plugin> m_plugin;
    bool m_held[128] = {};
    bool m_clear = false;
};
