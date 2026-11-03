#include "textops.h"
#include "searchregex.h"

#include <KSyntaxHighlighting/Definition>
#include <KSyntaxHighlighting/Repository>
#include <QFileInfo>
#include <QTextBlock>
#include <QTextCursor>
#include <QTextDocument>

namespace {

KSyntaxHighlighting::Repository &repository()
{
    static KSyntaxHighlighting::Repository repo;
    return repo;
}

int leadingWhitespace(const QString &s)
{
    int i = 0;
    while (i < s.size() && (s.at(i) == QLatin1Char(' ') || s.at(i) == QLatin1Char('\t')))
        ++i;
    return i;
}

// Zamienia tekst [a, b) jednym krokiem cofania
void replace(QTextDocument *d, int a, int b, const QString &text)
{
    QTextCursor c(d);
    c.setPosition(a);
    c.setPosition(b, QTextCursor::KeepAnchor);
    c.insertText(text);
}

QVariantMap selection(int start, int end)
{
    return {{QStringLiteral("start"), start}, {QStringLiteral("end"), end}};
}

} // namespace

TextOps::TextOps(QObject *parent)
    : QObject(parent)
{
}

QPoint TextOps::lineColumn(QQuickTextDocument *doc, int position) const
{
    if (!doc || !doc->textDocument())
        return {};
    const QTextBlock b = doc->textDocument()->findBlock(position);
    return {position - b.position(), b.blockNumber()};
}

int TextOps::positionOfLine(QQuickTextDocument *doc, int line) const
{
    if (!doc || !doc->textDocument())
        return 0;
    QTextDocument *d = doc->textDocument();
    const QTextBlock b = d->findBlockByNumber(std::clamp(line, 0, d->blockCount() - 1));
    return b.isValid() ? b.position() : 0;
}

int TextOps::lineCount(QQuickTextDocument *doc) const
{
    return doc && doc->textDocument() ? doc->textDocument()->blockCount() : 0;
}

QString TextOps::lineText(QQuickTextDocument *doc, int line) const
{
    if (!doc || !doc->textDocument())
        return {};
    return doc->textDocument()->findBlockByNumber(line).text();
}

QVariantMap TextOps::editLines(QQuickTextDocument *doc, int selStart, int selEnd, const QString &op,
                               const QString &unit, const QVariantMap &comment)
{
    if (!doc || !doc->textDocument())
        return selection(selStart, selEnd);
    QTextDocument *d = doc->textDocument();
    if (selEnd < selStart)
        std::swap(selStart, selEnd);
    QTextBlock first = d->findBlock(selStart);
    QTextBlock last = d->findBlock(selEnd);
    // Zaznaczenie kończące się na początku wiersza nie obejmuje tego wiersza (jak w VS Code)
    if (selEnd > selStart && last.blockNumber() > first.blockNumber() && selEnd == last.position())
        last = last.previous();
    const bool multi = last.blockNumber() > first.blockNumber();
    const int a = first.position();
    const int b = last.position() + last.length() - 1;          // koniec ostatniego wiersza (bez \n)
    QStringList lines = d->toPlainText().mid(a, b - a).split(QLatin1Char('\n'));
    const QString block = lines.join(QLatin1Char('\n'));

    QTextCursor edit(d);
    edit.beginEditBlock();
    QVariantMap result = selection(selStart, selEnd);

    if (op == QLatin1String("indent") || op == QLatin1String("outdent") || op == QLatin1String("comment")) {
        int firstDelta = 0;
        if (op == QLatin1String("indent")) {
            for (int i = 0; i < lines.size(); ++i) {
                if (lines[i].trimmed().isEmpty() && multi)
                    continue;
                lines[i].prepend(unit);
                if (i == 0)
                    firstDelta = int(unit.size());
            }
        } else if (op == QLatin1String("outdent")) {
            const int size = unit == QLatin1String("\t") ? 4 : std::max<int>(1, int(unit.size()));
            for (int i = 0; i < lines.size(); ++i) {
                int n = 0;
                if (lines[i].startsWith(QLatin1Char('\t')))
                    n = 1;
                else
                    while (n < size && n < lines[i].size() && lines[i].at(n) == QLatin1Char(' '))
                        ++n;
                lines[i].remove(0, n);
                if (i == 0)
                    firstDelta = -n;
            }
        } else {
            const QString marker = comment.value(QStringLiteral("line")).toString();
            const QString open = comment.value(QStringLiteral("start")).toString();
            const QString close = comment.value(QStringLiteral("end")).toString();
            if (!marker.isEmpty()) {
                int minIndent = INT_MAX;
                bool all = true, any = false;
                for (const QString &l : std::as_const(lines)) {
                    if (l.trimmed().isEmpty())
                        continue;
                    any = true;
                    minIndent = std::min(minIndent, leadingWhitespace(l));
                    if (!l.mid(leadingWhitespace(l)).startsWith(marker))
                        all = false;
                }
                if (!any) {
                    minIndent = 0;
                    all = false;
                }
                for (int i = 0; i < lines.size(); ++i) {
                    QString &l = lines[i];
                    if (l.trimmed().isEmpty() && any)
                        continue;
                    const int before = int(l.size());
                    if (all) {
                        const int at = leadingWhitespace(l);
                        int n = int(marker.size());
                        if (at + n < l.size() && l.at(at + n) == QLatin1Char(' '))
                            ++n;
                        l.remove(at, n);
                    } else {
                        l.insert(std::min<int>(minIndent, int(l.size())), marker + QLatin1Char(' '));
                    }
                    if (i == 0)
                        firstDelta = int(l.size()) - before;
                }
            } else if (!open.isEmpty()) {
                // Tylko komentarz blokowy (HTML, CSS): <!-- … --> wokół zaznaczonych wierszy
                const QString joined = lines.join(QLatin1Char('\n'));
                const QString trimmed = joined.trimmed();
                if (trimmed.startsWith(open) && trimmed.endsWith(close)) {
                    const int s = int(joined.indexOf(open));
                    QString inner = joined;
                    const int e = int(inner.lastIndexOf(close));
                    inner.remove(e, close.size());
                    if (e > 0 && inner.at(e - 1) == QLatin1Char(' '))
                        inner.remove(e - 1, 1);
                    int n = int(open.size());
                    if (s + n < inner.size() && inner.at(s + n) == QLatin1Char(' '))
                        ++n;
                    inner.remove(s, n);
                    lines = inner.split(QLatin1Char('\n'));
                    firstDelta = -n;
                } else {
                    const int at = leadingWhitespace(lines.first());
                    lines.first().insert(at, open + QLatin1Char(' '));
                    lines.last().append(QLatin1Char(' ') + close);
                    firstDelta = int(open.size()) + 1;
                }
            }
        }
        const QString out = lines.join(QLatin1Char('\n'));
        replace(d, a, b, out);
        if (multi) {
            result = selection(a, a + int(out.size()));
        } else {
            const int lineEnd = a + int(out.size());
            const auto shift = [&](int p) { return std::clamp(p + firstDelta, a, lineEnd); };
            result = selection(shift(selStart), shift(selEnd));
        }
    } else if (op == QLatin1String("moveUp")) {
        const QTextBlock prev = first.previous();
        if (prev.isValid()) {
            const QString above = prev.text();
            replace(d, prev.position(), b, block + QLatin1Char('\n') + above);
            const int shift = int(above.size()) + 1;
            result = selection(selStart - shift, selEnd - shift);
        }
    } else if (op == QLatin1String("moveDown")) {
        const QTextBlock next = last.next();
        if (next.isValid()) {
            const QString below = next.text();
            replace(d, a, next.position() + next.length() - 1, below + QLatin1Char('\n') + block);
            const int shift = int(below.size()) + 1;
            result = selection(selStart + shift, selEnd + shift);
        }
    } else if (op == QLatin1String("duplicateDown")) {
        replace(d, b, b, QLatin1Char('\n') + block);
        const int shift = int(block.size()) + 1;
        result = selection(selStart + shift, selEnd + shift);
    } else if (op == QLatin1String("duplicateUp")) {
        replace(d, a, a, block + QLatin1Char('\n'));
    } else if (op == QLatin1String("deleteLine")) {
        const int col = selStart - a;
        if (last.next().isValid())
            replace(d, a, b + 1, QString());
        else if (first.previous().isValid())
            replace(d, a - 1, b, QString());
        else
            replace(d, a, b, QString());
        const QTextBlock now = d->findBlock(std::min(a, d->characterCount() - 1));
        const int p = now.position() + std::min(col, now.length() - 1);
        result = selection(p, p);
    }
    edit.endEditBlock();
    return result;
}

QVariantList TextOps::matchBracket(QQuickTextDocument *doc, int position) const
{
    if (!doc || !doc->textDocument())
        return {};
    QTextDocument *d = doc->textDocument();
    static const QString opens = QStringLiteral("([{"), closes = QStringLiteral(")]}");
    const int count = d->characterCount();
    // Najpierw znak przed kursorem, potem za nim
    for (int at : {position - 1, position}) {
        if (at < 0 || at >= count)
            continue;
        const QChar ch = d->characterAt(at);
        int k = int(opens.indexOf(ch));
        const bool forward = k >= 0;
        if (!forward)
            k = int(closes.indexOf(ch));
        if (k < 0)
            continue;
        const QChar same = ch, other = forward ? closes.at(k) : opens.at(k);
        int depth = 0;
        const int step = forward ? 1 : -1;
        for (int p = at + step, n = 0; p >= 0 && p < count && n < 100000; p += step, ++n) {
            const QChar c = d->characterAt(p);
            if (c == same)
                ++depth;
            else if (c == other && depth-- == 0)
                return {at, p};
        }
        return {at};                                  // nawias bez pary
    }
    return {};
}

QVariantMap TextOps::detectIndent(const QString &text) const
{
    int tabs = 0, spaces = 0;
    QHash<int, int> deltas;
    int prev = 0, lines = 0;
    for (QStringView line : QStringView(text).split(QLatin1Char('\n'))) {
        if (++lines > 5000)
            break;
        if (line.trimmed().isEmpty())
            continue;
        if (line.startsWith(QLatin1Char('\t'))) {
            ++tabs;
            continue;
        }
        int n = 0;
        while (n < line.size() && line.at(n) == QLatin1Char(' '))
            ++n;
        if (n > 0)
            ++spaces;
        // Komentarze blokowe „ * …” wcinają o 1 — nie liczą się
        const int delta = std::abs(n - prev);
        if (delta >= 2 && delta <= 8)
            deltas[delta]++;
        prev = n;
    }
    if (tabs > spaces)
        return {{QStringLiteral("tabs"), true}, {QStringLiteral("size"), 4}};
    int size = 4, best = 0;
    for (auto it = deltas.cbegin(); it != deltas.cend(); ++it)
        if (it.value() > best || (it.value() == best && it.key() < size)) {
            best = it.value();
            size = it.key();
        }
    if (size != 2 && size != 3 && size != 4 && size != 8)
        size = 4;
    return {{QStringLiteral("tabs"), false}, {QStringLiteral("size"), spaces ? size : 4}};
}

QVariantMap TextOps::commentMarkers(const QString &fileName, const QString &language) const
{
    auto &repo = repository();
    KSyntaxHighlighting::Definition def = repo.definitionForFileName(QFileInfo(fileName).fileName());
    if (!def.isValid() && !language.isEmpty()) {
        for (const auto &dd : repo.definitions())
            if (dd.translatedName() == language || dd.name() == language) {
                def = dd;
                break;
            }
    }
    if (!def.isValid())
        return {{QStringLiteral("line"), QStringLiteral("#")}};
    const auto multi = def.multiLineCommentMarker();
    return {{QStringLiteral("line"), def.singleLineCommentMarker()},
            {QStringLiteral("start"), multi.first},
            {QStringLiteral("end"), multi.second}};
}

int TextOps::applyEdits(QQuickTextDocument *doc, const QVariantList &edits)
{
    if (!doc || !doc->textDocument() || edits.isEmpty())
        return 0;
    QTextDocument *d = doc->textDocument();
    const auto pos = [d](int line, int col) {
        const QTextBlock b = d->findBlockByNumber(line);
        if (!b.isValid())
            return d->characterCount() - 1;
        return b.position() + std::clamp(col, 0, b.length() - 1);
    };
    // Od końca — wcześniejsze pozycje się nie przesuwają
    struct E { int a, b; QString text; };
    QList<E> list;
    for (const QVariant &v : edits) {
        const QVariantMap m = v.toMap();
        list.append({pos(m.value(QStringLiteral("sl")).toInt(), m.value(QStringLiteral("sc")).toInt()),
                     pos(m.value(QStringLiteral("el")).toInt(), m.value(QStringLiteral("ec")).toInt()),
                     m.value(QStringLiteral("text")).toString()});
    }
    std::stable_sort(list.begin(), list.end(), [](const E &x, const E &y) { return x.a > y.a; });
    QTextCursor c(d);
    c.beginEditBlock();
    for (const E &e : std::as_const(list)) {
        c.setPosition(e.a);
        c.setPosition(std::max(e.a, e.b), QTextCursor::KeepAnchor);
        c.insertText(e.text);
    }
    c.endEditBlock();
    return int(list.size());
}

QVariantMap TextOps::wordAt(QQuickTextDocument *doc, int position) const
{
    if (!doc || !doc->textDocument())
        return {};
    QTextDocument *d = doc->textDocument();
    const auto word = [d](int p) { const QChar ch = d->characterAt(p); return ch.isLetterOrNumber() || ch == QLatin1Char('_') || ch == QLatin1Char('$'); };
    int a = position, b = position;
    while (a > 0 && word(a - 1))
        --a;
    while (b < d->characterCount() - 1 && word(b))
        ++b;
    QTextCursor c(d);
    c.setPosition(a);
    c.setPosition(b, QTextCursor::KeepAnchor);
    return {{QStringLiteral("start"), a}, {QStringLiteral("end"), b}, {QStringLiteral("text"), c.selectedText()}};
}

QVariantList TextOps::conflicts(QQuickTextDocument *doc) const
{
    if (!doc || !doc->textDocument())
        return {};
    QTextDocument *d = doc->textDocument();
    QVariantList out;
    int start = -1, base = -1, sep = -1;
    QString ours;
    for (QTextBlock b = d->begin(); b.isValid(); b = b.next()) {
        const QString t = b.text();
        const int n = b.blockNumber();
        if (t.startsWith(QLatin1String("<<<<<<<"))) {
            start = n;
            base = sep = -1;
            ours = t.mid(7).trimmed();
        } else if (start >= 0 && sep < 0 && t.startsWith(QLatin1String("|||||||"))) {
            base = n;
        } else if (start >= 0 && t.startsWith(QLatin1String("=======")) && sep < 0) {
            sep = n;
        } else if (start >= 0 && sep >= 0 && t.startsWith(QLatin1String(">>>>>>>"))) {
            out << QVariantMap{{QStringLiteral("startLine"), start}, {QStringLiteral("baseLine"), base},
                               {QStringLiteral("sepLine"), sep}, {QStringLiteral("endLine"), n},
                               {QStringLiteral("ours"), ours.isEmpty() ? QStringLiteral("HEAD") : ours},
                               {QStringLiteral("theirs"), t.mid(7).trimmed()}};
            start = -1;
        }
    }
    return out;
}

bool TextOps::resolveConflict(QQuickTextDocument *doc, int startLine, const QString &choice)
{
    for (const QVariant &v : conflicts(doc)) {
        const QVariantMap c = v.toMap();
        if (c.value(QStringLiteral("startLine")).toInt() != startLine)
            continue;
        QTextDocument *d = doc->textDocument();
        const int sl = startLine, bl = c.value(QStringLiteral("baseLine")).toInt();
        const int ml = c.value(QStringLiteral("sepLine")).toInt(), el = c.value(QStringLiteral("endLine")).toInt();
        const auto linesText = [d](int a, int b) {           // wiersze a…b−1 razem z końcami wierszy
            if (a >= b)
                return QString();
            const QTextBlock x = d->findBlockByNumber(a), y = d->findBlockByNumber(b);
            QTextCursor c(d);
            c.setPosition(x.position());
            c.setPosition(y.position(), QTextCursor::KeepAnchor);
            return c.selectedText().replace(QChar::ParagraphSeparator, QLatin1Char('\n'));
        };
        const QString oursText = linesText(sl + 1, bl >= 0 ? bl : ml), theirsText = linesText(ml + 1, el);
        const QString result = choice == QLatin1String("ours") ? oursText : choice == QLatin1String("theirs") ? theirsText : oursText + theirsText;
        const QTextBlock first = d->findBlockByNumber(sl), last = d->findBlockByNumber(el);
        QTextCursor cur(d);
        cur.beginEditBlock();
        cur.setPosition(first.position());
        // Do końca wiersza >>>>>>> razem z jego końcem (jeśli nie ostatni)
        cur.setPosition(last.next().isValid() ? last.next().position() : last.position() + last.length() - 1, QTextCursor::KeepAnchor);
        cur.insertText(result);
        cur.endEditBlock();
        return true;
    }
    return false;
}

QVariantList TextOps::multiEdit(QQuickTextDocument *doc, const QVariantList &ranges, const QStringList &texts, int caretOffset)
{
    if (!doc || !doc->textDocument() || ranges.isEmpty())
        return {};
    QTextDocument *d = doc->textDocument();
    const int maxPos = d->characterCount() - 1;
    struct R { int a, b, i; };
    QList<R> list;
    for (int i = 0; i < ranges.size(); ++i) {
        const QVariantMap m = ranges.at(i).toMap();
        const int a = std::clamp(m.value(QStringLiteral("a")).toInt(), 0, maxPos), b = std::clamp(m.value(QStringLiteral("b")).toInt(), 0, maxPos);
        list.append({std::min(a, b), std::max(a, b), i});
    }
    std::sort(list.begin(), list.end(), [](const R &x, const R &y) { return x.a < y.a; });
    // Nakładające się zakresy (dwa kursory w tym samym miejscu) łączą się w jeden
    QList<R> merged;
    for (const R &r : std::as_const(list)) {
        if (!merged.isEmpty() && r.a < merged.last().b)
            merged.last().b = std::max(merged.last().b, r.b);
        else if (!merged.isEmpty() && r.a == merged.last().a && r.b == merged.last().b)
            continue;
        else
            merged.append(r);
    }
    // Nowe pozycje — po kolei, z przesunięciem od wcześniejszych zmian
    QVariantList carets;
    int delta = 0;
    for (const R &r : std::as_const(merged)) {
        const QString &t = texts.value(r.i, texts.value(0));
        carets << QVariantMap{{QStringLiteral("p"), r.a + delta + (caretOffset < 0 ? int(t.size()) : std::min(caretOffset, int(t.size())))},
                              {QStringLiteral("i"), r.i}};
        delta += int(t.size()) - (r.b - r.a);
    }
    QTextCursor c(d);
    c.beginEditBlock();
    for (int k = int(merged.size()) - 1; k >= 0; --k) {
        const R &r = merged.at(k);
        c.setPosition(r.a);
        c.setPosition(r.b, QTextCursor::KeepAnchor);
        c.insertText(texts.value(r.i, texts.value(0)));
    }
    c.endEditBlock();
    return carets;
}

int TextOps::findNext(QQuickTextDocument *doc, const QString &needle, int from, bool wholeWord) const
{
    if (!doc || !doc->textDocument() || needle.isEmpty())
        return -1;
    const QString text = doc->textDocument()->toPlainText();
    const auto isWord = [](QChar ch) { return ch.isLetterOrNumber() || ch == QLatin1Char('_'); };
    for (int pass = 0; pass < 2; ++pass) {
        int i = int(text.indexOf(needle, pass == 0 ? from : 0));
        while (i >= 0 && (pass == 0 || i < from)) {
            const bool ok = !wholeWord || ((i == 0 || !isWord(text.at(i - 1))) && (i + needle.size() >= text.size() || !isWord(text.at(i + needle.size()))));
            if (ok)
                return i;
            i = int(text.indexOf(needle, i + 1));
        }
    }
    return -1;
}

QVariantList TextOps::findAll(QQuickTextDocument *doc, const QString &needle, bool wholeWord) const
{
    QVariantList out;
    if (!doc || !doc->textDocument() || needle.isEmpty())
        return out;
    const QString text = doc->textDocument()->toPlainText();
    const auto isWord = [](QChar ch) { return ch.isLetterOrNumber() || ch == QLatin1Char('_'); };
    for (int i = int(text.indexOf(needle)); i >= 0 && out.size() < 5000; i = int(text.indexOf(needle, i + needle.size()))) {
        if (!wholeWord || ((i == 0 || !isWord(text.at(i - 1))) && (i + needle.size() >= text.size() || !isWord(text.at(i + needle.size())))))
            out << i;
    }
    return out;
}

int TextOps::replaceAll(QQuickTextDocument *doc, const QString &query, bool matchCase, bool wholeWord, bool regex, const QString &replacement)
{
    if (!doc || !doc->textDocument() || query.isEmpty())
        return 0;
    QTextDocument *d = doc->textDocument();
    const QString text = d->toPlainText();
    const QRegularExpression re = searchRegex(query, matchCase, wholeWord, regex);
    struct R { int a, b; QString t; };
    QList<R> list;
    auto it = re.globalMatch(text);
    while (it.hasNext()) {
        const QRegularExpressionMatch m = it.next();
        if (m.capturedLength())
            list.append({int(m.capturedStart()), int(m.capturedEnd()), expandReplacement(m, replacement, regex)});
    }
    if (list.isEmpty())
        return 0;
    QTextCursor c(d);
    c.beginEditBlock();
    for (int i = int(list.size()) - 1; i >= 0; --i) {
        c.setPosition(list[i].a);
        c.setPosition(list[i].b, QTextCursor::KeepAnchor);
        c.insertText(list[i].t);
    }
    c.endEditBlock();
    return int(list.size());
}

bool TextOps::replaceAt(QQuickTextDocument *doc, int line, int col, const QString &query, bool matchCase, bool wholeWord, bool regex,
                        const QString &replacement)
{
    if (!doc || !doc->textDocument() || query.isEmpty())
        return false;
    QTextDocument *d = doc->textDocument();
    const QTextBlock b = d->findBlockByNumber(line);
    if (!b.isValid())
        return false;
    // Trafienie musi zaczynać się dokładnie tam, gdzie pokazał wynik szukania (wiersz mógł się zmienić)
    const QRegularExpression re = searchRegex(query, matchCase, wholeWord, regex);
    const QRegularExpressionMatch m = re.match(b.text(), col);
    if (!m.hasMatch() || m.capturedStart() != col || !m.capturedLength())
        return false;
    QTextCursor c(d);
    c.setPosition(b.position() + col);
    c.setPosition(b.position() + int(m.capturedEnd()), QTextCursor::KeepAnchor);
    c.insertText(expandReplacement(m, replacement, regex));
    return true;
}

namespace {

int indentOf(const QString &t)
{
    int n = 0;
    for (QChar c : t) {
        if (c == QLatin1Char(' '))
            ++n;
        else if (c == QLatin1Char('\t'))
            n += 4;
        else
            break;
    }
    return n;
}

// Zakres od wiersza line: kolejne wiersze z większym wcięciem (puste nie przerywają); −1 — nie da się zwinąć
int foldEnd(QTextDocument *d, int line)
{
    const QTextBlock b = d->findBlockByNumber(line);
    if (!b.isValid() || b.text().trimmed().isEmpty())
        return -1;
    // Klamra w osobnym wierszu (styl C/C++): nagłówkiem jest wiersz nad nią, zwija się klamra i treść
    const QTextBlock n = b.next();
    if (n.isValid() && n.text().trimmed() == QLatin1String("{") && indentOf(n.text()) == indentOf(b.text())) {
        const int inner = foldEnd(d, n.blockNumber());
        return inner > 0 ? inner : -1;
    }
    const int base = indentOf(b.text());
    int end = -1;
    for (QTextBlock n = b.next(); n.isValid(); n = n.next()) {
        const QString t = n.text();
        if (t.trimmed().isEmpty())
            continue;
        if (indentOf(t) <= base)
            break;
        end = n.blockNumber();
    }
    return end;
}

void relayout(QTextDocument *d, const QTextBlock &from, const QTextBlock &to)
{
    const int a = from.position(), b = to.position() + to.length();
    d->markContentsDirty(a, b - a);
    // TextEdit przebudowuje swoje węzły tekstu tylko po contentsChange — bez zmiany treści
    Q_EMIT d->contentsChange(a, b - a, b - a);
}

} // namespace

QVariantList TextOps::foldRanges(QQuickTextDocument *doc) const
{
    if (!doc || !doc->textDocument())
        return {};
    QTextDocument *d = doc->textDocument();
    if (d->blockCount() > 20000)
        return {};
    // Jedno przejście ze stosem wcięć zamiast szukania końca od każdego wiersza
    QVariantList out;
    struct Open { int line, indent; };
    QList<Open> stack;
    int lastNonEmpty = -1;
    for (QTextBlock b = d->begin(); b.isValid(); b = b.next()) {
        const QString t = b.text();
        if (t.trimmed().isEmpty())
            continue;
        const int ind = indentOf(t);
        while (!stack.isEmpty() && ind <= stack.last().indent) {
            const Open o = stack.takeLast();
            if (lastNonEmpty > o.line)
                out << QVariantMap{{QStringLiteral("start"), o.line}, {QStringLiteral("end"), lastNonEmpty}};
        }
        stack.append({b.blockNumber(), ind});
        lastNonEmpty = b.blockNumber();
    }
    while (!stack.isEmpty()) {
        const Open o = stack.takeLast();
        if (lastNonEmpty > o.line)
            out << QVariantMap{{QStringLiteral("start"), o.line}, {QStringLiteral("end"), lastNonEmpty}};
    }
    // Blok zaczynający się samą klamrą — nagłówkiem jest wiersz nad nią (jak w foldEnd)
    for (QVariant &v : out) {
        QVariantMap m = v.toMap();
        const QTextBlock b = d->findBlockByNumber(m.value(QStringLiteral("start")).toInt());
        const QTextBlock p = b.previous();
        if (b.text().trimmed() == QLatin1String("{") && p.isValid() && !p.text().trimmed().isEmpty() && indentOf(p.text()) == indentOf(b.text())) {
            m.insert(QStringLiteral("start"), p.blockNumber());
            v = m;
        }
    }
    std::sort(out.begin(), out.end(), [](const QVariant &a, const QVariant &b) {
        return a.toMap().value(QStringLiteral("start")).toInt() < b.toMap().value(QStringLiteral("start")).toInt();
    });
    return out;
}

QVariantList TextOps::foldedLines(QQuickTextDocument *doc) const
{
    QVariantList out;
    if (!doc || !doc->textDocument())
        return out;
    QTextDocument *d = doc->textDocument();
    for (QTextBlock b = d->begin(); b.isValid(); b = b.next())
        if (b.isVisible() && b.next().isValid() && !b.next().isVisible())
            out << b.blockNumber();
    return out;
}

bool TextOps::setFolded(QQuickTextDocument *doc, int line, bool folded)
{
    if (!doc || !doc->textDocument())
        return false;
    QTextDocument *d = doc->textDocument();
    const int end = foldEnd(d, line);
    if (end < 0)
        return false;
    const QTextBlock first = d->findBlockByNumber(line + 1), last = d->findBlockByNumber(end);
    for (QTextBlock b = first; b.isValid() && b.blockNumber() <= end; b = b.next())
        b.setVisible(!folded);
    // Rozwinięcie zostawia zwinięte bloki wewnątrz rozwiniętego (jak w VS Code) — tu prościej: wszystko widoczne
    relayout(d, first, last);
    return true;
}

void TextOps::unfoldAll(QQuickTextDocument *doc)
{
    if (!doc || !doc->textDocument())
        return;
    QTextDocument *d = doc->textDocument();
    bool any = false;
    for (QTextBlock b = d->begin(); b.isValid(); b = b.next())
        if (!b.isVisible()) {
            b.setVisible(true);
            any = true;
        }
    if (any)
        relayout(d, d->begin(), d->lastBlock());
}

void TextOps::foldAll(QQuickTextDocument *doc)
{
    if (!doc || !doc->textDocument())
        return;
    QTextDocument *d = doc->textDocument();
    // Zwija bloki najwyższego poziomu wewnątrz pliku (pierwszy poziom zagnieżdżenia), żeby był zarys
    const QVariantList ranges = foldRanges(doc);
    int minIndent = INT_MAX;
    for (const QVariant &v : ranges)
        minIndent = std::min(minIndent, indentOf(d->findBlockByNumber(v.toMap().value(QStringLiteral("start")).toInt()).text()));
    for (const QVariant &v : ranges) {
        const int s = v.toMap().value(QStringLiteral("start")).toInt();
        const int ind = indentOf(d->findBlockByNumber(s).text());
        // Najpłytsze bloki zostają otwarte, jeśli jest tylko jeden (np. cała klasa / główny obiekt QML)
        const bool single = std::count_if(ranges.begin(), ranges.end(), [&](const QVariant &r) {
            return indentOf(d->findBlockByNumber(r.toMap().value(QStringLiteral("start")).toInt()).text()) == minIndent; }) == 1;
        if (ind == minIndent && single)
            continue;
        const int e = v.toMap().value(QStringLiteral("end")).toInt();
        for (QTextBlock b = d->findBlockByNumber(s + 1); b.isValid() && b.blockNumber() <= e; b = b.next())
            b.setVisible(false);
    }
    relayout(d, d->begin(), d->lastBlock());
}

bool TextOps::repairFolds(QQuickTextDocument *doc)
{
    if (!doc || !doc->textDocument())
        return false;
    QTextDocument *d = doc->textDocument();
    bool changed = false;
    int coverEnd = -1;
    for (QTextBlock b = d->begin(); b.isValid(); b = b.next()) {
        const int n = b.blockNumber();
        if (b.isVisible()) {
            if (n > coverEnd && b.next().isValid() && !b.next().isVisible())
                coverEnd = foldEnd(d, n);
            continue;
        }
        if (n > coverEnd) {
            b.setVisible(true);
            changed = true;
        }
    }
    if (changed)
        relayout(d, d->begin(), d->lastBlock());
    return changed;
}

bool TextOps::lineVisible(QQuickTextDocument *doc, int line) const
{
    return doc && doc->textDocument() && doc->textDocument()->findBlockByNumber(line).isVisible();
}

void TextOps::revealLine(QQuickTextDocument *doc, int line)
{
    if (!doc || !doc->textDocument())
        return;
    QTextDocument *d = doc->textDocument();
    for (int guard = 0; guard < 50 && !d->findBlockByNumber(line).isVisible(); ++guard) {
        QTextBlock h = d->findBlockByNumber(line);
        while (h.isValid() && !h.isVisible())
            h = h.previous();
        if (!h.isValid() || !setFolded(doc, h.blockNumber(), false))
            break;
    }
}
