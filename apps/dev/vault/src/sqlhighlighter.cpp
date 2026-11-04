#include "sqlhighlighter.h"

#include <QTextDocument>

namespace {
const QSet<QString> &keywordSet()
{
    static const QSet<QString> k = [] {
        QSet<QString> s;
        for (const QString &w : QStringLiteral(
                 "SELECT FROM WHERE AND OR NOT NULL IS IN LIKE ILIKE BETWEEN EXISTS JOIN LEFT RIGHT INNER OUTER FULL CROSS NATURAL ON USING "
                 "GROUP BY ORDER ASC DESC HAVING LIMIT OFFSET FETCH FIRST NEXT ROWS ONLY DISTINCT AS CASE WHEN THEN ELSE END UNION ALL "
                 "INTERSECT EXCEPT INSERT INTO VALUES UPDATE SET DELETE CREATE TABLE VIEW INDEX UNIQUE PRIMARY KEY FOREIGN REFERENCES "
                 "DEFAULT CHECK CONSTRAINT ALTER ADD COLUMN DROP RENAME TO TRUNCATE BEGIN COMMIT ROLLBACK TRANSACTION SAVEPOINT WITH "
                 "RECURSIVE RETURNING EXPLAIN ANALYZE SHOW DESCRIBE PRAGMA IF CASCADE RESTRICT TEMPORARY TEMP TRIGGER FUNCTION PROCEDURE "
                 "RETURNS LANGUAGE REPLACE GRANT REVOKE SCHEMA DATABASE USE OVER PARTITION WINDOW FILTER LATERAL ANY SOME TRUE FALSE "
                 "INTEGER INT SMALLINT BIGINT TEXT VARCHAR CHAR CHARACTER VARYING BOOLEAN BOOL DATE TIME TIMESTAMP TIMESTAMPTZ INTERVAL "
                 "NUMERIC DECIMAL REAL DOUBLE PRECISION FLOAT BLOB BYTEA SERIAL BIGSERIAL JSON JSONB UUID AUTOINCREMENT AUTO_INCREMENT "
                 "UNSIGNED COLLATE ESCAPE CONFLICT DO NOTHING VACUUM ATTACH DETACH WITHOUT ROWID").split(QLatin1Char(' ')))
            s.insert(w);
        return s;
    }();
    return k;
}
} // namespace

SqlRules::SqlRules(QTextDocument *doc)
    : QSyntaxHighlighter(doc)
{
}

void SqlRules::highlightBlock(const QString &text)
{
    // Barwy jak w Aster Code (jasny / ciemny motyw)
    QTextCharFormat kw, fn, str, num, com, tab, ident;
    kw.setForeground(QColor(dark ? QStringLiteral("#C4A7FF") : QStringLiteral("#7C3AED")));
    kw.setFontWeight(QFont::DemiBold);
    fn.setForeground(QColor(dark ? QStringLiteral("#7DD3FC") : QStringLiteral("#0369A1")));
    str.setForeground(QColor(dark ? QStringLiteral("#86EFAC") : QStringLiteral("#15803D")));
    num.setForeground(QColor(dark ? QStringLiteral("#FDBA74") : QStringLiteral("#C2410C")));
    com.setForeground(QColor(dark ? QStringLiteral("#7B8494") : QStringLiteral("#8A93A3")));
    com.setFontItalic(true);
    tab.setForeground(QColor(dark ? QStringLiteral("#F9A8D4") : QStringLiteral("#BE185D")));
    ident.setForeground(QColor(dark ? QStringLiteral("#FDE68A") : QStringLiteral("#A16207")));

    const int n = int(text.size());
    int i = 0;
    // Stan 1 — wewnątrz komentarza /* */ z poprzedniego wiersza, 2 — wewnątrz napisu '…'
    if (previousBlockState() == 1 || previousBlockState() == 2) {
        const bool comment = previousBlockState() == 1;
        const int end = comment ? int(text.indexOf(QLatin1String("*/"))) : int(text.indexOf(QLatin1Char('\'')));
        if (end < 0) {
            setFormat(0, n, comment ? com : str);
            setCurrentBlockState(previousBlockState());
            return;
        }
        i = end + (comment ? 2 : 1);
        setFormat(0, i, comment ? com : str);
    }
    setCurrentBlockState(0);
    while (i < n) {
        const QChar c = text.at(i);
        const QChar next = i + 1 < n ? text.at(i + 1) : QChar();
        if (c == QLatin1Char('-') && next == QLatin1Char('-')) {
            setFormat(i, n - i, com);
            return;
        }
        if (c == QLatin1Char('/') && next == QLatin1Char('*')) {
            const int end = int(text.indexOf(QLatin1String("*/"), i + 2));
            if (end < 0) {
                setFormat(i, n - i, com);
                setCurrentBlockState(1);
                return;
            }
            setFormat(i, end + 2 - i, com);
            i = end + 2;
            continue;
        }
        if (c == QLatin1Char('\'')) {
            int j = i + 1;
            while (j < n) {
                if (text.at(j) == QLatin1Char('\'')) {
                    if (j + 1 < n && text.at(j + 1) == QLatin1Char('\'')) { j += 2; continue; }
                    break;
                }
                ++j;
            }
            if (j >= n) {
                setFormat(i, n - i, str);
                setCurrentBlockState(2);
                return;
            }
            setFormat(i, j + 1 - i, str);
            i = j + 1;
            continue;
        }
        if (c == QLatin1Char('"') || c == QLatin1Char('`')) {
            int j = int(text.indexOf(c, i + 1));
            if (j < 0)
                j = n - 1;
            const QString name = text.mid(i + 1, j - i - 1);
            setFormat(i, j + 1 - i, tables.contains(name) ? tab : ident);
            i = j + 1;
            continue;
        }
        if (c.isDigit() && (i == 0 || !(text.at(i - 1).isLetterOrNumber() || text.at(i - 1) == QLatin1Char('_')))) {
            int j = i;
            while (j < n && (text.at(j).isDigit() || text.at(j) == QLatin1Char('.')))
                ++j;
            setFormat(i, j - i, num);
            i = j;
            continue;
        }
        if (c.isLetter() || c == QLatin1Char('_')) {
            int j = i;
            while (j < n && (text.at(j).isLetterOrNumber() || text.at(j) == QLatin1Char('_') || text.at(j) == QLatin1Char('$')))
                ++j;
            const QString w = text.mid(i, j - i);
            int k = j;
            while (k < n && text.at(k) == QLatin1Char(' '))
                ++k;
            if (keywordSet().contains(w.toUpper()))
                setFormat(i, j - i, kw);
            else if (tables.contains(w))
                setFormat(i, j - i, tab);
            else if (k < n && text.at(k) == QLatin1Char('('))
                setFormat(i, j - i, fn);
            i = j;
            continue;
        }
        ++i;
    }
}

void SqlHighlighter::setDocument(QQuickTextDocument *d)
{
    if (d == m_doc)
        return;
    m_doc = d;
    delete m_rules;
    m_rules = d ? new SqlRules(d->textDocument()) : nullptr;
    apply();
    Q_EMIT changed();
}

void SqlHighlighter::setDark(bool d)
{
    if (d == m_dark)
        return;
    m_dark = d;
    apply();
    Q_EMIT changed();
}

void SqlHighlighter::setTables(const QStringList &t)
{
    if (t == m_tables)
        return;
    m_tables = t;
    apply();
    Q_EMIT changed();
}

void SqlHighlighter::apply()
{
    if (!m_rules)
        return;
    m_rules->dark = m_dark;
    m_rules->tables.clear();
    for (const QString &t : std::as_const(m_tables)) {
        m_rules->tables.insert(t);
        const int dot = int(t.indexOf(QLatin1Char('.')));
        if (dot > 0)
            m_rules->tables.insert(t.mid(dot + 1));
    }
    m_rules->rehighlight();
}
