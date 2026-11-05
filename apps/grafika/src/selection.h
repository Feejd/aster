#pragma once

#include <QImage>
#include <QList>
#include <QLineF>
#include <QObject>
#include <QQuickPaintedItem>
#include <QTimer>
#include <QVariantMap>
#include <QtQml/qqmlregistration.h>

class Project;

// Zaznaczenie pikseli — jak w programach do zdjęć: należy do strony, a nie do warstwy, ma miękkie krawędzie
// i obowiązuje przy malowaniu, kasowaniu, wypełnianiu oraz przy tworzeniu masek i korekcji. Maska zaznaczenia ma
// dłuższy bok 2048–4096 px; współrzędne wejściowe to piksele strony. Tryby: new | add | subtract | intersect.
// Nie zapisuje się w projekcie, ma własne cofanie.
class Selection : public QObject
{
    Q_OBJECT
    QML_ELEMENT
    QML_SINGLETON
    Q_PROPERTY(bool active READ active NOTIFY changed)
    Q_PROPERTY(bool canUndo READ canUndo NOTIFY changed)

public:
    explicit Selection(QObject *parent = nullptr);
    static Selection *instance();

    bool active() const { return !m_mask.isNull(); }
    bool canUndo() const { return !m_history.isEmpty(); }

    Q_INVOKABLE void shape(Project *project, qreal x, qreal y, qreal w, qreal h, bool ellipse, const QString &mode, qreal feather);
    Q_INVOKABLE void lasso(Project *project, const QVariantList &points, const QString &mode, qreal feather);
    // Różdżka: contiguous — tylko połączony obszar, inaczej ten kolor na całej stronie; onlyId — próbka z jednej warstwy
    Q_INVOKABLE void wand(Project *project, qreal x, qreal y, qreal tolerance, bool contiguous, const QString &onlyId, const QString &mode, qreal feather);
    Q_INVOKABLE void all(Project *project);
    Q_INVOKABLE void clear();
    Q_INVOKABLE void invert(Project *project);
    Q_INVOKABLE void feather(qreal radius);             // piksele strony
    Q_INVOKABLE void grow(qreal radius);                // ujemne — zmniejsza
    Q_INVOKABLE void translate(qreal dx, qreal dy);
    Q_INVOKABLE bool contains(qreal x, qreal y) const;
    Q_INVOKABLE void undo();

    // Działania na warstwie `id`. toLayer działa na każdym rodzaju warstwy; puste id — wszystko, co widać na stronie.
    Q_INVOKABLE QString toLayer(Project *project, const QString &id, bool cut);
    Q_INVOKABLE void maskLayer(Project *project, const QString &id, bool hide = false);

    // Dla silnika: zaznaczenie w pikselach obrazu; `pageToTarget` przelicza stronę na ten obraz. Format Alpha8.
    QImage mapped(const QTransform &pageToTarget, const QSize &size) const;
    // Maska z pikseli zdjęcia warstwy (AI)
    void fromLayer(Project *project, const QVariantMap &el, const QImage &mask, const QString &mode);
    const QImage &mask() const { return m_mask; }
    qreal scale() const { return m_k; }

Q_SIGNALS:
    void changed();

private:
    bool prepare(Project *project);
    QImage blank(bool premultiplied = true) const;
    void combine(const QImage &shape, const QString &mode, qreal feather);
    void remember();
    void set(const QImage &mask);

    static Selection *s_instance;
    QImage m_mask;                  // Alpha8; pusty — brak zaznaczenia
    QList<QImage> m_history;
    QSize m_size;
    QSizeF m_page;
    qreal m_k = 1;                  // pikseli maski na piksel strony
};

// Maszerujące mrówki: obrys zaznaczenia na płótnie
class SelectionView : public QQuickPaintedItem
{
    Q_OBJECT
    QML_ELEMENT

public:
    explicit SelectionView(QQuickItem *parent = nullptr);
    void paint(QPainter *painter) override;
    Q_INVOKABLE void rebuild();

protected:
    void geometryChange(const QRectF &now, const QRectF &old) override;

private:
    QList<QLineF> m_edges;
    QList<int> m_phase;
    QTimer m_tick;
    int m_step = 0;
};
