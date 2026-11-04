#pragma once

#include <algorithm>
#include <array>
#include <cmath>
#include <vector>

// Proste efekty Studia — bez alokacji i blokad, do użycia w wątku audio.
// Współczynniki liczy wątek interfejsu (w migawce), stan filtrów trzyma Renderer.

// Filtr dwubiegunowy (wzory RBJ „Audio EQ Cookbook”), postać transponowana II
struct Biquad
{
    float b0 = 1, b1 = 0, b2 = 0, a1 = 0, a2 = 0;
    bool flat() const { return b0 == 1 && b1 == 0 && b2 == 0 && a1 == 0 && a2 == 0; }

    static Biquad make(double b0, double b1, double b2, double a0, double a1, double a2)
    {
        Biquad q;
        q.b0 = float(b0 / a0);
        q.b1 = float(b1 / a0);
        q.b2 = float(b2 / a0);
        q.a1 = float(a1 / a0);
        q.a2 = float(a2 / a0);
        return q;
    }
    static Biquad lowShelf(double f, double db, double rate)
    {
        if (std::fabs(db) < 0.05)
            return {};
        const double A = std::pow(10.0, db / 40), w = 2 * M_PI * f / rate, cs = std::cos(w), sn = std::sin(w);
        const double al = sn / 2 * std::sqrt(2.0), sa = 2 * std::sqrt(A) * al;
        return make(A * ((A + 1) - (A - 1) * cs + sa), 2 * A * ((A - 1) - (A + 1) * cs), A * ((A + 1) - (A - 1) * cs - sa),
                    (A + 1) + (A - 1) * cs + sa, -2 * ((A - 1) + (A + 1) * cs), (A + 1) + (A - 1) * cs - sa);
    }
    static Biquad highShelf(double f, double db, double rate)
    {
        if (std::fabs(db) < 0.05)
            return {};
        const double A = std::pow(10.0, db / 40), w = 2 * M_PI * f / rate, cs = std::cos(w), sn = std::sin(w);
        const double al = sn / 2 * std::sqrt(2.0), sa = 2 * std::sqrt(A) * al;
        return make(A * ((A + 1) + (A - 1) * cs + sa), -2 * A * ((A - 1) + (A + 1) * cs), A * ((A + 1) + (A - 1) * cs - sa),
                    (A + 1) - (A - 1) * cs + sa, 2 * ((A - 1) - (A + 1) * cs), (A + 1) - (A - 1) * cs - sa);
    }
    static Biquad peak(double f, double db, double q, double rate)
    {
        if (std::fabs(db) < 0.05)
            return {};
        const double A = std::pow(10.0, db / 40), w = 2 * M_PI * f / rate, cs = std::cos(w), al = std::sin(w) / (2 * q);
        return make(1 + al * A, -2 * cs, 1 - al * A, 1 + al / A, -2 * cs, 1 - al / A);
    }
    static Biquad lowPass(double f, double rate)
    {
        const double w = 2 * M_PI * f / rate, cs = std::cos(w), al = std::sin(w) / (2 * 0.7071);
        return make((1 - cs) / 2, 1 - cs, (1 - cs) / 2, 1 + al, -2 * cs, 1 - al);
    }
    static Biquad highPass(double f, double rate)
    {
        const double w = 2 * M_PI * f / rate, cs = std::cos(w), al = std::sin(w) / (2 * 0.7071);
        return make((1 + cs) / 2, -(1 + cs), (1 + cs) / 2, 1 + al, -2 * cs, 1 - al);
    }
};

struct BiquadState
{
    float z1 = 0, z2 = 0;
    float run(const Biquad &q, float x)
    {
        const float y = q.b0 * x + z1;
        z1 = q.b1 * x - q.a1 * y + z2;
        z2 = q.b2 * x - q.a2 * y;
        return y;
    }
};

// De-esser: ścisza tylko górę pasma (od ok. 4,5 kHz), gdy przeważa w niej syczenie („s”, „sz”, „c”).
// Miarą jest udział góry w całym sygnale — nie zależy od głośności nagrania. Zwrotnica Linkwitza-Rileya
// (24 dB/okt.): dół + góra składają się z powrotem w ten sam dźwięk, więc poza syczeniem nic się nie zmienia.
struct DeEsser
{
    BiquadState lp[2][2], hp[2][2];       // [kanał][stopień]
    float envHi = 0, envAll = 0, g = 1;
    void process(float *l, float *r, int n, const Biquad &lpq, const Biquad &hpq, float amount, int rate)
    {
        const float sr = float(rate);
        const float att = 1.f - std::exp(-1.f / (0.0005f * sr)), rel = 1.f - std::exp(-1.f / (0.03f * sr));
        const float gDown = 1.f - std::exp(-1.f / (0.0005f * sr)), gUp = 1.f - std::exp(-1.f / (0.05f * sr));
        const float target = 0.5f - 0.3f * amount, power = 0.6f + 1.6f * amount;
        float *io[2] = {l, r};
        for (int i = 0; i < n; ++i) {
            float lo[2], hi[2];
            for (int c = 0; c < 2; ++c) {
                const float x = io[c][i];
                lo[c] = lp[c][1].run(lpq, lp[c][0].run(lpq, x));
                hi[c] = hp[c][1].run(hpq, hp[c][0].run(hpq, x));
            }
            const float h = 0.5f * std::fabs(hi[0] + hi[1]), all = 0.5f * std::fabs(l[i] + r[i]);
            envHi += (h > envHi ? att : rel) * (h - envHi);
            envAll += (all > envAll ? att : rel) * (all - envAll);
            const float ratio = envHi / (envAll + 1e-5f);
            const float want = ratio > target ? std::max(0.08f, std::pow(target / ratio, power)) : 1.f;
            g += (want < g ? gDown : gUp) * (want - g);
            l[i] = lo[0] + hi[0] * g;
            r[i] = lo[1] + hi[1] * g;
        }
    }
};

// Kompresor: jedno pokrętło „ile”. Próg i stosunek rosną razem, a wzmocnienie wyrównuje ściszenie.
struct CompParams
{
    bool on = false;
    float threshold = 0;     // dBFS
    float ratio = 1;
    float makeup = 1;        // liniowo

    static CompParams fromAmount(double amount)
    {
        CompParams c;
        if (amount < 0.01)
            return c;
        c.on = true;
        c.threshold = float(-8 - 22 * amount);
        c.ratio = float(1.5 + 4.5 * amount);
        c.makeup = float(std::pow(10.0, (-c.threshold * (1 - 1 / c.ratio) * 0.5) / 20));
        return c;
    }
};

struct CompState
{
    float reduction = 0;     // dB (≥ 0)
    float process(const CompParams &p, float peak, int rate)
    {
        const float att = std::exp(-1.f / (0.005f * rate)), rel = std::exp(-1.f / (0.15f * rate));
        const float db = 20.f * std::log10(peak + 1e-9f);
        const float over = db - p.threshold;
        const float target = over > 0 ? over * (1 - 1 / p.ratio) : 0.f;
        reduction = target > reduction ? att * reduction + (1 - att) * target : rel * reduction + (1 - rel) * target;
        return std::pow(10.f, -reduction / 20.f) * p.makeup;
    }
};

// Pogłos wspólny dla wszystkich ścieżek (każda wysyła do niego część dźwięku):
// klasyczny układ Schroedera/Moorera — 8 filtrów grzebieniowych z tłumieniem i 4 wszechprzepustowe na kanał.
class Reverb
{
public:
    static constexpr int Combs = 8, Allpasses = 4, MaxComb = 1800, MaxAllpass = 640;

    void setSize(float size) { m_feedback = 0.70f + 0.28f * std::clamp(size, 0.f, 1.f); }
    void setup(int rate, float size)
    {
        static const int combT[Combs] = {1116, 1188, 1277, 1356, 1422, 1491, 1557, 1617};
        static const int apT[Allpasses] = {556, 441, 341, 225};
        const double k = rate / 44100.0;
        for (int ch = 0; ch < 2; ++ch) {
            for (int i = 0; i < Combs; ++i)
                m_comb[ch][i].len = std::min(MaxComb, int((combT[i] + ch * 23) * k));
            for (int i = 0; i < Allpasses; ++i)
                m_ap[ch][i].len = std::min(MaxAllpass, int((apT[i] + ch * 23) * k));
        }
        for (auto &chs : m_comb)
            for (Comb &c : chs)
                c.pos = 0;
        for (auto &chs : m_ap)
            for (Allpass &a : chs)
                a.pos = 0;
        setSize(size);
    }
    void process(const float *inL, const float *inR, float *outL, float *outR, int n)
    {
        for (int i = 0; i < n; ++i) {
            const float in = (inL[i] + inR[i]) * 0.015f;
            for (int ch = 0; ch < 2; ++ch) {
                float acc = 0;
                for (Comb &c : m_comb[ch]) {
                    const float y = c.buf[c.pos];
                    c.store = y * (1 - m_damp) + c.store * m_damp;
                    c.buf[c.pos] = in + c.store * m_feedback;
                    if (++c.pos >= c.len)
                        c.pos = 0;
                    acc += y;
                }
                for (Allpass &a : m_ap[ch]) {
                    const float b = a.buf[a.pos];
                    const float y = b - acc;
                    a.buf[a.pos] = acc + b * 0.5f;
                    if (++a.pos >= a.len)
                        a.pos = 0;
                    acc = y;
                }
                (ch == 0 ? outL : outR)[i] += acc * 1.4f;
            }
        }
    }

private:
    struct Comb
    {
        std::array<float, MaxComb> buf{};
        int len = 1000, pos = 0;
        float store = 0;
    };
    struct Allpass
    {
        std::array<float, MaxAllpass> buf{};
        int len = 500, pos = 0;
    };
    Comb m_comb[2][Combs];
    Allpass m_ap[2][Allpasses];
    float m_feedback = 0.84f, m_damp = 0.25f;
};

// Echo wspólne dla ścieżek, zgrane z tempem (np. ósemka z kropką). Każde powtórzenie ciemniejsze;
// lewy i prawy kanał na zmianę („ping-pong”). Bufor przydzielany raz, poza wątkiem audio.
class Echo
{
public:
    static constexpr int MaxDelay = 2 * 48000;
    Echo() : m_l(MaxDelay, 0.f), m_r(MaxDelay, 0.f) {}
    void process(const float *inL, const float *inR, float *outL, float *outR, int n, int delay, float feedback)
    {
        delay = std::clamp(delay, 1, MaxDelay - 1);
        for (int i = 0; i < n; ++i) {
            int rp = m_pos - delay;
            if (rp < 0)
                rp += MaxDelay;
            const float dl = m_l[size_t(rp)], dr = m_r[size_t(rp)];
            m_lpL += 0.35f * (dr - m_lpL);              // ping-pong: lewy dostaje prawy i odwrotnie
            m_lpR += 0.35f * (dl - m_lpR);
            m_l[size_t(m_pos)] = (inL[i] + inR[i]) * 0.5f + m_lpL * feedback;
            m_r[size_t(m_pos)] = m_lpR * feedback;
            if (++m_pos >= MaxDelay)
                m_pos = 0;
            outL[i] += dl;
            outR[i] += dr;
        }
    }

private:
    std::vector<float> m_l, m_r;
    int m_pos = 0;
    float m_lpL = 0, m_lpR = 0;
};

// Sztuczny dubel (ADT): dwie kopie głosu opóźnione o ok. 19 i 27 ms, każda z wolno pływającym opóźnieniem —
// lekko inne wejście i wysokość (kilka centów), jak drugie nagranie tego samego tekstu. Kopie idą na boki,
// oryginał zostaje na środku. Bufor przydzielany raz, poza wątkiem audio.
class Doubler
{
public:
    static constexpr int Size = 8192;               // > 80 ms przy 96 kHz
    Doubler() : m_buf(Size, 0.f) {}
    void process(float *l, float *r, int n, float amount, int rate)
    {
        if (!m_used) {
            std::fill(m_buf.begin(), m_buf.end(), 0.f);
            m_used = true;
        }
        const float sr = float(rate), dry = 1.f - 0.25f * amount, wet = 0.7f * amount;
        const float incA = 6.2831853f * 0.37f / sr, incB = 6.2831853f * 0.29f / sr;
        for (int i = 0; i < n; ++i) {
            m_buf[size_t(m_pos)] = 0.5f * (l[i] + r[i]);
            const float a = tap((0.019f + 0.0022f * std::sin(m_phA)) * sr);
            const float b = tap((0.027f + 0.0026f * std::sin(m_phB)) * sr);
            m_phA += incA;
            m_phB += incB;
            if (m_phA > 6.2831853f)
                m_phA -= 6.2831853f;
            if (m_phB > 6.2831853f)
                m_phB -= 6.2831853f;
            if (++m_pos >= Size)
                m_pos = 0;
            l[i] = l[i] * dry + a * wet;
            r[i] = r[i] * dry + b * wet;
        }
    }
    // Nieużywany — przy ponownym włączeniu bez starego dźwięku w buforze
    void idle() { m_used = false; }

private:
    float tap(float delay) const
    {
        float p = float(m_pos) - delay;
        if (p < 0)
            p += Size;
        const int i = int(p);
        const float f = p - float(i);
        const float x0 = m_buf[size_t(i % Size)], x1 = m_buf[size_t((i + 1) % Size)];
        return x0 + (x1 - x0) * f;
    }
    std::vector<float> m_buf;
    int m_pos = 0;
    float m_phA = 0, m_phB = 1.7f;
    bool m_used = false;
};

// Ogranicznik z wyprzedzeniem (~1,3 ms): widzi szczyt, zanim ten dojdzie do wyjścia, i łagodnie ścisza,
// więc nawet mocno „dociśnięty” mastering nie trzeszczy. Na końcu twarde cięcie na pułapie (bezpiecznik).
class Limiter
{
public:
    static constexpr int Look = 64;
    float gain = 1.f;
    float process(float &l, float &r, float ceiling, float release)
    {
        m_bl[m_pos] = l;
        m_br[m_pos] = r;
        m_pk[m_pos] = std::max(std::fabs(l), std::fabs(r));
        float peak = 0;
        for (float p : m_pk)
            peak = std::max(peak, p);
        const float target = peak > ceiling ? ceiling / peak : 1.f;
        if (target < gain)
            gain += (target - gain) * 0.25f;
        else
            gain += (target - gain) * release;
        int rp = m_pos + 1;
        if (rp >= Look)
            rp = 0;
        l = std::clamp(m_bl[rp] * gain, -ceiling, ceiling);
        r = std::clamp(m_br[rp] * gain, -ceiling, ceiling);
        m_pos = rp;
        return gain;
    }

private:
    std::array<float, Look> m_bl{}, m_br{}, m_pk{};
    int m_pos = 0;
};

// Mastering sumy: korektor (dół/góra), kompresor „sklejający”, szerokość stereo i dociśnięcie do ogranicznika
struct MasterParams
{
    Biquad low, high;
    CompParams comp;
    float width = 1.f;     // 1 = bez zmian, >1 szerzej
    float drive = 1.f;     // wzmocnienie przed ogranicznikiem (głośność)
};
