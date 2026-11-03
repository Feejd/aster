#pragma once

#include <QRegularExpression>
#include <QString>

// Wspólne dla szukania i zamiany w projekcie (Project) oraz zamiany w otwartych kartach (TextOps):
// wyrażenie z opcji pola szukania i podstawianie grup $0…$9 w tekście zamiany.

inline QRegularExpression searchRegex(const QString &query, bool matchCase, bool wholeWord, bool regex)
{
    QString pattern = regex ? query : QRegularExpression::escape(query);
    if (wholeWord)
        pattern = QStringLiteral("\\b(?:") + pattern + QStringLiteral(")\\b");
    // Wieloliniowo: ^ i $ jak przy szukaniu wiersz po wierszu
    return QRegularExpression(pattern, (matchCase ? QRegularExpression::NoPatternOption : QRegularExpression::CaseInsensitiveOption)
                                           | QRegularExpression::UseUnicodePropertiesOption | QRegularExpression::MultilineOption);
}

// „$1” → pierwsza grupa, „$$” → „$”; bez wyrażenia regularnego tekst zostaje dosłowny
inline QString expandReplacement(const QRegularExpressionMatch &m, const QString &replacement, bool regex)
{
    if (!regex || !replacement.contains(QLatin1Char('$')))
        return replacement;
    QString out;
    for (int i = 0; i < replacement.size(); ++i) {
        const QChar ch = replacement.at(i);
        if (ch == QLatin1Char('$') && i + 1 < replacement.size()) {
            const QChar n = replacement.at(i + 1);
            if (n == QLatin1Char('$')) {
                out += QLatin1Char('$');
                ++i;
                continue;
            }
            if (n.isDigit()) {
                out += m.captured(n.digitValue());
                ++i;
                continue;
            }
        }
        out += ch;
    }
    return out;
}

// Zamienia wszystkie trafienia w tekście; zwraca ich liczbę
inline int replaceInText(QString &text, const QRegularExpression &re, const QString &replacement, bool regex)
{
    QString out;
    int last = 0, count = 0;
    auto it = re.globalMatch(text);
    while (it.hasNext()) {
        const QRegularExpressionMatch m = it.next();
        if (m.capturedLength() == 0)
            continue;
        out += QStringView(text).mid(last, m.capturedStart() - last);
        out += expandReplacement(m, replacement, regex);
        last = int(m.capturedEnd());
        ++count;
    }
    if (count) {
        out += QStringView(text).mid(last);
        text = out;
    }
    return count;
}
