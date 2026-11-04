#include "highlighter.h"

#include <QRegularExpression>
#include <QTextDocument>

class SyntaxColors::Impl : public QSyntaxHighlighter
{
public:
    Impl(QTextDocument *doc, SyntaxColors *owner)
        : QSyntaxHighlighter(doc)
        , o(owner)
    {
    }
    SyntaxColors *o;

protected:
    void highlightBlock(const QString &text) override
    {
        // Bardzo długie wiersze (zminifikowany JSON) — bez kolorów, żeby pisanie nie zwalniało
        if (text.size() > 20000)
            return;
        const bool dark = o->m_dark;
        QTextCharFormat key, str, num, lit, var, punct;
        key.setForeground(dark ? QColor(0x8C, 0xB4, 0xFF) : QColor(0x1F, 0x4F, 0xC8));
        str.setForeground(dark ? QColor(0x9F, 0xE0, 0x9A) : QColor(0x1A, 0x7F, 0x37));
        num.setForeground(dark ? QColor(0xF5, 0xB7, 0x6A) : QColor(0xB3, 0x5A, 0x00));
        lit.setForeground(dark ? QColor(0xE3, 0x9C, 0xF5) : QColor(0x8E, 0x2B, 0xB8));
        punct.setForeground(dark ? QColor(0x80, 0x88, 0x96) : QColor(0x8A, 0x90, 0x9C));
        var.setForeground(dark ? o->m_accent.lighter(150) : o->m_accent);
        var.setFontWeight(QFont::DemiBold);
        if (o->m_json) {
            static const QRegularExpression strings(QStringLiteral("\"(?:[^\"\\\\]|\\\\.)*\"(\\s*:)?"));
            static const QRegularExpression numbers(QStringLiteral("(?<![\\w.\"])-?\\d+(?:\\.\\d+)?(?:[eE][+-]?\\d+)?\\b"));
            static const QRegularExpression literals(QStringLiteral("\\b(?:true|false|null)\\b"));
            static const QRegularExpression puncts(QStringLiteral("[{}\\[\\],:]"));
            for (auto it = puncts.globalMatch(text); it.hasNext();) {
                const auto m = it.next();
                setFormat(int(m.capturedStart()), int(m.capturedLength()), punct);
            }
            for (auto it = numbers.globalMatch(text); it.hasNext();) {
                const auto m = it.next();
                setFormat(int(m.capturedStart()), int(m.capturedLength()), num);
            }
            for (auto it = literals.globalMatch(text); it.hasNext();) {
                const auto m = it.next();
                setFormat(int(m.capturedStart()), int(m.capturedLength()), lit);
            }
            for (auto it = strings.globalMatch(text); it.hasNext();) {
                const auto m = it.next();
                const bool isKey = m.capturedLength(1) > 0;
                const int len = int(m.capturedLength() - m.capturedLength(1));
                setFormat(int(m.capturedStart()), len, isKey ? key : str);
            }
        }
        QTextCharFormat unknown = var;
        unknown.setForeground(dark ? QColor(0xFF, 0x8A, 0x80) : QColor(0xC6, 0x28, 0x28));
        static const QRegularExpression vars(QStringLiteral("\\{\\{\\s*([^{}\\s]+)\\s*\\}\\}"));
        for (auto it = vars.globalMatch(text); it.hasNext();) {
            const auto m = it.next();
            const QString name = m.captured(1);
            const bool ok = o->m_known.isEmpty() || name.startsWith(QLatin1Char('$')) || o->m_known.contains(name);
            setFormat(int(m.capturedStart()), int(m.capturedLength()), ok ? var : unknown);
        }
    }
};

SyntaxColors::SyntaxColors(QObject *parent)
    : QObject(parent)
{
}

void SyntaxColors::setDocument(QQuickTextDocument *d)
{
    if (d == m_doc)
        return;
    m_doc = d;
    delete m_impl;
    m_impl = d ? new Impl(d->textDocument(), this) : nullptr;
    Q_EMIT changed();
}

void SyntaxColors::setDark(bool d)
{
    if (d == m_dark)
        return;
    m_dark = d;
    if (m_impl)
        m_impl->rehighlight();
    Q_EMIT changed();
}

void SyntaxColors::setJson(bool j)
{
    if (j == m_json)
        return;
    m_json = j;
    if (m_impl)
        m_impl->rehighlight();
    Q_EMIT changed();
}

void SyntaxColors::setAccent(const QColor &c)
{
    if (c == m_accent)
        return;
    m_accent = c;
    if (m_impl)
        m_impl->rehighlight();
    Q_EMIT changed();
}

void SyntaxColors::setKnown(const QStringList &k)
{
    if (k == m_known)
        return;
    m_known = k;
    if (m_impl)
        m_impl->rehighlight();
    Q_EMIT changed();
}
