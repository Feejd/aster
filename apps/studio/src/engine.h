#pragma once

#include "audiosource.h"
#include "dsp.h"
#include "tune.h"
#include "synthvoice.h"

#include <QList>
#include <QMutex>
#include <QObject>
#include <QString>
#include <atomic>
#include <functional>
#include <memory>
#include <thread>
#include <vector>

struct pw_thread_loop;
struct pw_context;
struct pw_core;
struct pw_registry;
struct pw_stream;

// ——— Stan miksu widziany przez wątek audio ———
// Wątek interfejsu buduje nowy Snapshot przy każdej zmianie projektu i podaje go silnikowi
// (wymiana wskaźnika atomowego). Wątek audio tylko czyta — bez blokad i bez alokacji;
// stare migawki zwalnia z powrotem wątek interfejsu.
struct ClipRT
{
    const AudioSource *src = nullptr;
    long long start = 0;          // początek na osi czasu (ramki)
    long long length = 0;         // długość na osi czasu
    long long srcStart = 0;       // fragment pliku: od…
    long long srcLen = 0;         // …i ile (zapętlony klip powtarza ten fragment)
    long long offset = 0;         // przesunięcie fazy pętli (po przycięciu lub podziale zapętlonego klipu)
    long long fadeIn = 0, fadeOut = 0;   // narastanie i wyciszanie (ramki)
    float gain = 1.f;                     // głośność klipu
    bool loop = false;
};

struct TrackRT
{
    std::vector<ClipRT> clips;
    float gainL = 1.f, gainR = 1.f;      // głośność × panorama
    bool audible = true;                  // po uwzględnieniu wycisz/solo
    Biquad eq[4];                         // usuwanie dudnienia, niskie, średnie, wysokie
    CompParams comp;
    float send = 0;                       // ile do pogłosu (po suwaku głośności)
    float echo = 0;                       // ile do echa
    float drive = 0;                      // przester / ciepło (0 = brak)
    TuneParams tune;                      // autotune
};

struct Snapshot
{
    std::vector<TrackRT> tracks;
    double bpm = 120;
    int beatsPerBar = 4;
    float master = 1.f;
    float reverbSize = 0.5f;              // mała sala … duża hala
    float click = 0.7f;                   // głośność metronomu
    int echoDelay = 24000;                // ramki (z tempa)
    float echoFeedback = 0.35f;
    MasterParams mastering;
    std::vector<SourcePtr> keep;          // trzyma pliki przy życiu, dopóki migawka jest w użyciu
};

// Mikser: ten sam kod gra na żywo i eksportuje (eksport brzmi dokładnie tak jak odsłuch)
class Renderer
{
public:
    static constexpr int MaxBlock = 2048;
    static constexpr int MaxTracks = 64;
    using Meters = std::atomic<float>[MaxTracks + 1][2];     // [ścieżka][kanał], ostatnia — suma

    Renderer() : m_tune(MaxTracks) {}
    // Miesza `n` ramek od pozycji `pos` (może być ujemna — odliczanie) do `out` (L/R z przeplotem)
    void process(const Snapshot *s, long long pos, int n, float *out, bool click, Meters *meters, int rate);
    // Pułap ogranicznika sumy (liniowo). Dla MP3/OGG niżej — koder dokłada własne szczyty.
    void setCeiling(float c) { m_ceiling = c; }

private:
    void block(const Snapshot *s, long long pos, int n, float *out, bool click, Meters *meters, int rate);
    float m_l[MaxBlock], m_r[MaxBlock], m_tl[MaxBlock], m_tr[MaxBlock];
    // Stan efektów ścieżek (po indeksie ścieżki) i wspólny pogłos
    BiquadState m_eq[MaxTracks][4][2];
    CompState m_comp[MaxTracks];
    std::vector<PitchCorrector> m_tune;   // osobny stan autotune dla każdej ścieżki
    Reverb m_reverb;
    int m_reverbRate = 0;
    float m_rl[MaxBlock], m_rr[MaxBlock], m_el[MaxBlock], m_er[MaxBlock];
    Echo m_echo;
    BiquadState m_mEq[2][2];
    CompState m_mComp;
    Limiter m_limiter;
    float m_ceiling = 0.977f;     // −0,2 dBFS
};

// Bufor pierścieniowy jeden-pisze-jeden-czyta (wątek audio → wątek zapisu nagrania)
class SpscRing
{
public:
    explicit SpscRing(size_t capacity) : m_buf(capacity) {}
    size_t write(const float *data, size_t n);
    size_t read(float *data, size_t n);
    size_t available() const;
    void clear() { m_read.store(m_write.load()); }

private:
    std::vector<float> m_buf;
    std::atomic<size_t> m_write{0}, m_read{0};
};

struct AudioDevice
{
    uint32_t id = 0;
    QString name;           // node.name — do target.object
    QString label;          // opis dla ludzi
    bool input = false;
};

// Silnik dźwięku: PipeWire (strumień odtwarzania + strumień nagrywania), transport, metronom, nagrywanie.
class Engine : public QObject
{
    Q_OBJECT
public:
    static constexpr int Rate = 48000;
    static constexpr long long NoSeek = -(1LL << 62);

    explicit Engine(QObject *parent = nullptr);
    ~Engine() override;

    bool start();                          // false → bez dźwięku (np. brak PipeWire); patrz error()
    bool running() const { return m_core != nullptr; }
    QString error() const { return m_error; }

    void setSnapshot(Snapshot *s);         // przejmuje własność
    void collect();                        // zwalnia migawki oddane przez wątek audio (wołać z wątku interfejsu)

    // Transport (ramki)
    void play(long long from, long long countInEnd = NoSeek);
    void stop();
    void seek(long long frame);
    long long position() const;
    bool playing() const { return m_playing.load(); }
    void setMetronome(bool on) { m_metronome.store(on); }
    // Region pętli odtwarzania (ćwiczenie fragmentu); nie działa w trakcie nagrywania
    void setCycle(bool on, long long start, long long end);
    void setLatencyOffset(long long frames) { m_extraLatency.store(frames); }
    void readMeters(std::vector<float> &tracks, float master[2]);   // szczyty od ostatniego odczytu

    // Nagrywanie: od pozycji `start` (wcześniej odliczanie), kanał wejścia 0 = oba zmieszane, 1 = lewy, 2 = prawy
    bool startRecording(const QString &path, long long start, int channel);
    // Kończy nagrywanie; zwraca nagrany dźwięk (pusty, gdy nic nie nagrano) i jego miejsce na osi czasu
    std::shared_ptr<AudioSource> stopRecording(long long *start);
    bool recording() const { return m_recThread.joinable(); }
    long long recordStart() const { return m_recStart; }
    std::vector<float> livePeaks() const;  // szczyty nagrywanego dźwięku (do rysowania w trakcie)

    // Odsłuch pojedynczego dźwięku (klik w piano rollu, klawiatura) — gra też przy zatrzymanym transporcie.
    // Dźwięk trzymany jest po stronie interfejsu jeszcze kilka sekund, więc wątek audio nigdy go nie zwalnia.
    void preview(SourcePtr sound, float gain);

    // Granie na żywo (klawiatura komputera, MIDI): nuta brzmi, dopóki nie przyjdzie liveNoteOff z tym samym id
    void liveNoteOn(int id, SynthVoice::Inst inst, double freq, float gain);
    void liveNoteOff(int id);

    // Wejście włączone tylko, gdy jakaś ścieżka czeka na nagranie (inaczej system pokazuje używany mikrofon)
    void setCapture(bool on);
    bool capturing() const { return m_in != nullptr; }
    void readInputLevel(float level[2]);

    // Urządzenia
    QList<AudioDevice> devices() const;
    void setOutput(const QString &name);
    void setInput(const QString &name);
    QString output() const { return m_outName; }
    QString input() const { return m_inName; }

    // Eksport miksu poza czasem rzeczywistym. format: wav | flac | mp3 | ogg. progress zwraca false → przerwij
    static bool exportMix(const Snapshot &s, long long frames, const QString &path, const QString &format,
                          const std::function<bool(double)> &progress, QString *error);

signals:
    void devicesChanged();
    void streamError(const QString &message);

private:
    friend struct EngineCallbacks;
    void connectOutput();
    void connectInput();
    void onPlayback();                     // wątek audio
    void onCapture();                      // wątek audio
    void writerLoop(QString path, int channel);
    std::vector<float> m_recData;          // nagrany dźwięk (mono), wypełniany przez wątek zapisu

    pw_thread_loop *m_loop = nullptr;
    pw_context *m_context = nullptr;
    pw_core *m_core = nullptr;
    pw_registry *m_registry = nullptr;
    pw_stream *m_out = nullptr;
    pw_stream *m_in = nullptr;
    void *m_hooks = nullptr;               // spa_hook-i (ukryte przed nagłówkiem)
    QString m_error;
    QString m_outName, m_inName;

    mutable QMutex m_devMutex;
    QList<AudioDevice> m_devices;

    // Wymiana migawek
    std::atomic<Snapshot *> m_next{nullptr};
    Snapshot *m_current = nullptr;         // tylko wątek audio
    Snapshot *m_retired[64] = {};
    std::atomic<unsigned> m_retiredW{0}, m_retiredR{0};
    std::unique_ptr<Snapshot> m_offline;   // migawka, gdy nie ma wątku audio

    // Transport
    std::atomic<bool> m_playing{false};
    std::atomic<bool> m_metronome{false};
    std::atomic<long long> m_seek{NoSeek};
    std::atomic<long long> m_pos{0};       // publikowana pozycja
    std::atomic<long long> m_countInEnd{NoSeek};
    std::atomic<long long> m_outDelay{0};
    std::atomic<long long> m_extraLatency{0};
    std::atomic<bool> m_cycle{false};
    std::atomic<long long> m_cycleStart{0}, m_cycleEnd{0};
    long long m_rtPos = 0;                 // tylko wątek audio
    Renderer m_renderer;
    Renderer::Meters m_meters{};

    // Nagrywanie
    SpscRing m_ring{size_t(Rate) * 2 * 8};
    std::atomic<bool> m_recActive{false};
    std::atomic<bool> m_recStop{false};
    std::atomic<long long> m_recFirst{NoSeek};
    long long m_recStart = 0;
    std::thread m_recThread;
    mutable QMutex m_liveMutex;
    std::vector<float> m_livePeaks;
    std::atomic<float> m_inPeak[2] = {};
    std::atomic<long long> m_recClipStart{0};

    // Głosy odsłuchu: wątek interfejsu wpisuje dźwięk i zwiększa numer, wątek audio zaczyna go od początku
    static constexpr int PreviewVoices = 8;
    struct PreviewSlot
    {
        std::atomic<const AudioSource *> src{nullptr};
        std::atomic<float> gain{1.f};
        std::atomic<unsigned> gen{0};
        unsigned seen = 0;               // tylko wątek audio
        long long pos = 0;               // tylko wątek audio
    };
    PreviewSlot m_preview[PreviewVoices];

    // Polecenia nut na żywo: kolejka jeden-pisze-jeden-czyta (interfejs → wątek audio), bez blokad
    struct LiveCmd
    {
        int id = 0;
        int inst = 0;
        float freq = 0, gain = 0;
        bool on = false;
    };
    static constexpr unsigned LiveQueue = 256;
    LiveCmd m_liveCmds[LiveQueue];
    std::atomic<unsigned> m_liveW{0}, m_liveR{0};
    static constexpr int LiveVoices = 16;
    SynthVoice m_voices[LiveVoices];              // tylko wątek audio
    int m_voiceId[LiveVoices] = {};
    long long m_voiceAge[LiveVoices] = {};
    long long m_voiceClock = 0;
    uint32_t m_voiceSeed = 12345;
    void pushLive(const LiveCmd &c);
    void renderLive(float *dst, uint32_t n);      // wątek audio
    int m_previewNext = 0;
    QList<QPair<qint64, SourcePtr>> m_previewKeep;
};
