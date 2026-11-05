#pragma once

#include "audiosource.h"
#include "engine.h"
#include <QPointF>
#include "plugin.h"
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
    Q_PROPERTY(QVariantList plugins READ plugins NOTIFY pluginsChanged)    // znalezione wtyczki VST3
    // Rack i mikser DAW-a
    Q_PROPERTY(QVariantList channels READ channels NOTIFY rackChanged)
    Q_PROPERTY(QVariantList patterns READ patterns NOTIFY rackChanged)
    Q_PROPERTY(QVariantList inserts READ inserts NOTIFY rackChanged)
    Q_PROPERTY(int currentPattern READ currentPattern WRITE setCurrentPattern NOTIFY rackChanged)
    Q_PROPERTY(bool patternMode READ patternMode WRITE setPatternMode NOTIFY rackChanged)   // WZÓR: gra w kółko bieżący wzór
    Q_PROPERTY(double swing READ swing WRITE setSwing NOTIFY rackChanged)
    Q_PROPERTY(int selectedChannel READ selectedChannel WRITE setSelectedChannel NOTIFY selectionChanged)
    Q_PROPERTY(int selectedInsert READ selectedInsert WRITE setSelectedInsert NOTIFY selectionChanged)
    Q_PROPERTY(QVariantList insertLevels READ insertLevels NOTIFY levelsChanged)
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
    QVariantList plugins() const;
    QVariantList channels() const;
    QVariantList patterns() const;
    QVariantList inserts() const;
    int currentPattern() const { return m_curPattern; }
    void setCurrentPattern(int id);
    bool patternMode() const { return m_patMode; }
    void setPatternMode(bool on);
    double swing() const { return m_swing; }
    int selectedChannel() const { return m_selChannel; }
    void setSelectedChannel(int id);
    int selectedInsert() const { return m_selInsert; }
    void setSelectedInsert(int id);
    QVariantList insertLevels() const { return m_insLevels; }
    void setSwing(double v);
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
    Q_INVOKABLE QString noteName(int root, int degree) const;     // „Fis1”
    Q_INVOKABLE QString chordName(int degree, bool seventh) const; // w tonacji projektu: „a-moll”
    // Odsłuch: Melodia/Akordy — value = nuta MIDI, 808 — stopień skali, Bit — numer wiersza (stopa, werbel…)
    Q_INVOKABLE void simulateMidi(int pitch, int velocity);
    // Granie na żywo instrumentem ścieżki Melodia/Akordy — brzmi, dopóki nie przyjdzie liveNoteOff
    Q_INVOKABLE bool inKey(int midi) const;                         // nuta należy do tonacji projektu
    Q_INVOKABLE void setMastering(const QString &key, double value);
    Q_INVOKABLE void applyMastering(const QString &preset);

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
    // Wtyczki VST3 na ścieżce (po efektach Studia). slot — numer z mix[ścieżka].plugins[…].id
    Q_INVOKABLE void scanPlugins();
    Q_INVOKABLE void addPlugin(int insert, const QString &uid);
    Q_INVOKABLE void removePlugin(int insert, int slot);
    Q_INVOKABLE void setPluginBypass(int insert, int slot, bool on);
    Q_INVOKABLE void openPlugin(int insert, int slot);
    Q_INVOKABLE void restartPlugin(int insert, int slot);      // po awarii albo gdy jej brakowało
    Q_INVOKABLE void restartChannel(int id);
    // Rack. kind: drum (arg „kit:row”), sampler (plik audio/ projektu), synth (id instrumentu), bass (kit), vst (uid)
    Q_INVOKABLE int addChannel(const QString &kind, const QString &arg, const QString &name = {});
    Q_INVOKABLE void removeChannel(int id);
    Q_INVOKABLE void setChannelInsert(int id, int insert);
    Q_INVOKABLE void setChannelVolume(int id, double db);
    Q_INVOKABLE void setChannelPan(int id, double pan);
    Q_INVOKABLE void setChannelMute(int id, bool on);
    Q_INVOKABLE void openChannelPlugin(int id);
    Q_INVOKABLE int addPattern(const QString &name = {}, int bars = 1);
    Q_INVOKABLE void removePattern(int id);
    Q_INVOKABLE void setPatternBars(int id, int bars);
    Q_INVOKABLE void setStep(int pattern, int channel, int step, double velocity);
    Q_INVOKABLE void setPatternNotes(int pattern, int channel, const QVariantList &notes);   // [{ step, len, pitch, vel }]
    Q_INVOKABLE QVariantMap patternData(int pattern, int channel) const;
    Q_INVOKABLE int addPatternClip(int track, int pattern, double start, double length);
    // Mikser
    Q_INVOKABLE int addInsert(const QString &name = {});
    Q_INVOKABLE void removeInsert(int id);
    Q_INVOKABLE bool setInsertSend(int id, int to, double db);       // poniżej −60 dB — bez wysyłki; pętle odrzucone
    Q_INVOKABLE void setInsertToMaster(int id, bool on);
    Q_INVOKABLE bool setInsertDuck(int id, int from, double amount);   // sidechain: from = 0 wyłącza
    Q_INVOKABLE bool setPluginSide(int insert, int slot, int from);    // wejście boczne wtyczki
    Q_INVOKABLE void freezeInsert(int id, bool on);                    // efekty i instrumenty do pliku — procesor odpoczywa
    Q_INVOKABLE void setInsertVolume(int id, double db);
    Q_INVOKABLE void setInsertPan(int id, double pan);
    Q_INVOKABLE void setInsertMute(int id, bool on);
    Q_INVOKABLE void setInsertSolo(int id, bool on);
    Q_INVOKABLE void setInsertFx(int id, const QString &key, double value);
    Q_INVOKABLE void applyInsertPreset(int id, const QString &preset);
    Q_INVOKABLE void renameInsert(int id, const QString &name);
    Q_INVOKABLE void renameChannel(int id, const QString &name);
    Q_INVOKABLE void renamePattern(int id, const QString &name);
    Q_INVOKABLE int duplicatePattern(int id);
    // Sampler: klucze attack decay sustain release from to tune cutoff resonance root choke, 0/1: reverse loop oneShot
    Q_INVOKABLE void setChannelParam(int id, const QString &key, double value);
    Q_INVOKABLE QVariantMap channelParams(int id) const;
    Q_INVOKABLE void chopChannel(int id, const QString &mode, int count);   // equal — po równo, onsets — na uderzenia, none — całość
    Q_INVOKABLE void slicesToPattern(int id);                   // plasterki w bieżącym wzorze, w oryginalnych miejscach
    Q_INVOKABLE void stretchChannel(int id, int bars);          // do tempa projektu, bez zmiany wysokości (0 — najbliższa potęga dwójki)
    Q_INVOKABLE void channelNoteOn(int id, int pitch, double velocity = 0.85);    // gra teraz (klawiatura, MIDI, podgląd)
    Q_INVOKABLE void channelNoteOff(int id, int pitch);
    // Automatyka. Cel: vol:<insert> pan:<insert> reverb|echo|drive|double|deess:<insert> chvol:<kanał>
    // master plug:<slot>:<parametr> chplug:<kanał>:<parametr>
    Q_INVOKABLE QVariantList autoTargets(int insert) const;       // [{ target, label }] insertu
    Q_INVOKABLE QVariantList channelAutoTargets(int channel) const;
    Q_INVOKABLE int addAutomation(const QString &target, const QString &label);   // klip na pasie Automatyka: cały utwór
    Q_INVOKABLE void setAutoPoints(int clip, const QVariantList &points);         // [{ t (s od początku klipu), v }]
    Q_INVOKABLE QVariantList patternPreview(int id) const;       // nuty wzoru dla klipu: [{ x, w, y }] w 0…1
    // Biblioteka i ustawienia. kind: "channel" albo "insert"
    Q_INVOKABLE QVariantList library() const;
    Q_INVOKABLE QString libraryFolder() const;
    Q_INVOKABLE int addSample(const QString &pathOrUrl);         // kopia do projektu i kanał samplera
    Q_INVOKABLE void previewFile(const QString &path);
    Q_INVOKABLE QVariantList presetList(const QString &kind) const;
    Q_INVOKABLE bool savePreset(const QString &kind, int id, const QString &name);
    Q_INVOKABLE void loadPreset(const QString &kind, int id, const QString &path);
    Q_INVOKABLE QStringList projectSounds() const;               // pliki z audio/ do samplera
    // Odszumianie wszystkich nagrań ścieżki (w tle); level 0 — z powrotem oryginały
    Q_INVOKABLE void denoiseTrack(int index, int level);
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
    void pluginsChanged();
    void presetsChanged();
    void rackChanged();
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
        QString autoTarget;             // klip automatyki: co steruje (zob. compileAutos), bez pliku
        QList<QPointF> autoPts;         // punkty: ramki od początku klipu, wartość 0…1
        int pattern = 0;                // klip wzoru (id): zapętlony, bez pliku; srcLen — długość wzoru
        QString origFile;               // odszumiony klip: plik przed odszumianiem (powrót i ponowne odszumianie)
    };
    struct Slot
    {
        int id = 0;
        Plug::Info info;
        bool bypass = false;
        QByteArray state;               // ostatni znany stan (także gdy wtyczki brakuje na tym komputerze)
        std::shared_ptr<Plug::Plugin> plugin;
        int side = 0;                   // insert na wejściu bocznym (0 — brak)
    };
    struct Send
    {
        int to = 0;                     // id insertu
        double db = 0;
    };
    // Insert miksera: tu mieszka głośność, panorama, efekty i wtyczki
    struct Insert
    {
        int id = 0;
        QString name;
        int color = 0;
        double volume = 0, pan = 0;     // dB, -1…1
        bool mute = false, solo = false;
        // Efekty: korektor (dB), kompresja i pogłos (0…1), usuwanie dudnienia (filtr 80 Hz)
        double eqLow = 0, eqMid = 0, eqHigh = 0, comp = 0, reverb = 0, echo = 0, drive = 0, tune = 0;
        double dbl = 0;                 // sztuczny dubel: dwie lekko przesunięte i rozstrojone kopie po bokach
        double deess = 0;               // de-esser: ściszanie syczenia („s”, „sz”, „c”)
        int denoise = 0;                // odszumianie nagrań: 0 wył., 1 lekko, 2 średnio, 3 mocno (też nowych nagrań)
        bool lowCut = false;
        QString preset;
        bool toMaster = true;
        int duckFrom = 0;               // sidechain Studia: insert, który ścisza ten (0 — brak)
        double duck = 0.6;
        QString frozen;                 // zamrożony: gra ten plik (po efektach) zamiast źródeł i wtyczek
        QList<Send> sends;
        QList<Slot> slots_;             // wtyczki VST3
    };
    // Pas playlisty: klipy i insert, do którego gra audio
    struct Track
    {
        int id = 0;
        QString name;
        int color = 0;
        int insert = 0;                 // id insertu
        bool armed = false;
        int input = 0;
        // Rodzaj: audio (nagrania, pliki) albo wzór z Beat Makera — drums (perkusja) / bass (808)
        QString kind = QStringLiteral("audio");
        bool beat = false;              // bit z pliku (rodzaj audio) — inny podpis i ikona w nagłówku
        QString role;                   // "main" | "double" | "adlib" — ścieżki wokalu rapera (zob. vocalTrack)
        QJsonObject pattern;
        QList<Clip> clips;
    };
    // Kanał: co gra. kind: drum (kit, row), sampler (file, root, oneShot), synth (inst), bass (kit), vst (vst)
    struct Channel
    {
        int id = 0;
        QString name;
        int color = 0;
        int insert = 0;
        double volume = 0, pan = 0;
        bool mute = false;
        QString kind, kit, row, file, inst;
        int root = 60;
        bool oneShot = true;
        // Sampler (też kanały perkusji)
        double attack = 0.001, decay = 0.1, sustain = 1, release = 0.012;
        double from = 0, to = 1;        // zakres: ułamek pliku
        bool reverse = false, loop = false;
        double tune = 0, cutoff = 20000, resonance = 0.7;
        int choke = 0;                  // grupa ucinania (0 — brak)
        QList<double> slices;           // plasterki: ułamki pliku
        QString origFile;               // przed rozciągnięciem do tempa
        Slot vst;
        std::shared_ptr<Instrument> instrument;
    };
    struct PatNote
    {
        double step = 0, len = 1;       // szesnastki
        int pitch = 60;
        double vel = 0.8;
    };
    struct PatData
    {
        QList<double> steps;            // siła na krok (0 — pusty), wysokość to podstawa kanału
        QList<PatNote> notes;
    };
    // Wzór: kroki i nuty wielu kanałów
    struct Pattern
    {
        int id = 0;
        QString name;
        int bars = 1;
        QHash<int, PatData> data;       // id kanału → dane
    };
    struct Mastering
    {
        double eqLow = 0, eqHigh = 0, comp = 0, width = 1, drive = 0;   // dB, dB, 0…1, ×, dB
        QString preset;
    };
    void applyPresetTo(Insert &t, const QString &preset);
    void applyMasteringPreset(const QString &preset);
    static void cutStart(Clip &c, long long d);     // przytnij początek o d ramek (pętla: przesuwa fazę)
    void carve(int track, long long a, long long b, int keepId);   // wytnij [a, b) z klipów ścieżki
    static QList<Clip> carved(const QList<Clip> &clips, long long a, long long b, int keepId, int *nextId);

    QJsonObject toJson(bool pluginStates = true) const;     // false — do cofania: stan wtyczek zostaje w nich samych
    std::shared_ptr<Plug::Plugin> makePlugin(const Slot &s, bool applyState, bool offline = false);
    void fromJson(const QJsonObject &o);
    void checkpoint();                         // stan przed zmianą → cofanie
    void changed(bool structure = true);       // po zmianie: widok QML, migawka dla silnika, „niezapisany”
    void rebuildView();
    void rebuildMix();
    Snapshot *buildSnapshot(bool forExport = false);        // eksport: własne kopie wtyczek (na żywo grają dalej)
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
    QList<Plug::Info> m_pluginList;
    QHash<int, QByteArray> m_slotMemo;                     // stan usuniętych wtyczek — na wypadek cofnięcia
    bool m_scanning = false, m_rebuild = false;
    mutable QHash<int, QByteArray> m_lastState;            // ostatni zapisany stan wtyczek — po awarii wracają z nim
    // Odszumia pliki (obecny plik klipu → oryginał) i podmienia je w klipach ścieżki o numerze id
    void startDenoise(int trackId, const QHash<QString, QString> &files, int level, bool quiet);
    void resetLyrics();
    long long m_punchIn = 0, m_punchOut = 0;          // wymiana fragmentu w trakcie nagrywania (ramki); równe — wyłączona
    void updateMonitor();                      // która ścieżka dostaje głos z mikrofonu (uzbrojona albo nagrywana)
    QList<Track> m_tracks;
    QList<Insert> m_inserts;
    QList<Channel> m_channels;
    QList<Pattern> m_patterns;
    int m_curPattern = 0;
    int m_selChannel = 0, m_selInsert = 0;
    QVariantList m_insLevels;
    void convertPatternTrack(int index);        // ścieżka Beat Makera → kanały, wzór i klipy wzoru
    int rackChannel(const QString &kind, const QString &kit, const QString &row, const QString &inst, const QString &name, int insert, double volume);
    void defaultRack();                         // pusty projekt: zestaw perkusyjny i pierwszy wzór
    Insert *findInsert(int id);
    bool m_patMode = false;
    double m_swing = 0;
    int insertIndex(int id) const;
    Insert &ins(int track) { return m_inserts[insertIndex(m_tracks[track].insert)]; }
    Insert &ins(const Track &t) { return m_inserts[insertIndex(t.insert)]; }
    const Insert &ins(const Track &t) const { return m_inserts[insertIndex(t.insert)]; }
    int newInsert(const QString &name, int color);
    QJsonObject insertJson(const Insert &in, bool pluginStates) const;
    Insert insertFromJson(const QJsonObject &o, const QHash<int, Slot> &oldSlots);
    QJsonObject rackJson(bool pluginStates) const;
    void rackFromJson(const QJsonObject &o, const QHash<int, Channel> &oldChannels);
    std::shared_ptr<Instrument> makeInstrument(Channel &c);
    SourcePtr channelSource(const Channel &c) const;          // dźwięk kanału (po odwróceniu)
    void rebuildInstrument(Channel &c);
    void compileChannels(Snapshot *s, bool forExport);
    void compileAutos(Snapshot *s);
    QHash<int, Plug::Plugin *> m_snapPlugins;   // slot → instancja w budowanej migawce (eksport ma własne)
    QList<int> insertOrder() const;
    bool wouldLoop(int source, int target) const;      // dźwięk z target dochodzi już do source
    void compileLatency(Snapshot *s);
    int m_lastLatency = 0;
    long long patternFrames(const Pattern &p) const;
    Pattern *findPattern(int id);
    Channel *findChannel(int id);
    const Channel *findChannel(int id) const { return const_cast<Studio *>(this)->findChannel(id); }
    const Insert *findInsert(int id) const { return const_cast<Studio *>(this)->findInsert(id); }
    void applyPatternLoop();
    void clearRack();
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
