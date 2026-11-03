#pragma once

#include <QJsonObject>
#include <QObject>
#include <QQmlEngine>
#include <QTimer>
#include <QVariantList>

// Projekt montażu: trzy ścieżki — wideo (klipy jeden za drugim, bez przerw, z opcjonalnym
// przenikaniem), tekst i muzyka (elementy w dowolnym miejscu). Czas liczony w klatkach (30 kl./s).
// Projekty zapisują się same (JSON w ~/.local/share/Aster/aster-montaz/projects), a z modelu
// powstaje opis MLT XML — dla podglądu (mniejszy obraz) i eksportu (pełny rozmiar).
class Project : public QObject
{
    Q_OBJECT
    QML_ELEMENT
    QML_SINGLETON
    Q_PROPERTY(bool isOpen READ isOpen NOTIFY openChanged)
    Q_PROPERTY(QString name READ name WRITE setName NOTIFY changed)
    Q_PROPERTY(QString format READ format NOTIFY changed)
    Q_PROPERTY(int width READ width NOTIFY changed)
    Q_PROPERTY(int height READ height NOTIFY changed)
    Q_PROPERTY(int fps READ fps CONSTANT)
    Q_PROPERTY(QVariantList media READ media NOTIFY changed)
    Q_PROPERTY(QVariantList clips READ clips NOTIFY changed)
    Q_PROPERTY(QVariantList texts READ texts NOTIFY changed)
    Q_PROPERTY(QVariantList music READ music NOTIFY changed)
    Q_PROPERTY(QVariantList overlays READ overlays NOTIFY changed)
    Q_PROPERTY(int duration READ duration NOTIFY changed)
    Q_PROPERTY(int revision READ revision NOTIFY changed)
    Q_PROPERTY(bool canUndo READ canUndo NOTIFY changed)
    Q_PROPERTY(bool canRedo READ canRedo NOTIFY changed)
    Q_PROPERTY(QVariantList projects READ projects NOTIFY projectsChanged)
    Q_PROPERTY(QVariantList textStyles READ textStyles CONSTANT)
    Q_PROPERTY(QVariantList looks READ looks CONSTANT)
    Q_PROPERTY(QVariantList textAnimations READ textAnimations CONSTANT)
    Q_PROPERTY(QVariantList transitions READ transitions CONSTANT)
    Q_PROPERTY(QVariantList motions READ motions CONSTANT)
    Q_PROPERTY(bool fadeIn READ fadeIn NOTIFY changed)
    Q_PROPERTY(bool fadeOut READ fadeOut NOTIFY changed)
    Q_PROPERTY(bool duck READ duck NOTIFY changed)         // przyciszanie muzyki i filmu pod lektorem

public:
    ~Project() override;

    // Jedna instancja dla QML i podglądu/eksportu (C++)
    static Project *instance();
    static Project *create(QQmlEngine *, QJSEngine *);

    static constexpr int Fps = 30;

    bool isOpen() const { return !m_id.isEmpty(); }
    QString name() const { return m_name; }
    void setName(const QString &name);
    QString format() const { return m_format; }
    int width() const;
    int height() const;
    int fps() const { return Fps; }
    QVariantList media() const;
    QVariantList clips() const;
    QVariantList texts() const;
    QVariantList music() const;
    QVariantList overlays() const;
    int duration() const { return m_duration; }
    int revision() const { return m_revision; }
    bool canUndo() const { return !m_undo.isEmpty(); }
    bool canRedo() const { return !m_redo.isEmpty(); }
    QVariantList projects() const { return m_projects; }
    QVariantList textStyles() const;
    QVariantList looks() const;
    QVariantList textAnimations() const;
    QVariantList transitions() const;
    QVariantList motions() const;
    Q_INVOKABLE void applyTransitionToAll(const QString &fromId);    // to samo przejście między wszystkimi klipami
    Q_INVOKABLE QVariantMap textBox(const QString &id) const;        // prostokąt napisu w ułamkach kadru {x, y, w, h}
    bool fadeIn() const { return m_fadeIn; }
    bool fadeOut() const { return m_fadeOut; }
    bool duck() const { return m_duck; }

    // ——— Projekty ———
    Q_INVOKABLE void newProject(const QString &format);             // "9:16", "16:9", "1:1"
    Q_INVOKABLE bool openProject(const QString &id);
    Q_INVOKABLE void closeProject();
    Q_INVOKABLE void deleteProject(const QString &id);
    Q_INVOKABLE QString guessFormat(const QStringList &files) const; // z proporcji pierwszego filmu/zdjęcia

    // ——— Edycja ———
    Q_INVOKABLE int importFiles(const QStringList &pathsOrUrls, int atFrame = -1);   // zwraca liczbę dodanych
    Q_INVOKABLE QString addFromMedia(const QString &path, int frame);                 // z biblioteki na oś czasu
    Q_INVOKABLE QString addText(int frame, const QString &text = QString());
    // Druga ścieżka obrazu: film albo zdjęcie (naklejka PNG) nad głównym obrazem; zwraca id albo ""
    Q_INVOKABLE QString addVoice(const QString &path, int frame);   // nagranie lektora na ścieżkę dźwięku
    Q_INVOKABLE QString recordingsDir() const;                       // nagrania tego projektu
    Q_INVOKABLE QString addOverlay(const QString &pathOrUrl, int frame, const QString &name = QString());
    Q_INVOKABLE void trim(const QString &id, int deltaStart, int deltaEnd);          // przesunięcie krawędzi w klatkach osi
    Q_INVOKABLE void moveClip(const QString &id, int index);                         // ścieżka wideo: nowa kolejność
    Q_INVOKABLE void moveItem(const QString &id, int start);                         // tekst/muzyka: nowe miejsce
    Q_INVOKABLE QString split(const QString &id, int frame);                         // zwraca id drugiej części
    Q_INVOKABLE void remove(const QString &id);
    Q_INVOKABLE void setValue(const QString &id, const QString &key, const QVariant &value);
    Q_INVOKABLE QVariantMap item(const QString &id) const;
    Q_INVOKABLE QString kindOf(const QString &id) const;                             // "clip" / "text" / "music" / ""
    Q_INVOKABLE QString clipAt(int frame) const;
    Q_INVOKABLE QString itemAt(const QString &track, int frame) const;
    Q_INVOKABLE int clipIndex(const QString &id) const;
    Q_INVOKABLE void undo();
    Q_INVOKABLE void redo();

    // ——— Pomocnicze ———
    Q_INVOKABLE QString time(int frames, bool fine = true) const;    // 0:05,12 (sekundy i klatki)
    Q_INVOKABLE QString toPath(const QString &pathOrUrl) const;
    Q_INVOKABLE QString videosDir() const;
    Q_INVOKABLE QString when(qint64 msecs) const;
    Q_INVOKABLE void showInFolder(const QString &path) const;
    Q_INVOKABLE QString thumb(const QString &path, int frame, const QString &look = QString()) const { return thumbUrl(path, frame, look); }
    Q_INVOKABLE QString wave(const QString &path) const;              // image://mwave/… — kształt fali dźwięku
    Q_INVOKABLE void setOption(const QString &key, const QVariant &value);   // ustawienia całego filmu (fadeIn, fadeOut)
    Q_INVOKABLE bool saveMlt(const QString &pathOrUrl) const;        // projekt dla Kdenlive/Shotcut

    QString xml(int width, int height) const;
    // Napisy z mowy: [{start, end, text, words: [{text, start, end}]}] w klatkach osi; zastępują poprzednie
    // napisy z mowy. anim — animacja napisów (np. „karaoke”). Zwraca liczbę dodanych.
    int setCaptions(const QVariantList &items, const QString &style, const QString &anim = QStringLiteral("brak"));                         // opis MLT dla danego rozmiaru

    static QString thumbUrl(const QString &path, int frame, const QString &look = QString());   // image://mthumb/…
    // Filtry MLT „wyglądu” klipu: [(usługa, [(właściwość, wartość)])] — wspólne dla filmu i miniatur
    using FilterList = QList<QPair<QString, QList<QPair<QString, QString>>>>;
    static FilterList lookFilters(const QString &look, double brightness = 0, double contrast = 1, double saturation = 1);
    // Filtry dźwięku mowy: odszumianie (RNNoise, przy mocnym także szum stały) i „wyraźny głos”
    static FilterList voiceFilters(int denoise, bool clearVoice);

Q_SIGNALS:
    void changed();
    void openChanged();
    void projectsChanged();
    void message(const QString &text);

private:
    explicit Project(QObject *parent = nullptr);   // tylko przez instance()/create() — jedna instancja

    struct Media { QString path, kind, name; int frames = 0; int w = 0, h = 0; bool audio = false; };
    struct Clip {
        QString id, path, kind, name;
        int in = 0, out = 0;           // klatki źródła (30 kl./s)
        double speed = 1.0;
        double volume = 1.0;
        int denoise = 0;               // odszumianie dźwięku: 0 — wył., 1 — lekkie, 2 — mocne
        bool clearVoice = false;       // „wyraźny głos”: bez dudnienia, wyrównana głośność
        bool fill = true;              // wypełnij kadr (przytnij) zamiast pasów
        bool blurBg = false;           // zmieść całość na rozmytym tle z tego samego klipu
        bool flip = false;             // odbicie lustrzane
        QString motion;                // ruch kadru: zoomin, zoomout, panleft, panright, pulse, shake
        QString trans = QStringLiteral("fade");   // rodzaj przejścia z poprzedniego klipu (gdy fade > 0)
        QString look;                  // filtr kolorów („zywy”, „cieply”…; puste — bez)
        double brightness = 0, contrast = 1, saturation = 1;
        int fade = 0;                  // przenikanie z poprzedniego klipu (klatki osi)
        int srcFrames = 0;             // długość źródła (0 — zdjęcie, bez limitu)
        // wyliczane
        int start = 0, length = 0;
    };
    struct Text {
        QString id, text, style, anim = QStringLiteral("wjazd");
        int start = 0, length = 0;
        bool caption = false;
        double x = -1, y = -1;          // środek napisu w % kadru (−1 — miejsce ze stylu)
        double scale = 1;               // wielkość względem stylu
        QString color;                  // kolor liter zamiast koloru stylu
        struct Word { QString text; int start = 0, end = 0; };   // czasy słów (klatki od początku napisu) — z rozpoznawania mowy
        QList<Word> words;
    };
    // Słowa napisu z czasami: zapamiętane z mowy, a gdy tekst zmieniono — rozłożone proporcjonalnie do długości
    QList<Text::Word> wordTimings(const Text &t) const;
    struct Music {
        QString id, path, name;
        int start = 0, in = 0, out = 0;
        int srcFrames = 0;
        double volume = 0.8;
        bool fadeOut = true;
        bool voice = false;             // nagranie lektora (pod nim muzyka i film się przyciszają)
        int denoise = 0;                // jak w klipie
        bool clearVoice = false;
    };
    struct Overlay {
        QString id, path, kind, name;
        int start = 0, in = 0, out = 0, srcFrames = 0;   // srcFrames 0 — zdjęcie (bez limitu długości)
        double aspect = 1;                               // szerokość / wysokość źródła
        double x = 50, y = 32;                           // środek w % kadru
        double scale = 0.5;                              // szerokość jako ułamek szerokości kadru
        double rotation = 0, opacity = 1, volume = 1;
        QString shape = QStringLiteral("rect");          // rect, rounded, circle
        bool chroma = false;                             // usuń zielone (albo niebieskie) tło
        QString key = QStringLiteral("#00B140");
        double variance = 0.25;
        QString anim = QStringLiteral("wyskok");         // brak, pojawianie, wyskok, wjazd
    };

    // Ułożenie napisu w kadrze (w pikselach danego rozmiaru)
    struct TextLayout { QString text, valign; int size = 0, lines = 1, longest = 0; double x = 0, y = 0, w = 0, h = 0; };
    TextLayout layoutText(const Text &t, int width, int height) const;

    QString m_id, m_name, m_format = QStringLiteral("9:16");
    bool m_fadeIn = false, m_fadeOut = false;
    bool m_duck = true;   // rozjaśnienie z czerni na początku, ściemnienie na końcu
    QList<Media> m_media;
    QList<Clip> m_clips;
    QList<Text> m_texts;
    QList<Music> m_music;
    QList<Overlay> m_overlays;
    int m_duration = 0;
    int m_revision = 0;
    qint64 m_created = 0;
    QList<QJsonObject> m_undo, m_redo;
    QString m_lastKey;               // łączenie kolejnych zmian suwaka w jeden krok cofania
    qint64 m_lastKeyTime = 0;
    QVariantList m_projects;
    QTimer m_saveTimer;

    QJsonObject toJson() const;
    void fromJson(const QJsonObject &o);
    void snapshot(const QString &mergeKey = QString());
    void commit();                    // przelicz, powiadom, zapisz za chwilę
    void layout();
    void save();
    void loadProjects();
    QString projectsDir() const;
    QString newId() const;
    const Media *probe(const QString &path);
    static int clipLength(const Clip &c);
    Clip *clip(const QString &id);
    Text *text(const QString &id);
    Music *track(const QString &id);
    Overlay *overlay(const QString &id);
};
