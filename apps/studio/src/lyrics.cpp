#include "lyrics.h"

#include <QHash>
#include <numeric>

namespace Lyrics {

namespace {

bool vowel(QChar c)
{
    return QStringLiteral("aąeęioóuyáéíúäöü").contains(c);
}

// Sylaby: pozycje samogłosek; „i” przed samogłoską tylko zmiękcza („nie”, „się”, „miasto”)
QList<int> nuclei(const QString &s, int from, int to)
{
    QList<int> out;
    for (int i = from; i < to; ++i) {
        if (!vowel(s[i]))
            continue;
        if (s[i] == u'i' && i + 1 < to && vowel(s[i + 1]) && i > from && !vowel(s[i - 1]))
            continue;
        out << i;
    }
    return out;
}

// Brzmienie końcówki: pisownia sprowadzona do wymowy
QString sound(QString e)
{
    e.remove(QLatin1Char(' '));
    e.replace(QStringLiteral("ó"), QStringLiteral("u"));
    e.replace(QStringLiteral("rz"), QStringLiteral("ż"));
    e.replace(QStringLiteral("ch"), QStringLiteral("h"));
    e.replace(QStringLiteral("dż"), QStringLiteral("cz"));
    if (!e.isEmpty()) {
        static const QHash<QChar, QChar> devoice{{u'b', u'p'}, {u'd', u't'}, {u'g', u'k'}, {u'w', u'f'},
                                                 {u'z', u's'}, {u'ż', u'š'}, {u'ź', u'ś'}};
        const QChar last = e.back();
        if (devoice.contains(last))
            e.back() = devoice.value(last);
        if (e.endsWith(u'š'))
            e.replace(e.size() - 1, 1, QStringLiteral("sz"));
    }
    return e;
}

// Same samogłoski końcówki (asonans): ą≈o, ę≈e, y≈i
QString vowels(const QString &e)
{
    QString v;
    for (int i = 0; i < e.size(); ++i) {
        const QChar c = e[i];
        if (!vowel(c) || (c == u'i' && i + 1 < e.size() && vowel(e[i + 1]) && i > 0 && !vowel(e[i - 1])))
            continue;
        v += c == u'ą' ? u'o' : c == u'ę' ? u'e' : c == u'y' ? u'i' : c == u'ó' ? u'u' : c;
    }
    return v;
}

struct Ending
{
    int at = -1;
    int lastAt = -1;        // ostatnia sylaba (rym męski: „bit” — „kit”)
    QString exact, vow, last;
    QChar tail;             // ostatni dźwięk (samogłoska albo spółgłoska po ubezdźwięcznieniu)
};

Ending ending(const QString &text)
{
    const QString s = text.toLower();
    // Dwa ostatnie słowa (ciągi liter)
    struct Word { int a, b; };
    QList<Word> words;
    for (int i = s.size() - 1; i >= 0 && words.size() < 2;) {
        if (!s[i].isLetter()) {
            --i;
            continue;
        }
        const int b = i + 1;
        while (i >= 0 && s[i].isLetter())
            --i;
        words.prepend({i + 1, b});
    }
    Ending e;
    if (words.isEmpty())
        return e;
    const Word last = words.last();
    const QList<int> n1 = nuclei(s, last.a, last.b);
    if (n1.size() >= 2) {
        e.at = n1[n1.size() - 2];
    } else if (words.size() == 2 && n1.size() == 1) {
        // Słowo jednosylabowe: końcówka zaczyna się w poprzednim („to ja” — „boja”)
        const QList<int> n0 = nuclei(s, words[0].a, words[0].b);
        e.at = n0.isEmpty() ? n1[0] : n0.last();
    } else if (!n1.isEmpty()) {
        e.at = n1[0];
    } else {
        return e;
    }
    if (!n1.isEmpty()) {
        e.lastAt = n1.last();
        QString tail;
        for (int i = e.lastAt; i < last.b; ++i)
            tail += s[i];
        e.last = sound(tail);
    }
    QString raw;
    for (int i = e.at; i < last.b; ++i)
        if (s[i].isLetter())
            raw += s[i];
    e.exact = sound(raw);
    e.vow = vowels(raw);
    e.tail = e.exact.isEmpty() ? QChar() : e.exact.back();
    if (vowel(e.tail))
        e.tail = e.vow.isEmpty() ? e.tail : e.vow.back();
    return e;
}

int find(QList<int> &p, int x)
{
    while (p[x] != x)
        x = p[x] = p[p[x]];
    return x;
}

}

QList<Line> analyze(const QStringList &lines)
{
    QList<Line> out(lines.size());
    QList<int> content;                     // numery wersów (bez nagłówków i pustych)
    QList<Ending> ends;
    for (int i = 0; i < lines.size(); ++i) {
        const QString t = lines[i].trimmed();
        if (t.isEmpty())
            continue;
        // Nagłówek części: [Refren], (Zwrotka 2), „Refren:”, „#hook”
        const bool head = (t.startsWith(u'[') && t.endsWith(u']')) || (t.startsWith(u'(') && t.endsWith(u')'))
                          || t.startsWith(u'#') || (t.endsWith(u':') && t.size() <= 30);
        out[i].kind = head ? Kind::Head : Kind::Line;
        if (head)
            continue;
        content << i;
        ends << ending(lines[i]);
    }
    const int n = int(content.size());
    QList<int> parent(n);
    std::iota(parent.begin(), parent.end(), 0);
    QList<bool> paired(n, false), exact(n, false), male(n, false);
    for (int a = 0; a < n; ++a) {
        for (int b = a + 1; b < n && b <= a + 3; ++b) {
            const Ending &x = ends[a], &y = ends[b];
            if (x.at < 0 || y.at < 0)
                continue;
            const bool same = x.exact == y.exact && x.exact.size() >= 2;
            const bool assonance = !x.vow.isEmpty() && x.vow == y.vow && x.tail == y.tail && (x.vow.size() >= 2 || same);
            const bool masculine = !same && !assonance && x.last.size() >= 2 && x.last == y.last;
            if (!same && !assonance && !masculine)
                continue;
            if (masculine)
                male[a] = male[b] = true;
            parent[find(parent, a)] = find(parent, b);
            paired[a] = paired[b] = true;
            if (same)
                exact[a] = exact[b] = true;
        }
    }
    QHash<int, int> group;
    for (int k = 0; k < n; ++k) {
        if (!paired[k])
            continue;
        const int root = find(parent, k);
        if (!group.contains(root))
            group.insert(root, int(group.size()));
        Line &l = out[content[k]];
        l.rhyme = group.value(root);
        l.rhymeAt = male[k] && !exact[k] ? ends[k].lastAt : ends[k].at;
        l.exact = exact[k];
    }
    return out;
}

}
