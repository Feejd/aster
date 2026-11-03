#pragma once

#include <QColor>
#include <QQuickPaintedItem>

// Kształt fali klipu: fragment pliku (srcStart…+srcLength, z pętlą) w skali osi czasu.
// Element obejmuje tylko widoczną część klipu (from = czas w klipie przy lewej krawędzi) — długie klipy
// przy dużym powiększeniu nie tworzą ogromnych tekstur.
// live: true — rysuje dźwięk, który właśnie się nagrywa (od początku nagrania).
class Waveform : public QQuickPaintedItem
{
    Q_OBJECT
    QML_ELEMENT
    Q_PROPERTY(QString file MEMBER m_file NOTIFY changed)
    Q_PROPERTY(double srcStart MEMBER m_srcStart NOTIFY changed)
    Q_PROPERTY(double srcLength MEMBER m_srcLength NOTIFY changed)
    Q_PROPERTY(double loopOffset MEMBER m_offset NOTIFY changed)
    Q_PROPERTY(double from MEMBER m_from NOTIFY changed)              // czas w klipie (s) przy lewej krawędzi elementu
    Q_PROPERTY(double pxPerSec MEMBER m_pxPerSec NOTIFY changed)
    Q_PROPERTY(bool loop MEMBER m_loop NOTIFY changed)
    Q_PROPERTY(bool live MEMBER m_live NOTIFY changed)
    Q_PROPERTY(QColor color MEMBER m_color NOTIFY changed)
    Q_PROPERTY(int version MEMBER m_version NOTIFY changed)           // zmiana → przerysuj (wczytane pliki, nagrywanie)

public:
    explicit Waveform(QQuickItem *parent = nullptr);
    void paint(QPainter *p) override;

signals:
    void changed();

private:
    QString m_file;
    double m_srcStart = 0, m_srcLength = 0, m_offset = 0, m_from = 0, m_pxPerSec = 100;
    bool m_loop = false, m_live = false;
    QColor m_color = Qt::white;
    int m_version = 0;
};
