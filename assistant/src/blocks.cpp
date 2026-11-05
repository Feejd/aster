#include "blocks.h"

#include <QRegularExpression>
#include <QStringList>

namespace Blocks {

static QString kindOf(const QString &lang)
{
    const QString l = lang.toLower();
    if (l == QLatin1String("bash") || l == QLatin1String("sh") || l == QLatin1String("shell") || l == QLatin1String("zsh")
        || l == QLatin1String("console"))
        return QStringLiteral("bash");
    if (l == QLatin1String("plik") || l == QLatin1String("file"))
        return QStringLiteral("plik");
    if (l == QLatin1String("zmiana") || l == QLatin1String("edit"))
        return QStringLiteral("zmiana");
    return QStringLiteral("inny");
}

QList<Block> parse(const QString &text)
{
    static const QRegularExpression open(QStringLiteral("^[ \\t]*(`{3,})[ \\t]*([A-Za-z]*)(?:[ \\t]*:[ \\t]*(.*?))?[ \\t]*$"));
    QList<Block> out;
    qsizetype pos = 0;
    Block cur;
    QString fence;
    bool in = false;
    QStringList body;
    while (pos <= text.size()) {
        qsizetype nl = text.indexOf(QLatin1Char('\n'), pos);
        const bool last = nl < 0;
        if (last)
            nl = text.size();
        const QString line = text.mid(pos, nl - pos);
        if (!in) {
            const auto m = open.match(line);
            if (m.hasMatch()) {
                in = true;
                fence = m.captured(1);
                cur = Block();
                cur.kind = kindOf(m.captured(2));
                cur.arg = m.captured(3).trimmed();
                cur.start = pos;
                body.clear();
            }
        } else {
            const QString t = line.trimmed();
            // zamknięcie: tyle samo (albo więcej) samych „`”
            if (t.size() >= fence.size() && !t.isEmpty() && t.count(QLatin1Char('`')) == t.size()) {
                cur.body = body.join(QLatin1Char('\n'));
                cur.end = last ? nl : nl + 1;
                cur.closed = true;
                out << cur;
                in = false;
            } else {
                body << line;
            }
        }
        if (last)
            break;
        pos = nl + 1;
    }
    if (in) {
        cur.body = body.join(QLatin1Char('\n'));
        cur.end = text.size();
        out << cur;
    }
    return out;
}

QString command(const QList<Block> &blocks)
{
    for (const Block &b : blocks) {
        if (b.kind != QLatin1String("bash") || !b.closed)
            continue;
        QStringList lines;
        for (QString l : b.body.split(QLatin1Char('\n'))) {
            if (l.startsWith(QLatin1String("$ ")))
                l = l.mid(2);
            if (!l.trimmed().isEmpty() && !l.trimmed().startsWith(QLatin1Char('#')))
                lines << l;
        }
        const QString c = lines.join(QLatin1Char('\n')).trimmed();
        if (!c.isEmpty())
            return c;
    }
    return {};
}

static QString shortPath(const QString &p)
{
    return p.isEmpty() ? QStringLiteral("plik") : p;
}

QString display(const QString &text)
{
    const QList<Block> blocks = parse(text);
    QString out;
    qsizetype pos = 0;
    for (const Block &b : blocks) {
        out += text.mid(pos, b.start - pos);
        if (b.kind == QLatin1String("plik"))
            out += (b.closed ? QStringLiteral("_Plik %1_\n") : QStringLiteral("_Piszę plik %1…_\n")).arg(shortPath(b.arg));
        else if (b.kind == QLatin1String("zmiana"))
            out += (b.closed ? QStringLiteral("_Zmiana w %1_\n") : QStringLiteral("_Zmieniam %1…_\n")).arg(shortPath(b.arg));
        else if (b.kind != QLatin1String("bash"))
            out += text.mid(b.start, b.end - b.start);
        pos = b.end;
    }
    out += text.mid(pos);
    // kilka plików pod rząd — bez pustych wierszy między nimi
    out.replace(QRegularExpression(QStringLiteral("\\n{3,}")), QStringLiteral("\n\n"));
    return out.trimmed();
}

QString compact(const QString &text)
{
    const QList<Block> blocks = parse(text);
    QString out;
    qsizetype pos = 0;
    for (const Block &b : blocks) {
        out += text.mid(pos, b.start - pos);
        if ((b.kind == QLatin1String("plik") || b.kind == QLatin1String("zmiana")) && b.closed) {
            const int lines = int(b.body.count(QLatin1Char('\n'))) + 1;
            out += QStringLiteral("```%1:%2\n[… %3 wierszy — już zapisane; przeczytaj plik, jeśli potrzebujesz …]\n```\n")
                       .arg(b.kind, b.arg).arg(lines);
        } else {
            out += text.mid(b.start, b.end - b.start);
        }
        pos = b.end;
    }
    out += text.mid(pos);
    return out;
}

QList<Hunk> hunks(const QString &body)
{
    QList<Hunk> out;
    enum { None, Before, After } state = None;
    Hunk cur;
    QStringList before, after;
    for (const QString &line : body.split(QLatin1Char('\n'))) {
        const QString t = line.trimmed();
        if (t.startsWith(QLatin1String("<<<<<<<"))) {
            state = Before;
            before.clear();
            after.clear();
        } else if (t.startsWith(QLatin1String("=======")) && state == Before) {
            state = After;
        } else if (t.startsWith(QLatin1String(">>>>>>>")) && state == After) {
            out << Hunk{before.join(QLatin1Char('\n')), after.join(QLatin1Char('\n'))};
            state = None;
        } else if (state == Before) {
            before << line;
        } else if (state == After) {
            after << line;
        }
    }
    return out;
}

} // namespace Blocks
