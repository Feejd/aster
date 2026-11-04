#pragma once

#include <QColor>
#include <QImage>
#include <QSizeF>
#include <QVariantMap>

class QPainter;

// Źródło zdjęć użytych w projekcie (zdjęcia elementów i tła). `pixels` — ile pikseli zdjęcie zajmie na wyjściu
// (dłuższy bok), żeby na ekranie rysować mniejszą kopię, a w eksporcie pełną rozdzielczość.
class ImageSource
{
public:
    virtual ~ImageSource() = default;
    virtual QImage image(const QString &key, qreal pixels) const = 0;
    // Grafika wektorowa (SVG: ikony, naklejki) — rysowana ostro w każdym rozmiarze
    virtual QByteArray vector(const QString &key) const { Q_UNUSED(key); return {}; }
};

// Rysowanie projektu — jedno dla płótna na ekranie, miniatur i eksportu (PNG, JPG, PDF),
// więc to, co widać w edytorze, wychodzi w pliku co do piksela.
//
// Element to mapa: id, type ("text" | "shape" | "image" | "vector"), x, y, w, h (piksele strony), rotation (stopnie,
// wokół środka), opacity (0..1) oraz pola rodzaju (opis w docs/grafika-format.md).
namespace Art {

// Wysokość bloku tekstu przy szerokości `el.w` (tekst sam łamie się w wiersze)
qreal textHeight(const QVariantMap &el);
// Szerokość najdłuższego wiersza bez łamania (do wstawiania nowego tekstu)
qreal textNaturalWidth(const QVariantMap &el);

// Ile element wystaje poza swoje pole (miękki cień) — tyle zapasu potrzebuje podgląd
qreal bleed(const QVariantMap &el);
// Element w jego własnym układzie: prostokąt (0, 0, w, h), bez obrotu i przezroczystości
void paintElement(QPainter *p, const QVariantMap &el, const ImageSource *images);
// Tło strony: { type: "color" | "gradient" | "radial" | "image", color, color2, angle, src }
void paintBackground(QPainter *p, const QVariantMap &bg, const QSizeF &page, const ImageSource *images);
// Cała strona: { width, height, background, elements: [...] } w układzie strony (piksele projektu)
void paintPage(QPainter *p, const QVariantMap &doc, const ImageSource *images, qreal bleed = 0);
// Strona jako obraz o podanym rozmiarze (miniatury, PNG, JPG)
QImage renderPage(const QVariantMap &doc, const QSize &size, const ImageSource *images, const QColor &under = Qt::transparent);

}
