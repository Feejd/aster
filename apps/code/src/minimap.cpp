#include "minimap.h"

#include <QPainter>
#include <QTextBlock>
#include <QTextDocument>
#include <QTextLayout>

Minimap::Minimap(QQuickItem *parent)
    : QQuickPaintedItem(parent)
{
    m_repaint.setSingleShot(true);
    m_repaint.setInterval(120);
    connect(&m_repaint, &QTimer::timeout, this, [this] { update(); });
}

void Minimap::setDocument(QQuickTextDocument *d)
{
    if (d == m_document)
        return;
    m_document = d;
    if (d && d->textDocument())
        connect(d->textDocument(), &QTextDocument::contentsChange, this, [this] { m_repaint.start(); });
    update();
    Q_EMIT changed();
}

int Minimap::visibleBlocks() const
{
    return m_document && m_document->textDocument() ? m_document->textDocument()->blockCount() : 0;
}

qreal Minimap::offset() const
{
    const qreal total = visibleBlocks() * LineH;
    if (total <= height())
        return 0;
    const int scrollable = std::max(1, visibleBlocks() - m_visibleLines);
    return (total - height()) * std::clamp(qreal(m_firstLine) / scrollable, 0.0, 1.0);
}

int Minimap::lineAt(qreal y) const
{
    return std::clamp(int((y + offset()) / LineH), 0, std::max(0, visibleBlocks() - 1));
}

void Minimap::paint(QPainter *p)
{
    if (!m_document || !m_document->textDocument())
        return;
    QTextDocument *doc = m_document->textDocument();
    const qreal off = offset();
    const int first = int(off / LineH);
    const int last = int((off + height()) / LineH) + 1;
    p->setPen(Qt::NoPen);
    // Wiersze: każdy ciąg znaków bez spacji jako pasek w kolorze formatu
    QTextBlock b = doc->findBlockByNumber(first);
    for (int n = first; b.isValid() && n <= last; b = b.next(), ++n) {
        const qreal y = n * LineH - off;
        const QString t = b.text();
        if (t.trimmed().isEmpty())
            continue;
        const QList<QTextLayout::FormatRange> fmts = b.layout() ? b.layout()->formats() : QList<QTextLayout::FormatRange>();
        const auto colorAt = [&](int i) {
            for (const auto &f : fmts)
                if (i >= f.start && i < f.start + f.length && f.format.hasProperty(QTextFormat::ForegroundBrush))
                    return f.format.foreground().color();
            return m_text;
        };
        int col = 0, runStart = -1;
        QColor runColor;
        const auto flush = [&](int end) {
            if (runStart < 0)
                return;
            QColor c = runColor;
            c.setAlphaF(c.alphaF() * 0.75);
            p->fillRect(QRectF(runStart * CharW + 2, y, (end - runStart) * CharW, LineH - 0.5), c);
            runStart = -1;
        };
        for (int i = 0; i < t.size() && col * CharW < width() - 4; ++i) {
            const QChar ch = t.at(i);
            const int w = ch == QLatin1Char('\t') ? 4 : 1;
            if (ch.isSpace()) {
                flush(col);
            } else {
                const QColor c = colorAt(i);
                if (runStart >= 0 && c != runColor)
                    flush(col);
                if (runStart < 0) {
                    runStart = col;
                    runColor = c;
                }
            }
            col += w;
        }
        flush(col);
    }
    // Znaczniki (błędy, trafienia szukania) przy prawej krawędzi
    for (const QVariant &v : std::as_const(m_marks)) {
        const QVariantMap m = v.toMap();
        const qreal y = m.value(QStringLiteral("line")).toInt() * LineH - off;
        if (y < -2 || y > height())
            continue;
        p->fillRect(QRectF(width() - 4, y - 1, 4, 3), QColor(m.value(QStringLiteral("color")).toString()));
    }
    // Widoczna część edytora
    const qreal sy = m_firstLine * LineH - off;
    p->fillRect(QRectF(0, sy, width(), std::max(8.0, m_visibleLines * LineH)), m_slider);
}
