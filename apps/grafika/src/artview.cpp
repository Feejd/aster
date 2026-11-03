#include "artview.h"

#include "art.h"
#include "project.h"

#include <QPainter>

ArtView::ArtView(QQuickItem *parent)
    : QQuickPaintedItem(parent)
{
    setAntialiasing(true);
}

// Klucze, które nie zmieniają wyglądu w układzie elementu (ustawia je QML), więc nie wymagają rysowania od nowa
static QVariantMap looks(QVariantMap m)
{
    for (const char *k : {"x", "y", "rotation", "opacity"})
        m.remove(QLatin1String(k));
    return m;
}

void ArtView::setElement(const QVariantMap &element)
{
    if (element == m_element)
        return;
    const bool repaint = looks(element) != looks(m_element);
    m_element = element;
    Q_EMIT elementChanged();
    if (repaint)
        update();
}

void ArtView::setProject(Project *project)
{
    if (m_project == project)
        return;
    if (m_project)
        disconnect(m_project, nullptr, this, nullptr);
    m_project = project;
    if (m_project)
        connect(m_project, &Project::imagesChanged, this, [this] { update(); });
    Q_EMIT projectChanged();
    update();
}

qreal ArtView::bleed() const
{
    return m_element.value(QStringLiteral("kind")).toString() == QLatin1String("background") ? 0 : Art::bleed(m_element);
}

void ArtView::paint(QPainter *painter)
{
    const qreal w = m_element.value(QStringLiteral("w")).toDouble();
    const qreal h = m_element.value(QStringLiteral("h")).toDouble();
    if (w <= 0 || h <= 0)
        return;
    const qreal b = bleed();
    painter->scale(width() / (w + 2 * b), height() / (h + 2 * b));
    painter->translate(b, b);
    if (m_element.value(QStringLiteral("kind")).toString() == QLatin1String("background"))
        Art::paintBackground(painter, m_element, QSizeF(w, h), m_project);
    else
        Art::paintElement(painter, m_element, m_project);
}
