#include "curl.h"
#include "runner.h"
#include "workspace.h"

#include <QFileInfo>
#include <QJsonArray>
#include <QJsonDocument>
#include <QRegularExpression>
#include <QUrl>
#include <QUrlQuery>

namespace {

QJsonObject kv(const QString &k, const QString &v, const QString &type = {})
{
    QJsonObject o{{QStringLiteral("key"), k}, {QStringLiteral("value"), v}, {QStringLiteral("enabled"), true}};
    if (!type.isEmpty())
        o[QStringLiteral("type")] = type;
    return o;
}

QString quote(const QString &s)
{
    static const QRegularExpression plain(QStringLiteral("^[A-Za-z0-9_./:@%+=,-]+$"));
    if (plain.match(s).hasMatch())
        return s;
    QString q = s;
    q.replace(QLatin1Char('\''), QStringLiteral("'\\''"));
    return QLatin1Char('\'') + q + QLatin1Char('\'');
}

// a=1&b=2 (bez spacji i nowych wierszy) — wygląda na formularz
bool looksUrlEncoded(const QString &s)
{
    static const QRegularExpression re(QStringLiteral("^[^=&\\s{}\\[\\]\"]+=[^&\\s]*(&[^=&\\s]+=[^&\\s]*)*$"));
    return re.match(s).hasMatch();
}

} // namespace

QStringList Curl::split(const QString &command, QString *error)
{
    QStringList words;
    QString cur;
    bool inWord = false;
    const QString s = command;
    const qsizetype n = s.size();
    for (qsizetype i = 0; i < n; ++i) {
        const QChar c = s.at(i);
        if (c == QLatin1Char('\\') && i + 1 < n && (s.at(i + 1) == QLatin1Char('\n') || s.at(i + 1) == QLatin1Char('\r'))) {
            ++i;   // kontynuacja wiersza
            if (i + 1 < n && s.at(i) == QLatin1Char('\r') && s.at(i + 1) == QLatin1Char('\n'))
                ++i;
            continue;
        }
        if (c.isSpace()) {
            if (inWord) {
                words << cur;
                cur.clear();
                inWord = false;
            }
            continue;
        }
        inWord = true;
        if (c == QLatin1Char('\'')) {
            const qsizetype end = s.indexOf(QLatin1Char('\''), i + 1);
            if (end < 0) {
                if (error)
                    *error = QStringLiteral("Niezamknięty apostrof w poleceniu");
                return {};
            }
            cur += s.mid(i + 1, end - i - 1);
            i = end;
        } else if (c == QLatin1Char('$') && i + 1 < n && s.at(i + 1) == QLatin1Char('\'')) {
            // $'…' — sekwencje \n, \t, \', \\ (Chrome tak kopiuje treść z nowymi wierszami)
            for (i += 2; i < n && s.at(i) != QLatin1Char('\''); ++i) {
                if (s.at(i) == QLatin1Char('\\') && i + 1 < n) {
                    const QChar e = s.at(++i);
                    if (e == QLatin1Char('n'))
                        cur += QLatin1Char('\n');
                    else if (e == QLatin1Char('t'))
                        cur += QLatin1Char('\t');
                    else if (e == QLatin1Char('r'))
                        cur += QLatin1Char('\r');
                    else if (e == QLatin1Char('u') && i + 4 < n) {
                        cur += QChar(s.mid(i + 1, 4).toUShort(nullptr, 16));
                        i += 4;
                    } else
                        cur += e;
                } else {
                    cur += s.at(i);
                }
            }
        } else if (c == QLatin1Char('"')) {
            for (++i; i < n && s.at(i) != QLatin1Char('"'); ++i) {
                if (s.at(i) == QLatin1Char('\\') && i + 1 < n && QStringLiteral("\"\\$`\n").contains(s.at(i + 1))) {
                    ++i;
                    if (s.at(i) == QLatin1Char('\n'))
                        continue;
                }
                cur += s.at(i);
            }
            if (i >= n) {
                if (error)
                    *error = QStringLiteral("Niezamknięty cudzysłów w poleceniu");
                return {};
            }
        } else if (c == QLatin1Char('\\') && i + 1 < n) {
            cur += s.at(++i);
        } else {
            cur += c;
        }
    }
    if (inWord)
        words << cur;
    return words;
}

QJsonObject Curl::parse(const QString &command, QString *error)
{
    QStringList w = split(command.trimmed(), error);
    if (w.isEmpty()) {
        if (error && error->isEmpty())
            *error = QStringLiteral("Wklej polecenie cURL");
        return {};
    }
    if (w.first() == QLatin1String("curl") || w.first().endsWith(QLatin1String("/curl")))
        w.removeFirst();

    // Opcje bez wartości, które pomijamy (wyjście, postęp, przekierowania — Pulse i tak za nimi idzie)
    static const QStringList noArg{QStringLiteral("-L"), QStringLiteral("--location"), QStringLiteral("-s"), QStringLiteral("--silent"),
                                   QStringLiteral("-S"), QStringLiteral("--show-error"), QStringLiteral("-v"), QStringLiteral("--verbose"),
                                   QStringLiteral("-i"), QStringLiteral("--include"), QStringLiteral("--compressed"), QStringLiteral("-f"),
                                   QStringLiteral("--fail"), QStringLiteral("-#"), QStringLiteral("--progress-bar"), QStringLiteral("--http1.1"),
                                   QStringLiteral("--http2"), QStringLiteral("--http1.0"), QStringLiteral("-N"), QStringLiteral("--no-buffer"),
                                   QStringLiteral("-g"), QStringLiteral("--globoff"), QStringLiteral("--fail-with-body"), QStringLiteral("-O")};
    static const QStringList withArg{QStringLiteral("-o"), QStringLiteral("--output"), QStringLiteral("-m"), QStringLiteral("--max-time"),
                                     QStringLiteral("--connect-timeout"), QStringLiteral("-w"), QStringLiteral("--write-out"), QStringLiteral("--retry"),
                                     QStringLiteral("-x"), QStringLiteral("--proxy"), QStringLiteral("--resolve"), QStringLiteral("-c"),
                                     QStringLiteral("--cookie-jar"), QStringLiteral("--cacert"), QStringLiteral("--cert"), QStringLiteral("--key")};

    QString method, url;
    QJsonArray headers, form;
    QStringList data;
    bool get = false, head = false, insecure = false, jsonFlag = false, dataFile = false;
    QString dataFilePath;
    QJsonObject auth{{QStringLiteral("type"), QStringLiteral("none")}};

    for (int i = 0; i < w.size(); ++i) {
        QString opt = w.at(i), val;
        bool hasVal = false;
        // --opcja=wartość
        if (opt.startsWith(QLatin1String("--")) && opt.contains(QLatin1Char('='))) {
            val = opt.mid(opt.indexOf(QLatin1Char('=')) + 1);
            opt = opt.left(opt.indexOf(QLatin1Char('=')));
            hasVal = true;
        }
        // -XPOST, -HAccept:… (krótka opcja z doklejoną wartością)
        static const QString shortWithVal = QStringLiteral("XHdFuAbeom");
        if (!hasVal && opt.size() > 2 && opt.at(0) == QLatin1Char('-') && opt.at(1) != QLatin1Char('-') && shortWithVal.contains(opt.at(1))) {
            val = opt.mid(2);
            opt = opt.left(2);
            hasVal = true;
        }
        auto next = [&]() -> QString {
            if (hasVal)
                return val;
            return i + 1 < w.size() ? w.at(++i) : QString();
        };
        if (opt == QLatin1String("-X") || opt == QLatin1String("--request")) {
            method = next().toUpper();
        } else if (opt == QLatin1String("-H") || opt == QLatin1String("--header")) {
            const QString h = next();
            const int colon = h.indexOf(QLatin1Char(':'));
            if (colon > 0)
                headers.append(kv(h.left(colon).trimmed(), h.mid(colon + 1).trimmed()));
        } else if (opt == QLatin1String("-d") || opt == QLatin1String("--data") || opt == QLatin1String("--data-ascii")
                   || opt == QLatin1String("--data-binary") || opt == QLatin1String("--data-raw")) {
            const QString d = next();
            if (opt != QLatin1String("--data-raw") && d.startsWith(QLatin1Char('@')) && d.size() > 1) {
                dataFile = true;
                dataFilePath = d.mid(1);
            } else {
                data << d;
            }
        } else if (opt == QLatin1String("--data-urlencode")) {
            const QString d = next();
            const int eq = d.indexOf(QLatin1Char('='));
            data << (eq >= 0 ? d.left(eq + 1) + QString::fromUtf8(QUrl::toPercentEncoding(d.mid(eq + 1))) : QString::fromUtf8(QUrl::toPercentEncoding(d)));
        } else if (opt == QLatin1String("--json")) {
            data << next();
            jsonFlag = true;
        } else if (opt == QLatin1String("-F") || opt == QLatin1String("--form") || opt == QLatin1String("--form-string")) {
            const QString f = next();
            const int eq = f.indexOf(QLatin1Char('='));
            if (eq > 0) {
                QString v = f.mid(eq + 1);
                if (opt != QLatin1String("--form-string") && v.startsWith(QLatin1Char('@'))) {
                    v = v.mid(1);
                    const int semi = v.indexOf(QLatin1Char(';'));
                    form.append(kv(f.left(eq), semi >= 0 ? v.left(semi) : v, QStringLiteral("file")));
                } else {
                    form.append(kv(f.left(eq), v, QStringLiteral("text")));
                }
            }
        } else if (opt == QLatin1String("-u") || opt == QLatin1String("--user")) {
            const QString u = next();
            const int colon = u.indexOf(QLatin1Char(':'));
            auth = {{QStringLiteral("type"), QStringLiteral("basic")}, {QStringLiteral("user"), colon >= 0 ? u.left(colon) : u},
                    {QStringLiteral("password"), colon >= 0 ? u.mid(colon + 1) : QString()}};
        } else if (opt == QLatin1String("-A") || opt == QLatin1String("--user-agent")) {
            headers.append(kv(QStringLiteral("User-Agent"), next()));
        } else if (opt == QLatin1String("-b") || opt == QLatin1String("--cookie")) {
            headers.append(kv(QStringLiteral("Cookie"), next()));
        } else if (opt == QLatin1String("-e") || opt == QLatin1String("--referer")) {
            headers.append(kv(QStringLiteral("Referer"), next()));
        } else if (opt == QLatin1String("-G") || opt == QLatin1String("--get")) {
            get = true;
        } else if (opt == QLatin1String("-I") || opt == QLatin1String("--head")) {
            head = true;
        } else if (opt == QLatin1String("-k") || opt == QLatin1String("--insecure")) {
            insecure = true;
        } else if (opt == QLatin1String("--url")) {
            url = next();
        } else if (withArg.contains(opt)) {
            next();
        } else if (noArg.contains(opt)) {
            // pomijamy
        } else if (opt.startsWith(QLatin1Char('-')) && opt.size() > 1) {
            // Sklejone krótkie flagi (-sSL, -sk); k — bez sprawdzania certyfikatu
            if (!opt.startsWith(QLatin1String("--")) && opt.contains(QLatin1Char('k')))
                insecure = true;
        } else if (url.isEmpty()) {
            url = opt;
        }
    }
    if (url.isEmpty()) {
        if (error)
            *error = QStringLiteral("W poleceniu nie ma adresu");
        return {};
    }

    QJsonObject req;
    QJsonObject body{{QStringLiteral("mode"), QStringLiteral("none")}};
    const QString joined = data.join(QLatin1Char('&'));
    if (get && !data.isEmpty()) {
        url += (url.contains(QLatin1Char('?')) ? QLatin1Char('&') : QLatin1Char('?')) + joined;
        data.clear();
    }

    // Typ treści z nagłówka (zostaje w nagłówkach tylko, gdy nie wynika z trybu treści)
    QString contentType;
    int ctIndex = -1;
    for (int i = 0; i < headers.size(); ++i)
        if (headers.at(i).toObject().value(QLatin1String("key")).toString().compare(QLatin1String("content-type"), Qt::CaseInsensitive) == 0) {
            contentType = headers.at(i).toObject().value(QLatin1String("value")).toString();
            ctIndex = i;
        }
    if (!data.isEmpty()) {
        const bool isJson = jsonFlag || contentType.contains(QLatin1String("json"))
                            || (contentType.isEmpty() && (QJsonDocument::fromJson(joined.toUtf8()).isObject() || QJsonDocument::fromJson(joined.toUtf8()).isArray()));
        if (isJson) {
            QJsonParseError pe;
            const QJsonDocument doc = QJsonDocument::fromJson(joined.toUtf8(), &pe);
            body = {{QStringLiteral("mode"), QStringLiteral("json")},
                    {QStringLiteral("text"), pe.error == QJsonParseError::NoError ? QString::fromUtf8(doc.toJson(QJsonDocument::Indented)).trimmed() : joined}};
            if (contentType.isEmpty() || contentType.startsWith(QLatin1String("application/json")))
                ctIndex >= 0 ? headers.removeAt(ctIndex) : void();
            if (jsonFlag) {
                bool hasAccept = false;
                for (const QJsonValue &h : headers)
                    hasAccept |= h.toObject().value(QLatin1String("key")).toString().compare(QLatin1String("accept"), Qt::CaseInsensitive) == 0;
                if (!hasAccept)
                    headers.append(kv(QStringLiteral("Accept"), QStringLiteral("application/json")));
            }
        } else if ((contentType.isEmpty() || contentType.contains(QLatin1String("x-www-form-urlencoded"))) && looksUrlEncoded(joined)) {
            QJsonArray items;
            for (const QString &pair : joined.split(QLatin1Char('&'))) {
                const int eq = pair.indexOf(QLatin1Char('='));
                auto dec = [](const QString &x) { return QUrl::fromPercentEncoding(QString(x).replace(QLatin1Char('+'), QLatin1Char(' ')).toUtf8()); };
                items.append(kv(dec(pair.left(eq)), dec(pair.mid(eq + 1))));
            }
            body = {{QStringLiteral("mode"), QStringLiteral("urlencoded")}, {QStringLiteral("form"), items}};
            if (ctIndex >= 0)
                headers.removeAt(ctIndex);
        } else {
            body = {{QStringLiteral("mode"), QStringLiteral("text")}, {QStringLiteral("text"), joined}};
            if (!contentType.isEmpty()) {
                body[QStringLiteral("contentType")] = contentType;
                headers.removeAt(ctIndex);
            }
        }
    } else if (dataFile) {
        body = {{QStringLiteral("mode"), QStringLiteral("file")}, {QStringLiteral("file"), dataFilePath}};
        if (!contentType.isEmpty()) {
            body[QStringLiteral("contentType")] = contentType;
            headers.removeAt(ctIndex);
        }
    } else if (!form.isEmpty()) {
        body = {{QStringLiteral("mode"), QStringLiteral("form")}, {QStringLiteral("form"), form}};
        if (ctIndex >= 0 && contentType.startsWith(QLatin1String("multipart/form-data")))
            headers.removeAt(ctIndex);
    }

    // Authorization: Bearer … → zakładka autoryzacji
    for (int i = 0; i < headers.size(); ++i) {
        const QJsonObject h = headers.at(i).toObject();
        if (h.value(QLatin1String("key")).toString().compare(QLatin1String("authorization"), Qt::CaseInsensitive) == 0
            && h.value(QLatin1String("value")).toString().startsWith(QLatin1String("Bearer "), Qt::CaseInsensitive)) {
            auth = {{QStringLiteral("type"), QStringLiteral("bearer")}, {QStringLiteral("token"), h.value(QLatin1String("value")).toString().mid(7).trimmed()}};
            headers.removeAt(i);
            break;
        }
    }

    if (method.isEmpty())
        method = head ? QStringLiteral("HEAD") : (body.value(QLatin1String("mode")).toString() != QLatin1String("none") ? QStringLiteral("POST") : QStringLiteral("GET"));

    // Parametry z adresu do osobnej listy
    QJsonArray params;
    const int q = url.indexOf(QLatin1Char('?'));
    if (q >= 0) {
        QString query = url.mid(q + 1);
        const int hash = query.indexOf(QLatin1Char('#'));
        if (hash >= 0)
            query.truncate(hash);
        url.truncate(q);
        for (const QString &pair : query.split(QLatin1Char('&'), Qt::SkipEmptyParts)) {
            const int eq = pair.indexOf(QLatin1Char('='));
            auto dec = [](const QString &x) { return QUrl::fromPercentEncoding(QString(x).replace(QLatin1Char('+'), QLatin1Char(' ')).toUtf8()); };
            params.append(kv(dec(eq >= 0 ? pair.left(eq) : pair), eq >= 0 ? dec(pair.mid(eq + 1)) : QString()));
        }
    }

    // Nazwa: ścieżka adresu (np. „POST /users”)
    const QUrl u(url, QUrl::TolerantMode);
    QString path = u.path();
    if (path.isEmpty() || path == QLatin1String("/"))
        path = u.host().isEmpty() ? url : u.host();
    req = {{QStringLiteral("name"), method + QLatin1Char(' ') + path}, {QStringLiteral("method"), method}, {QStringLiteral("url"), url},
           {QStringLiteral("params"), params}, {QStringLiteral("headers"), headers}, {QStringLiteral("body"), body}, {QStringLiteral("auth"), auth}};
    if (insecure)
        req[QStringLiteral("insecure")] = true;
    return normalizedRequest(req);
}

QString Curl::build(const QJsonObject &reqIn, bool multiline)
{
    const QJsonObject req = normalizedRequest(reqIn);
    QStringList parts{QStringLiteral("curl")};
    const QString method = req.value(QLatin1String("method")).toString();
    const QJsonObject body = req.value(QLatin1String("body")).toObject();
    const QString mode = body.value(QLatin1String("mode")).toString();
    const bool hasBody = mode != QLatin1String("none");
    if (method == QLatin1String("HEAD"))
        parts << QStringLiteral("-I");
    else if (!(method == QLatin1String("GET") && !hasBody) && !(method == QLatin1String("POST") && hasBody))
        parts << QStringLiteral("-X ") + method;
    parts << quote(Vars::fullUrl(req));
    if (req.value(QLatin1String("insecure")).toBool())
        parts << QStringLiteral("-k");
    // Nagłówki: jawne, typ treści i autoryzacja (bez domyślnych User-Agent/Accept od Pulse); Basic jako -u
    const QJsonObject auth = req.value(QLatin1String("auth")).toObject();
    const QString basic = auth.value(QLatin1String("user")).toString() + QLatin1Char(':') + auth.value(QLatin1String("password")).toString();
    const QByteArray basicHeader = "Basic " + basic.toUtf8().toBase64();
    for (const auto &h : Runner::effectiveHeaders(req)) {
        if (auth.value(QLatin1String("type")).toString() == QLatin1String("basic") && h.first == "Authorization" && h.second == basicHeader) {
            parts << QStringLiteral("-u ") + quote(basic);
            continue;
        }
        if ((h.first == "User-Agent" && h.second == "AsterPulse/1.0") || (h.first == "Accept" && h.second == "*/*"))
            continue;
        if (mode == QLatin1String("form") && h.first.compare("Content-Type", Qt::CaseInsensitive) == 0 && h.second.startsWith("multipart/form-data"))
            continue;
        parts << QStringLiteral("-H ") + quote(QString::fromUtf8(h.first) + QStringLiteral(": ") + QString::fromUtf8(h.second));
    }
    if (mode == QLatin1String("json") || mode == QLatin1String("text")) {
        QString text = body.value(QLatin1String("text")).toString();
        // JSON w jednym wierszu — łatwiej wkleić do terminala
        if (mode == QLatin1String("json")) {
            const QJsonDocument doc = QJsonDocument::fromJson(text.toUtf8());
            if (!doc.isNull())
                text = QString::fromUtf8(doc.toJson(QJsonDocument::Compact));
        }
        parts << QStringLiteral("--data-raw ") + quote(text);
    } else if (mode == QLatin1String("urlencoded")) {
        for (const QJsonValue &v : body.value(QLatin1String("form")).toArray()) {
            const QJsonObject o = v.toObject();
            if (o.value(QLatin1String("enabled")).toBool(true) && !o.value(QLatin1String("key")).toString().isEmpty())
                parts << QStringLiteral("--data-urlencode ") + quote(o.value(QLatin1String("key")).toString() + QLatin1Char('=') + o.value(QLatin1String("value")).toString());
        }
    } else if (mode == QLatin1String("form")) {
        for (const QJsonValue &v : body.value(QLatin1String("form")).toArray()) {
            const QJsonObject o = v.toObject();
            if (!o.value(QLatin1String("enabled")).toBool(true) || o.value(QLatin1String("key")).toString().isEmpty())
                continue;
            const bool file = o.value(QLatin1String("type")).toString() == QLatin1String("file");
            parts << (file ? QStringLiteral("-F ") : QStringLiteral("--form-string "))
                         + quote(o.value(QLatin1String("key")).toString() + (file ? QStringLiteral("=@") : QStringLiteral("=")) + o.value(QLatin1String("value")).toString());
        }
    } else if (mode == QLatin1String("file")) {
        parts << QStringLiteral("--data-binary ") + quote(QLatin1Char('@') + body.value(QLatin1String("file")).toString());
    }
    return parts.join(multiline ? QStringLiteral(" \\\n  ") : QStringLiteral(" "));
}
