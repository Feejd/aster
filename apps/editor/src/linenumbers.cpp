#include "linenumbers.h"

#include <QAbstractTextDocumentLayout>
#include <QPainter>
#include <QTextBlock>
#include <QTextDocument>

LineNumbers::LineNumbers(QQuickItem *parent)
    : QQuickPaintedItem(parent)
{
    setAntialiasing(true);
}

void LineNumbers::setDocument(QQuickTextDocument *d)
{
    if (d == m_document)
        return;
    m_document = d;
    if (d && d->textDocument()) {
        connect(d->textDocument(), &QTextDocument::blockCountChanged, this, [this] { update(); Q_EMIT changed(); });
        connect(d->textDocument()->documentLayout(), &QAbstractTextDocumentLayout::update, this, [this] { update(); });
    }
    update();
    Q_EMIT changed();
}

int LineNumbers::lineCount() const
{
    return m_document && m_document->textDocument() ? m_document->textDocument()->blockCount() : 0;
}

void LineNumbers::paint(QPainter *painter)
{
    if (!m_document || !m_document->textDocument())
        return;
    QTextDocument *doc = m_document->textDocument();
    QAbstractTextDocumentLayout *layout = doc->documentLayout();
    painter->setFont(m_font);
    const QFontMetricsF fm(m_font);
    QTextBlock block = doc->findBlock(m_firstPosition);
    // Wiersz nad widokiem też (częściowo widoczny)
    if (block.previous().isValid())
        block = block.previous();
    const qreal right = width() - 12;
    for (; block.isValid(); block = block.next()) {
        const QRectF r = layout->blockBoundingRect(block);
        const qreal y = r.top() - m_offset;
        if (y > height())
            break;
        if (y + r.height() < 0)
            continue;
        const bool current = block.blockNumber() == m_currentLine;
        painter->setPen(current ? m_currentColor : m_color);
        // Numer na wysokości pierwszej linii wiersza (zawinięty wiersz — tylko raz)
        const qreal lineH = block.layout() && block.layout()->lineCount() > 0 ? block.layout()->lineAt(0).height() : fm.height();
        painter->drawText(QRectF(0, y, right, lineH), Qt::AlignRight | Qt::AlignVCenter, QString::number(block.blockNumber() + 1));
    }
}
