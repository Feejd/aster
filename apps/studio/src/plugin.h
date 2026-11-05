#pragma once

#include <QByteArray>
#include <QList>
#include <QString>
#include <atomic>
#include <memory>

// Wspólny interfejs wtyczek. Formaty: VST3 (vst3host.cpp) i CLAP (claphost.cpp). Studio trzyma wtyczkę
// w osobnym procesie (remote.cpp): jej awaria nie zamyka programu, a dźwięk idzie dalej bez niej.
// process() i automate() woła wątek audio (bez blokad i alokacji), resztę — wątek interfejsu.
namespace Plug {

struct Info
{
    QString format;               // "vst3" | "clap"
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

class Plugin
{
public:
    virtual ~Plugin() = default;
    const Info &info() const { return m_info; }

    // Wątek audio: l, r — wejście i wyjście w miejscu (n ≤ maxBlock). side — wejście boczne, gdy wtyczka je ma
    virtual void process(float *l, float *r, int n, const Note *notes, int noteCount, const Transport &t,
                         const float *sideL = nullptr, const float *sideR = nullptr) = 0;
    virtual void automate(unsigned id, double value) = 0;   // wartość na początek następnego process()
    virtual int latency() const { return m_latency.load(); }

    // Wątek interfejsu
    virtual bool hasSidechain() const = 0;
    virtual QList<Param> params() const = 0;
    virtual void setParam(unsigned id, double value) = 0;
    virtual QByteArray state() const = 0;
    virtual bool setState(const QByteArray &data) = 0;
    virtual bool hasEditor() const = 0;
    virtual bool openEditor() = 0;
    virtual void closeEditor() = 0;
    virtual bool crashed() const { return false; }

protected:
    Info m_info;
    std::atomic<int> m_latency{0};
};

// Wtyczki z jednego pliku (w procesie, który to woła — wtyczka może go zabić; Studio robi to w procesie pomocniczym)
QList<Info> scanFile(const QString &path);
// Pliki wtyczek w standardowych miejscach: ~/.vst3, ~/.clap, systemowe, VST3_PATH, CLAP_PATH
QStringList pluginFiles();
// W tym procesie
std::unique_ptr<Plugin> loadLocal(const Info &info, double rate, int maxBlock, QString *error);
// W osobnym procesie (offline: eksport — bez limitu czasu na blok)
std::unique_ptr<Plugin> loadRemote(const Info &info, double rate, int maxBlock, bool offline, QString *error);

}

namespace Vst3 {
QList<Plug::Info> scanFile(const QString &path);
std::unique_ptr<Plug::Plugin> load(const Plug::Info &info, double rate, int maxBlock, QString *error);
}
namespace Clap {
QList<Plug::Info> scanFile(const QString &path);
std::unique_ptr<Plug::Plugin> load(const Plug::Info &info, double rate, int maxBlock, QString *error);
}
