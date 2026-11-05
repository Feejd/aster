#include "gutter.h"

#include <QAbstractTextDocumentLayout>
#include <QPainter>
#include <QPainterPath>
#include <QTextBlock>
#include <QTextDocument>

namespace {

QVector<size_t> hashes(const QString &text)
{
    QVector<size_t> out;
    for (QStringView l : QStringView(text).split(QLatin1Char('\n')))
        out << qHash(l);
    return out;
}

} // namespace

Gutter::Gutter(QQuickItem *parent)
    : QQuickPaintedItem(parent)
{
    setAntialiasing(true);
    m_diffTimer.setSingleShot(true);
    m_diffTimer.setInterval(250);
    connect(&m_diffTimer, &QTimer::timeout, this, &Gutter::recompute);
}

void Gutter::setDocument(QQuickTextDocument *d)
{
    if (d == m_document)
        return;
    m_document = d;
    if (d && d->textDocument()) {
        connect(d->textDocument(), &QTextDocument::blockCountChanged, this, [this] { update(); Q_EMIT changed(); });
        connect(d->textDocument()->documentLayout(), &QAbstractTextDocumentLayout::update, this, [this] { update(); });
        connect(d->textDocument(), &QTextDocument::contentsChanged, this, [this] { if (m_hasBase) m_diffTimer.start(); });
    }
    m_diffTimer.start();
    update();
    Q_EMIT changed();
}

void Gutter::setBaseText(const QString &t)
{
    QString norm = t;
    norm.replace(QLatin1String("\r\n"), QLatin1String("\n"));
    if (norm == m_baseText)
        return;
    m_baseText = norm;
    Q_EMIT baseChanged();
    m_diffTimer.start(0);
}

void Gutter::setHasBase(bool on)
{
    if (on == m_hasBase)
        return;
    m_hasBase = on;
    Q_EMIT baseChanged();
    m_diffTimer.start(0);
}

void Gutter::setDiagnostics(const QVariantList &list)
{
    m_diagList = list;
    m_diagLines.clear();
    for (const QVariant &v : list) {
        const QVariantMap m = v.toMap();
        const int line = m.value(QStringLiteral("line")).toInt(), sev = m.value(QStringLiteral("severity")).toInt();
        m_diagLines.insert(line, std::min(m_diagLines.value(line, 99), sev));
    }
    update();
    Q_EMIT changed();
}

void Gutter::setBreakpoints(const QVariantList &list)
{
    m_bpList = list;
    m_bps.clear();
    for (const QVariant &v : list)
        m_bps.insert(v.toInt());
    update();
    Q_EMIT changed();
}

int Gutter::lineCount() const
{
    return m_document && m_document->textDocument() ? m_document->textDocument()->blockCount() : 0;
}

void Gutter::recompute()
{
    m_marks.clear();
    m_deletedBefore.clear();
    int changes = 0;
    if (m_hasBase && m_document && m_document->textDocument()) {
        const QVector<size_t> a = hashes(m_baseText);
        const QVector<size_t> b = hashes(m_document->textDocument()->toPlainText());
        const int na = int(a.size()), nb = int(b.size());
        m_marks.fill(0, nb);
        m_deletedBefore.fill(false, nb + 1);

        // Wspólny początek i koniec — zwykle zmiany są w jednym miejscu, środek jest mały
        int p = 0;
        while (p < na && p < nb && a[p] == b[p])
            ++p;
        int s = 0;
        while (s < na - p && s < nb - p && a[na - 1 - s] == b[nb - 1 - s])
            ++s;
        const int n = na - p - s, m = nb - p - s;

        // Fragmenty zmian: (od, do) w starej i nowej wersji
        struct Hunk { int i0, i1, j0, j1; };
        QVector<Hunk> hunks;
        if (n > 0 || m > 0) {
            if (qint64(n) * m <= 4'000'000 && n < 65535 && m < 65535) {
                // Najdłuższy wspólny podciąg (tablica od końca), potem przejście do przodu
                std::vector<quint16> t(size_t(n + 1) * (m + 1), 0);
                const auto at = [&](int i, int j) -> quint16 & { return t[size_t(i) * (m + 1) + j]; };
                for (int i = n - 1; i >= 0; --i)
                    for (int j = m - 1; j >= 0; --j)
                        at(i, j) = a[p + i] == b[p + j] ? at(i + 1, j + 1) + 1 : std::max(at(i + 1, j), at(i, j + 1));
                int i = 0, j = 0, hi = 0, hj = 0;
                while (i < n || j < m) {
                    if (i < n && j < m && a[p + i] == b[p + j]) {
                        if (hi < i || hj < j)
                            hunks.append({hi, i, hj, j});
                        ++i, ++j;
                        hi = i, hj = j;
                    } else if (j < m && (i == n || at(i, j + 1) >= at(i + 1, j))) {
                        ++j;
                    } else {
                        ++i;
                    }
                }
                if (hi < n || hj < m)
                    hunks.append({hi, n, hj, m});
            } else {
                hunks.append({0, n, 0, m});
            }
        }
        for (const Hunk &h : std::as_const(hunks)) {
            const int del = h.i1 - h.i0, ins = h.j1 - h.j0;
            ++changes;
            if (ins == 0) {
                m_deletedBefore[p + h.j0] = true;
                continue;
            }
            for (int j = h.j0; j < h.j1; ++j)
                m_marks[p + j] = del == 0 ? 1 : 2;
        }
    }
    m_changeCount = changes;
    Q_EMIT marksChanged();
    update();
}

int Gutter::nextChange(int line, bool backwards) const
{
    const int n = int(m_marks.size());
    const auto changedAt = [&](int i) { return (i < n && m_marks[i]) || (i <= n && i < m_deletedBefore.size() && m_deletedBefore[i]); };
    // Początek następnego bloku zmian (pomija wiersze bieżącego)
    if (!backwards) {
        int i = line;
        while (i <= n && changedAt(i))
            ++i;
        for (; i <= n; ++i)
            if (changedAt(i))
                return std::min(i, std::max(0, n - 1));
    } else {
        int i = line;
        while (i >= 0 && changedAt(i))
            --i;
        for (; i >= 0; --i)
            if (changedAt(i)) {
                while (i > 0 && changedAt(i - 1))
                    --i;
                return std::min(i, std::max(0, n - 1));
            }
    }
    return -1;
}

void Gutter::paint(QPainter *painter)
{
    if (!m_document || !m_document->textDocument())
        return;
    QTextDocument *doc = m_document->textDocument();
    QAbstractTextDocumentLayout *layout = doc->documentLayout();
    painter->setFont(m_font);
    const QFontMetricsF fm(m_font);
    QTextBlock block = doc->findBlock(m_firstPosition);
    if (block.previous().isValid())
        block = block.previous();
    const qreal markX = width() - 8;
    const qreal right = markX - 22;                 // między numerem a znacznikiem zmian — strzałka zwijania
    const int marked = int(m_marks.size());
    for (; block.isValid(); block = block.next()) {
        const QRectF r = layout->blockBoundingRect(block);
        const qreal y = r.top() - m_offset;
        if (y > height())
            break;
        if (y + r.height() < 0)
            continue;
        if (!block.isVisible())
            continue;                                   // wiersz w zwiniętym bloku
        const int n = block.blockNumber();
        const bool current = n == m_currentLine;
        painter->setPen(current ? m_currentColor : m_color);
        const qreal lineH = block.layout() && block.layout()->lineCount() > 0 ? block.layout()->lineAt(0).height() : fm.height();
        painter->drawText(QRectF(0, y, right, lineH), Qt::AlignRight | Qt::AlignVCenter, QString::number(n + 1));

        // Kropka błędu albo ostrzeżenia z serwera języka, po lewej od numeru
        if (const int sev = m_diagLines.value(n, 0); sev == 1 || sev == 2) {
            painter->setPen(Qt::NoPen);
            painter->setBrush(sev == 1 ? m_error : m_warning);
            painter->drawEllipse(QPointF(7, y + lineH / 2), 3, 3);
        }

        // Punkt przerwania (czerwone kółko) i wiersz zatrzymania debugera (żółta strzałka)
        if (m_bps.contains(n)) {
            painter->setPen(Qt::NoPen);
            painter->setBrush(QColor(0xE5, 0x48, 0x4D));
            painter->drawEllipse(QPointF(8, y + lineH / 2), 5, 5);
        }
        if (n == m_stopLine) {
            QPainterPath arrow;
            const qreal cy = y + lineH / 2;
            arrow.moveTo(2, cy - 4); arrow.lineTo(8, cy - 4); arrow.lineTo(13, cy); arrow.lineTo(8, cy + 4); arrow.lineTo(2, cy + 4);
            arrow.closeSubpath();
            painter->setPen(QPen(QColor(0x7A, 0x5A, 0x00), 1));
            painter->setBrush(QColor(0xF5, 0xC2, 0x3D));
            painter->drawPath(arrow);
        }

        if (n < marked && m_marks[n]) {
            painter->setPen(Qt::NoPen);
            painter->setBrush(m_marks[n] == 1 ? m_added : m_modified);
            painter->drawRoundedRect(QRectF(markX, y, 3, r.height()), 1, 1);
        }
        if (n < m_deletedBefore.size() && m_deletedBefore[n]) {
            QPainterPath tri;
            tri.moveTo(markX - 1, y - 4);
            tri.lineTo(markX + 5, y);
            tri.lineTo(markX - 1, y + 4);
            tri.closeSubpath();
            painter->setPen(Qt::NoPen);
            painter->setBrush(m_deleted);
            painter->drawPath(tri);
        }
        if (!block.next().isValid() && n + 1 < m_deletedBefore.size() && m_deletedBefore[n + 1]) {
            const qreal yb = y + r.height();
            QPainterPath tri;
            tri.moveTo(markX - 1, yb - 4);
            tri.lineTo(markX + 5, yb);
            tri.lineTo(markX - 1, yb + 4);
            tri.closeSubpath();
            painter->setPen(Qt::NoPen);
            painter->setBrush(m_deleted);
            painter->drawPath(tri);
        }
    }
}
