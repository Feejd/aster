// aster (skrót: ai) — Asystent Aster w terminalu.
//   aster "jak spakować folder do zip"         odpowiedź od razu, strumieniowo
//   aster                                      rozmowa (/nowa, /model, /wyjdz)
//   journalctl -b -p err | aster "co nie tak?" dane z potoku jako kontekst pytania
// Komendy zaproponowane przez asystenta (bloki ```bash) są tylko pokazywane: uruchamia je
// użytkownik odpowiedzią [T/n] — nigdy same. Odpowiedzi daje usługa aster-assistant (D-Bus).

#include <QCoreApplication>
#include <QDBusConnection>
#include <QDBusArgument>
#include <QDBusMessage>
#include <QEventLoop>
#include <QJsonArray>
#include <QJsonDocument>
#include <QJsonObject>
#include <QRegularExpression>
#include <QTimer>

#include <atomic>
#include <csignal>
#include <cstdio>
#include <cstdlib>
#include <string>
#include <poll.h>
#include <termios.h>
#include <unistd.h>

static const QString kService = QStringLiteral("org.aster.Assistant");
static const QString kPath = QStringLiteral("/org/aster/Assistant");
static const QString kIface = QStringLiteral("org.aster.Assistant");

static std::atomic<bool> g_interrupted{false};
static bool g_color = false;      // kolory na stdout (terminal)
static bool g_errColor = false;   // kolory na stderr

static void onSigint(int)
{
    g_interrupted = true;
}

static void out(const QString &s)
{
    const QByteArray b = s.toUtf8();
    std::fwrite(b.constData(), 1, b.size(), stdout);
    std::fflush(stdout);
}
static void err(const QString &s)
{
    const QByteArray b = s.toUtf8();
    std::fwrite(b.constData(), 1, b.size(), stderr);
    std::fflush(stderr);
}
static QString dim(const QString &s, bool on) { return on ? QStringLiteral("\x1b[2m") + s + QStringLiteral("\x1b[0m") : s; }
static QString bold(const QString &s, bool on) { return on ? QStringLiteral("\x1b[1m") + s + QStringLiteral("\x1b[0m") : s; }

static QDBusMessage call(const QString &method, const QVariantList &args = {}, int timeout = 30000)
{
    QDBusMessage m = QDBusMessage::createMethodCall(kService, kPath, kIface, method);
    m.setArguments(args);
    return QDBusConnection::sessionBus().call(m, QDBus::Block, timeout);
}

static bool failedCall(const QDBusMessage &r)
{
    if (r.type() != QDBusMessage::ErrorMessage)
        return false;
    err(QStringLiteral("aster: %1\n").arg(r.errorName().startsWith(QLatin1String("org.freedesktop.DBus.Error.Service"))
                                              ? QStringLiteral("usługa asystenta nie działa (%1)").arg(r.errorMessage())
                                              : r.errorMessage()));
    return true;
}

// Wiersz z terminala (także gdy stdin to potok); nullopt — Ctrl+D albo brak terminala
static bool readTty(QString *line, bool echo = true)
{
    static FILE *tty = std::fopen("/dev/tty", "r");
    if (!tty)
        return false;
    termios old{};
    const bool hide = !echo && tcgetattr(fileno(tty), &old) == 0;
    if (hide) {
        termios t = old;
        t.c_lflag &= ~ECHO;
        tcsetattr(fileno(tty), TCSANOW, &t);
    }
    char buf[4096];
    clearerr(tty);
    const char *got = std::fgets(buf, sizeof buf, tty);
    if (hide) {
        tcsetattr(fileno(tty), TCSANOW, &old);
        err(QStringLiteral("\n"));
    }
    if (!got)
        return false;
    *line = QString::fromUtf8(buf).trimmed();
    return true;
}

// Strumień odpowiedzi w terminalu: bloki kodu wcięte i w kolorze, bez znaczników ```.
// Wiersz zaczynający się od „`” czeka na koniec (może być znacznikiem bloku).
struct Printer {
    bool inCode = false;
    QString line;
    int printed = 0;
    bool midLine = false;   // coś już wypisano w bieżącym wierszu ekranu

    void emitPart(const QString &part, bool lineStart)
    {
        if (part.isEmpty())
            return;
        midLine = true;
        if (inCode)
            out((g_color ? QStringLiteral("\x1b[36m") : QString()) + (lineStart ? QStringLiteral("  ") : QString()) + part
                + (g_color ? QStringLiteral("\x1b[0m") : QString()));
        else
            out(part);
    }
    void feed(const QString &t)
    {
        for (const QChar ch : t) {
            if (ch == QLatin1Char('\n')) {
                if (line.trimmed().startsWith(QLatin1String("```"))) {
                    inCode = !inCode;
                } else {
                    emitPart(line.mid(printed), printed == 0);
                    out(QStringLiteral("\n"));
                    midLine = false;
                }
                line.clear();
                printed = 0;
            } else {
                line += ch;
            }
        }
        if (!line.isEmpty() && !line.trimmed().startsWith(QLatin1Char('`')) && !line.trimmed().isEmpty()) {
            emitPart(line.mid(printed), printed == 0);
            printed = line.size();
        }
    }
    void finish()
    {
        if (!line.isEmpty() && !line.trimmed().startsWith(QLatin1String("```")))
            emitPart(line.mid(printed), printed == 0);
        if (midLine)
            out(QStringLiteral("\n"));
        midLine = false;
        line.clear();
        printed = 0;
        inCode = false;
    }
};

class Client : public QObject
{
    Q_OBJECT
public:
    QString conv;
    QString text;
    QString badge;
    QString error;
    bool waitingFirst = false;
    QEventLoop *loop = nullptr;
    Printer printer;

    Client()
    {
        QDBusConnection bus = QDBusConnection::sessionBus();
        bus.connect(kService, kPath, kIface, QStringLiteral("Chunk"), this, SLOT(chunk(QString, QString)));
        bus.connect(kService, kPath, kIface, QStringLiteral("Finished"), this, SLOT(finished(QString, QString, QString)));
        bus.connect(kService, kPath, kIface, QStringLiteral("Failed"), this, SLOT(failed(QString, QString)));
    }

    // Jedno pytanie: wypisuje odpowiedź strumieniowo; false — błąd albo przerwanie
    bool ask(const QString &prompt, const QString &context)
    {
        text.clear();
        badge.clear();
        error.clear();
        printer = Printer();
        const QDBusMessage r = call(QStringLiteral("Ask"), {conv, prompt, context, QStringLiteral("terminal")});
        if (failedCall(r))
            return false;
        conv = r.arguments().value(0).toString();
        waitingFirst = g_errColor;
        if (waitingFirst)
            err(dim(QStringLiteral("⋯"), true));
        QEventLoop l;
        loop = &l;
        QTimer poll;
        poll.setInterval(100);
        QObject::connect(&poll, &QTimer::timeout, &l, [&] {
            if (!g_interrupted)
                return;
            g_interrupted = false;
            call(QStringLiteral("Cancel"), {conv});
            error = QStringLiteral("przerwano");
            l.quit();
        });
        poll.start();
        l.exec();
        loop = nullptr;
        clearWaiting();
        printer.finish();
        if (!error.isEmpty()) {
            err((g_errColor ? QStringLiteral("\x1b[31m") : QString()) + QStringLiteral("aster: ") + error
                + (g_errColor ? QStringLiteral("\x1b[0m") : QString()) + QStringLiteral("\n"));
            return false;
        }
        return true;
    }

    void clearWaiting()
    {
        if (waitingFirst) {
            err(QStringLiteral("\r\x1b[K"));
            waitingFirst = false;
        }
    }

public Q_SLOTS:
    void chunk(const QString &c, const QString &t)
    {
        if (c != conv || !loop)
            return;
        clearWaiting();
        text += t;
        printer.feed(t);
    }
    void finished(const QString &c, const QString &t, const QString &b)
    {
        if (c != conv || !loop)
            return;
        if (text.isEmpty() && !t.isEmpty()) {
            clearWaiting();
            printer.feed(t);
        }
        text = t;
        badge = b;
        loop->quit();
    }
    void failed(const QString &c, const QString &m)
    {
        if (c != conv || !loop)
            return;
        error = m;
        loop->quit();
    }
};

static QVariantMap status()
{
    const QDBusMessage r = call(QStringLiteral("Status"));
    if (r.type() != QDBusMessage::ReplyMessage || r.arguments().isEmpty())
        return {};
    return qdbus_cast<QVariantMap>(r.arguments().at(0));
}

static QString who(const QVariantMap &s)
{
    return QStringLiteral("%1 · %2").arg(s.value(QStringLiteral("badge")).toString(), s.value(QStringLiteral("model")).toString());
}

// Komendy z bloków ```bash / ```sh / ```console w odpowiedzi
static QStringList commands(const QString &text)
{
    QStringList out;
    static const QRegularExpression re(QStringLiteral("```(?:bash|sh|shell|zsh|console)[ \\t]*\\n(.*?)```"),
                                       QRegularExpression::DotMatchesEverythingOption);
    auto it = re.globalMatch(text);
    while (it.hasNext()) {
        QStringList lines = it.next().captured(1).split(QLatin1Char('\n'));
        for (QString &l : lines)
            if (l.startsWith(QLatin1String("$ ")))
                l = l.mid(2);
        const QString cmd = lines.join(QLatin1Char('\n')).trimmed();
        if (!cmd.isEmpty() && !out.contains(cmd))
            out << cmd;
    }
    return out;
}

// Pokazuje każdą zaproponowaną komendę i pyta [T/n]; ryzykowne (sudo, rm -r, dd…) domyślnie „nie”
static void offerCommands(const QString &text)
{
    if (!isatty(STDOUT_FILENO))
        return;
    const QStringList cmds = commands(text);
    static const QRegularExpression risky(QStringLiteral("(^|[\\s;&|(])(sudo|pkexec|rm\\s+-\\w*[rf]|dd\\s|mkfs|shred|chmod\\s+-R|chown\\s+-R|rpm-ostree|bootc|systemctl|reboot|poweroff)|>\\s*/dev/"));
    int shown = 0;
    for (const QString &cmd : cmds) {
        if (++shown > 3)
            break;
        const bool danger = risky.match(cmd).hasMatch();
        err(QStringLiteral("\n") + bold(QStringLiteral("Uruchomić?"), g_errColor) + QStringLiteral("\n"));
        for (const QString &l : cmd.split(QLatin1Char('\n')))
            err((g_errColor ? QStringLiteral("\x1b[36m") : QString()) + QStringLiteral("  ") + l + (g_errColor ? QStringLiteral("\x1b[0m") : QString()) + QStringLiteral("\n"));
        if (danger)
            err(dim(QStringLiteral("  Ta komenda zmienia system albo usuwa dane — sprawdź ją dokładnie.\n"), g_errColor));
        err(danger ? QStringLiteral("[t/N] ") : QStringLiteral("[T/n] "));
        QString answer;
        if (!readTty(&answer)) {
            err(QStringLiteral("\n"));
            return;
        }
        const QString a = answer.toLower();
        const bool yes = a.isEmpty() ? !danger : (a == QLatin1String("t") || a == QLatin1String("tak") || a == QLatin1String("y") || a == QLatin1String("yes"));
        if (!yes)
            continue;
        std::signal(SIGINT, SIG_IGN);   // Ctrl+C trafia do komendy, nie do nas
        const int code = std::system(cmd.toUtf8().constData());
        struct sigaction sa{};
        sa.sa_handler = onSigint;
        sigaction(SIGINT, &sa, nullptr);
        if (code != 0)
            err(dim(QStringLiteral("(kod wyjścia %1)\n").arg(WIFEXITED(code) ? WEXITSTATUS(code) : code), g_errColor));
    }
}

static void printHelp()
{
    out(QStringLiteral(
        "Asystent Aster w terminalu\n\n"
        "  aster \"pytanie\"            odpowiedź od razu\n"
        "  aster                      rozmowa (wiele pytań)\n"
        "  polecenie | aster \"pytanie\" wynik polecenia jako kontekst, np.\n"
        "                             journalctl -b -p err | aster \"co tu jest nie tak?\"\n"
        "                             git diff | aster \"napisz opis commita\"\n"
        "  aster --stan               kto odpowiada (model lokalny czy chmura)\n\n"
        "W rozmowie: /nowa — nowa rozmowa, /model — dostawca i model, /wyjdz — koniec.\n"
        "Zaproponowane komendy uruchamiasz sam, odpowiadając [T/n].\n"
        "Dostawcę, model i klucz API ustawisz też w Ustawieniach → Asystent. `ai` to skrót od `aster`.\n"));
}

// /model: wybór dostawcy (z ostrzeżeniem, gdzie trafią pytania), modelu i klucza API
static void chooseModel(const QString &arg)
{
    if (!arg.isEmpty()) {
        call(QStringLiteral("Configure"), {QVariantMap{{QStringLiteral("model"), arg}}});
        err(QStringLiteral("Model: %1\n").arg(arg));
        return;
    }
    const QDBusMessage r = call(QStringLiteral("Providers"));
    if (failedCall(r))
        return;
    const QJsonArray list = QJsonDocument::fromJson(r.arguments().value(0).toString().toUtf8()).array();
    const QString current = status().value(QStringLiteral("provider")).toString();
    err(QStringLiteral("\n"));
    for (int i = 0; i < list.size(); ++i) {
        const QJsonObject p = list.at(i).toObject();
        const bool cloud = p.value(QStringLiteral("needsKey")).toBool();
        QString where = cloud ? QStringLiteral("chmura · %1").arg(p.value(QStringLiteral("region")).toString()) : QStringLiteral("na tym komputerze");
        if (cloud)
            where += p.value(QStringLiteral("hasKey")).toBool() ? QStringLiteral(" · klucz zapisany") : QStringLiteral(" · bez klucza");
        err(QStringLiteral("  %1. %2  %3%4\n")
                .arg(i + 1, 2)
                .arg(p.value(QStringLiteral("name")).toString().leftJustified(26))
                .arg(dim(where, g_errColor), p.value(QStringLiteral("id")).toString() == current ? bold(QStringLiteral("  ← teraz"), g_errColor) : QString()));
    }
    err(QStringLiteral("Numer dostawcy (Enter — bez zmian): "));
    QString answer;
    if (!readTty(&answer))
        return;
    QJsonObject chosen;
    if (answer.isEmpty()) {
        for (const QJsonValue &v : list)
            if (v.toObject().value(QStringLiteral("id")).toString() == current)
                chosen = v.toObject();
    } else {
        bool ok = false;
        const int n = answer.toInt(&ok);
        if (!ok || n < 1 || n > list.size()) {
            err(QStringLiteral("Nie ma takiego numeru.\n"));
            return;
        }
        chosen = list.at(n - 1).toObject();
    }
    const QString id = chosen.value(QStringLiteral("id")).toString();
    const QString name = chosen.value(QStringLiteral("name")).toString();
    const bool cloud = chosen.value(QStringLiteral("needsKey")).toBool();
    if (cloud && id != current) {
        err(QStringLiteral("Pytania (i dane z potoku) będą wysyłane na serwery %1 — %2. Zgadzasz się? [t/N] ")
                .arg(name, chosen.value(QStringLiteral("region")).toString()));
        if (!readTty(&answer) || !(answer.toLower() == QLatin1String("t") || answer.toLower() == QLatin1String("tak")))
            return;
    }
    if (cloud && !chosen.value(QStringLiteral("hasKey")).toBool()) {
        err(QStringLiteral("Klucz API %1 (%2)\nwpisz albo wklej — nie będzie widoczny, Enter pomija: ")
                .arg(name, chosen.value(QStringLiteral("keyUrl")).toString()));
        if (readTty(&answer, false) && !answer.isEmpty()) {
            const QDBusMessage k = call(QStringLiteral("SetApiKey"), {id, answer}, 150000);
            if (!failedCall(k))
                err(QStringLiteral("Klucz zapisany w portfelu systemu.\n"));
        }
    }
    const QString model = chosen.value(QStringLiteral("model")).toString();
    err(QStringLiteral("Model [%1]: ").arg(model));
    QVariantMap cfg{{QStringLiteral("provider"), id}};
    if (readTty(&answer) && !answer.isEmpty())
        cfg.insert(QStringLiteral("model"), answer);
    call(QStringLiteral("Configure"), {cfg});
    err(QStringLiteral("Odpowiada teraz: %1\n").arg(who(status())));
}

static int chat(Client &client)
{
    const QVariantMap s = status();
    if (s.isEmpty()) {
        failedCall(call(QStringLiteral("Status")));
        return 1;
    }
    err(bold(QStringLiteral("Asystent Aster"), g_errColor) + dim(QStringLiteral(" · ") + who(s), g_errColor) + QStringLiteral("\n"));
    if (!s.value(QStringLiteral("ready")).toBool())
        err(s.value(QStringLiteral("problem")).toString() + QStringLiteral(" (albo wpisz /model)\n"));
    err(dim(QStringLiteral("/nowa — nowa rozmowa · /model — zmień model · /wyjdz — koniec\n"), g_errColor));

    for (;;) {
        out(g_color ? QStringLiteral("\n\x1b[1;34m›\x1b[0m ") : QStringLiteral("\n› "));
        char buf[16384];
        clearerr(stdin);
        g_interrupted = false;
        if (!std::fgets(buf, sizeof buf, stdin)) {
            if (g_interrupted)
                continue;          // Ctrl+C przy pustym wierszu — jak w powłoce
            out(QStringLiteral("\n"));
            return 0;              // Ctrl+D
        }
        const QString line = QString::fromUtf8(buf).trimmed();
        if (line.isEmpty())
            continue;
        if (line.startsWith(QLatin1Char('/'))) {
            const QString cmd = line.section(QLatin1Char(' '), 0, 0).toLower();
            const QString arg = line.section(QLatin1Char(' '), 1).trimmed();
            if (cmd == QLatin1String("/wyjdz") || cmd == QLatin1String("/wyjdź") || cmd == QLatin1String("/koniec")
                || cmd == QLatin1String("/exit") || cmd == QLatin1String("/quit") || cmd == QLatin1String("/q"))
                return 0;
            if (cmd == QLatin1String("/nowa") || cmd == QLatin1String("/new")) {
                client.conv.clear();
                err(dim(QStringLiteral("Nowa rozmowa.\n"), g_errColor));
            } else if (cmd == QLatin1String("/model")) {
                chooseModel(arg);
            } else if (cmd == QLatin1String("/pomoc") || cmd == QLatin1String("/help")) {
                printHelp();
            } else {
                err(QStringLiteral("Nie znam %1 — są: /nowa, /model, /wyjdz, /pomoc\n").arg(cmd));
            }
            continue;
        }
        out(QStringLiteral("\n"));
        if (client.ask(line, QString())) {
            err(dim(QStringLiteral("— %1\n").arg(client.badge), g_errColor));
            offerCommands(client.text);
        }
    }
}

int main(int argc, char *argv[])
{
    QCoreApplication app(argc, argv);
    g_color = isatty(STDOUT_FILENO) && qEnvironmentVariableIsEmpty("NO_COLOR");
    g_errColor = isatty(STDERR_FILENO) && qEnvironmentVariableIsEmpty("NO_COLOR");

    struct sigaction sa{};
    sa.sa_handler = onSigint;   // bez SA_RESTART: Ctrl+C przerywa też czekanie na wiersz
    sigaction(SIGINT, &sa, nullptr);

    QStringList args = app.arguments().mid(1);
    if (!args.isEmpty() && (args.first() == QLatin1String("-h") || args.first() == QLatin1String("--help") || args.first() == QLatin1String("--pomoc"))) {
        printHelp();
        return 0;
    }
    if (!QDBusConnection::sessionBus().isConnected()) {
        err(QStringLiteral("aster: brak szyny sesji D-Bus\n"));
        return 1;
    }
    if (!args.isEmpty() && args.first() == QLatin1String("--stan")) {
        const QVariantMap s = status();
        if (s.isEmpty())
            return failedCall(call(QStringLiteral("Status"))) ? 1 : 1;
        out(who(s) + QStringLiteral("\n"));
        if (!s.value(QStringLiteral("region")).toString().isEmpty())
            out(QStringLiteral("Serwery: %1\n").arg(s.value(QStringLiteral("region")).toString()));
        if (!s.value(QStringLiteral("ready")).toBool())
            out(s.value(QStringLiteral("problem")).toString() + QStringLiteral("\n"));
        return 0;
    }

    Client client;
    QString context;
    bool piped = !isatty(STDIN_FILENO);
    // Wejście bez terminala, ale bez potoku (skrypt, ssh, cron): gdy przez 3 s nic nie przyjdzie, pytanie idzie bez kontekstu
    if (piped && !args.isEmpty()) {
        pollfd p{STDIN_FILENO, POLLIN, 0};
        if (poll(&p, 1, 3000) == 0)
            piped = false;
    }
    if (piped) {
        QByteArray all;
        char buf[65536];
        size_t n;
        while ((n = std::fread(buf, 1, sizeof buf, stdin)) > 0)
            all.append(buf, qsizetype(n));
        context = QString::fromUtf8(all);
    }
    const QString prompt = args.join(QLatin1Char(' ')).trimmed();
    if (prompt.isEmpty() && !piped)
        return chat(client);
    if (prompt.isEmpty() && context.trimmed().isEmpty()) {
        err(QStringLiteral("aster: pusty potok i brak pytania — np. journalctl -b -p err | aster \"co tu jest nie tak?\"\n"));
        return 2;
    }
    if (!client.ask(prompt, context))
        return client.error == QLatin1String("przerwano") ? 130 : 1;
    if (g_errColor)
        err(dim(QStringLiteral("— %1\n").arg(client.badge), true));
    offerCommands(client.text);
    return 0;
}

#include "aster.moc"
