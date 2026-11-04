#pragma once

#include "audiosource.h"
#include "engine.h"
#include "midiinput.h"

#include <QDateTime>
#include <QHash>
#include <QJsonObject>
#include <QObject>
#include <QQmlEngine>
#include <QTimer>
#include <QVariantList>
#include <atomic>
#include <functional>

// Studio: projekt piosenki (tempo, metrum, ścieżki z klipami), edycja z cofaniem, zapis i odczyt,
// a pod spodem silnik dźwięku (Engine). Projekt to folder: projekt.json + audio/ (nagrania i zaimportowane pliki)
// + Eksport/ (gotowe miksy). Czasy dla QML są w sekundach, w środku — w ramkach 48 kHz.
class Studio : public QObject
{
    Q_OBJECT
    QML_ELEMENT
    QML_SINGLETON
    Q_PROPERTY(bool open READ isOpen NOTIFY projectChanged)
    Q_PROPERTY(QString name READ name NOTIFY projectChanged)
    Q_PROPERTY(QString folder READ folder NOTIFY projectChanged)
    Q_PROPERTY(bool dirty READ dirty NOTIFY dirtyChanged)
    Q_PROPERTY(double bpm READ bpm WRITE setBpm NOTIFY settingsChanged)
    Q_PROPERTY(int beatsPerBar READ beatsPerBar WRITE setBeatsPerBar NOTIFY settingsChanged)
    Q_PROPERTY(bool metronome READ metronome WRITE setMetronome NOTIFY settingsChanged)
    Q_PROPERTY(bool countIn READ countIn WRITE setCountIn NOTIFY settingsChanged)
    // Odsłuch głosu w słuchawkach z efektami uzbrojonej ścieżki (autotune na żywo); zapamiętany w ustawieniach
    Q_PROPERTY(bool monitor READ monitor WRITE setMonitor NOTIFY devicesChanged)
    Q_PROPERTY(double masterVolume READ masterVolume WRITE setMasterVolume NOTIFY settingsChanged)
    Q_PROPERTY(double reverbSize READ reverbSize WRITE setReverbSize NOTIFY settingsChanged)     // 0 mały pokój … 1 hala
    Q_PROPERTY(double clickVolume READ clickVolume WRITE setClickVolume NOTIFY settingsChanged)
    Q_PROPERTY(bool cycle READ cycle WRITE setCycleOn NOTIFY cycleChanged)                       // region pętli odtwarzania
    Q_PROPERTY(double cycleStart READ cycleStart NOTIFY cycleChanged)
    Q_PROPERTY(double cycleEnd READ cycleEnd NOTIFY cycleChanged)
    // Wymiana fragmentu (punch-in): nagranie tylko w regionie pętli, z rozbiegiem przed nim; reszta zostaje
    Q_PROPERTY(bool punch READ punch WRITE setPunch NOTIFY cycleChanged)
    // Tekst piosenki: wersy z czasem (od taktu, co ile taktów albo ustawione w trakcie grania) i rymami
    Q_PROPERTY(QString lyrics READ lyrics WRITE setLyrics NOTIFY lyricsChanged)
    Q_PROPERTY(QVariantList lyricLines READ lyricLines NOTIFY lyricsChanged)
    Q_PROPERTY(int lyricsStart READ lyricsStart WRITE setLyricsStart NOTIFY lyricsChanged)   // takt pierwszego wersu (od 1)
    Q_PROPERTY(int lyricsBars READ lyricsBars WRITE setLyricsBars NOTIFY lyricsChanged)     // taktów na wers
    Q_PROPERTY(QVariantList presets READ presets CONSTANT)
    Q_PROPERTY(QVariantMap mastering READ mastering NOTIFY settingsChanged)
    Q_PROPERTY(QVariantList masteringPresets READ masteringPresets CONSTANT)
    Q_PROPERTY(QString echoTime READ echoTime WRITE setEchoTime NOTIFY settingsChanged)   // 1/4 | 1/8 | 3/16
    Q_PROPERTY(QVariantList kits READ kits CONSTANT)
    // Tonacja piosenki (dla autotune): tonika 0 = C … 11 = H, molowa albo durowa
    Q_PROPERTY(int keyRoot READ keyRoot WRITE setKeyRoot NOTIFY settingsChanged)
    Q_PROPERTY(bool keyMinor READ keyMinor WRITE setKeyMinor NOTIFY settingsChanged)
    Q_PROPERTY(QString keyName READ keyName NOTIFY settingsChanged)
    Q_PROPERTY(QVariantList genres READ genres CONSTANT)
    Q_PROPERTY(QVariantList instruments READ instruments CONSTANT)
    Q_PROPERTY(QStringList midiDevices READ midiDevices NOTIFY midiDevicesChanged)     // podłączone klawiatury MIDI
    Q_PROPERTY(QString artist READ artist WRITE setArtist NOTIFY artistChanged)       // podpis na okładce i w tagach
    Q_PROPERTY(bool sharing READ sharing NOTIFY sharingChanged)
    Q_PROPERTY(QVariantList rhythms READ rhythms CONSTANT)
    Q_PROPERTY(QVariantList progressions READ progressions CONSTANT)
    Q_PROPERTY(QVariantList tracks READ tracks NOTIFY tracksChanged)
    // Głośność, panorama, wycisz, solo ścieżek — osobno, żeby ruch suwaka nie przebudowywał listy ścieżek
    Q_PROPERTY(QVariantList mix READ mix NOTIFY mixChanged)
    Q_PROPERTY(int selectedTrack READ selectedTrack WRITE setSelectedTrack NOTIFY selectionChanged)
    Q_PROPERTY(int selectedClip READ selectedClip WRITE setSelectedClip NOTIFY selectionChanged)
    Q_PROPERTY(double duration READ duration NOTIFY tracksChanged)        // koniec ostatniego klipu
    Q_PROPERTY(bool playing READ playing NOTIFY transportChanged)
    Q_PROPERTY(bool recording READ recording NOTIFY transportChanged)
    Q_PROPERTY(bool countingIn READ countingIn NOTIFY positionChanged)
    Q_PROPERTY(double position READ position NOTIFY positionChanged)
    Q_PROPERTY(double recordStart READ recordStart NOTIFY transportChanged)
    // Nagrywanie w pętli: które podejście trwa (od 1) i gdzie w nagraniu się zaczyna (s) — do rysowania
    Q_PROPERTY(int recordTake READ recordTake NOTIFY positionChanged)
    Q_PROPERTY(double recordTakeOffset READ recordTakeOffset NOTIFY positionChanged)
    Q_PROPERTY(QVariantList levels READ levels NOTIFY levelsChanged)        // szczyt ścieżek 0…1
    Q_PROPERTY(QVariantList masterLevel READ masterLevel NOTIFY levelsChanged)
    Q_PROPERTY(double inputLevel READ inputLevel NOTIFY levelsChanged)
    Q_PROPERTY(bool audioOk READ audioOk CONSTANT)
    Q_PROPERTY(QString audioError READ audioError NOTIFY audioErrorChanged)
    Q_PROPERTY(QVariantList outputs READ outputs NOTIFY devicesChanged)
    Q_PROPERTY(QVariantList inputs READ inputs NOTIFY devicesChanged)
    Q_PROPERTY(QString output READ output WRITE setOutput NOTIFY devicesChanged)
    Q_PROPERTY(QString input READ input WRITE setInput NOTIFY devicesChanged)
    Q_PROPERTY(double latency READ latency WRITE setLatency NOTIFY devicesChanged)   // ręczna korekta nagrań (ms)
    Q_PROPERTY(bool canUndo READ canUndo NOTIFY historyChanged)
    Q_PROPERTY(bool canRedo READ canRedo NOTIFY historyChanged)
    Q_PROPERTY(bool busy READ busy NOTIFY busyChanged)                      // wczytywanie plików
    Q_PROPERTY(bool exporting READ exporting NOTIFY exportChanged)
    Q_PROPERTY(double exportProgress READ exportProgress NOTIFY exportChanged)
    Q_PROPERTY(QVariantList recent READ recent NOTIFY recentChanged)
    Q_PROPERTY(QString projectsFolder READ projectsFolder CONSTANT)
    Q_PROPERTY(int sourcesVersion READ sourcesVersion NOTIFY sourcesChanged)

public:
    explicit Studio(QObject *parent = nullptr);
    ~Studio() override;
    static Studio *instance() { return s_instance; }
    SourcePtr source(const QString &file) const { return m_sources.value(file); }
    std::vector<float> livePeaks() const { return m_engine.livePeaks(); }

    bool isOpen() const { return !m_folder.isEmpty(); }
    QString name() const { return m_name; }
    QString folder() const { return m_folder; }
    bool dirty() const { return m_dirty; }
    double bpm() const { return m_bpm; }
    void setBpm(double v);
    int beatsPerBar() const { return m_beatsPerBar; }
    void setBeatsPerBar(int v);
    bool metronome() const { return m_metronome; }
    void setMetronome(bool v);
    bool countIn() const { return m_countIn; }
    void setCountIn(bool v);
    double masterVolume() const { return m_masterDb; }
    double reverbSize() const { return m_reverbSize; }
    void setReverbSize(double v);
    double clickVolume() const { return m_clickVolume; }
    void setClickVolume(double v);
    bool cycle() const { return m_cycle; }
    void setCycleOn(bool on);
    double cycleStart() const { return m_cycleStart; }
    double cycleEnd() const { return m_cycleEnd; }
    bool punch() const { return m_punch; }
    QString lyrics() const { return m_lyrics; }
    void setLyrics(const QString &text);
    QVariantList lyricLines() const { return m_lyricView; }
    int lyricsStart() const { return m_lyricsStart; }
    void setLyricsStart(int bar);
    int lyricsBars() const { return m_lyricsBars; }
    void setLyricsBars(int bars);
    void setPunch(bool on);
    QVariantList presets() const;
    QVariantMap mastering() const;
    QVariantList masteringPresets() const;
    QString echoTime() const { return m_echoTime; }
    void setEchoTime(const QString &t);
    QVariantList kits() const;
    int keyRoot() const { return m_keyRoot; }
    void setKeyRoot(int r);
    bool keyMinor() const { return m_keyMinor; }
    void setKeyMinor(bool m);
    QString keyName() const;
    QVariantList genres() const;
    QVariantList instruments() const;
    QStringList midiDevices() const { return m_midi.devices(); }
    QString artist() const;
    void setArtist(const QString &a);
    bool sharing() const { return m_sharing; }
    QVariantList rhythms() const;
    QVariantList progressions() const;
    void setMasterVolume(double db);
    QVariantList tracks() const { return m_tracksView; }
    QVariantList mix() const { return m_mixView; }
    int selectedTrack() const { return m_selTrack; }
    void setSelectedTrack(int i);
    int selectedClip() const { return m_selClip; }
    void setSelectedClip(int id);
    double duration() const;
    bool playing() const { return m_engine.playing(); }
    bool recording() const { return m_engine.recording(); }
    bool countingIn() const { return recording() && m_position < recordStart(); }
    double position() const { return m_position; }
    double recordStart() const { return double(m_engine.recordStart()) / Engine::Rate; }
    int recordTake() const;
    double recordTakeOffset() const;
    QVariantList levels() const { return m_levels; }
    QVariantList masterLevel() const { return {m_master[0], m_master[1]}; }
    double inputLevel() const { return m_input; }
    bool audioOk() const { return m_engine.running(); }
    QString audioError() const { return m_audioError; }
    QVariantList outputs() const { return devices(false); }
    QVariantList inputs() const { return devices(true); }
    QString output() const { return m_engine.output(); }
    void setOutput(const QString &name);
    QString input() const { return m_engine.input(); }
    void setInput(const QString &name);
    double latency() const { return m_latencyMs; }
    bool monitor() const { return m_monitor; }
    void setMonitor(bool on);
    void setLatency(double ms);
    bool canUndo() const { return !m_undo.isEmpty(); }
    bool canRedo() const { return !m_redo.isEmpty(); }
    bool busy() const { return m_loading > 0; }
    bool exporting() const { return m_exporting; }
    double exportProgress() const { return m_exportProgress; }
    QVariantList recent() const;
    QString projectsFolder() const;
    int sourcesVersion() const { return m_sourcesVersion; }

    // Projekt
    // template: "" (pusty) albo gatunek z genres — gotowy bit, 808, ścieżka wokalu z efektami i mastering
    Q_INVOKABLE bool newProject(const QString &name, double bpm, int beatsPerBar, const QString &templ = {});
    Q_INVOKABLE bool openProject(const QString &pathOrUrl);
    Q_INVOKABLE bool save();
    Q_INVOKABLE void closeProject();
    Q_INVOKABLE void forgetRecent(const QString &folder);
    Q_INVOKABLE QString suggestName() const;

    // Ścieżki (index = kolejność na liście)
    Q_INVOKABLE void addTrack(const QString &name = {});
    Q_INVOKABLE void removeTrack(int index);
    Q_INVOKABLE void renameTrack(int index, const QString &name);
    Q_INVOKABLE void moveTrack(int from, int to);
    Q_INVOKABLE void setTrackVolume(int index, double db);
    Q_INVOKABLE void setTrackPan(int index, double pan);
    Q_INVOKABLE void setTrackMute(int index, bool on);
    Q_INVOKABLE void setTrackSolo(int index, bool on);
    Q_INVOKABLE void setTrackArmed(int index, bool on);
    Q_INVOKABLE void setTrackInput(int index, int channel);     // 0 = oba kanały, 1 = lewy, 2 = prawy
    // key: eqLow | eqMid | eqHigh (dB) | comp | reverb (0…1) | lowCut (0/1)
    Q_INVOKABLE void setTrackFx(int index, const QString &key, double value);
    Q_INVOKABLE void applyPreset(int index, const QString &preset);
    Q_INVOKABLE void remember() { checkpoint(); }
    // Beat Maker: kind = drums | bass; genre — wzór startowy
    Q_INVOKABLE int addPatternTrack(const QString &kind, const QString &genre);
    Q_INVOKABLE void setPattern(int index, const QVariantMap &pattern);
    Q_INVOKABLE QVariantMap genrePattern(const QString &kind, const QString &genre) const;
    Q_INVOKABLE QString noteName(int root, int degree) const;     // „Fis1”
    Q_INVOKABLE QString chordName(int degree, bool seventh) const; // w tonacji projektu: „a-moll”
    Q_INVOKABLE void chordsToNotes(int index);
    // Odsłuch: Melodia/Akordy — value = nuta MIDI, 808 — stopień skali, Bit — numer wiersza (stopa, werbel…)
    Q_INVOKABLE void previewNote(int index, int value, double velocity = 1.0);
    Q_INVOKABLE void simulateMidi(int pitch, int velocity);
    // Granie na żywo instrumentem ścieżki Melodia/Akordy — brzmi, dopóki nie przyjdzie liveNoteOff
    Q_INVOKABLE void liveNoteOn(int index, int pitch, double velocity = 1.0);
    Q_INVOKABLE void liveNoteOff(int pitch);     // do testów: jak nuta z klawiatury (0 = puszczenie)                    // ścieżka Akordy → Melodia (piano roll)
    Q_INVOKABLE bool inKey(int midi) const;                         // nuta należy do tonacji projektu
    Q_INVOKABLE void setMastering(const QString &key, double value);
    Q_INVOKABLE void applyMastering(const QString &preset);
    Q_INVOKABLE bool keyFrom808();                              // tonacja jak w pierwszej ścieżce 808               // zapamiętaj stan do cofnięcia (np. przed ruchem suwaka)

    // Klipy (id)
    Q_INVOKABLE void moveClip(int id, int track, double start);
    Q_INVOKABLE void trimClipStart(int id, double start);
    Q_INVOKABLE void trimClipEnd(int id, double end);
    Q_INVOKABLE bool splitClip(int id, double at);
    Q_INVOKABLE void setClipLoop(int id, bool on);
    Q_INVOKABLE void duplicateClip(int id);
    Q_INVOKABLE void removeClip(int id);
    Q_INVOKABLE QVariantMap clip(int id) const;
    Q_INVOKABLE void setClipGain(int id, double db);
    Q_INVOKABLE void setClipFades(int id, double fadeIn, double fadeOut);   // sekundy
    Q_INVOKABLE void renameClip(int id, const QString &name);
    Q_INVOKABLE void setCycle(double start, double end);
    Q_INVOKABLE void cycleClip(int id);                         // region pętli = klip
    Q_INVOKABLE void importFiles(const QVariantList &urls, int track, double start);
    Q_INVOKABLE void setClipTake(int id, int take);             // podejście z nagrywania w pętli (comping: podziel i wybierz)
    // Ścieżki rapera: role "main" (wokal), "double" (dubel), "adlib" (ad-libsy). Znajduje albo zakłada ścieżkę
    // z dopasowanym brzmieniem i ustawia ją do nagrania; zwraca jej numer (−1 — nie da się)
    Q_INVOKABLE int vocalTrack(const QString &role);
    // Dubel albo ad-lib do fragmentu klipu: ścieżka roli, region = klip, wymiana fragmentu i od razu nagrywanie
    Q_INVOKABLE void recordOver(int clipId, const QString &role);
    // Wers `line` (numer wiersza tekstu) zaczyna się w `seconds` (do 1/16 nuty); seconds < 0 — znów według taktów
    Q_INVOKABLE void markLyric(int line, double seconds);
    Q_INVOKABLE void clearLyricMarks();
    Q_INVOKABLE int lyricAt(double seconds) const;   // wiersz tekstu, który właśnie leci (−1 — przed pierwszym)
    // Gotowy bit (MP3, WAV…): rozpoznaje tempo i tonację, ustawia je w projekcie i kładzie bit na siatce taktów.
    // Bez otwartego projektu tworzy nowy „na swoim bicie” — ścieżki na wokal, dubel i ad-libsy.
    Q_INVOKABLE void importBeat(const QVariant &url);

    // Transport
    Q_INVOKABLE void play();
    Q_INVOKABLE void stop();
    Q_INVOKABLE void toggle();
    Q_INVOKABLE void seek(double seconds);
    Q_INVOKABLE void record();

    Q_INVOKABLE void undo();
    Q_INVOKABLE void redo();

    // Eksport do <projekt>/Eksport/<nazwa>.<format>; wynik w exportFinished
    Q_INVOKABLE void exportMix(const QString &format);
    Q_INVOKABLE void cancelExport() { m_cancelExport.store(true); }

    // Udostępnianie: piosenka (MP3 z okładką i tagami) albo projekt do remiksu (paczka ZIP) w <projekt>/Udostępnione;
    // wynik w shareReady. Potem: na telefon (KDE Connect), e-mailem, do schowka, w folderze
    Q_INVOKABLE QString coverPreview(const QString &title, const QString &artist);   // adres pliku z okładką
    Q_INVOKABLE void shareSong(const QString &title, const QString &artist);
    Q_INVOKABLE void shareProject();
    Q_INVOKABLE QVariantList phones() const;
    Q_INVOKABLE bool sendToPhone(const QString &id, const QString &path);
    Q_INVOKABLE void sendEmail(const QString &path, const QString &subject);
    Q_INVOKABLE void copyFile(const QString &path);

    // Pomocnicze dla interfejsu
    Q_INVOKABLE double snap(double seconds, int division) const;   // do siatki: division części miary (1 = miara, 0 = takt)
    Q_INVOKABLE QString barBeat(double seconds) const;              // „12.3”
    Q_INVOKABLE QString clock(double seconds) const;                // „1:05,2”
    Q_INVOKABLE void showInFolder(const QString &path) const;
    Q_INVOKABLE QString tracksLabel(int n) const;                   // „3 ścieżki”
    Q_INVOKABLE QString when(const QDateTime &t) const;             // „Dziś, 14:02”

signals:
    void projectChanged();
    void dirtyChanged();
    void settingsChanged();
    void tracksChanged();
    void mixChanged();
    void selectionChanged();
    void transportChanged();
    void positionChanged();
    void levelsChanged();
    void audioErrorChanged();
    void devicesChanged();
    void historyChanged();
    void busyChanged();
    void exportChanged();
    void recentChanged();
    void sourcesChanged();
    void cycleChanged();
    void midiDevicesChanged();
    void artistChanged();
    void sharingChanged();
    void lyricsChanged();
    void shareReady(const QString &path, const QString &kind);
    void shareFailed(const QString &error);
    void midiNote(int pitch, int velocity, bool on);            // nuta z klawiatury MIDI (siła 1…127)
    void exportFinished(bool ok, const QString &path, const QString &error);
    void message(const QString &text);

private:
    struct Clip
    {
        int id = 0;
        QString file, name;
        long long start = 0, length = 0, srcStart = 0, srcLen = 0, offset = 0;
        long long fadeIn = 0, fadeOut = 0;
        double gain = 0;                // dB
        bool loop = false;
        // Podejścia z nagrywania w pętli: wszystkie w jednym pliku. takes[k] — o ile początek fragmentu
        // podejścia k jest dalej w pliku niż podejścia 0 (stałe przy przesuwaniu, przycinaniu i dzieleniu klipu)
        QList<long long> takes;
        int take = 0;
    };
    struct Track
    {
        int id = 0;
        QString name;
        int color = 0;
        double volume = 0, pan = 0;     // dB, -1…1
        bool mute = false, solo = false, armed = false;
        int input = 0;
        // Efekty: korektor (dB), kompresja i pogłos (0…1), usuwanie dudnienia (filtr 80 Hz)
        double eqLow = 0, eqMid = 0, eqHigh = 0, comp = 0, reverb = 0, echo = 0, drive = 0, tune = 0;
        double dbl = 0;                 // sztuczny dubel: dwie lekko przesunięte i rozstrojone kopie po bokach
        bool lowCut = false;
        QString preset;
        // Rodzaj: audio (nagrania, pliki) albo wzór z Beat Makera — drums (perkusja) / bass (808)
        QString kind = QStringLiteral("audio");
        bool beat = false;              // bit z pliku (rodzaj audio) — inny podpis i ikona w nagłówku
        QString role;                   // "main" | "double" | "adlib" — ścieżki wokalu rapera (zob. vocalTrack)
        QJsonObject pattern;
        QList<Clip> clips;
    };
    struct Mastering
    {
        double eqLow = 0, eqHigh = 0, comp = 0, width = 1, drive = 0;   // dB, dB, 0…1, ×, dB
        QString preset;
    };
    void renderPattern(int index);
    void renderKeyTracks();                         // po zmianie tonacji — akordy idą za nią                  // wzór → plik audio/_bit-N.wav → klipy ścieżki
    void applyPresetTo(Track &t, const QString &preset);
    void applyMasteringPreset(const QString &preset);
    static void cutStart(Clip &c, long long d);     // przytnij początek o d ramek (pętla: przesuwa fazę)
    void carve(int track, long long a, long long b, int keepId);   // wytnij [a, b) z klipów ścieżki
    static QList<Clip> carved(const QList<Clip> &clips, long long a, long long b, int keepId, int *nextId);

    QJsonObject toJson() const;
    void fromJson(const QJsonObject &o);
    void checkpoint();                         // stan przed zmianą → cofanie
    void changed(bool structure = true);       // po zmianie: widok QML, migawka dla silnika, „niezapisany”
    void rebuildView();
    void rebuildMix();
    Snapshot *buildSnapshot() const;
    void tick();
    Clip *findClip(int id, int *track = nullptr);
    long long frames(double seconds) const { return llround(seconds * Engine::Rate); }
    long long maxSrcLen(const Clip &c) const;
    void loadSources(const QStringList &files);
    QString uniqueAudioPath(const QString &base, const QString &ext) const;
    QVariantList devices(bool input) const;
    void addRecent(const QString &folder);
    void updateCapture();
    void setDirty(bool d);
    void finishRecording();
    using ExportDone = std::function<void(bool ok, const QString &path, const QString &error)>;
    void startExport(const QString &format, const QString &path, ExportDone done);
    std::vector<float> roughWave(int bins) const;   // przybliżony kształt piosenki z klipów (do okładki)
    QString shareFolder() const;

    static inline Studio *s_instance = nullptr;
    bool m_sharing = false;
    int m_coverVersion = 0;
    Engine m_engine;
    MidiInput m_midi;
    QTimer m_timer;
    QString m_name, m_folder, m_audioError;
    bool m_dirty = false;
    double m_bpm = 120;
    int m_beatsPerBar = 4;
    bool m_metronome = true, m_countIn = true;
    double m_masterDb = 0;
    double m_reverbSize = 0.5, m_clickVolume = 0.7;
    Mastering m_mastering;
    QString m_echoTime = QStringLiteral("3/16");
    int m_keyRoot = 9;               // a-moll — dobra domyślna dla głosu
    bool m_keyMinor = true;
    bool m_cycle = false;
    double m_cycleStart = 0, m_cycleEnd = 0;
    double m_latencyMs = 0;
    bool m_monitor = false;
    long long m_recLoopStart = 0, m_recLoopEnd = 0;   // region pętli przy nagrywaniu (ramki); równe — bez pętli
    bool m_punch = false;
    QString m_lyrics;
    QList<double> m_lyricMarks;        // początek wersu w miarach od początku piosenki (dla każdego wiersza; −1 — z taktów)
    int m_lyricsStart = 1, m_lyricsBars = 1;
    QVariantList m_lyricView;
    void rebuildLyrics();
    void resetLyrics();
    long long m_punchIn = 0, m_punchOut = 0;          // wymiana fragmentu w trakcie nagrywania (ramki); równe — wyłączona
    void updateMonitor();                      // która ścieżka dostaje głos z mikrofonu (uzbrojona albo nagrywana)
    QList<Track> m_tracks;
    QVariantList m_tracksView, m_mixView;
    int m_nextId = 1;
    int m_selTrack = 0, m_selClip = 0;
    QHash<QString, SourcePtr> m_sources;
    int m_sourcesVersion = 0;
    int m_loading = 0;
    QList<QJsonObject> m_undo, m_redo;
    double m_position = 0;
    QVariantList m_levels;
    double m_master[2] = {0, 0};
    double m_input = 0;
    int m_recTrack = -1;
    QString m_recPath;
    bool m_exporting = false;
    double m_exportProgress = 0;
    std::atomic<bool> m_cancelExport{false};
    std::atomic<double> m_exportShared{0};
};
