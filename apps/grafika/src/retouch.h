#pragma once

#include <QElapsedTimer>
#include <QImage>
#include <QObject>
#include <QPointF>
#include <QPointer>
#include <QTimer>
#include <QTransform>
#include <QVariantMap>
#include <QtQml/qqmlregistration.h>

class Project;
class QThreadPool;

// Malowanie i retusz po pikselach warstwy-zdjęcia: pędzel, gumka, wypełnianie, stempel, rozjaśnianie, ściemnianie,
// rozmazywanie, rozmywanie. Współrzędne wejściowe — piksele strony; kreska liczy się na zdjęciu w pełnej rozdzielczości.
// Jedna kreska nie nakłada się sama na siebie (maska kreski, jak w Photoshopie), krycie to górna granica. W trakcie
// widać wynik na żywo na właściwej warstwie (Project::setLive), a po puszczeniu zdjęcie zapisuje się w tle jako nowy
// plik w projekcie — poprzednie zostaje w historii cofania.
class Retouch : public QObject
{
    Q_OBJECT
    QML_ELEMENT
    QML_SINGLETON
    Q_PROPERTY(QString tool READ tool WRITE setTool NOTIFY settingsChanged)     // brush | eraser | clone | dodge | burn | smudge | blur
    Q_PROPERTY(QString color READ color WRITE setColor NOTIFY settingsChanged)
    Q_PROPERTY(qreal size READ size WRITE setSize NOTIFY settingsChanged)        // piksele strony
    Q_PROPERTY(qreal hardness READ hardness WRITE setHardness NOTIFY settingsChanged)   // 0..1
    Q_PROPERTY(qreal strength READ strength WRITE setStrength NOTIFY settingsChanged)   // krycie, siła 0..1
    Q_PROPERTY(bool hasSource READ hasSource NOTIFY sourceChanged)
    Q_PROPERTY(QPointF source READ source NOTIFY sourceChanged)                  // źródło stempla (piksele strony)

public:
    explicit Retouch(QObject *parent = nullptr);
    ~Retouch() override;

    QString tool() const { return m_tool; }
    void setTool(const QString &tool);
    QString color() const { return m_color; }
    void setColor(const QString &color);
    qreal size() const { return m_size; }
    void setSize(qreal size);
    qreal hardness() const { return m_hardness; }
    void setHardness(qreal hardness);
    qreal strength() const { return m_strength; }
    void setStrength(qreal strength);
    bool hasSource() const { return m_hasSource; }
    QPointF source() const { return m_sourcePage; }

    Q_INVOKABLE bool press(Project *project, const QString &id, qreal x, qreal y);
    Q_INVOKABLE void move(qreal x, qreal y);
    Q_INVOKABLE void release();
    Q_INVOKABLE void setSource(Project *project, const QString &id, qreal x, qreal y);
    // Wypełnienie obszaru podobnego koloru od klikniętego punktu; tolerance 0..1
    Q_INVOKABLE void fill(Project *project, const QString &id, qreal x, qreal y, qreal tolerance);
    // Zaznaczenie: skasowanie albo wypełnienie zaznaczonych pikseli warstwy
    Q_INVOKABLE void clearSelected(Project *project, const QString &id);
    Q_INVOKABLE void fillSelected(Project *project, const QString &id);

Q_SIGNALS:
    void settingsChanged();
    void sourceChanged();
    void failed(const QString &message);

private:
    bool load(Project *project, const QString &id);
    void dabsTo(const QPointF &to);
    void dab(const QPointF &center);
    void smudge(const QPointF &center);
    void flush();
    void store(const QImage &image);

    QString m_tool = QStringLiteral("brush");
    QString m_color = QStringLiteral("#16181D");
    qreal m_size = 40;
    qreal m_hardness = 0.7;
    qreal m_strength = 1;

    QPointer<Project> m_project;
    QString m_id;
    QString m_key;                  // zdjęcie, na którym pracujemy
    QVariantMap m_el;
    QImage m_img;                   // bieżący wynik: ARGB32 z premultiplikacją, pełna rozdzielczość
    QImage m_base;                  // stan sprzed kreski
    QImage m_blurred;               // rozmyta kopia (narzędzie Rozmyj)
    QImage m_mask;                  // maska kreski
    QImage m_carry;                 // rozmazywanie: niesiona łata
    QImage m_clip;                  // zaznaczenie w pikselach zdjęcia (puste — bez ograniczeń)
    QTransform m_toImage;           // strona → piksele zdjęcia
    qreal m_scale = 1;              // pikseli zdjęcia na piksel strony
    qreal m_radius = 20;
    QRgb m_ink = 0;
    QPointF m_last;
    qreal m_left = 0;               // reszta odległości do następnego odcisku
    bool m_active = false;
    bool m_dirty = false;
    int m_saving = 0;

    bool m_hasSource = false;
    bool m_aligned = false;         // odstęp stempla ustalony pierwszą kreską
    QPointF m_sourceImage, m_offset, m_sourcePage, m_sourcePageStart, m_pressPage;

    QTimer m_live;
    QThreadPool *m_pool;
};
