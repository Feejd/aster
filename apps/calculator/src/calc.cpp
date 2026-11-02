#include "calc.h"

#include <QClipboard>
#include <QGuiApplication>
#include <QRegularExpression>
#include <QSettings>
#include <cmath>
#include <cstdio>
#include <stdexcept>

namespace {

using Real = long double;

// Stałe w precyzji long double (M_PI to double — sin(30°) dawałby 0,49999999999999998)
constexpr Real Pi = 3.14159265358979323846264338327950288L;
constexpr Real E = 2.71828182845904523536028747135266250L;

struct CalcError : std::runtime_error {
    using std::runtime_error::runtime_error;
};

// Parser zejściowy na tekście z ekranu kalkulatora
class Parser
{
public:
    Parser(const QString &s, bool degrees)
        : m_s(s)
        , m_deg(degrees)
    {
    }

    Real run()
    {
        if (m_s.trimmed().isEmpty())
            return 0;
        Real v = expr();
        skip();
        if (m_i < m_s.size())
            throw CalcError("syntax");
        return v;
    }

private:
    struct Val {
        Real v;
        bool percent = false;
    };

    void skip()
    {
        while (m_i < m_s.size() && m_s.at(m_i).isSpace())
            ++m_i;
    }
    QChar peek()
    {
        skip();
        return m_i < m_s.size() ? m_s.at(m_i) : QChar();
    }
    bool eat(QChar c)
    {
        if (peek() == c) {
            ++m_i;
            return true;
        }
        return false;
    }
    bool eatWord(const char *w)
    {
        skip();
        const QString word = QString::fromLatin1(w);
        if (m_s.mid(m_i, word.size()) == word) {
            m_i += word.size();
            return true;
        }
        return false;
    }
    static bool isMinus(QChar c) { return c == QLatin1Char('-') || c == QChar(0x2212); }

    Real expr()
    {
        Val a = term();
        Real v = a.percent ? a.v : a.v;
        for (;;) {
            const QChar c = peek();
            if (c == QLatin1Char('+') || isMinus(c)) {
                ++m_i;
                const Val b = term();
                // Jak w Windows: 200 + 10% → 200 + 20
                const Real rhs = b.percent ? v * b.v : b.v;
                v = c == QLatin1Char('+') ? v + rhs : v - rhs;
            } else {
                return v;
            }
        }
    }

    Val term()
    {
        Val a = power();
        for (;;) {
            const QChar c = peek();
            if (c == QChar(0x00D7) || c == QLatin1Char('*')) {
                ++m_i;
                a = {a.v * power().v};
            } else if (c == QChar(0x00F7) || c == QLatin1Char('/')) {
                ++m_i;
                const Real d = power().v;
                if (d == 0)
                    throw CalcError("div0");
                a = {a.v / d};
            } else if (startsPrimary()) {
                a = {a.v * power().v};                  // mnożenie domyślne: 2π, 3(4+1), (2)(3)
            } else {
                return a;
            }
        }
    }

    bool startsPrimary()
    {
        const QChar c = peek();
        return c == QLatin1Char('(') || c == QChar(0x03C0) || c == QChar(0x221A) || c.isLetter();
    }

    Val power()
    {
        Val base = unary();
        if (eat(QLatin1Char('^'))) {
            const Real e = power().v;                   // prawostronnie: 2^3^2 = 2^9
            const Real r = std::pow(base.v, e);
            if (std::isnan(r))
                throw CalcError("domain");
            return {r};
        }
        return base;
    }

    Val unary()
    {
        const QChar c = peek();
        if (isMinus(c)) {
            ++m_i;
            Val v = unary();
            return {-v.v, v.percent};
        }
        if (c == QLatin1Char('+')) {
            ++m_i;
            return unary();
        }
        return postfix();
    }

    Val postfix()
    {
        Val v = primary();
        for (;;) {
            if (eat(QLatin1Char('!'))) {
                if (v.v < 0 || v.v > 1754)
                    throw CalcError(v.v < 0 ? "domain" : "overflow");
                if (v.v == std::floor(v.v)) {
                    Real r = 1;
                    for (int k = 2; k <= int(v.v); ++k)
                        r *= k;
                    v = {r};
                } else {
                    v = {std::tgamma(v.v + 1)};
                }
            } else if (eat(QChar(0x00B2))) {
                v = {v.v * v.v};
            } else if (eat(QChar(0x00B3))) {
                v = {v.v * v.v * v.v};
            } else if (eat(QLatin1Char('%'))) {
                v = {v.v / 100, true};
            } else {
                return v;
            }
        }
    }

    Real toRad(Real x) const { return m_deg ? x * Pi / 180 : x; }
    Real fromRad(Real x) const { return m_deg ? x * 180 / Pi : x; }

    Real group()
    {
        // Nawias zamknięty albo niedomknięty (dopisany na końcu wyrażenia)
        Real v = expr();
        eat(QLatin1Char(')'));
        return v;
    }

    Val primary()
    {
        skip();
        if (m_i >= m_s.size())
            throw CalcError("syntax");
        const QChar c = m_s.at(m_i);
        if (c.isDigit() || c == QLatin1Char(',') || c == QLatin1Char('.')) {
            QString num;
            while (m_i < m_s.size()) {
                const QChar d = m_s.at(m_i);
                if (d.isDigit())
                    num += d;
                else if (d == QLatin1Char(',') || d == QLatin1Char('.'))
                    num += QLatin1Char('.');
                else if (d == QChar(0x202F) || d == QChar(0x00A0) || d == QLatin1Char(' '))
                    ;                                   // odstępy tysięcy
                else if ((d == QLatin1Char('e') || d == QLatin1Char('E')) && m_i + 1 < m_s.size()
                         && (m_s.at(m_i + 1).isDigit() || m_s.at(m_i + 1) == QLatin1Char('+') || isMinus(m_s.at(m_i + 1)))) {
                    num += QLatin1Char('e');
                    ++m_i;
                    num += isMinus(m_s.at(m_i)) ? QLatin1Char('-') : m_s.at(m_i);
                } else
                    break;
                ++m_i;
            }
            bool ok = false;
            const Real v = num.toStdString().empty() ? 0 : std::strtold(num.toLatin1().constData(), nullptr);
            ok = num != QLatin1String(".");
            if (!ok)
                throw CalcError("syntax");
            return {v};
        }
        if (eat(QLatin1Char('(')))
            return {group()};
        if (eat(QChar(0x03C0)))
            return {Pi};
        if (eat(QChar(0x221A))) {
            const Real x = eat(QLatin1Char('(')) ? group() : postfix().v;
            if (x < 0)
                throw CalcError("domain");
            return {std::sqrt(x)};
        }
        // Funkcje: najpierw dłuższe nazwy (asin przed sin)
        static const char *names[] = {"asin", "acos", "atan", "sin", "cos", "tan", "ln", "log", "abs", "exp"};
        for (const char *n : names) {
            if (eatWord(n)) {
                const Real x = eat(QLatin1Char('(')) ? group() : postfix().v;
                const QString f = QString::fromLatin1(n);
                Real r = 0;
                if (f == QLatin1String("sin"))
                    r = std::sin(toRad(x));
                else if (f == QLatin1String("cos"))
                    r = std::cos(toRad(x));
                else if (f == QLatin1String("tan")) {
                    if (m_deg && std::fmod(std::fabs(x) - 90, Real(180)) == 0)
                        throw CalcError("domain");
                    r = std::tan(toRad(x));
                } else if (f == QLatin1String("asin") || f == QLatin1String("acos")) {
                    if (x < -1 || x > 1)
                        throw CalcError("domain");
                    r = fromRad(f == QLatin1String("asin") ? std::asin(x) : std::acos(x));
                } else if (f == QLatin1String("atan"))
                    r = fromRad(std::atan(x));
                else if (f == QLatin1String("ln") || f == QLatin1String("log")) {
                    if (x <= 0)
                        throw CalcError("domain");
                    r = f == QLatin1String("ln") ? std::log(x) : std::log10(x);
                } else if (f == QLatin1String("abs"))
                    r = std::fabs(x);
                else
                    r = std::exp(x);
                // sin(180°) to dokładnie 0, nie 1,2e−16
                if (std::fabs(r) < 1e-15L)
                    r = 0;
                return {r};
            }
        }
        if (eat(QLatin1Char('e')))
            return {E};
        throw CalcError("syntax");
    }

    QString m_s;
    bool m_deg;
    int m_i = 0;
};

} // namespace

Calc::Calc(QObject *parent)
    : QObject(parent)
{
    QSettings s;
    m_history = s.value(QStringLiteral("history")).toList();
}

QVariantMap Calc::evaluate(const QString &expression, bool degrees) const
{
    try {
        const Real v = Parser(expression, degrees).run();
        if (std::isinf(v))
            throw CalcError("overflow");
        if (std::isnan(v))
            throw CalcError("domain");
        return {{QStringLiteral("ok"), true}, {QStringLiteral("value"), double(v)}, {QStringLiteral("text"), formatReal(v)}};
    } catch (const CalcError &e) {
        const QString kind = QString::fromLatin1(e.what());
        const QString msg = kind == QLatin1String("div0") ? QStringLiteral("Nie można dzielić przez zero")
            : kind == QLatin1String("overflow")          ? QStringLiteral("Przepełnienie")
            : kind == QLatin1String("domain")            ? QStringLiteral("Nieprawidłowe dane wejściowe")
                                                         : QString();
        return {{QStringLiteral("ok"), false}, {QStringLiteral("error"), msg}};
    }
}

QString Calc::format(double value) const
{
    return formatReal(value);
}

QString Calc::formatReal(long double value) const
{
    if (value == 0)
        return QStringLiteral("0");
    const long double a = std::fabs(value);
    char buf[64];
    if (a >= 1e17L || a < 1e-10L) {
        // Zapis naukowy: „1,234568e+20”
        std::snprintf(buf, sizeof buf, "%.9Le", value);
        QString s = QString::fromLatin1(buf);
        QString mant = s.section(QLatin1Char('e'), 0, 0), exp = s.section(QLatin1Char('e'), 1);
        if (mant.contains(QLatin1Char('.'))) {
            while (mant.endsWith(QLatin1Char('0')))
                mant.chop(1);
            if (mant.endsWith(QLatin1Char('.')))
                mant.chop(1);
        }
        const int e = exp.toInt();
        return mant.replace(QLatin1Char('.'), QLatin1Char(',')).replace(QLatin1Char('-'), QChar(0x2212)) + QStringLiteral("e")
            + (e < 0 ? QString(QChar(0x2212)) : QStringLiteral("+")) + QString::number(std::abs(e));
    }
    // 17 cyfr znaczących z long double: szum binarny (0,1 + 0,2) leży dalej, więc znika przy zaokrągleniu
    std::snprintf(buf, sizeof buf, "%.17Lg", value);
    QString s = QString::fromLatin1(buf);
    if (s.contains(QLatin1Char('e'))) {
        std::snprintf(buf, sizeof buf, "%.*Lf", std::max(0, 17 - int(std::floor(std::log10(a))) - 1), value);
        s = QString::fromLatin1(buf);
    }
    if (s.contains(QLatin1Char('.'))) {
        while (s.endsWith(QLatin1Char('0')))
            s.chop(1);
        if (s.endsWith(QLatin1Char('.')))
            s.chop(1);
    }
    const bool neg = s.startsWith(QLatin1Char('-'));
    if (neg)
        s.remove(0, 1);
    s.replace(QLatin1Char('.'), QLatin1Char(','));
    return (neg ? QString(QChar(0x2212)) : QString()) + group(s);
}

QString Calc::group(const QString &number) const
{
    // Odstęp (wąski, niełamliwy) co trzy cyfry części całkowitej
    const int comma = number.indexOf(QLatin1Char(','));
    QString whole = comma >= 0 ? number.left(comma) : number;
    const QString rest = comma >= 0 ? number.mid(comma) : QString();
    whole.remove(QChar(0x202F));
    if (whole.size() <= 4)                            // „1000” bez odstępu, jak w polskiej typografii
        return whole + rest;
    QString out;
    for (int i = 0; i < whole.size(); ++i) {
        if (i > 0 && (whole.size() - i) % 3 == 0)
            out += QChar(0x202F);
        out += whole.at(i);
    }
    return out + rest;
}

QString Calc::fromClipboard() const
{
    // Wklejony tekst: „1 234,5”, „1234.5”, „2*3/4” — do zapisu kalkulatora; reszta znaków wypada
    QString t = QGuiApplication::clipboard()->text().trimmed();
    t.replace(QLatin1Char('*'), QChar(0x00D7)).replace(QLatin1Char('/'), QChar(0x00F7)).replace(QLatin1Char('-'), QChar(0x2212));
    t.replace(QLatin1Char('.'), QLatin1Char(','));
    t.remove(QRegularExpression(QStringLiteral("[\\s\\x{00A0}\\x{202F}]")));
    t.remove(QRegularExpression(QStringLiteral("[^0-9,+\\x{2212}\\x{00D7}\\x{00F7}()%^\\x{03C0}\\x{221A}!a-z\\x{00B2}]")));
    return t.left(200);
}

void Calc::toClipboard(const QString &text) const
{
    QString t = text;
    t.remove(QChar(0x202F));
    t.replace(QChar(0x2212), QLatin1Char('-'));
    QGuiApplication::clipboard()->setText(t);
}

void Calc::addHistory(const QString &expr, const QString &result)
{
    m_history.prepend(QVariantMap{{QStringLiteral("expr"), expr}, {QStringLiteral("result"), result}});
    while (m_history.size() > 50)
        m_history.removeLast();
    QSettings().setValue(QStringLiteral("history"), m_history);
    Q_EMIT historyChanged();
}

void Calc::clearHistory()
{
    m_history.clear();
    QSettings().remove(QStringLiteral("history"));
    Q_EMIT historyChanged();
}
