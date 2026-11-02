#pragma once

#include <QImage>
#include <QQuickPaintedItem>

// Okładka z zaokrąglonymi rogami rysowana bez shaderów (tanio także w maszynie wirtualnej
// i przy renderowaniu programowym). Plik wczytywany od razu w docelowym rozmiarze, z pamięcią podręczną.
class RoundImage : public QQuickPaintedItem
{
    Q_OBJECT
    QML_ELEMENT
    Q_PROPERTY(QString source READ source WRITE setSource NOTIFY sourceChanged)   // ścieżka pliku
    Q_PROPERTY(qreal radius READ radius WRITE setRadius NOTIFY radiusChanged)
    Q_PROPERTY(bool ready READ ready NOTIFY readyChanged)

public:
    explicit RoundImage(QQuickItem *parent = nullptr);
    void paint(QPainter *painter) override;

    QString source() const { return m_source; }
    void setSource(const QString &s);
    qreal radius() const { return m_radius; }
    void setRadius(qreal r);
    bool ready() const { return !m_image.isNull(); }

Q_SIGNALS:
    void sourceChanged();
    void radiusChanged();
    void readyChanged();

protected:
    void geometryChange(const QRectF &newGeometry, const QRectF &oldGeometry) override;

private:
    void reload();
    QString m_source;
    qreal m_radius = 0;
    QImage m_image;
};
