#include "beatsynth.h"
#include "dsp.h"
#include "synthvoice.h"

#include <QJsonArray>
#include <QVariantMap>
#include <cmath>
#include <vector>

namespace BeatSynth {

namespace {

// Brzmienie zestawu: parametry syntezy każdego instrumentu
struct Kit
{
    const char *id, *label, *hint;
    double kickF0, kickF1, kickDrop, kickDecay, kickClick, kickDrive;
    double snareTone, snareNoise, snareDecay, snareBright;
    double clapDecay, clapBright;
    double hatBright, hatDecay, ohatDecay, hatLevel;
    double percFreq, percDecay;
    double bassDecay, bassDrive, bassGlide;
    double lofi;
};

const Kit s_kits[] = {
    {"trap", "Trap", "Głęboka 808, ostre hi-haty, klaskanie",
     165, 45, 30, 0.32, 0.5, 0.3, 200, 0.8, 0.16, 2600, 0.22, 1300, 8200, 0.035, 0.32, 0.45, 900, 0.05, 1.7, 0.45, 0.07, 0},
    {"drill", "Drill", "Ślizgające się 808, ciemne i twarde",
     150, 48, 28, 0.30, 0.45, 0.35, 225, 0.9, 0.14, 2900, 0.18, 1400, 9000, 0.030, 0.26, 0.40, 1000, 0.04, 2.2, 0.55, 0.12, 0},
    {"boombap", "Boom bap", "Mięsista stopa, chropowaty werbel",
     120, 50, 22, 0.38, 0.7, 0.5, 180, 0.85, 0.22, 1800, 0.20, 1100, 6500, 0.050, 0.35, 0.40, 750, 0.05, 0.55, 0.30, 0.03, 0.25},
    {"lofi", "Lo-fi", "Miękko, ciepło, z trzaskami płyty",
     110, 48, 20, 0.35, 0.3, 0.2, 170, 0.6, 0.20, 1400, 0.20, 1000, 5000, 0.040, 0.30, 0.30, 650, 0.06, 0.70, 0.15, 0.04, 0.85},
    {"house", "House", "Równa stopa, klaśnięcia, otwarte hi-haty",
     140, 52, 40, 0.28, 0.6, 0.35, 210, 0.75, 0.16, 2400, 0.25, 1500, 9500, 0.030, 0.22, 0.45, 1100, 0.04, 0.35, 0.40, 0.0, 0},
    {"pop", "Pop", "Czysto i dynamicznie",
     130, 50, 30, 0.30, 0.6, 0.3, 200, 0.75, 0.18, 2500, 0.20, 1300, 8500, 0.040, 0.30, 0.40, 900, 0.05, 0.50, 0.30, 0.03, 0},
};

const Kit &kit(const QString &id)
{
    for (const Kit &k : s_kits)
        if (id == QLatin1String(k.id))
            return k;
    return s_kits[0];
}

const char *const s_rows[] = {"kick", "snare", "clap", "hat", "openhat", "perc"};

// Gatunki: tempo, zestaw i wzory (własne, typowe dla gatunku). 'x' = uderzenie, 'o' = ciche (duch), '.' = nic;
// rolki hi-hatu: cyfra 2–4 = tyle uderzeń w jednym kroku. Bas: litera = stopień skali molowej (a = tonika, h = oktawa)
struct Genre
{
    const char *id, *label, *hint;
    int bpm;
    const char *kit;
    double swing;
    const char *kick, *snare, *clap, *hat, *rolls, *openhat, *perc;
    int root;
    const char *bass;
    bool glide;
};

const Genre s_genres[] = {
    {"trap", "Trap", "140 BPM, połówkowe tempo, rolki hi-hatów, długa 808", 140, "trap", 0,
     "x......x..x.....x..x......x.....",
     "................................",
     "........x...............x.......",
     "x.x.x.x.x.x.x.xxx.x.x.x.x.x.xxxx",
     "..............23............2234",
     "......................x.........",
     "...........o...................o",
     6, "a......h..f.....a..e......f..e..", true},
    {"drill", "Drill", "142 BPM, przesunięty werbel, ślizgi 808", 142, "drill", 0,
     "x.........x.....x......x..x.....",
     "........x............x..x.......",
     "................................",
     "x..x..x.x..x..x.x..x..x.x..x..xx",
     "..............................23",
     "................................",
     "......o...............o.........",
     1, "a.........d.....a.....g...f.....", true},
    {"boombap", "Boom bap", "90 BPM, bujający rytm, klasyczny hip-hop", 90, "boombap", 0.18,
     "x......xx.x.....x......x..x.....",
     "....x.......x.......x.......x...",
     "................................",
     "x.x.x.x.x.x.x.x.x.x.x.x.x.x.x.x.",
     "................................",
     "..............x.................",
     "..............o...............o.",
     9, "a.........c.....d.........e.....", false},
    {"lofi", "Lo-fi", "82 BPM, leniwie i ciepło", 82, "lofi", 0.22,
     "x.......x.x.....x.......x.x.....",
     "....x.......x.......x.......x...",
     "................................",
     "x.o.x.o.x.o.x.o.x.o.x.o.x.o.x.o.",
     "................................",
     "................................",
     "......o.......o.......o.......o.",
     2, "a.......e.......f.......d.......", false},
    {"house", "House", "124 BPM, cztery na podłogę", 124, "house", 0,
     "x...x...x...x...x...x...x...x...",
     "................................",
     "....x.......x.......x.......x...",
     "o...o...o...o...o...o...o...o...",
     "................................",
     "..x...x...x...x...x...x...x...x.",
     ".......o...............o..o.....",
     5, "..a...a...a...c...a...a...e...d.", false},
    {"pop", "Pop", "100 BPM, prosto i przebojowo", 100, "pop", 0,
     "x.......x.x.....x.......x.x.....",
     "....x.......x.......x.......x...",
     "....x.......x.......x.......x...",
     "x.x.x.x.x.x.x.x.x.x.x.x.x.x.x.x.",
     "................................",
     "..............................x.",
     "................................",
     0, "a.......a.e.....f.......d.......", false},
};

const Genre *genre(const QString &id)
{
    for (const Genre &g : s_genres)
        if (id == QLatin1String(g.id))
            return &g;
    return nullptr;
}

QJsonArray steps(const char *s)
{
    QJsonArray a;
    for (const char *p = s; *p; ++p)
        a.append(*p == 'x' ? 1.0 : *p == 'o' ? 0.55 : 0.0);
    return a;
}

// Liczby pseudolosowe o stałym ziarnie — ten sam wzór zawsze brzmi tak samo
struct Noise
{
    uint32_t s = 22222;
    float next()
    {
        s = s * 1664525u + 1013904223u;
        return float(int32_t(s)) / 2147483648.f;
    }
};

const int s_scale[7] = {0, 2, 3, 5, 7, 8, 10};      // skala molowa naturalna

struct Buffer
{
    std::vector<float> l, r;
    long long size() const { return (long long)l.size(); }
    void add(long long at, const std::vector<float> &v, float gain, float pan)
    {
        const float gl = gain * (pan > 0 ? 1 - pan : 1), gr = gain * (pan < 0 ? 1 + pan : 1);
        for (size_t i = 0; i < v.size(); ++i) {
            const long long k = at + (long long)i;
            if (k < 0 || k >= size())
                continue;
            l[size_t(k)] += v[i] * gl;
            r[size_t(k)] += v[i] * gr;
        }
    }
};

double env(double t, double decay) { return std::exp(-3.0 * t / decay); }

std::vector<float> kickVoice(const Kit &k, int rate, Noise &rnd)
{
    const int n = int(rate * (k.kickDecay * 2.2 + 0.05));
    std::vector<float> v(static_cast<size_t>(n));
    double ph = 0;
    BiquadState hp;
    const Biquad hpq = Biquad::highPass(2500, rate);
    const double drive = 1 + 2.5 * k.kickDrive, norm = 1 / std::tanh(drive);
    for (int i = 0; i < n; ++i) {
        const double t = double(i) / rate;
        const double f = k.kickF1 + (k.kickF0 - k.kickF1) * std::exp(-t * k.kickDrop);
        ph += 2 * M_PI * f / rate;
        double x = std::sin(ph) * env(t, k.kickDecay);
        x += hp.run(hpq, rnd.next()) * std::exp(-t * 350) * k.kickClick;
        v[size_t(i)] = float(std::tanh(x * drive) * norm);
    }
    return v;
}

std::vector<float> snareVoice(const Kit &k, int rate, Noise &rnd)
{
    const int n = int(rate * (k.snareDecay * 2.5));
    std::vector<float> v(static_cast<size_t>(n));
    BiquadState hp;
    const Biquad hpq = Biquad::highPass(k.snareBright, rate);
    double p1 = 0, p2 = 0;
    for (int i = 0; i < n; ++i) {
        const double t = double(i) / rate;
        const double f = k.snareTone * (1 + 0.3 * std::exp(-t * 60));
        p1 += 2 * M_PI * f / rate;
        p2 += 2 * M_PI * f * 1.62 / rate;
        const double tone = (std::sin(p1) + 0.5 * std::sin(p2)) * env(t, 0.09) * (1 - k.snareNoise * 0.5);
        const double noise = hp.run(hpq, rnd.next()) * env(t, k.snareDecay) * k.snareNoise * 1.6;
        v[size_t(i)] = float(std::tanh((tone + noise) * 1.3));
    }
    return v;
}

std::vector<float> clapVoice(const Kit &k, int rate, Noise &rnd)
{
    const int n = int(rate * (k.clapDecay * 2.5 + 0.03));
    std::vector<float> v(static_cast<size_t>(n));
    // Pasmowy: biquad szczytowy na szumie przepuszczonym przez filtr górnoprzepustowy
    BiquadState hp, bp;
    const Biquad hpq = Biquad::highPass(k.clapBright * 0.6, rate);
    const Biquad bpq = Biquad::peak(k.clapBright, 12, 1.5, rate);
    for (int i = 0; i < n; ++i) {
        const double t = double(i) / rate;
        double e = 0;
        for (double b : {0.0, 0.011, 0.022})              // kilka dłoni naraz
            if (t >= b)
                e = std::max(e, std::exp(-(t - b) * 220));
        if (t >= 0.03)
            e = std::max(e, 0.6 * env(t - 0.03, k.clapDecay));
        const double x = bp.run(bpq, hp.run(hpq, rnd.next()));
        v[size_t(i)] = float(std::tanh(x * e * 0.9));
    }
    return v;
}

std::vector<float> hatVoice(const Kit &k, int rate, double decay, int length, Noise &rnd)
{
    const int n = std::min(length, int(rate * decay * 2.5));
    std::vector<float> v(size_t(std::max(n, 1)));
    static const double ratios[6] = {205.3, 304.4, 369.6, 522.7, 540.0, 800.0};
    double ph[6] = {};
    BiquadState hp1, hp2;
    const Biquad hpq = Biquad::highPass(k.hatBright * 0.85, rate);
    const double scale = k.hatBright / 8000.0;
    for (int i = 0; i < n; ++i) {
        const double t = double(i) / rate;
        double sq = 0;
        for (int j = 0; j < 6; ++j) {
            ph[j] += ratios[j] * 2.0 * scale / rate;
            sq += (std::fmod(ph[j], 1.0) < 0.5 ? 1 : -1);
        }
        const double x = hp2.run(hpq, hp1.run(hpq, rnd.next() * 0.7 + sq * 0.08));
        double e = env(t, decay);
        if (i > n - 64)                                     // ucięcie (otwarty hi-hat zamknięty kolejnym)
            e *= double(n - i) / 64;
        v[size_t(i)] = float(x * e * 1.6);
    }
    return v;
}

std::vector<float> percVoice(const Kit &k, int rate, Noise &rnd)
{
    const int n = int(rate * k.percDecay * 3);
    std::vector<float> v(static_cast<size_t>(n));
    double p1 = 0, p2 = 0;
    for (int i = 0; i < n; ++i) {
        const double t = double(i) / rate;
        p1 += 2 * M_PI * k.percFreq / rate;
        p2 += 2 * M_PI * k.percFreq * 1.71 / rate;
        v[size_t(i)] = float((std::sin(p1) * 0.7 + std::sin(p2) * 0.4) * env(t, k.percDecay) + rnd.next() * std::exp(-t * 900) * 0.4);
    }
    return v;
}

double stepTime(int i, double stepSec, double swing) { return i * stepSec + ((i % 2) ? swing * stepSec : 0.0); }

void lofi(Buffer &b, double amount, int rate, Noise &rnd)
{
    if (amount <= 0)
        return;
    // Ciemniej (filtr dolnoprzepustowy) i trzaski płyty
    const double cutoff = 16000 - amount * 12000;
    const float a = float(1 - std::exp(-2 * M_PI * cutoff / rate));
    float zl = 0, zr = 0;
    for (long long i = 0; i < b.size(); ++i) {
        zl += a * (b.l[size_t(i)] - zl);
        zr += a * (b.r[size_t(i)] - zr);
        float crackle = 0;
        if (rnd.next() > 1 - 0.0004 * amount)
            crackle = rnd.next() * 0.12f * float(amount);
        b.l[size_t(i)] = zl + crackle + rnd.next() * 0.003f * float(amount);
        b.r[size_t(i)] = zr + crackle + rnd.next() * 0.003f * float(amount);
    }
}

void normalize(Buffer &b, float target)
{
    float peak = 0;
    for (long long i = 0; i < b.size(); ++i)
        peak = std::max({peak, std::fabs(b.l[size_t(i)]), std::fabs(b.r[size_t(i)])});
    if (peak < 1e-6f)
        return;
    const float g = target / peak;
    for (long long i = 0; i < b.size(); ++i) {
        b.l[size_t(i)] *= g;
        b.r[size_t(i)] *= g;
    }
}

// ——— Akordy i melodia ———

struct Instrument { const char *id, *label, *hint; };
const Instrument s_instruments[] = {
    {"piano", "Pianino", "Ciepły fortepian"},
    {"epiano", "Klawisze elektryczne", "Miękkie, dzwoniące — lo-fi, R&B"},
    {"pad", "Pad", "Długa, szeroka plama dźwięku"},
    {"pluck", "Pluck", "Szarpana struna — krótko i rytmicznie"},
    {"bells", "Dzwonki", "Szklane dzwonki — klasyka trapu"},
    {"lead", "Lead", "Wyrazisty syntezator na melodię"},
};

struct Rhythm { const char *id, *label; };
const Rhythm s_rhythms[] = {
    {"sustain", "Cały takt"}, {"half", "Półnuty"}, {"stabs", "Staccato"}, {"arp", "Arpeggio ósemki"}, {"arp16", "Arpeggio szesnastki"},
};

struct Progression { const char *id, *label, *hint; int chords[4]; };
const Progression s_progressions[] = {
    {"sad", "Smutna", "i – VI – III – VII", {0, 5, 2, 6}},
    {"dark", "Mroczna", "i – i – VI – v", {0, 0, 5, 4}},
    {"epic", "Epicka", "VI – VII – i – i", {5, 6, 0, 0}},
    {"dreamy", "Rozmarzona", "iv – VII – III – VI", {3, 6, 2, 5}},
    {"hopeful", "Z nadzieją", "VI – III – VII – iv", {5, 2, 6, 3}},
    {"simple", "Dwa akordy", "i – VI", {0, 5, 0, 5}},
};

const int s_major[7] = {0, 2, 4, 5, 7, 9, 11};

int scaleSemis(int degree, bool minor)
{
    const int *sc = minor ? s_scale : s_major;
    return 12 * (degree / 7) + sc[degree % 7];
}

double midiHz(double m) { return 440.0 * std::pow(2.0, (m - 69) / 12.0); }

std::vector<float> keyVoice(const QString &inst, double f, long long len, int rate, Noise &rnd)
{
    SynthVoice v;
    v.start(instrumentOf(inst), f, rate, uint32_t(int32_t(rnd.next() * 2e9f)) ^ 0x9E3779B9u);
    const long long n = len + llround(v.releaseSeconds() * rate);
    std::vector<float> out(static_cast<size_t>(n), 0.f);
    for (long long i = 0; i < n; ++i) {
        if (i == len)
            v.release();
        out[size_t(i)] = v.next();
    }
    return out;
}

// Prowadzenie głosów: przewrót akordu najbliższy poprzedniemu (palce nie skaczą po klawiaturze)
std::vector<int> voiceChord(std::vector<int> notes, double &prevCenter)
{
    std::vector<int> best = notes;
    double bestCost = 1e9;
    for (size_t inv = 0; inv < notes.size(); ++inv) {
        std::vector<int> c = notes;
        for (size_t i = 0; i < inv; ++i)
            c[i] += 12;
        for (int shift : {-12, 0, 12}) {
            double center = 0;
            for (int m : c)
                center += m + shift;
            center /= double(c.size());
            const double cost = std::fabs(center - prevCenter);
            if (cost < bestCost) {
                bestCost = cost;
                best = c;
                for (int &m : best)
                    m += shift;
            }
        }
    }
    double center = 0;
    for (int m : best)
        center += m;
    prevCenter = center / double(best.size());
    std::sort(best.begin(), best.end());
    return best;
}

} // namespace

QVariantList kits()
{
    QVariantList list;
    for (const Kit &k : s_kits)
        list.append(QVariantMap{{QStringLiteral("id"), QString::fromUtf8(k.id)}, {QStringLiteral("label"), QString::fromUtf8(k.label)},
                                {QStringLiteral("hint"), QString::fromUtf8(k.hint)}});
    return list;
}

QVariantList genres()
{
    QVariantList list;
    for (const Genre &g : s_genres)
        list.append(QVariantMap{{QStringLiteral("id"), QString::fromUtf8(g.id)}, {QStringLiteral("label"), QString::fromUtf8(g.label)},
                                {QStringLiteral("bpm"), g.bpm}, {QStringLiteral("hint"), QString::fromUtf8(g.hint)}});
    return list;
}

SynthVoice::Inst instrumentOf(const QString &id)
{
    if (id == QLatin1String("epiano"))
        return SynthVoice::EPiano;
    if (id == QLatin1String("pad"))
        return SynthVoice::Pad;
    if (id == QLatin1String("pluck"))
        return SynthVoice::Pluck;
    if (id == QLatin1String("bells"))
        return SynthVoice::Bells;
    if (id == QLatin1String("lead"))
        return SynthVoice::Lead;
    return SynthVoice::Piano;
}

QVariantList instruments()
{
    QVariantList list;
    for (const Instrument &i : s_instruments)
        list.append(QVariantMap{{QStringLiteral("id"), QString::fromUtf8(i.id)}, {QStringLiteral("label"), QString::fromUtf8(i.label)},
                                {QStringLiteral("hint"), QString::fromUtf8(i.hint)}});
    return list;
}

QVariantList rhythms()
{
    QVariantList list;
    for (const Rhythm &r : s_rhythms)
        list.append(QVariantMap{{QStringLiteral("id"), QString::fromUtf8(r.id)}, {QStringLiteral("label"), QString::fromUtf8(r.label)}});
    return list;
}

QVariantList progressions()
{
    QVariantList list;
    for (const Progression &p : s_progressions)
        list.append(QVariantMap{{QStringLiteral("id"), QString::fromUtf8(p.id)}, {QStringLiteral("label"), QString::fromUtf8(p.label)},
                                {QStringLiteral("hint"), QString::fromUtf8(p.hint)},
                                {QStringLiteral("chords"), QVariantList{p.chords[0], p.chords[1], p.chords[2], p.chords[3]}}});
    return list;
}

QString chordName(int root, bool minor, int degree, bool seventh)
{
    static const char *names[12] = {"C", "Cis", "D", "Dis", "E", "F", "Fis", "G", "Gis", "A", "B", "H"};
    degree = std::clamp(degree, 0, 6);
    const int r = scaleSemis(degree, minor);
    const int third = scaleSemis(degree + 2, minor) - r, fifth = scaleSemis(degree + 4, minor) - r;
    const QString n = QString::fromUtf8(names[(root + r) % 12]);
    QString s;
    if (third == 4)
        s = n + QStringLiteral("-dur");
    else if (fifth == 6)
        s = n.toLower() + QStringLiteral(" zmn.");
    else
        s = n.toLower() + QStringLiteral("-moll");
    return seventh ? s + QStringLiteral("⁷") : s;
}

QStringList rowNames()
{
    QStringList list;
    for (const char *r : s_rows)
        list << QString::fromUtf8(r);
    return list;
}

QJsonObject emptyPattern(Kind kind, const QString &kitId, int bars)
{
    const int n = std::clamp(bars, 1, 4) * 16;
    QJsonArray zeros, none, ones;
    for (int i = 0; i < n; ++i) {
        zeros.append(0.0);
        none.append(-1);
        ones.append(1);
    }
    if (kind == Bass)
        return QJsonObject{{QStringLiteral("kit"), kitId}, {QStringLiteral("bars"), n / 16}, {QStringLiteral("root"), 0},
                           {QStringLiteral("notes"), none}, {QStringLiteral("glide"), true}};
    QJsonObject rows;
    for (const char *r : s_rows)
        rows.insert(QString::fromUtf8(r), zeros);
    return QJsonObject{{QStringLiteral("kit"), kitId}, {QStringLiteral("bars"), n / 16}, {QStringLiteral("swing"), 0.0},
                       {QStringLiteral("rows"), rows}, {QStringLiteral("rolls"), ones}};
}

QJsonObject genrePattern(const QString &id, Kind kind)
{
    const Genre *g = genre(id);
    if (!g)
        g = &s_genres[0];
    if (kind == Melody)
        return QJsonObject{{QStringLiteral("instrument"), QStringLiteral("lead")}, {QStringLiteral("bars"), 4}, {QStringLiteral("notes"), QJsonArray()}};
    if (kind == Keys) {
        struct K { const char *genre, *inst, *rhythm, *prog; int octave; bool seventh; };
        static const K table[] = {
            {"trap", "bells", "arp", "sad", 5, false}, {"drill", "pluck", "arp16", "dark", 4, false},
            {"boombap", "epiano", "half", "dreamy", 4, true}, {"lofi", "epiano", "sustain", "dreamy", 4, true},
            {"house", "piano", "stabs", "sad", 4, true}, {"pop", "piano", "half", "epic", 4, false},
        };
        const K *k = &table[0];
        for (const K &x : table)
            if (id == QLatin1String(x.genre))
                k = &x;
        QJsonArray chords;
        for (const Progression &pr : s_progressions)
            if (QLatin1String(pr.id) == QLatin1String(k->prog))
                for (int c : pr.chords)
                    chords.append(c);
        return QJsonObject{{QStringLiteral("instrument"), QString::fromUtf8(k->inst)}, {QStringLiteral("rhythm"), QString::fromUtf8(k->rhythm)},
                           {QStringLiteral("chords"), chords}, {QStringLiteral("octave"), k->octave}, {QStringLiteral("seventh"), k->seventh}};
    }
    if (kind == Bass) {
        QJsonArray notes;
        for (const char *p = g->bass; *p; ++p)
            notes.append(*p == '.' ? -1 : int(*p - 'a'));
        return QJsonObject{{QStringLiteral("kit"), QString::fromUtf8(g->kit)}, {QStringLiteral("bars"), 2},
                           {QStringLiteral("root"), g->root}, {QStringLiteral("notes"), notes}, {QStringLiteral("glide"), g->glide}};
    }
    QJsonObject rows{{QStringLiteral("kick"), steps(g->kick)}, {QStringLiteral("snare"), steps(g->snare)},
                     {QStringLiteral("clap"), steps(g->clap)}, {QStringLiteral("hat"), steps(g->hat)},
                     {QStringLiteral("openhat"), steps(g->openhat)}, {QStringLiteral("perc"), steps(g->perc)}};
    QJsonArray rolls;
    for (const char *p = g->rolls; *p; ++p)
        rolls.append(*p >= '2' && *p <= '4' ? int(*p - '0') : 1);
    return QJsonObject{{QStringLiteral("kit"), QString::fromUtf8(g->kit)}, {QStringLiteral("bars"), 2},
                       {QStringLiteral("swing"), g->swing}, {QStringLiteral("rows"), rows}, {QStringLiteral("rolls"), rolls}};
}

int noteMidi(const QJsonObject &p, int degree)
{
    const int root = std::clamp(p.value(QStringLiteral("root")).toInt(), 0, 11);
    // 808 w okolicach 30–60 Hz: tonika w oktawie 1 (C1 = MIDI 24), od Fis wzwyż — oktawa niżej nie schodzi poniżej 28 Hz
    const int base = 24 + root;
    return base + 12 * (degree / 7) + s_scale[degree % 7];
}

QJsonArray chordNotes(const QJsonObject &p)
{
    const QString rhythm = p.value(QStringLiteral("rhythm")).toString(QStringLiteral("sustain"));
    const QJsonArray chords = p.value(QStringLiteral("chords")).toArray();
    const bool minor = p.value(QStringLiteral("keyMinor")).toBool(true);
    const int root = std::clamp(p.value(QStringLiteral("keyRoot")).toInt(9), 0, 11);
    const int octave = std::clamp(p.value(QStringLiteral("octave")).toInt(4), 2, 6);
    const bool seventh = p.value(QStringLiteral("seventh")).toBool(false);
    const int base = 12 * (octave + 1) + root;
    double center = base + 5;
    struct Ev { int step, len; int tone; double vel; };    // tone −1 = cały akord
    std::vector<Ev> bar;
    if (rhythm == QLatin1String("half"))
        bar = {{0, 8, -1, 0.9}, {8, 8, -1, 0.75}};
    else if (rhythm == QLatin1String("stabs"))
        bar = {{0, 2, -1, 1}, {3, 2, -1, 0.7}, {6, 2, -1, 0.85}, {10, 2, -1, 0.75}, {12, 3, -1, 0.9}};
    else if (rhythm == QLatin1String("arp")) {
        static const int seq[8] = {0, 1, 2, 3, 2, 1, 0, 1};
        for (int i = 0; i < 8; ++i)
            bar.push_back({i * 2, 2, seq[i], i % 2 ? 0.7 : 0.95});
    } else if (rhythm == QLatin1String("arp16")) {
        for (int i = 0; i < 16; ++i)
            bar.push_back({i, 1, i % 4, i % 4 == 0 ? 1.0 : 0.65});
    } else {
        bar = {{0, 16, -1, 0.9}};
    }
    QJsonArray out;
    auto note = [&out](int step, int len, int pitch, double vel, double pan) {
        out.append(QJsonObject{{QStringLiteral("step"), step}, {QStringLiteral("len"), len}, {QStringLiteral("pitch"), pitch},
                               {QStringLiteral("vel"), vel}, {QStringLiteral("pan"), pan}});
    };
    for (int ci = 0; ci < std::min(8, int(chords.size())); ++ci) {
        const int d = std::clamp(chords.at(ci).toInt(), 0, 6);
        std::vector<int> notes;
        for (int t = 0; t < (seventh ? 4 : 3); ++t)
            notes.push_back(base + scaleSemis(d + 2 * t, minor));
        notes = voiceChord(notes, center);
        for (const Ev &e : bar) {
            if (e.tone < 0) {
                for (size_t t = 0; t < notes.size(); ++t)
                    note(ci * 16 + e.step, e.len, notes[t], e.vel * 0.6, double(t) / notes.size() * 0.6 - 0.3);
            } else {
                // Arpeggio: kolejne dźwięki akordu, czwarty to podstawa oktawę wyżej
                const int midi = e.tone < int(notes.size()) && !(e.tone == 3 && !seventh) ? notes[size_t(e.tone)] : notes[0] + 12;
                note(ci * 16 + e.step, e.len, midi, e.vel, e.tone % 2 ? 0.25 : -0.25);
            }
        }
    }
    return out;
}

std::shared_ptr<AudioSource> kitSample(const QString &kitId, const QString &row, int rate)
{
    const Kit &k = kit(kitId);
    Noise rnd;
    std::vector<float> l, r;
    float gain = 1;
    if (row == QLatin1String("kick")) {
        l = kickVoice(k, rate, rnd);
        gain = 0.95f;
    } else if (row == QLatin1String("snare")) {
        l = snareVoice(k, rate, rnd);
        gain = 0.7f;
    } else if (row == QLatin1String("clap")) {
        l = clapVoice(k, rate, rnd);
        r = clapVoice(k, rate, rnd);
        gain = 0.8f;
    } else if (row == QLatin1String("hat")) {
        l = hatVoice(k, rate, k.hatDecay, rate, rnd);
        gain = float(k.hatLevel);
    } else if (row == QLatin1String("openhat")) {
        l = hatVoice(k, rate, k.ohatDecay, rate, rnd);
        gain = float(k.hatLevel) * 0.8f;
    } else {
        l = percVoice(k, rate, rnd);
        gain = 0.35f;
    }
    if (r.size() != l.size())
        r = l;
    auto src = std::make_shared<AudioSource>();
    src->channels = 2;
    src->frames = (long long)l.size();
    src->data.resize(l.size() * 2);
    for (size_t i = 0; i < l.size(); ++i) {
        src->data[2 * i] = l[i] * gain;
        src->data[2 * i + 1] = r[i] * gain;
    }
    src->computePeaks();
    return src;
}

BassParams bassParams(const QString &kitId)
{
    const Kit &k = kit(kitId);
    return {k.bassDecay, k.bassGlide, k.bassDrive};
}

std::shared_ptr<AudioSource> render(const QJsonObject &p, Kind kind, double bpm, int rate)
{
    const Kit &k = kit(p.value(QStringLiteral("kit")).toString());
    const int bars = kind == Keys ? std::clamp(int(p.value(QStringLiteral("chords")).toArray().size()), 1, 8)
                   : kind == Melody ? std::clamp(p.value(QStringLiteral("bars")).toInt(4), 1, 8)
                                    : std::clamp(p.value(QStringLiteral("bars")).toInt(2), 1, 4);
    const int nSteps = bars * 16;
    const double stepSec = 60.0 / std::clamp(bpm, 30.0, 300.0) / 4;
    const long long loop = llround(nSteps * stepSec * rate);
    // Dwa przejścia wzoru, wynik to drugie — ogony z pierwszego wchodzą na początek (pętla bez szwu)
    Buffer b;
    b.l.assign(size_t(2 * loop), 0.f);
    b.r.assign(size_t(2 * loop), 0.f);
    Noise rnd;

    if (kind == Drums) {
        const double swing = std::clamp(p.value(QStringLiteral("swing")).toDouble(), 0.0, 0.5);
        const QJsonObject rows = p.value(QStringLiteral("rows")).toObject();
        const QJsonArray rolls = p.value(QStringLiteral("rolls")).toArray();
        const auto kick = kickVoice(k, rate, rnd), snare = snareVoice(k, rate, rnd), perc = percVoice(k, rate, rnd);
        const auto clapL = clapVoice(k, rate, rnd), clapR = clapVoice(k, rate, rnd);    // dwa różne szumy — szerokie klaśnięcie
        const auto hat = hatVoice(k, rate, k.hatDecay, rate, rnd);
        auto vel = [&](const char *row, int i) { return rows.value(QString::fromUtf8(row)).toArray().at(i % nSteps).toDouble(); };
        for (int pass = 0; pass < 2; ++pass) {
            for (int i = 0; i < nSteps; ++i) {
                const double t = stepTime(i, stepSec, swing);
                const long long at = pass * loop + llround(t * rate);
                if (double v = vel("kick", i))
                    b.add(at, kick, float(v * 0.95), 0);
                if (double v = vel("snare", i))
                    b.add(at, snare, float(v * 0.7), 0);
                if (double v = vel("clap", i)) {
                    b.add(at, clapL, float(v * 0.8), -1);
                    b.add(at, clapR, float(v * 0.8), 1);
                }
                if (double v = vel("perc", i))
                    b.add(at, perc, float(v * 0.35), -0.35f);
                if (double v = vel("hat", i)) {
                    const int roll = std::clamp(rolls.at(i).toInt(1), 1, 4);
                    for (int r = 0; r < roll; ++r) {
                        // Rolka: kolejne uderzenia w kroku, lekko cichnące
                        const long long rat = at + llround(r * stepSec / roll * rate);
                        b.add(rat, hat, float(v * k.hatLevel * (roll > 1 ? 1.0 - 0.12 * r : 1.0)), 0.15f);
                    }
                }
                if (double v = vel("openhat", i)) {
                    // Otwarty hi-hat gra do następnego zamkniętego (jak w prawdziwym talerzu)
                    int next = i + 1;
                    while (next < i + nSteps && !vel("hat", next) && !vel("openhat", next))
                        ++next;
                    const int len = int((next - i) * stepSec * rate);
                    b.add(at, hatVoice(k, rate, k.ohatDecay, len, rnd), float(v * k.hatLevel * 0.8), -0.15f);
                }
            }
        }
        lofi(b, k.lofi, rate, rnd);
        normalize(b, 0.75f);
    } else if (kind == Keys || kind == Melody) {
        // Nuty: z akordów (w tonacji projektu) albo wprost z piano rolla
        const QString inst = p.value(QStringLiteral("instrument")).toString(QStringLiteral("piano"));
        const QJsonArray notes = kind == Keys ? chordNotes(p) : p.value(QStringLiteral("notes")).toArray();
        for (int pass = 0; pass < 2; ++pass)
            for (const QJsonValue &nv : notes) {
                const QJsonObject n = nv.toObject();
                const int step = n.value(QStringLiteral("step")).toInt();
                if (step < 0 || step >= nSteps)
                    continue;
                const long long at = pass * loop + llround(step * stepSec * rate);
                const long long len = llround(std::max(1, n.value(QStringLiteral("len")).toInt(2)) * stepSec * rate);
                const int pitch = std::clamp(n.value(QStringLiteral("pitch")).toInt(60), 12, 120);
                b.add(at, keyVoice(inst, midiHz(pitch), len, rate, rnd), float(n.value(QStringLiteral("vel")).toDouble(0.85)),
                      float(n.value(QStringLiteral("pan")).toDouble(0)));
            }
        normalize(b, 0.6f);
    } else {
        // 808: jeden głos; przy ślizgu nuta płynnie przechodzi w następną bez ponownego uderzenia
        const QJsonArray notes = p.value(QStringLiteral("notes")).toArray();
        const bool glide = p.value(QStringLiteral("glide")).toBool(true);
        struct Ev { long long at; double freq; int step; };
        std::vector<Ev> evs;
        for (int pass = 0; pass < 2; ++pass)
            for (int i = 0; i < nSteps; ++i) {
                const int d = notes.at(i).toInt(-1);
                if (d < 0)
                    continue;
                const double f = 440.0 * std::pow(2.0, (noteMidi(p, std::min(d, 14)) - 69) / 12.0);
                evs.push_back({pass * loop + llround(i * stepSec * rate), f, pass * nSteps + i});
            }
        double ph = 0, freq = 0, from = 0, amp = 0, sinceTrig = 1e9, sinceSlide = 1e9;
        size_t e = 0;
        const double drive = 1 + 4 * k.bassDrive, norm = 1 / std::tanh(drive);
        const double decayK = std::exp(-3.0 / (k.bassDecay * rate));
        for (long long i = 0; i < 2 * loop; ++i) {
            if (e < evs.size() && i == evs[e].at) {
                const bool slide = glide && k.bassGlide > 0 && e > 0 && evs[e].step - evs[e - 1].step <= 3 && amp > 0.05;
                if (slide) {
                    from = freq;
                    sinceSlide = 0;
                } else {
                    from = evs[e].freq;
                    sinceTrig = 0;
                    sinceSlide = 1e9;
                    amp = 1;
                }
                freq = evs[e].freq;
                ++e;
                if (!slide)
                    freq = from;
            }
            double f = freq;
            if (sinceSlide < k.bassGlide * rate) {
                const double x = sinceSlide / (k.bassGlide * rate);
                f = from + (evs[e - 1].freq - from) * (x * x * (3 - 2 * x));
                if (sinceSlide + 1 >= k.bassGlide * rate)
                    freq = evs[e - 1].freq;
            }
            const double punch = 1 + 0.6 * std::exp(-sinceTrig / rate * 60);
            ph += 2 * M_PI * f * punch / rate;
            const double attack = std::min(1.0, sinceTrig / (0.003 * rate));
            // Następna nuta bez ślizgu — krótkie wyciszenie poprzedniej, żeby nie trzasnęło
            double cut = 1;
            if (e < evs.size() && !(glide && k.bassGlide > 0 && e > 0 && evs[e].step - evs[e - 1].step <= 3)) {
                const long long left = evs[e].at - i;
                if (left < rate / 200)
                    cut = double(left) / (rate / 200);
            }
            const double x = std::sin(ph) * amp * attack * cut;
            const float y = float(std::tanh(x * drive) * norm);
            b.l[size_t(i)] = y;
            b.r[size_t(i)] = y;
            amp *= decayK;
            sinceTrig += 1;
            sinceSlide += 1;
        }
        lofi(b, k.lofi * 0.5, rate, rnd);
        normalize(b, 0.7f);
    }

    auto src = std::make_shared<AudioSource>();
    src->channels = kind == Bass ? 1 : 2;
    src->frames = loop;
    src->data.resize(size_t(loop * src->channels));
    for (long long i = 0; i < loop; ++i) {
        if (kind != Bass) {
            src->data[size_t(2 * i)] = b.l[size_t(loop + i)];
            src->data[size_t(2 * i + 1)] = b.r[size_t(loop + i)];
        } else {
            src->data[size_t(i)] = b.l[size_t(loop + i)];
        }
    }
    src->computePeaks();
    return src;
}

} // namespace BeatSynth
