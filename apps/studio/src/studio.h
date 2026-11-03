#pragma once

#include "audiosource.h"
#include "engine.h"

#include <QDateTime>
#include <QHash>
#include <QJsonObject>
#include <QObject>
#include <QQmlEngine>
#include <QTimer>
#include <QVariantList>
#include <atomic>

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
    Q_PROPERTY(double masterVolume READ masterVolume WRITE setMasterVolume NOTIFY settingsChanged)
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
    Q_INVOKABLE bool newProject(const QString &name, double bpm, int beatsPerBar);
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

    // Klipy (id)
    Q_INVOKABLE void moveClip(int id, int track, double start);
    Q_INVOKABLE void trimClipStart(int id, double start);
    Q_INVOKABLE void trimClipEnd(int id, double end);
    Q_INVOKABLE bool splitClip(int id, double at);
    Q_INVOKABLE void setClipLoop(int id, bool on);
    Q_INVOKABLE void duplicateClip(int id);
    Q_INVOKABLE void removeClip(int id);
    Q_INVOKABLE QVariantMap clip(int id) const;
    Q_INVOKABLE void importFiles(const QVariantList &urls, int track, double start);

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
    void exportFinished(bool ok, const QString &path, const QString &error);
    void message(const QString &text);

private:
    struct Clip
    {
        int id = 0;
        QString file, name;
        long long start = 0, length = 0, srcStart = 0, srcLen = 0, offset = 0;
        bool loop = false;
    };
    struct Track
    {
        int id = 0;
        QString name;
        int color = 0;
        double volume = 0, pan = 0;     // dB, -1…1
        bool mute = false, solo = false, armed = false;
        int input = 0;
        QList<Clip> clips;
    };

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

    static inline Studio *s_instance = nullptr;
    Engine m_engine;
    QTimer m_timer;
    QString m_name, m_folder, m_audioError;
    bool m_dirty = false;
    double m_bpm = 120;
    int m_beatsPerBar = 4;
    bool m_metronome = true, m_countIn = true;
    double m_masterDb = 0;
    double m_latencyMs = 0;
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
