#include "agent.h"
#include "curl.h"
#include "runner.h"
#include "workspace.h"

#include <QCoreApplication>
#include <QDBusConnection>
#include <QDBusConnectionInterface>
#include <QDBusMessage>
#include <QDir>
#include <QFile>
#include <QFileInfo>
#include <QJsonArray>
#include <QJsonDocument>
#include <QMimeDatabase>
#include <QNetworkAccessManager>
#include <QStringDecoder>

#include <cstdio>

const QString PulseService::busName = QStringLiteral("org.aster.pulse");
const QString PulseService::objectPath = QStringLiteral("/org/aster/Pulse");

namespace {

QString toJson(const QJsonObject &o, bool indented = false)
{
    return QString::fromUtf8(QJsonDocument(o).toJson(indented ? QJsonDocument::Indented : QJsonDocument::Compact));
}

QJsonObject failure(const QString &error, const QJsonObject &extra = {})
{
    QJsonObject o = extra;
    o[QStringLiteral("ok")] = false;
    o[QStringLiteral("error")] = error;
    return o;
}

// Zmienne jawne środowiska (bez portfela) — do eksportu cURL bez sekretów
QHash<QString, QString> plainVariables(const Workspace &ws, const QString &env)
{
    QHash<QString, QString> vars;
    for (const QJsonValue &vv : ws.environment(env).value(QLatin1String("vars")).toArray()) {
        const QJsonObject v = vv.toObject();
        if (!v.value(QLatin1String("secret")).toBool() && v.value(QLatin1String("enabled")).toBool(true))
            vars.insert(v.value(QLatin1String("key")).toString(), v.value(QLatin1String("value")).toString());
    }
    return vars;
}

} // namespace

bool AgentRun::parseJsonBody(const QByteArray &body, const QString &contentType, QJsonValue *out)
{
    const QString ct = contentType.toLower();
    const QByteArray t = body.trimmed();
    if (t.isEmpty())
        return false;
    if (!ct.contains(QLatin1String("json")) && !(t.startsWith('{') || t.startsWith('[')))
        return false;
    QJsonParseError pe;
    const QJsonDocument doc = QJsonDocument::fromJson(t, &pe);
    if (pe.error != QJsonParseError::NoError)
        return false;
    *out = doc.isArray() ? QJsonValue(doc.array()) : QJsonValue(doc.object());
    return true;
}

QJsonObject AgentRun::output(const QJsonObject &result, const QByteArray &body, qint64 maxBody)
{
    QJsonObject o;
    for (const char *k : {"ok", "status", "statusText", "timeMs", "size", "contentType", "redirectedTo", "error"})
        if (result.contains(QLatin1String(k)))
            o[QLatin1String(k)] = result.value(QLatin1String(k));
    QJsonObject sentHeaders;
    for (const QJsonValue &h : result.value(QLatin1String("requestHeaders")).toArray())
        sentHeaders[h.toArray().at(0).toString()] = h.toArray().at(0).toString().compare(QLatin1String("authorization"), Qt::CaseInsensitive) == 0
                                                        ? QStringLiteral("(ukryte)")
                                                        : h.toArray().at(1).toString();
    o[QStringLiteral("request")] = QJsonObject{{QStringLiteral("method"), result.value(QLatin1String("method"))},
                                               {QStringLiteral("url"), result.value(QLatin1String("url"))},
                                               {QStringLiteral("headers"), sentHeaders}};
    if (!result.contains(QLatin1String("status")))
        return o;
    QJsonObject headers;
    for (const QJsonValue &h : result.value(QLatin1String("headers")).toArray()) {
        const QString k = h.toArray().at(0).toString().toLower(), v = h.toArray().at(1).toString();
        headers[k] = headers.contains(k) ? headers.value(k).toString() + QStringLiteral(", ") + v : v;
    }
    o[QStringLiteral("headers")] = headers;
    QJsonValue json;
    if (body.size() <= maxBody && parseJsonBody(body, result.value(QLatin1String("contentType")).toString(), &json)) {
        o[QStringLiteral("body")] = json;
        return o;
    }
    QByteArray part = body.left(maxBody);
    o[QStringLiteral("bodyTruncated")] = body.size() > maxBody;
    // Ucięcie w środku znaku UTF-8 to jeszcze nie binarka — cofamy się o niepełny znak
    for (int back = 0; back < 4 && part.size() > 0; ++back) {
        QStringDecoder dec(QStringDecoder::Utf8);
        const QString text = dec.decode(part);
        if (!dec.hasError() && !text.contains(QChar(0))) {
            o[QStringLiteral("body")] = text;
            return o;
        }
        if (body.size() <= maxBody)
            break;
        part.chop(1);
    }
    if (body.isEmpty()) {
        o[QStringLiteral("body")] = QString();
        return o;
    }
    o[QStringLiteral("body")] = QJsonValue::Null;
    o[QStringLiteral("bodyBase64")] = QString::fromLatin1(part.toBase64());
    return o;
}

void AgentRun::start(QNetworkAccessManager *nam, const QString &ref, const QJsonObject &request, const QJsonObject &options,
                     const QString &source, QObject *context, const Done &done)
{
    Workspace ws;
    QString error;
    const QString dir = Workspace::locate(options.value(QLatin1String("dir")).toString(), QDir::currentPath());
    const bool loaded = ws.load(dir, &error);
    QJsonObject req = request;
    if (req.isEmpty()) {
        if (!loaded)
            return done(failure(error, {{QStringLiteral("workspace"), dir}}));
        req = ws.findRequest(ref, &error);
        if (req.isEmpty())
            return done(failure(error, {{QStringLiteral("workspace"), dir}, {QStringLiteral("ref"), ref}}));
    }
    req = normalizedRequest(req);
    // Dodatkowe nagłówki z wywołania
    QJsonArray hs = req.value(QLatin1String("headers")).toArray();
    for (const QJsonValue &h : options.value(QLatin1String("headers")).toArray())
        hs.append(h);
    req[QStringLiteral("headers")] = hs;
    if (options.value(QLatin1String("insecure")).toBool())
        req[QStringLiteral("insecure")] = true;

    QString env = options.value(QLatin1String("env")).toString();
    QHash<QString, QString> vars;
    QStringList missing;
    if (loaded) {
        if (env.isEmpty())
            env = ws.activeEnvironment();
        else if (ws.environment(env).isEmpty()) {
            QStringList names;
            for (const QJsonValue &e : ws.environments())
                names << e.toObject().value(QLatin1String("name")).toString();
            return done(failure(QStringLiteral("Nie ma środowiska „%1” (są: %2)").arg(env, names.join(QStringLiteral(", "))),
                                {{QStringLiteral("workspace"), ws.dir()}}));
        } else {
            env = ws.environment(env).value(QLatin1String("name")).toString();
        }
        QString secretError;
        vars = ws.variables(env, &missing, &secretError);
    }
    const QJsonObject overrides = options.value(QLatin1String("vars")).toObject();
    for (auto it = overrides.begin(); it != overrides.end(); ++it) {
        vars.insert(it.key(), it.value().toVariant().toString());
        missing.removeAll(it.key());
    }
    QStringList unresolved;
    const QJsonObject resolved = Vars::resolveRequest(req, vars, &unresolved);
    const QJsonObject info{{QStringLiteral("ref"), ref}, {QStringLiteral("environment"), env}, {QStringLiteral("workspace"), loaded ? ws.dir() : QString()}};
    if (!unresolved.isEmpty() && !options.value(QLatin1String("allowUnresolved")).toBool()) {
        QStringList secretOnes;
        for (const QString &u : unresolved)
            if (missing.contains(u))
                secretOnes << u;
        QString msg = QStringLiteral("Brak wartości zmiennych: %1").arg(unresolved.join(QStringLiteral(", ")));
        if (!secretOnes.isEmpty())
            msg += QStringLiteral(" — tajne (%1) nie są zapisane w portfelu dla środowiska „%2”; wpisz je w Aster Pulse albo podaj --var").arg(secretOnes.join(QStringLiteral(", ")), env);
        else if (!env.isEmpty())
            msg += QStringLiteral(" (środowisko „%1”)").arg(env);
        QJsonObject f = failure(msg, info);
        f[QStringLiteral("unresolved")] = QJsonArray::fromStringList(unresolved);
        return done(f);
    }

    auto *runner = new Runner(nam, context);
    const qint64 maxBody = options.value(QLatin1String("maxBody")).toInteger(1000000);
    const QString workspaceDir = loaded ? ws.dir() : QString();
    QObject::connect(runner, &Runner::finished, context, [=](const QJsonObject &result, const QByteArray &body) {
        runner->deleteLater();
        History::append(req, result, env, source, workspaceDir);
        QJsonObject o = AgentRun::output(result, body, maxBody);
        for (auto it = info.begin(); it != info.end(); ++it)
            if (!it.value().toString().isEmpty())
                o[it.key()] = it.value();
        if (!unresolved.isEmpty())
            o[QStringLiteral("unresolved")] = QJsonArray::fromStringList(unresolved);
        // Surowa treść dla --out (nie trafia do JSON)
        o[QStringLiteral("_raw")] = QString::fromLatin1(body.toBase64());
        done(o);
    });
    const int timeout = int(options.value(QLatin1String("timeout")).toDouble(30) * 1000);
    runner->start(resolved, timeout);
}

// ——— D-Bus ———

PulseService::PulseService(QNetworkAccessManager *nam, bool window, QObject *parent)
    : QObject(parent)
    , m_nam(nam)
    , m_window(window)
{
    // Usługa bez okna kończy się po 10 minutach bez wywołań
    m_idle.setSingleShot(true);
    m_idle.setInterval(10 * 60 * 1000);
    connect(&m_idle, &QTimer::timeout, this, [this] {
        if (!m_window && m_pending == 0)
            QCoreApplication::quit();
    });
    if (!m_window)
        m_idle.start();
}

void PulseService::touch()
{
    if (!m_window)
        m_idle.start();
}

QString PulseService::Run(const QString &ref, const QString &env, const QString &dir)
{
    return RunWith(ref, toJson({{QStringLiteral("env"), env}, {QStringLiteral("dir"), dir}}));
}

QString PulseService::RunWith(const QString &ref, const QString &optionsJson)
{
    touch();
    const QJsonObject options = QJsonDocument::fromJson(optionsJson.toUtf8()).object();
    setDelayedReply(true);
    const QDBusMessage msg = message();
    ++m_pending;
    AgentRun::start(m_nam, ref, {}, options, QStringLiteral("dbus"), this, [this, msg](QJsonObject o) {
        o.remove(QStringLiteral("_raw"));
        const QString out = toJson(o);
        QDBusConnection::sessionBus().send(msg.createReply(out));
        --m_pending;
        touch();
        Q_EMIT requestFinished(out);
    });
    return {};
}

QString PulseService::Send(const QString &requestJson, const QString &optionsJson)
{
    touch();
    QJsonObject req = QJsonDocument::fromJson(requestJson.toUtf8()).object();
    QString error;
    if (req.contains(QLatin1String("curl")))
        req = Curl::parse(req.value(QLatin1String("curl")).toString(), &error);
    if (req.isEmpty())
        return toJson(failure(error.isEmpty() ? QStringLiteral("Podaj zapytanie jako JSON: {\"method\", \"url\", …} albo {\"curl\": \"curl …\"}") : error));
    const QJsonObject options = QJsonDocument::fromJson(optionsJson.toUtf8()).object();
    setDelayedReply(true);
    const QDBusMessage msg = message();
    ++m_pending;
    AgentRun::start(m_nam, QString(), req, options, QStringLiteral("dbus"), this, [this, msg](QJsonObject o) {
        o.remove(QStringLiteral("_raw"));
        const QString out = toJson(o);
        QDBusConnection::sessionBus().send(msg.createReply(out));
        --m_pending;
        touch();
        Q_EMIT requestFinished(out);
    });
    return {};
}

QString PulseService::List(const QString &dir)
{
    touch();
    Workspace ws;
    QString error;
    const QString d = Workspace::locate(dir, QDir::currentPath());
    if (!ws.load(d, &error))
        return toJson(failure(error, {{QStringLiteral("workspace"), d}}));
    QJsonObject o = ws.describe();
    o[QStringLiteral("ok")] = true;
    return toJson(o);
}

QString PulseService::Curl(const QString &ref, const QString &env, const QString &dir)
{
    touch();
    Workspace ws;
    QString error;
    if (!ws.load(Workspace::locate(dir, QDir::currentPath()), &error))
        return toJson(failure(error));
    const QJsonObject req = ws.findRequest(ref, &error);
    if (req.isEmpty())
        return toJson(failure(error));
    const QJsonObject resolved = Vars::resolveRequest(req, plainVariables(ws, env.isEmpty() ? ws.activeEnvironment() : env));
    return toJson({{QStringLiteral("ok"), true}, {QStringLiteral("curl"), Curl::build(resolved)}});
}

QString PulseService::ImportCurl(const QString &command)
{
    touch();
    QString error;
    const QJsonObject req = Curl::parse(command, &error);
    if (req.isEmpty())
        return toJson(failure(error));
    return toJson({{QStringLiteral("ok"), true}, {QStringLiteral("request"), req}});
}

bool PulseService::Activate(const QString &token)
{
    if (!m_window)
        return false;
    Q_EMIT activated(token);
    return true;
}

// ——— Terminal ———

namespace {

void print(const QString &s, FILE *to = stdout)
{
    const QByteArray b = s.toUtf8();
    fwrite(b.constData(), 1, b.size(), to);
    if (!s.endsWith(QLatin1Char('\n')))
        fputc('\n', to);
    fflush(to);
}

const char *kUsage = R"(Aster Pulse — testowanie API

  aster-pulse [FOLDER]                          okno programu (FOLDER — projekt albo obszar Pulse)
  aster-pulse run KOLEKCJA/ZAPYTANIE [opcje]    wyślij zapisane zapytanie, wynik jako JSON
  aster-pulse send METODA ADRES [opcje]         wyślij dowolne zapytanie (adres może mieć {{zmienne}})
  aster-pulse send --curl 'curl …' [opcje]      wyślij polecenie cURL
  aster-pulse list [--dir FOLDER]               kolekcje, zapytania i środowiska (JSON)
  aster-pulse curl KOLEKCJA/ZAPYTANIE [--env E] polecenie cURL (tajne zmienne zostają jako {{nazwa}})
  aster-pulse import [PLIK|-] --collection NAZWA [--name NAZWA]
                                                zapisz polecenie cURL (z pliku albo wejścia) w kolekcji

Opcje:
  --env NAZWA         środowisko (domyślnie to wybrane w programie)
  --dir FOLDER        obszar roboczy (domyślnie pulse/ w projekcie nad bieżącym katalogiem, potem ~/Dokumenty/Pulse)
  --var KLUCZ=WART    wartość zmiennej, także tajnej (można wiele razy)
  -H 'Nazwa: wart'    nagłówek (można wiele razy)
  -d TREŚĆ            treść (send); --json TREŚĆ — treść JSON
  --timeout S         limit czasu w sekundach (domyślnie 30)
  -k, --insecure      bez sprawdzania certyfikatu (serwery testowe)
  --max-body BAJTY    najwięcej treści w wyniku (domyślnie 1000000)
  --out PLIK          zapisz treść odpowiedzi do pliku
  --body              wypisz samą treść odpowiedzi zamiast JSON
  --allow-unresolved  wyślij mimo zmiennych bez wartości

Kod wyjścia: 0 — odpowiedź z kodem < 400, 2 — odpowiedź z kodem ≥ 400, 1 — błąd (brak połączenia, zła nazwa…).
Tajne zmienne są w portfelu systemu (Secret Service). D-Bus: org.aster.pulse /org/aster/Pulse, interfejs
org.aster.Pulse — Run(ref, env, dir), RunWith(ref, opcjeJson), Send(zapytanieJson, opcjeJson), List(dir), Curl(ref, env, dir).
)";

struct Args {
    QStringList positional;
    QJsonObject options;
    QJsonArray headers;
    QString body, out, collection, name, curl;
    bool json = false, bodyOnly = false, help = false;
    QString error;
};

Args parseArgs(const QStringList &a)
{
    Args r;
    QJsonObject vars;
    for (int i = 0; i < a.size(); ++i) {
        const QString s = a.at(i);
        auto val = [&]() -> QString {
            if (i + 1 >= a.size()) {
                r.error = QStringLiteral("Opcja %1 potrzebuje wartości").arg(s);
                return {};
            }
            return a.at(++i);
        };
        if (s == QLatin1String("--env") || s == QLatin1String("-e"))
            r.options[QStringLiteral("env")] = val();
        else if (s == QLatin1String("--dir"))
            r.options[QStringLiteral("dir")] = val();
        else if (s == QLatin1String("--var")) {
            const QString v = val();
            const int eq = v.indexOf(QLatin1Char('='));
            if (eq <= 0)
                r.error = QStringLiteral("--var potrzebuje KLUCZ=WARTOŚĆ");
            else
                vars[v.left(eq)] = v.mid(eq + 1);
        } else if (s == QLatin1String("-H") || s == QLatin1String("--header")) {
            const QString h = val();
            const int colon = h.indexOf(QLatin1Char(':'));
            if (colon > 0)
                r.headers.append(QJsonObject{{QStringLiteral("key"), h.left(colon).trimmed()}, {QStringLiteral("value"), h.mid(colon + 1).trimmed()}, {QStringLiteral("enabled"), true}});
        } else if (s == QLatin1String("-d") || s == QLatin1String("--data"))
            r.body = val();
        else if (s == QLatin1String("--json")) {
            r.body = val();
            r.json = true;
        } else if (s == QLatin1String("--timeout"))
            r.options[QStringLiteral("timeout")] = val().toDouble();
        else if (s == QLatin1String("-k") || s == QLatin1String("--insecure"))
            r.options[QStringLiteral("insecure")] = true;
        else if (s == QLatin1String("--max-body"))
            r.options[QStringLiteral("maxBody")] = val().toLongLong();
        else if (s == QLatin1String("--allow-unresolved"))
            r.options[QStringLiteral("allowUnresolved")] = true;
        else if (s == QLatin1String("--out") || s == QLatin1String("-o"))
            r.out = val();
        else if (s == QLatin1String("--body"))
            r.bodyOnly = true;
        else if (s == QLatin1String("--collection"))
            r.collection = val();
        else if (s == QLatin1String("--name"))
            r.name = val();
        else if (s == QLatin1String("--curl"))
            r.curl = val();
        else if (s == QLatin1String("-h") || s == QLatin1String("--help"))
            r.help = true;
        else if (s.startsWith(QLatin1String("--")))
            r.error = QStringLiteral("Nieznana opcja %1 (aster-pulse --help)").arg(s);
        else
            r.positional << s;
    }
    if (!vars.isEmpty())
        r.options[QStringLiteral("vars")] = vars;
    if (!r.headers.isEmpty())
        r.options[QStringLiteral("headers")] = r.headers;
    return r;
}

int finishRun(QJsonObject o, const Args &args)
{
    const QByteArray raw = QByteArray::fromBase64(o.take(QLatin1String("_raw")).toString().toLatin1());
    if (!args.out.isEmpty() && o.contains(QLatin1String("status"))) {
        QFile f(args.out);
        if (f.open(QIODevice::WriteOnly)) {
            f.write(raw);
            o[QStringLiteral("savedTo")] = QFileInfo(f).absoluteFilePath();
        } else {
            o[QStringLiteral("saveError")] = QStringLiteral("Nie można zapisać %1").arg(args.out);
        }
    }
    if (args.bodyOnly && o.contains(QLatin1String("status"))) {
        fwrite(raw.constData(), 1, raw.size(), stdout);
        fflush(stdout);
    } else {
        print(toJson(o, true));
    }
    if (!o.contains(QLatin1String("status")))
        return 1;
    return o.value(QLatin1String("status")).toInt() >= 400 ? 2 : 0;
}

int fail(const QString &msg, int code = 1)
{
    print(toJson(failure(msg), true));
    return code;
}

} // namespace

int runCommandLine(int argc, char **argv)
{
    if (argc < 2)
        return -1;
    const QString cmd = QString::fromLocal8Bit(argv[1]);
    static const QStringList commands{QStringLiteral("run"), QStringLiteral("send"), QStringLiteral("list"), QStringLiteral("curl"),
                                      QStringLiteral("import"), QStringLiteral("--dbus"), QStringLiteral("--help"), QStringLiteral("-h"), QStringLiteral("help")};
    if (!commands.contains(cmd))
        return -1;

    QCoreApplication app(argc, argv);
    app.setApplicationName(QStringLiteral("aster-pulse"));
    app.setOrganizationName(QStringLiteral("Aster"));
    QNetworkAccessManager nam;

    if (cmd == QLatin1String("--help") || cmd == QLatin1String("-h") || cmd == QLatin1String("help")) {
        print(QString::fromUtf8(kUsage));
        return 0;
    }
    if (cmd == QLatin1String("--dbus")) {
        QDBusConnection bus = QDBusConnection::sessionBus();
        PulseService service(&nam, false);
        if (!bus.registerService(PulseService::busName)) {
            print(QStringLiteral("Usługa %1 już działa").arg(PulseService::busName), stderr);
            return 0;
        }
        bus.registerObject(PulseService::objectPath, &service, QDBusConnection::ExportAllSlots | QDBusConnection::ExportAllSignals);
        return app.exec();
    }

    const Args args = parseArgs(app.arguments().mid(2));
    if (args.help) {
        print(QString::fromUtf8(kUsage));
        return 0;
    }
    if (!args.error.isEmpty())
        return fail(args.error, 64);

    if (cmd == QLatin1String("list")) {
        Workspace ws;
        QString error;
        const QString dir = Workspace::locate(args.options.value(QLatin1String("dir")).toString(), QDir::currentPath());
        if (!ws.load(dir, &error))
            return fail(error);
        QJsonObject o = ws.describe();
        o[QStringLiteral("ok")] = true;
        print(toJson(o, true));
        return 0;
    }

    if (cmd == QLatin1String("curl")) {
        if (args.positional.isEmpty())
            return fail(QStringLiteral("Podaj zapytanie: aster-pulse curl KOLEKCJA/ZAPYTANIE"), 64);
        Workspace ws;
        QString error;
        if (!ws.load(Workspace::locate(args.options.value(QLatin1String("dir")).toString(), QDir::currentPath()), &error))
            return fail(error);
        const QJsonObject req = ws.findRequest(args.positional.first(), &error);
        if (req.isEmpty())
            return fail(error);
        const QString env = args.options.value(QLatin1String("env")).toString();
        QHash<QString, QString> vars = plainVariables(ws, env.isEmpty() ? ws.activeEnvironment() : env);
        const QJsonObject overrides = args.options.value(QLatin1String("vars")).toObject();
        for (auto it = overrides.begin(); it != overrides.end(); ++it)
            vars.insert(it.key(), it.value().toString());
        print(Curl::build(Vars::resolveRequest(req, vars)));
        return 0;
    }

    if (cmd == QLatin1String("import")) {
        QString text = args.curl;
        if (text.isEmpty()) {
            QFile f;
            const QString src = args.positional.value(0, QStringLiteral("-"));
            if (src == QLatin1String("-") ? f.open(stdin, QIODevice::ReadOnly) : (f.setFileName(src), f.open(QIODevice::ReadOnly)))
                text = QString::fromUtf8(f.readAll());
            else
                return fail(QStringLiteral("Nie można przeczytać %1").arg(src));
        }
        QString error;
        QJsonObject req = Curl::parse(text, &error);
        if (req.isEmpty())
            return fail(error);
        if (!args.name.isEmpty())
            req[QStringLiteral("name")] = args.name;
        if (args.collection.isEmpty()) {
            print(toJson({{QStringLiteral("ok"), true}, {QStringLiteral("request"), req}}, true));
            return 0;
        }
        Workspace ws;
        const QString dir = Workspace::locate(args.options.value(QLatin1String("dir")).toString(), QDir::currentPath());
        if (!ws.load(dir, &error)) {
            if (!Workspace::create(dir, QString(), false) || !ws.load(dir, &error))
                return fail(error);
        }
        QJsonObject col;
        for (const QJsonObject &c : ws.collections())
            if (c.value(QLatin1String("name")).toString().compare(args.collection, Qt::CaseInsensitive) == 0
                || QFileInfo(c.value(QLatin1String("file")).toString()).completeBaseName() == args.collection)
                col = c;
        if (col.isEmpty()) {
            const QString file = ws.createCollection(args.collection, &error);
            if (file.isEmpty())
                return fail(error);
            for (const QJsonObject &c : ws.collections())
                if (c.value(QLatin1String("file")).toString() == file)
                    col = c;
        }
        QJsonArray reqs = col.value(QLatin1String("requests")).toArray();
        reqs.append(req);
        col[QStringLiteral("requests")] = reqs;
        if (!ws.saveCollection(col, &error))
            return fail(error);
        print(toJson({{QStringLiteral("ok"), true}, {QStringLiteral("ref"), ws.refFor(col, req)}, {QStringLiteral("workspace"), ws.dir()}, {QStringLiteral("request"), req}}, true));
        return 0;
    }

    // run / send
    QJsonObject request;
    QString ref;
    if (cmd == QLatin1String("run")) {
        if (args.positional.isEmpty())
            return fail(QStringLiteral("Podaj zapytanie: aster-pulse run KOLEKCJA/ZAPYTANIE (lista: aster-pulse list)"), 64);
        ref = args.positional.first();
    } else {
        QString error;
        if (!args.curl.isEmpty()) {
            request = Curl::parse(args.curl, &error);
        } else if (args.positional.size() >= 2) {
            request = normalizedRequest({{QStringLiteral("method"), args.positional.at(0)}, {QStringLiteral("url"), args.positional.at(1)}});
        } else if (args.positional.size() == 1) {
            request = normalizedRequest({{QStringLiteral("method"), args.body.isEmpty() ? QStringLiteral("GET") : QStringLiteral("POST")}, {QStringLiteral("url"), args.positional.at(0)}});
        } else {
            return fail(QStringLiteral("Podaj metodę i adres: aster-pulse send GET {{baseUrl}}/health"), 64);
        }
        if (request.isEmpty())
            return fail(error);
        if (!args.body.isEmpty()) {
            const bool isJson = args.json || QJsonDocument::fromJson(args.body.toUtf8()).isObject() || QJsonDocument::fromJson(args.body.toUtf8()).isArray();
            request[QStringLiteral("body")] = QJsonObject{{QStringLiteral("mode"), isJson ? QStringLiteral("json") : QStringLiteral("text")}, {QStringLiteral("text"), args.body}};
        }
    }
    int code = 1;
    bool finished = false, looping = false;
    AgentRun::start(&nam, ref, request, args.options, QStringLiteral("cli"), &app, [&](const QJsonObject &o) {
        code = finishRun(o, args);
        finished = true;
        if (looping)
            QCoreApplication::exit(code);
    });
    // Błąd przed wysłaniem (zła nazwa, brak zmiennej) kończy od razu — wywołanie zwrotne już się odbyło
    if (finished)
        return code;
    looping = true;
    app.exec();
    return code;
}
