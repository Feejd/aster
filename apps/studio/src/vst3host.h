#pragma once

#include <QByteArray>
#include <QList>
#include <QString>
#include <atomic>
#include <memory>
#include <vector>

// Host wtyczek VST3. Wtyczka żyje w procesie Studia: process() woła wątek audio (bez blokad i alokacji),
// reszta — wątek interfejsu. Dźwięk stereo, nuty i parametry z dokładnością do próbki.
// Okno wtyczki to osobne okno X11 (przez XWayland) — VST3 na Linuksie nie zna Waylanda.
namespace Vst3 {

struct Info
{
    QString path, uid, name, vendor, category;
    bool instrument = false;
};

struct Param
{
    unsigned id = 0;
    QString name, unit;
    double value = 0;             // 0…1
    bool automatable = true;
};

struct Note
{
    int offset = 0;               // próbka w bloku
    bool on = true;
    int pitch = 60;
    float velocity = 0.8f;
};

struct Transport
{
    double bpm = 120;
    long long samples = 0;        // pozycja na osi czasu
    bool playing = false;
    int beatsPerBar = 4;
};

// Wszystkie wtyczki w ~/.vst3, /usr/lib64/vst3, /usr/lib/vst3, /usr/local/lib/vst3 (i VST3_PATH)
QList<Info> scan();

class Plugin
{
public:
    static std::unique_ptr<Plugin> load(const Info &info, double rate, int maxBlock, QString *error);
    ~Plugin();
    const Info &info() const { return m_info; }

    // Wątek audio: l, r — wejście i wyjście w miejscu (n ≤ maxBlock)
    void process(float *l, float *r, int n, const Note *notes, int noteCount, const Transport &t);
    int latency() const { return m_latency.load(); }

    // Wątek interfejsu
    QList<Param> params() const;
    void setParam(unsigned id, double value);
    QByteArray state() const;
    bool setState(const QByteArray &data);
    bool hasEditor() const;
    bool openEditor();
    void closeEditor();

    struct Impl;

private:
    Plugin();
    std::unique_ptr<Impl> d;
    Info m_info;
    std::atomic<int> m_latency{0};
};

}
