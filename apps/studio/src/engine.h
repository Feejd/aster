#pragma once

#include "audiosource.h"
#include "dsp.h"
#include "instrument.h"
#include "vst3host.h"
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
    bool raw = false;                     // plik zamrożonego insertu: bez łagodzenia brzegów (uderzenie w ramce 0)
};

// Insert miksera: suma tego, co do niego idzie, efekty, głośność i wysyłki
struct SendRT
{
    int to = 0;                           // numer insertu
    float gain = 0;
    int delay = 0;                        // wyrównanie opóźnień wtyczek (ramki)
};

struct PluginRT
{
    Vst3::Plugin *plugin = nullptr;       // żyje w Snapshot::plugins
    int side = -1;                        // insert podany na wejście boczne
};

struct InsertRT
{
    float gain = 1.f, pan = 0.f;          // suwak i panorama (automatyka je zastępuje)
    bool audible = true;                  // po uwzględnieniu wycisz/solo
    bool toMaster = true;                 // grupa bez wyjścia na master gra tylko przez wysyłki
    Biquad eq[4];                         // usuwanie dudnienia, niskie, średnie, wysokie
    CompParams comp;
    float send = 0;                       // ile do pogłosu (po suwaku głośności)
    float echo = 0;                       // ile do echa
    float drive = 0;                      // przester / ciepło (0 = brak)
    float dbl = 0;                        // sztuczny dubel (0 = brak)
    float deess = 0;                      // de-esser (0 = brak)
    Biquad deessLp, deessHp;              // jego zwrotnica (dół / góra)
    TuneParams tune;                      // autotune
    std::vector<PluginRT> fx;             // wtyczki VST3 po efektach Studia
    int duckFrom = -1;                    // sidechain Studia: insert, który ścisza ten
    float duck = 0;                       // jak mocno (0…1)
    int delay = 0;                        // wyrównanie opóźnień wtyczek na drodze do sumy (ramki)
    std::vector<SendRT> sends;            // po suwaku, do insertów dalej w Snapshot::order
};

// Automatyka: krzywa jednego parametru w czasie utworu
struct AutoRT
{
    enum Kind { Volume, Pan, Reverb, Echo, Drive, Double, Deess, Kinds, ChannelVolume, Master, Param };
    Kind kind = Volume;
    int index = 0;                        // insert albo kanał
    Vst3::Plugin *plugin = nullptr;       // Param
    unsigned param = 0;
    long long start = 0, end = 0;
    std::vector<std::pair<long long, float>> points;   // ramki od początku utworu, wartość 0…1
    float at(long long pos) const
    {
        if (points.empty())
            return 0;
        if (pos <= points.front().first)
            return points.front().second;
        if (pos >= points.back().first)
            return points.back().second;
        for (size_t i = 1; i < points.size(); ++i)
            if (pos < points[i].first) {
                const auto &a = points[i - 1], &b = points[i];
                return a.second + (b.second - a.second) * float(pos - a.first) / float(std::max(1LL, b.first - a.first));
            }
        return points.back().second;
    }
    // Fader: te same pozycje co suwak miksera (0 dB przy ~71%, +6 dB na górze)
    static float gainOf(float v)
    {
        if (v <= 0.001f)
            return 0;
        const float db = 6.f + 40.f * std::log10(v);
        return std::pow(10.f, db / 20.f);
    }
};

// Pas playlisty: klipy audio i insert, do którego grają
struct LaneRT
{
    int insert = 0;
    std::vector<ClipRT> clips;
};

// Nuta w czasie utworu (ramki), posortowane rosnąco
struct SeqEvent
{
    long long at = 0;
    int pitch = 60;
    float velocity = 0.8f;
    bool on = true;
};

// Kanał: instrument, jego nuty i insert docelowy
struct ChannelRT
{
    Instrument *inst = nullptr;           // żyje w Snapshot::instruments
    int insert = 0;
    float gainL = 1.f, gainR = 1.f;
    bool audible = true;
    std::vector<SeqEvent> events;
};

struct Snapshot
{
    std::vector<LaneRT> lanes;
    std::vector<InsertRT> inserts;
    std::vector<ChannelRT> channels;
    std::vector<AutoRT> autos;
    int latency = 0;                      // opóźnienie całej sumy przez wtyczki (ramki)
    std::vector<int> order;               // inserty w kolejności liczenia: źródła wysyłek przed celami
    std::vector<std::shared_ptr<Instrument>> instruments;
    double bpm = 120;
    int beatsPerBar = 4;
    float master = 1.f;
    float reverbSize = 0.5f;              // mała sala … duża hala
    float click = 0.7f;                   // głośność metronomu
    int echoDelay = 24000;                // ramki (z tempa)
    float echoFeedback = 0.35f;
    MasterParams mastering;
    std::vector<SourcePtr> keep;          // trzyma pliki przy życiu, dopóki migawka jest w użyciu
    std::vector<std::shared_ptr<Vst3::Plugin>> plugins;   // i wtyczki (zwalnia je wątek interfejsu)
};

// Mikser: ten sam kod gra na żywo i eksportuje (eksport brzmi dokładnie tak jak odsłuch)
class Renderer
{
public:
    static constexpr int MaxBlock = 2048;
    static constexpr int MaxTracks = 64;
    using Meters = std::atomic<float>[MaxTracks + 1][2];     // [ścieżka][kanał], ostatnia — suma

    static constexpr int MaxChannels = 128;
    static constexpr int MaxDelay = 32768;     // ponad 0,6 s opóźnienia wtyczek na ścieżce
    Renderer() : m_tune(MaxTracks), m_dbl(MaxTracks), m_bus(size_t(MaxTracks) * 2 * MaxBlock, 0.f), m_delay(size_t(MaxTracks) * 2 * MaxDelay, 0.f) {}
    // Miesza `n` ramek od pozycji `pos` (może być ujemna — odliczanie) do `out` (L/R z przeplotem)
    // clips: false — bez klipów (zatrzymany transport): grają tylko głosy na żywo i ogony pogłosu/echa
    void process(const Snapshot *s, long long pos, int n, float *out, bool click, Meters *meters, int rate, bool clips = true);
    void setLive(LivePool *live) { m_live = live; }
    // Zamrażanie: wyjściem staje się ten insert po efektach, przed suwakiem
    void setTap(int insert) { m_tap = insert; }
    // Nuty grane teraz (klawiatura, MIDI): wchodzą na początek najbliższego bloku
    struct LiveNote { int channel; bool on; int pitch; float velocity; };
    void setLiveNotes(const LiveNote *notes, int count) { m_liveNotes = notes; m_liveCount = count; }
    // Odsłuch wejścia (mono) na ścieżce `track` w tym wywołaniu process() — przed efektami, jak klipy
    void setMonitor(int track, const float *buf, int count) { m_monTrack = track; m_mon = buf; m_monN = count; m_monPos = 0; }
    // Pułap ogranicznika sumy (liniowo). Dla MP3/OGG niżej — koder dokłada własne szczyty.
    void setCeiling(float c) { m_ceiling = c; }

private:
    void block(const Snapshot *s, long long pos, int n, float *out, bool click, Meters *meters, int rate, bool clips);
    LivePool *m_live = nullptr;           // głosy grane na żywo (tylko w silniku, nie przy eksporcie)
    const LiveNote *m_liveNotes = nullptr;
    int m_liveCount = 0;
    const float *m_mon = nullptr;         // odsłuch wejścia: próbki, ich liczba i ile już zużyto
    int m_monTrack = -1, m_monN = 0, m_monPos = 0;
    void sequence(const Snapshot *s, long long pos, int n, bool playing);
    float *busL(int i) { return m_bus.data() + size_t(i) * 2 * MaxBlock; }
    float *busR(int i) { return busL(i) + MaxBlock; }
    float m_l[MaxBlock], m_r[MaxBlock], m_cl[MaxBlock], m_cr[MaxBlock];
    std::vector<float> m_bus;             // po dwa kanały na każdy insert
    std::vector<float> m_delay;           // pierścień po suwaku każdego insertu (kompensacja opóźnień)
    int m_delayPos[MaxTracks] = {};
    float m_duckEnv[MaxTracks] = {};
    float m_dl[MaxBlock], m_dr[MaxBlock];
    float m_tapL[MaxBlock], m_tapR[MaxBlock];
    bool m_tapHit = false;
    void delayed(int insert, int delay, int n, float *l, float *r);
    bool m_any[MaxTracks] = {};           // ten insert ma dźwięk w tym bloku
    size_t m_cursor[MaxChannels] = {};    // następna nuta kanału
    long long m_nextPos = 0;              // gdzie powinien zacząć się kolejny blok (inaczej — skok głowicy)
    const Snapshot *m_seqSnap = nullptr;
    bool m_wasPlaying = false;
    Vst3::Note m_ev[512];
    float m_autoVal[MaxTracks][AutoRT::Kinds];
    bool m_autoSet[MaxTracks][AutoRT::Kinds];
    float m_gainL[MaxTracks], m_gainR[MaxTracks];      // poprzedni blok: głośność płynie, bez trzasków
    bool m_gainKnown[MaxTracks] = {};
    int m_tap = -1;
    float m_autoMaster = -1;
    std::vector<float> m_autoLast;                     // ostatnio wysłana wartość parametru wtyczki
    // Stan efektów ścieżek (po indeksie ścieżki) i wspólny pogłos
    BiquadState m_eq[MaxTracks][4][2];
    CompState m_comp[MaxTracks];
    DeEsser m_deess[MaxTracks];
    std::vector<PitchCorrector> m_tune;   // osobny stan autotune dla każdej ścieżki
    std::vector<Doubler> m_dbl;           // i sztucznego dubla
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
    // Region pętli odtwarzania (ćwiczenie fragmentu); przy nagrywaniu — podejścia jedno po drugim
    void setCycle(bool on, long long start, long long end);
    void setLatencyOffset(long long frames) { m_extraLatency.store(frames); }
    void setPluginLatency(long long frames) { m_pluginLatency.store(frames); }   // nagranie wyrównane do tego, co słychać
    void readMeters(std::vector<float> &tracks, float master[2]);   // szczyty od ostatniego odczytu

    // Nagrywanie: od pozycji `start` (wcześniej odliczanie), kanał wejścia 0 = oba zmieszane, 1 = lewy, 2 = prawy
    bool startRecording(const QString &path, long long start, int channel);
    // Kończy nagrywanie; zwraca nagrany dźwięk (pusty, gdy nic nie nagrano) i jego miejsce na osi czasu
    std::shared_ptr<AudioSource> stopRecording(long long *start);
    bool recording() const { return m_recThread.joinable(); }
    long long recordStart() const { return m_recStart; }
    std::vector<float> livePeaks() const;  // szczyty nagrywanego dźwięku (do rysowania w trakcie)
    long long recordedFrames() const;       // ile już nagrano (z dokładnością do PeakStep)

    // Odsłuch pojedynczego dźwięku (klik w piano rollu, klawiatura) — gra też przy zatrzymanym transporcie.
    // Dźwięk trzymany jest po stronie interfejsu jeszcze kilka sekund, więc wątek audio nigdy go nie zwalnia.
    void preview(SourcePtr sound, float gain);

    // Granie na żywo (klawiatura komputera, MIDI): nuta brzmi, dopóki nie przyjdzie liveNoteOff z tym samym id
    void liveNoteOn(int id, int track, SynthVoice::Inst inst, double freq, float gain);
    void channelNote(int channel, bool on, int pitch, float velocity);   // nuta na kanał (numer w migawce)
    void liveNoteOff(int id);

    // Odsłuch: głos z mikrofonu słychać na ścieżce `track` z jej efektami (autotune, pogłos…); -1 — wyłączony.
    // channel jak przy nagrywaniu: 0 = oba zmieszane, 1 = lewy, 2 = prawy
    void setMonitor(int track, int channel);

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
    // Insert po efektach do pliku WAV (zmiennoprzecinkowego), bez sumy i ogranicznika; skip — opóźnienie jego wtyczek
    static bool renderInsert(const Snapshot &s, int insert, long long frames, int skip, const QString &path);
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
    std::atomic<long long> m_pluginLatency{0};
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

    // Odsłuch: wątek wejścia pisze mono, wątek wyjścia czyta (opóźnienie trzymane przy kilku ms)
    SpscRing m_monRing{size_t(Rate)};
    std::atomic<int> m_monTrack{-1}, m_monChannel{0};
    std::vector<float> m_monBuf = std::vector<float>(16384);   // tylko wątek wyjścia

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
        int track = 0;
        int inst = 0;
        float freq = 0, gain = 0;
        bool on = false;
    };
    static constexpr unsigned LiveQueue = 256;
    LiveCmd m_liveCmds[LiveQueue];
    std::atomic<unsigned> m_liveW{0}, m_liveR{0};
    LivePool m_live;                              // tylko wątek audio
    static constexpr unsigned NoteQueue = 256;
    Renderer::LiveNote m_noteQueue[NoteQueue], m_noteBlock[NoteQueue];
    std::atomic<unsigned> m_noteW{0}, m_noteR{0};
    void pushLive(const LiveCmd &c);
    void takeLiveCommands();                      // wątek audio
    int m_previewNext = 0;
    QList<QPair<qint64, SourcePtr>> m_previewKeep;
};
