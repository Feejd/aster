// aster (skrót: ai) — Aster Intelligence w terminalu.
//   aster "jak spakować folder do zip"         odpowiedź od razu, strumieniowo
//   aster                                      rozmowa (/nowa, /model, /wyjdz)
//   journalctl -b -p err | aster "co nie tak?" dane z potoku jako kontekst pytania
// Aster Intelligence jest agentem: sam uruchamia polecenia potrzebne do rozwiązania sprawy (tutaj, w tym
// terminalu), czyta ich wynik i działa dalej. Polecenia tylko do odczytu — od razu; zmieniające system —
// po odpowiedzi [T/n] na pytanie po ludzku. Odpowiedzi daje usługa aster-assistant (D-Bus).

#include <QCoreApplication>
#include "blocks.h"
#include "commands.h"

#include <QCryptographicHash>
#include <QDateTime>
#include <QSaveFile>
#include <QSet>
#include <QStandardPaths>
#include <QThread>
#include <QDir>
#include <QFile>
#include <QHash>
#include <QSysInfo>
#include <QDBusConnection>
#include <QDBusArgument>
#include <QDBusMessage>
#include <QEventLoop>
#include <QProcess>
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
    bool hidden = false;    // blok ```bash — polecenie pokaże karta działania, nie tekst
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
    QString fence;          // otwarcie bieżącego bloku (``` albo ````)
    void feed(const QString &t)
    {
        static const QRegularExpression open(QStringLiteral("^(`{3,})\\s*([A-Za-z]*)(?:\\s*:\\s*(.*))?$"));
        for (const QChar ch : t) {
            if (ch == QLatin1Char('\n')) {
                const QString tl = line.trimmed();
                const bool closing = inCode && tl.size() >= fence.size() && !tl.isEmpty() && tl.count(QLatin1Char('`')) == tl.size();
                const auto m = inCode ? QRegularExpressionMatch() : open.match(tl);
                if (closing) {
                    inCode = false;
                    hidden = false;
                } else if (!inCode && m.hasMatch()) {
                    inCode = true;
                    fence = m.captured(1);
                    const QString kind = m.captured(2).toLower();
                    static const QStringList shells{QStringLiteral("bash"), QStringLiteral("sh"), QStringLiteral("shell"), QStringLiteral("zsh"), QStringLiteral("console")};
                    hidden = shells.contains(kind) || kind == QLatin1String("plik") || kind == QLatin1String("zmiana");
                    // Treść pliku nie zalewa terminala — wystarczy, który plik powstaje
                    if (kind == QLatin1String("plik") || kind == QLatin1String("zmiana")) {
                        out(dim(QStringLiteral("  %1 %2\n").arg(kind == QLatin1String("plik") ? QStringLiteral("📄") : QStringLiteral("✎"), m.captured(3).trimmed()), g_color));
                        midLine = false;
                    }
                } else if (hidden) {
                    // pomijane
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
        if (!hidden && !line.isEmpty() && !line.trimmed().startsWith(QLatin1Char('`')) && !line.trimmed().isEmpty()) {
            emitPart(line.mid(printed), printed == 0);
            printed = line.size();
        }
    }
    void finish()
    {
        if (!hidden && !line.isEmpty() && !line.trimmed().startsWith(QLatin1String("```")))
            emitPart(line.mid(printed), printed == 0);
        hidden = false;
        if (midLine)
            out(QStringLiteral("\n"));
        midLine = false;
        line.clear();
        printed = 0;
        inCode = false;
        fence.clear();
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
        bus.connect(kService, kPath, kIface, QStringLiteral("ActionRequested"), this,
                    SLOT(action(QString, QString, QString, QString, bool)));
    }

    // Jedno pytanie: wypisuje odpowiedź strumieniowo; false — błąd albo przerwanie
    bool ask(const QString &prompt, const QString &context)
    {
        text.clear();
        badge.clear();
        error.clear();
        printer = Printer();
        const QDBusMessage r = call(QStringLiteral("AskIn"), {conv, prompt, context, QStringLiteral("terminal"), QDir::currentPath()});
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

    // Agent chce uruchomić polecenie: zwykłe — od razu, ważne — po [T/n].
    // Polecenie działa w tym terminalu i bieżącym folderze (sudo zapyta o hasło jak zwykle);
    // wyjście widać na bieżąco i wraca do modelu, który działa dalej.
    void action(const QString &c, const QString &id, const QString &command, const QString &description, bool safe)
    {
        if (c != conv || !loop)
            return;
        clearWaiting();
        printer.finish();
        const bool tty = isatty(STDIN_FILENO) || isatty(STDERR_FILENO);
        // Zdanie-opis zwykle już widać (było przed blokiem z poleceniem); polecenie — przygaszone, pod nim
        const bool said = text.contains(description);
        // Zapis plików: wystarczy opis (pliki już widać wyżej); polecenie po nich — pokazane
        const QString shown = command.startsWith(QLatin1String("aster --zmiany ")) ? command.section(QStringLiteral("&& \\\n"), 1) : command;
        if (!shown.trimmed().isEmpty())
            err(dim(QStringLiteral("  $ ") + shown.trimmed().section(QLatin1Char('\n'), 0, 0)
                        + (shown.trimmed().contains(QLatin1Char('\n')) ? QStringLiteral(" …") : QString()), g_errColor) + QStringLiteral("\n"));
        int code = -2;
        QString output;
        if (!safe) {
            err((said ? QString() : bold(description, g_errColor) + QStringLiteral(" ")) + (tty ? QStringLiteral("[T/n] ") : QString()));
            QString answer;
            const bool asked = tty && readTty(&answer);
            const QString a = answer.toLower();
            const bool yes = asked && (a.isEmpty() || a == QLatin1String("t") || a == QLatin1String("tak") || a == QLatin1String("y")
                                       || a == QLatin1String("yes"));
            if (!asked)
                err(QStringLiteral("\n") + dim(QStringLiteral("(bez terminala nie mogę zapytać — pomijam)"), g_errColor) + QStringLiteral("\n"));
            if (!yes) {
                call(QStringLiteral("ActionResult"), {conv, id, -2, QString()});
                text.clear();
                printer = Printer();
                return;
            }
        } else {
            if (!said)
                err(dim(QStringLiteral("→ ") + description, g_errColor) + QStringLiteral("\n"));
        }
        QProcess p;
        p.setProcessChannelMode(QProcess::MergedChannels);
        // Ważne dostają klawiaturę (np. hasło do sudo); pozostałe — nie, żeby o nic nie pytały
        if (safe)
            p.setStandardInputFile(QProcess::nullDevice());
        else
            p.setInputChannelMode(QProcess::ForwardedInputChannel);
        std::signal(SIGINT, SIG_IGN);   // Ctrl+C trafia do polecenia, nie do nas
        QProcessEnvironment env = QProcessEnvironment::systemEnvironment();
        env.insert(QStringLiteral("ASTER_AGENT"), QStringLiteral("1"));
        p.setProcessEnvironment(env);
        p.start(QStringLiteral("bash"), {QStringLiteral("-c"), command});
        if (!p.waitForStarted(5000)) {
            output = QStringLiteral("Nie udało się uruchomić bash.");
            code = 127;
        } else {
            while (p.state() != QProcess::NotRunning) {
                p.waitForReadyRead(100);
                const QString chunk = QString::fromUtf8(p.readAll());
                if (!chunk.isEmpty()) {
                    output += chunk;
                    out(dim(chunk, g_color));
                }
            }
            const QString rest = QString::fromUtf8(p.readAll());
            output += rest;
            out(dim(rest, g_color));
            if (!output.isEmpty() && !output.endsWith(QLatin1Char('\n')))
                out(QStringLiteral("\n"));
            code = p.exitStatus() == QProcess::NormalExit ? p.exitCode() : 130;
        }
        struct sigaction sa{};
        sa.sa_handler = onSigint;
        sigaction(SIGINT, &sa, nullptr);
        if (code != 0)
            err(dim(QStringLiteral("(kod wyjścia %1)\n").arg(code), g_errColor));
        out(QStringLiteral("\n"));
        call(QStringLiteral("ActionResult"), {conv, id, code, output});
        text.clear();
        printer = Printer();
        waitingFirst = g_errColor;
        if (waitingFirst)
            err(dim(QStringLiteral("⋯"), true));
    }
};

// Pasek postępu pobierania modelu w terminalu
class Progress : public QObject
{
    Q_OBJECT
public Q_SLOTS:
    void update(const QString &, qlonglong got, qlonglong total)
    {
        if (total <= 0)
            return;
        const int width = 30;
        const int fill = int(double(got) / double(total) * width);
        err(QStringLiteral("\r  [%1%2] %3% · %4 z %5 MB")
                .arg(QString(fill, QChar(0x2588)), QString(width - fill, QChar(0x2591)))
                .arg(int(double(got) * 100 / double(total)))
                .arg(got / 1000000).arg(total / 1000000));
    }
    void finish(const QString &, bool ok, const QString &message) { Q_EMIT done(ok, message); }
Q_SIGNALS:
    void done(bool ok, const QString &message);
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

// aster --model-lokalny [lista|auto|<id>] — modele na tym komputerze; „auto” pobiera polecany dla tego sprzętu
// (do użycia np. przez instalator albo pierwsze uruchomienie) i ustawia go jako używany
static QString cores(int n)
{
    const int d = n % 10, t = n % 100;
    return QString::number(n) + (n == 1 ? QStringLiteral(" rdzeń") : d >= 2 && d <= 4 && (t < 12 || t > 14) ? QStringLiteral(" rdzenie") : QStringLiteral(" rdzeni"));
}

static int localModel(const QString &arg)
{
    const QDBusMessage r = call(QStringLiteral("LocalModels"));
    if (failedCall(r))
        return 1;
    const QJsonObject o = QJsonDocument::fromJson(r.arguments().value(0).toString().toUtf8()).object();
    const QJsonObject hw = o.value(QStringLiteral("hardware")).toObject();
    const QJsonArray models = o.value(QStringLiteral("models")).toArray();
    auto gb = [](double b) { return QString::number(b / 1e9, 'f', 1).replace(QLatin1Char('.'), QLatin1Char(',')) + QStringLiteral(" GB"); };
    if (arg.isEmpty() || arg == QLatin1String("lista")) {
        out(QStringLiteral("Ten komputer: %1 GB pamięci, %2, wolne %3\n\n")
                .arg(hw.value(QStringLiteral("ramGb")).toInt()).arg(cores(hw.value(QStringLiteral("cores")).toInt()))
                .arg(gb(hw.value(QStringLiteral("freeDisk")).toDouble())));
        for (const QJsonValue &v : models) {
            const QJsonObject m = v.toObject();
            QStringList tags;
            if (m.value(QStringLiteral("active")).toBool()) tags << QStringLiteral("w użyciu");
            else if (m.value(QStringLiteral("installed")).toBool()) tags << QStringLiteral("pobrany");
            if (m.value(QStringLiteral("recommended")).toBool()) tags << QStringLiteral("polecany");
            if (!m.value(QStringLiteral("fits")).toBool()) tags << QStringLiteral("za mało pamięci");
            out(QStringLiteral("  %1  %2  %3%4\n    %5\n")
                    .arg(m.value(QStringLiteral("id")).toString(), -12).arg(bold(m.value(QStringLiteral("name")).toString(), g_color))
                    .arg(gb(m.value(QStringLiteral("size")).toDouble()))
                    .arg(tags.isEmpty() ? QString() : QStringLiteral("  [") + tags.join(QStringLiteral(", ")) + QStringLiteral("]"))
                    .arg(dim(m.value(QStringLiteral("description")).toString(), g_color)));
        }
        out(QStringLiteral("\nPobranie: aster --model-lokalny auto  (albo nazwa z lewej kolumny)\n"));
        return 0;
    }
    const QString id = arg == QLatin1String("auto") ? o.value(QStringLiteral("recommended")).toString() : arg;
    QString name = id;
    bool have = false;
    for (const QJsonValue &v : models)
        if (v.toObject().value(QStringLiteral("id")).toString() == id) {
            name = v.toObject().value(QStringLiteral("name")).toString();
            have = v.toObject().value(QStringLiteral("installed")).toBool();
        }
    if (!have) {
        if (arg == QLatin1String("auto"))
            err(QStringLiteral("Pobieram %1 — dobrany do tego komputera (%2 GB pamięci, %3)…\n").arg(name)
                    .arg(hw.value(QStringLiteral("ramGb")).toInt()).arg(cores(hw.value(QStringLiteral("cores")).toInt())));
        else
            err(QStringLiteral("Pobieram %1…\n").arg(name));
        QEventLoop loop;
        bool ok = false;
        QString message;
        QDBusConnection bus = QDBusConnection::sessionBus();
        Progress progress;
        bus.connect(kService, kPath, kIface, QStringLiteral("DownloadProgress"), &progress, SLOT(update(QString, qlonglong, qlonglong)));
        QObject::connect(&progress, &Progress::done, &loop, [&](bool success, const QString &m) {
            ok = success;
            message = m;
            loop.quit();
        });
        bus.connect(kService, kPath, kIface, QStringLiteral("DownloadFinished"), &progress, SLOT(finish(QString, bool, QString)));
        const QDBusMessage d = call(QStringLiteral("DownloadModel"), {id});
        if (failedCall(d))
            return 1;
        if (!d.arguments().value(0).toString().isEmpty()) {
            err(QStringLiteral("aster: ") + d.arguments().value(0).toString() + QStringLiteral("\n"));
            return 1;
        }
        QTimer poll;
        poll.setInterval(150);
        QObject::connect(&poll, &QTimer::timeout, &loop, [&] {
            if (g_interrupted) {
                g_interrupted = false;
                call(QStringLiteral("CancelDownload"));
            }
        });
        poll.start();
        loop.exec();
        err(QStringLiteral("\n"));
        if (!ok) {
            err(QStringLiteral("aster: ") + message + QStringLiteral("\n"));
            return 1;
        }
    }
    call(QStringLiteral("UseModel"), {id});
    out(QStringLiteral("Gotowe — Aster Intelligence używa modelu %1 na tym komputerze.\n").arg(name));
    return 0;
}

// ——— Okna i programy (powłoka Aster: D-Bus org.aster.Shell) ———

static QDBusMessage shellCall(const QString &method, const QVariantList &args = {})
{
    QDBusMessage m = QDBusMessage::createMethodCall(QStringLiteral("org.aster.Shell"), QStringLiteral("/org/aster/Shell"),
                                                    QStringLiteral("org.aster.Shell"), method);
    m.setArguments(args);
    return QDBusConnection::sessionBus().call(m, QDBus::Block, 10000);
}

static bool shellFailed(const QDBusMessage &r)
{
    if (r.type() != QDBusMessage::ErrorMessage)
        return false;
    err(QStringLiteral("aster: powłoka Aster nie odpowiada — okna i programy obsługuje tylko pulpit Aster (%1)\n").arg(r.errorMessage()));
    return true;
}

static int listWindows()
{
    const QDBusMessage r = shellCall(QStringLiteral("ListWindows"));
    if (shellFailed(r))
        return 1;
    const QJsonArray list = QJsonDocument::fromJson(r.arguments().value(0).toString().toUtf8()).array();
    if (list.isEmpty()) {
        out(QStringLiteral("Nie ma otwartych okien.\n"));
        return 0;
    }
    for (const QJsonValue &v : list) {
        const QJsonObject o = v.toObject();
        QString state;
        if (o.value(QStringLiteral("active")).toBool())
            state = QStringLiteral("  (na wierzchu)");
        else if (o.value(QStringLiteral("minimized")).toBool())
            state = QStringLiteral("  (zminimalizowane)");
        out(QStringLiteral("%1. %2 — %3%4\n").arg(o.value(QStringLiteral("n")).toInt())
                .arg(o.value(QStringLiteral("app")).toString(), o.value(QStringLiteral("title")).toString(), state));
    }
    return 0;
}

static int windowAction(const QString &action, const QString &query)
{
    if (query.isEmpty()) {
        err(QStringLiteral("aster: które okno? Podaj numer albo nazwę (lista: aster --okna)\n"));
        return 2;
    }
    const QDBusMessage r = shellCall(QStringLiteral("WindowAction"), {action, query});
    if (shellFailed(r))
        return 1;
    const QString problem = r.arguments().value(0).toString();
    if (!problem.isEmpty()) {
        err(problem + QStringLiteral("\n"));
        return 1;
    }
    return 0;
}

// Programy Aster z GitHuba (jak tools/install-apps.sh): id → nazwa
static QString asterAppName(const QString &id)
{
    static const QHash<QString, QString> names{
        {QStringLiteral("code"), QStringLiteral("Aster Code")}, {QStringLiteral("grafika"), QStringLiteral("Grafika")},
        {QStringLiteral("montaz"), QStringLiteral("Montaż")}, {QStringLiteral("studio"), QStringLiteral("Studio")},
        {QStringLiteral("editor"), QStringLiteral("Edytor tekstu")}, {QStringLiteral("calculator"), QStringLiteral("Kalkulator")},
        {QStringLiteral("photos"), QStringLiteral("Zdjęcia")}, {QStringLiteral("music"), QStringLiteral("Muzyka")},
        {QStringLiteral("video"), QStringLiteral("Wideo")}, {QStringLiteral("pdf"), QStringLiteral("Podgląd PDF")},
        {QStringLiteral("camera"), QStringLiteral("Kamera")}};
    return names.value(id);
}

static int openApp(const QStringList &args)
{
    if (args.isEmpty()) {
        err(QStringLiteral("aster: który program? np. aster --otworz \"aster code\" ~/projekt\n"));
        return 2;
    }
    const QDBusMessage r = shellCall(QStringLiteral("OpenApp"), {args.first(), QStringList(args.mid(1)), QDir::currentPath()});
    if (shellFailed(r))
        return 1;
    const QString res = r.arguments().value(0).toString();
    if (res.startsWith(QLatin1String("ok:"))) {
        out(QStringLiteral("Otwarto: %1 (okno pojawi się za chwilę)\n").arg(res.mid(3)));
        return 0;
    }
    if (res.startsWith(QLatin1String("nie-ma:"))) {
        const QString id = res.mid(7);
        out(QStringLiteral("Programu %1 nie ma jeszcze na tym komputerze. Instalacja: aster --instaluj %2\n").arg(asterAppName(id), id));
        return 3;
    }
    err(res + QStringLiteral("\n"));
    return 1;
}

static int run(const QString &program, const QStringList &args)
{
    QProcess p;
    p.setProcessChannelMode(QProcess::ForwardedChannels);
    p.setInputChannelMode(QProcess::ForwardedInputChannel);
    p.start(program, args);
    if (!p.waitForStarted(10000))
        return 127;
    p.waitForFinished(-1);
    return p.exitStatus() == QProcess::NormalExit ? p.exitCode() : 130;
}

// Program Aster jako Flatpak z wydania „aplikacje” na GitHubie (pierwszy raz dochodzą biblioteki KDE z Flathub, ok. 400 MB)
static int installApp(QString id)
{
    id = id.toLower().remove(QStringLiteral("aster")).remove(QStringLiteral("org.")).remove(QLatin1Char('.')).trimmed();
    if (id == QLatin1String("montaż"))
        id = QStringLiteral("montaz");
    if (asterAppName(id).isEmpty()) {
        err(QStringLiteral("aster: nie znam programu Aster „%1”. Są: code, grafika, montaz, studio, editor, calculator, photos, "
                           "music, video, pdf, camera. Inne programy: flatpak install --user flathub <id>\n").arg(id));
        return 2;
    }
    const QString arch = QSysInfo::currentCpuArchitecture() == QLatin1String("arm64") ? QStringLiteral("aarch64") : QStringLiteral("x86_64");
    const QString file = QDir::tempPath() + QStringLiteral("/aster-%1-%2.flatpak").arg(id, arch);
    err(bold(QStringLiteral("Pobieram %1…").arg(asterAppName(id)), g_errColor) + QStringLiteral("\n"));
    run(QStringLiteral("flatpak"), {QStringLiteral("remote-add"), QStringLiteral("--user"), QStringLiteral("--if-not-exists"), QStringLiteral("flathub"),
                                    QStringLiteral("https://dl.flathub.org/repo/flathub.flatpakrepo")});
    if (run(QStringLiteral("curl"), {QStringLiteral("-fL"), isatty(STDERR_FILENO) ? QStringLiteral("--progress-bar") : QStringLiteral("-sS"),
                                     QStringLiteral("-o"), file,
                                     QStringLiteral("https://github.com/Feejd/aster/releases/download/aplikacje/%1-%2.flatpak").arg(id, arch)}) != 0) {
        err(QStringLiteral("aster: nie udało się pobrać %1 (brak internetu albo paczki dla %2)\n").arg(asterAppName(id), arch));
        return 1;
    }
    err(bold(QStringLiteral("Instaluję %1 (za pierwszym razem dochodzą biblioteki KDE, ok. 400 MB)…").arg(asterAppName(id)), g_errColor) + QStringLiteral("\n"));
    const int code = run(QStringLiteral("flatpak"), {QStringLiteral("install"), QStringLiteral("--user"), QStringLiteral("--reinstall"), QStringLiteral("-y"),
                                                     QStringLiteral("--noninteractive"), file});
    QFile::remove(file);
    if (code == 0)
        out(QStringLiteral("Gotowe — %1 jest zainstalowany (aster --otworz %2).\n").arg(asterAppName(id), id));
    return code;
}

// ——— Tryb projektu: pliki od agenta, punkty powrotu, procesy w tle ———

static QString capture(const QString &program, const QStringList &args, int *code = nullptr, const QProcessEnvironment &env = {})
{
    QProcess p;
    if (!env.isEmpty())
        p.setProcessEnvironment(env);
    p.setStandardInputFile(QProcess::nullDevice());
    p.start(program, args);
    if (!p.waitForStarted(10000)) {
        if (code)
            *code = 127;
        return {};
    }
    p.waitForFinished(-1);
    if (code)
        *code = p.exitStatus() == QProcess::NormalExit ? p.exitCode() : 130;
    return QString::fromUtf8(p.readAllStandardOutput()) + QString::fromUtf8(p.readAllStandardError());
}

// Punkty powrotu: osobne repozytorium gita poza projektem (~/.local/share/aster/punkty/<skrót>.git, drzewo robocze =
// folder projektu) — działa też w folderach bez gita i nie dotyka gita użytkownika
struct Snapshots {
    QString root;
    QString gitDir;

    explicit Snapshots(const QString &projectRoot)
        : root(projectRoot)
    {
        const QString hash = QString::fromLatin1(QCryptographicHash::hash(projectRoot.toUtf8(), QCryptographicHash::Sha1).toHex().left(12));
        gitDir = QStandardPaths::writableLocation(QStandardPaths::GenericDataLocation) + QStringLiteral("/aster/punkty/") + hash + QStringLiteral(".git");
    }
    QString git(const QStringList &args, int *code = nullptr) const
    {
        QProcessEnvironment env = QProcessEnvironment::systemEnvironment();
        env.insert(QStringLiteral("GIT_AUTHOR_NAME"), QStringLiteral("Aster Intelligence"));
        env.insert(QStringLiteral("GIT_AUTHOR_EMAIL"), QStringLiteral("intelligence@aster.local"));
        env.insert(QStringLiteral("GIT_COMMITTER_NAME"), QStringLiteral("Aster Intelligence"));
        env.insert(QStringLiteral("GIT_COMMITTER_EMAIL"), QStringLiteral("intelligence@aster.local"));
        return capture(QStringLiteral("git"), QStringList{QStringLiteral("--git-dir=") + gitDir, QStringLiteral("--work-tree=") + root,
                                                          QStringLiteral("-c"), QStringLiteral("core.quotepath=off")} + args,
                       code, env);
    }
    bool ensure() const
    {
        if (QFileInfo::exists(gitDir + QStringLiteral("/HEAD")))
            return true;
        QDir().mkpath(gitDir);
        int code = 0;
        capture(QStringLiteral("git"), {QStringLiteral("init"), QStringLiteral("-q"), QStringLiteral("--bare"), gitDir}, &code);
        if (code != 0)
            return false;
        QFile ex(gitDir + QStringLiteral("/info/exclude"));
        QDir().mkpath(gitDir + QStringLiteral("/info"));
        if (ex.open(QIODevice::WriteOnly))
            ex.write("# Duże i odtwarzalne foldery — bez nich punkty powrotu są szybkie\n.git/\nnode_modules/\n.venv/\nvenv/\n"
                     "__pycache__/\n.next/\n.nuxt/\ndist/\nbuild/\ntarget/\n.cache/\n*.log\n*.sqlite-journal\n");
        QFile r(gitDir + QStringLiteral("/aster-root"));
        if (r.open(QIODevice::WriteOnly))
            r.write(root.toUtf8());
        return true;
    }
    // Stan projektu teraz → refs/punkty/<nazwa> (jeśli już jest — nic)
    bool take(const QString &name) const
    {
        if (!ensure())
            return false;
        int code = 0;
        git({QStringLiteral("rev-parse"), QStringLiteral("-q"), QStringLiteral("--verify"), QStringLiteral("refs/punkty/") + name}, &code);
        if (code == 0)
            return true;
        git({QStringLiteral("add"), QStringLiteral("-A"), QStringLiteral(".")}, &code);
        git({QStringLiteral("commit"), QStringLiteral("-q"), QStringLiteral("--allow-empty"), QStringLiteral("--no-verify"), QStringLiteral("-m"), name}, &code);
        if (code != 0)
            return false;
        git({QStringLiteral("update-ref"), QStringLiteral("refs/punkty/") + name, QStringLiteral("HEAD")}, &code);
        return code == 0;
    }
    QStringList list() const
    {
        if (!QFileInfo::exists(gitDir + QStringLiteral("/HEAD")))
            return {};
        return git({QStringLiteral("for-each-ref"), QStringLiteral("--sort=-creatordate"),
                    QStringLiteral("--format=%(refname:lstrip=2)\t%(creatordate:format:%Y-%m-%d %H:%M)"), QStringLiteral("refs/punkty")})
            .split(QLatin1Char('\n'), Qt::SkipEmptyParts);
    }
    // Projekt wraca do stanu z punktu; obecny stan zostaje jako punkt „przed-cofnieciem-…” (cofnięcie da się cofnąć)
    QString restore(const QString &name) const
    {
        const QString ref = QStringLiteral("refs/punkty/") + name;
        int code = 0;
        git({QStringLiteral("rev-parse"), QStringLiteral("-q"), QStringLiteral("--verify"), ref}, &code);
        if (code != 0)
            return QStringLiteral("Nie ma punktu %1").arg(name);
        take(QStringLiteral("przed-cofnieciem-") + QDateTime::currentDateTime().toString(QStringLiteral("yyyyMMdd-HHmmss")));
        // pliki dodane po punkcie — do usunięcia; reszta wraca z punktu
        const QStringList added = git({QStringLiteral("diff"), QStringLiteral("--name-only"), QStringLiteral("--diff-filter=A"), ref, QStringLiteral("HEAD")})
                                      .split(QLatin1Char('\n'), Qt::SkipEmptyParts);
        for (const QString &f : added)
            QFile::remove(root + QLatin1Char('/') + f);
        const QString changed = git({QStringLiteral("diff"), QStringLiteral("--name-only"), ref, QStringLiteral("HEAD")});
        git({QStringLiteral("checkout"), QStringLiteral("-f"), ref, QStringLiteral("--"), QStringLiteral(".")}, &code);
        if (code != 0)
            return QStringLiteral("Nie udało się przywrócić plików");
        const int n = int(changed.split(QLatin1Char('\n'), Qt::SkipEmptyParts).size());
        return QStringLiteral("ok:%1").arg(n);
    }
};

static QStringList allSnapshotRoots()
{
    QStringList roots;
    const QDir d(QStandardPaths::writableLocation(QStandardPaths::GenericDataLocation) + QStringLiteral("/aster/punkty"));
    for (const QString &g : d.entryList({QStringLiteral("*.git")}, QDir::Dirs)) {
        QFile f(d.filePath(g) + QStringLiteral("/aster-root"));
        if (f.open(QIODevice::ReadOnly))
            roots << QString::fromUtf8(f.readAll()).trimmed();
    }
    return roots;
}

static QString rel(const QString &path, const QString &workdir)
{
    if (!workdir.isEmpty() && path.startsWith(workdir + QLatin1Char('/')))
        return path.mid(workdir.size() + 1);
    if (path.startsWith(QDir::homePath() + QLatin1Char('/')))
        return QStringLiteral("~/") + path.mid(QDir::homePath().size() + 1);
    return path;
}

static int lineCount(const QString &t)
{
    if (t.isEmpty())
        return 0;
    return int(t.count(QLatin1Char('\n'))) + (t.endsWith(QLatin1Char('\n')) ? 0 : 1);
}

// Zamiana fragmentu: dokładnie raz; inaczej — te same wiersze bez różnic w odstępach na końcach i wcięciach
static bool replaceOnce(QString &text, const QString &before, const QString &after, QString *problem)
{
    if (before.isEmpty()) {
        *problem = QStringLiteral("pusty fragment STARE");
        return false;
    }
    const qsizetype n = text.count(before);
    if (n == 1) {
        text.replace(text.indexOf(before), before.size(), after);
        return true;
    }
    if (n > 1) {
        *problem = QStringLiteral("fragment występuje %1 razy — dodaj więcej wierszy dla jednoznaczności").arg(n);
        return false;
    }
    QStringList lines = text.split(QLatin1Char('\n'));
    QStringList want = before.split(QLatin1Char('\n'));
    while (!want.isEmpty() && want.last().trimmed().isEmpty())
        want.removeLast();
    int found = -1, count = 0;
    for (int i = 0; i + want.size() <= lines.size(); ++i) {
        bool ok = true;
        for (int j = 0; j < want.size() && ok; ++j)
            ok = lines.at(i + j).trimmed() == want.at(j).trimmed();
        if (ok) {
            found = i;
            ++count;
        }
    }
    if (count != 1) {
        *problem = count == 0 ? QStringLiteral("nie ma w pliku fragmentu zaczynającego się od „%1”").arg(want.value(0).trimmed().left(80))
                              : QStringLiteral("fragment występuje %1 razy").arg(count);
        return false;
    }
    QStringList repl = after.split(QLatin1Char('\n'));
    for (int j = 0; j < want.size(); ++j)
        lines.removeAt(found);
    for (int j = 0; j < repl.size(); ++j)
        lines.insert(found + j, repl.at(j));
    text = lines.join(QLatin1Char('\n'));
    return true;
}

// aster --zmiany KATALOG --punkt PUNKT --w FOLDER — pliki zapisane przez agenta (manifest od usługi)
static int applyChanges(const QStringList &args)
{
    const QString dir = args.value(0);
    const QString punkt = args.indexOf(QLatin1String("--punkt")) >= 0 ? args.value(args.indexOf(QLatin1String("--punkt")) + 1) : QString();
    const QString workdir = args.indexOf(QLatin1String("--w")) >= 0 ? args.value(args.indexOf(QLatin1String("--w")) + 1) : QDir::currentPath();
    QFile mf(dir + QStringLiteral("/manifest.json"));
    if (!mf.open(QIODevice::ReadOnly)) {
        err(QStringLiteral("aster: nie ma zmian w %1\n").arg(dir));
        return 2;
    }
    const QJsonArray items = QJsonDocument::fromJson(mf.readAll()).array();
    QStringList planned;
    for (const QJsonValue &v : items)
        if (v.toObject().value(QStringLiteral("kind")).toString() == QLatin1String("plik"))
            planned << v.toObject().value(QStringLiteral("path")).toString();
    // Punkt powrotu każdego projektu, którego dotyczą zmiany — raz na pytanie, przed pierwszym zapisem
    QStringList roots;
    for (const QJsonValue &v : items) {
        const QString root = Commands::projectRoot(v.toObject().value(QStringLiteral("path")).toString(), planned);
        if (!root.isEmpty() && !roots.contains(root) && QFileInfo(root).isDir())
            roots << root;
    }
    if (!punkt.isEmpty())
        for (const QString &r : std::as_const(roots))
            if (!Snapshots(r).take(punkt))
                err(dim(QStringLiteral("(nie udało się zrobić punktu powrotu w %1)\n").arg(rel(r, workdir)), g_errColor));
    int failed = 0;
    for (const QJsonValue &v : items) {
        const QJsonObject o = v.toObject();
        const QString path = o.value(QStringLiteral("path")).toString();
        QFile src(dir + QLatin1Char('/') + o.value(QStringLiteral("file")).toString());
        if (!src.open(QIODevice::ReadOnly))
            continue;
        const QString body = QString::fromUtf8(src.readAll());
        QFile target(path);
        const bool existed = target.exists();
        QString old;
        if (existed && target.open(QIODevice::ReadOnly)) {
            old = QString::fromUtf8(target.readAll());
            target.close();
        }
        QString next;
        if (o.value(QStringLiteral("kind")).toString() == QLatin1String("plik")) {
            next = body;
        } else {
            if (!existed) {
                out(QStringLiteral("✗ %1: plik nie istnieje (nowy plik zapisz blokiem plik)\n").arg(rel(path, workdir)));
                ++failed;
                continue;
            }
            next = old;
            QStringList problems;
            const auto hs = Blocks::hunks(body);
            if (hs.isEmpty())
                problems << QStringLiteral("brak par <<<<<<< STARE / ======= / >>>>>>> NOWE");
            for (const Blocks::Hunk &h : hs) {
                QString problem;
                if (!replaceOnce(next, h.before, h.after, &problem))
                    problems << problem;
            }
            if (!problems.isEmpty()) {
                out(QStringLiteral("✗ %1: %2 — przeczytaj plik (cat -n) i spróbuj jeszcze raz; nic w nim nie zmieniłem\n")
                        .arg(rel(path, workdir), problems.join(QStringLiteral("; "))));
                ++failed;
                continue;
            }
        }
        QDir().mkpath(QFileInfo(path).absolutePath());
        QSaveFile w(path);
        if (!w.open(QIODevice::WriteOnly) || w.write(next.toUtf8()) < 0 || !w.commit()) {
            out(QStringLiteral("✗ %1: nie da się zapisać (%2)\n").arg(rel(path, workdir), w.errorString()));
            ++failed;
            continue;
        }
        if (!existed)
            out(QStringLiteral("+ %1 (nowy, %2 wierszy)\n").arg(rel(path, workdir)).arg(lineCount(next)));
        else
            out(QStringLiteral("~ %1 (%2 → %3 wierszy)\n").arg(rel(path, workdir)).arg(lineCount(old)).arg(lineCount(next)));
    }
    if (!roots.isEmpty() && !punkt.isEmpty())
        out(dim(QStringLiteral("(punkt powrotu: %1 — cofnięcie: aster --cofnij %1)\n").arg(punkt), g_color));
    QDir(dir).removeRecursively();
    return failed ? 1 : 0;
}

// aster --punkty [FOLDER] — punkty powrotu projektu (bez folderu: bieżący projekt albo wszystkie)
static int listSnapshots(const QString &folder)
{
    const QString start = folder.isEmpty() ? QDir::currentPath() : Commands::expandPath(folder, QDir::currentPath());
    QString root = Commands::projectRoot(start + QStringLiteral("/x"));
    const QStringList roots = root.isEmpty() ? allSnapshotRoots() : QStringList{root};
    bool any = false;
    for (const QString &r : roots) {
        const QStringList l = Snapshots(r).list();
        if (l.isEmpty())
            continue;
        any = true;
        out(bold(rel(r, QString()), g_color) + QStringLiteral("\n"));
        for (const QString &line : l.mid(0, 15))
            out(QStringLiteral("  %1   %2\n").arg(line.section(QLatin1Char('\t'), 1), line.section(QLatin1Char('\t'), 0, 0)));
    }
    if (!any)
        out(QStringLiteral("Brak punktów powrotu — powstają same, gdy Aster Intelligence zmienia pliki projektu.\n"));
    return 0;
}

// aster --cofnij [PUNKT] [--w FOLDER] — projekt wraca do stanu sprzed zmian agenta (bez punktu: ostatni w bieżącym projekcie)
static int undo(const QStringList &args)
{
    QString name = args.value(0);
    if (name == QLatin1String("--w"))
        name.clear();
    const QString folder = args.indexOf(QLatin1String("--w")) >= 0 ? args.value(args.indexOf(QLatin1String("--w")) + 1) : QDir::currentPath();
    QStringList roots;
    if (!name.isEmpty()) {
        for (const QString &r : allSnapshotRoots())
            for (const QString &l : Snapshots(r).list())
                if (l.section(QLatin1Char('\t'), 0, 0) == name)
                    roots << r;
    } else {
        const QString r = Commands::projectRoot(Commands::expandPath(folder, QDir::currentPath()) + QStringLiteral("/x"));
        if (!r.isEmpty()) {
            for (const QString &l : Snapshots(r).list())
                if (!l.startsWith(QLatin1String("przed-cofnieciem-"))) {
                    name = l.section(QLatin1Char('\t'), 0, 0);
                    break;
                }
            roots << r;
        }
    }
    if (roots.isEmpty() || name.isEmpty()) {
        err(QStringLiteral("aster: nie ma takiego punktu powrotu (lista: aster --punkty)\n"));
        return 1;
    }
    int code = 0;
    for (const QString &r : roots) {
        const QString res = Snapshots(r).restore(name);
        if (res.startsWith(QLatin1String("ok:")))
            out(QStringLiteral("Cofnięto zmiany w %1 (%2 plików wróciło do stanu z punktu %3). Ponowne zastosowanie: "
                               "aster --punkty i aster --cofnij przed-cofnieciem-…\n").arg(rel(r, QString()), res.mid(3), name));
        else {
            err(res + QStringLiteral("\n"));
            code = 1;
        }
    }
    return code;
}

// ——— Procesy w tle (systemd --user: aster-tlo-NAZWA) ———

static QString unitFor(const QString &name)
{
    QString n = name.toLower();
    n.replace(QRegularExpression(QStringLiteral("[^a-z0-9_-]")), QStringLiteral("-"));
    return QStringLiteral("aster-tlo-") + (n.isEmpty() ? QStringLiteral("serwer") : n);
}

static QString shellQuote(const QString &s)
{
    static const QRegularExpression plain(QStringLiteral("^[A-Za-z0-9_./:=@%+,-]+$"));
    if (plain.match(s).hasMatch())
        return s;
    return QLatin1Char('\'') + QString(s).replace(QLatin1Char('\''), QStringLiteral("'\\''")) + QLatin1Char('\'');
}

// Porty, na których nasłuchują procesy usługi (cgroup); gdy żadnych (np. kontener) — wszystkie porty użytkownika
static QString portsOf(const QString &unit)
{
    const QString cg = capture(QStringLiteral("systemctl"), {QStringLiteral("--user"), QStringLiteral("show"), QStringLiteral("-p"),
                                                             QStringLiteral("ControlGroup"), QStringLiteral("--value"), unit}).trimmed();
    QSet<QString> pids;
    if (!cg.isEmpty()) {
        QFile f(QStringLiteral("/sys/fs/cgroup") + cg + QStringLiteral("/cgroup.procs"));
        if (f.open(QIODevice::ReadOnly))
            for (const QByteArray &p : f.readAll().split('\n'))
                if (!p.trimmed().isEmpty())
                    pids << QString::fromLatin1(p.trimmed());
    }
    const QStringList lines = capture(QStringLiteral("ss"), {QStringLiteral("-ltnpH")}).split(QLatin1Char('\n'), Qt::SkipEmptyParts);
    QStringList mine, all;
    static const QRegularExpression pidRe(QStringLiteral("pid=(\\d+)"));
    for (const QString &l : lines) {
        const QStringList cols = l.simplified().split(QLatin1Char(' '));
        const QString addr = cols.value(3);
        const QString port = addr.section(QLatin1Char(':'), -1);
        const QString prog = l.section(QStringLiteral("((\""), 1).section(QLatin1Char('"'), 0, 0);
        if (prog.isEmpty())
            continue;
        const QString entry = QStringLiteral("%1 (%2)").arg(port, prog);
        all << entry;
        auto it = pidRe.globalMatch(l);
        while (it.hasNext())
            if (pids.contains(it.next().captured(1)))
                mine << entry;
    }
    mine.removeDuplicates();
    all.removeDuplicates();
    if (!mine.isEmpty())
        return QStringLiteral("Porty: ") + mine.join(QStringLiteral(", "));
    return all.isEmpty() ? QStringLiteral("Porty: na razie żaden") : QStringLiteral("Porty użytkownika: ") + all.join(QStringLiteral(", "));
}

static QString unitState(const QString &unit)
{
    return capture(QStringLiteral("systemctl"), {QStringLiteral("--user"), QStringLiteral("is-active"), unit}).trimmed();
}

static QString unitLogs(const QString &unit, int n)
{
    return capture(QStringLiteral("journalctl"), {QStringLiteral("--user"), QStringLiteral("-u"), unit, QStringLiteral("-n"), QString::number(n),
                                                  QStringLiteral("--no-pager"), QStringLiteral("-o"), QStringLiteral("cat")});
}

static int background(const QStringList &args)
{
    const QString what = args.value(0);
    if (what == QLatin1String("lista") || what.isEmpty()) {
        const QStringList units = capture(QStringLiteral("systemctl"), {QStringLiteral("--user"), QStringLiteral("list-units"), QStringLiteral("aster-tlo-*"),
                                                                        QStringLiteral("--all"), QStringLiteral("--no-legend"), QStringLiteral("--plain")})
                                      .split(QLatin1Char('\n'), Qt::SkipEmptyParts);
        if (units.isEmpty())
            out(QStringLiteral("Nic nie działa w tle.\n"));
        for (const QString &u : units) {
            const QString unit = u.simplified().section(QLatin1Char(' '), 0, 0);
            if (!unit.startsWith(QLatin1String("aster-tlo-")) || !unit.endsWith(QLatin1String(".service")))
                continue;
            out(QStringLiteral("%1 — %2 · %3\n").arg(unit.mid(10).chopped(8), u.simplified().section(QLatin1Char(' '), 2, 3), portsOf(unit)));
        }
        return 0;
    }
    const QString name = args.value(1);
    const QString unit = unitFor(name) + QStringLiteral(".service");
    if (what == QLatin1String("logi")) {
        out(QStringLiteral("%1: %2 · %3\n").arg(name, unitState(unit), portsOf(unit)));
        out(unitLogs(unit, args.value(2).toInt() > 0 ? args.value(2).toInt() : 60));
        return 0;
    }
    if (what == QLatin1String("stop")) {
        int code = 0;
        capture(QStringLiteral("systemctl"), {QStringLiteral("--user"), QStringLiteral("stop"), unit}, &code);
        out(code == 0 ? QStringLiteral("Zatrzymano: %1\n").arg(name) : QStringLiteral("Nie było uruchomione: %1\n").arg(name));
        return 0;
    }
    if (what != QLatin1String("start") || name.isEmpty()) {
        err(QStringLiteral("aster --tlo start NAZWA [--w FOLDER] -- polecenie | logi NAZWA [N] | stop NAZWA | lista\n"));
        return 2;
    }
    const int dash = int(args.indexOf(QLatin1String("--")));
    if (dash < 0 || dash + 1 >= args.size()) {
        err(QStringLiteral("aster: po „--” podaj polecenie, np. aster --tlo start web --w ~/Projekty/sklep -- npm run dev\n"));
        return 2;
    }
    const int wi = int(args.indexOf(QLatin1String("--w")));
    const QString dir = wi >= 0 && wi < dash ? Commands::expandPath(args.value(wi + 1), QDir::currentPath()) : QDir::currentPath();
    QStringList cmd;
    for (const QString &a : args.mid(dash + 1))
        cmd << shellQuote(a);
    // To samo NAZWA działa już — restart z nowym poleceniem
    capture(QStringLiteral("systemctl"), {QStringLiteral("--user"), QStringLiteral("stop"), unit});
    capture(QStringLiteral("systemctl"), {QStringLiteral("--user"), QStringLiteral("reset-failed"), unit});
    int code = 0;
    const QString res = capture(QStringLiteral("systemd-run"),
                                {QStringLiteral("--user"), QStringLiteral("--quiet"), QStringLiteral("--collect"), QStringLiteral("--unit=") + unit,
                                 QStringLiteral("--property=WorkingDirectory=") + dir, QStringLiteral("--setenv=PATH=") + qEnvironmentVariable("PATH"),
                                 QStringLiteral("--setenv=TERM=dumb"), QStringLiteral("--setenv=FORCE_COLOR=0"), QStringLiteral("--setenv=CI=1"),
                                 QStringLiteral("bash"), QStringLiteral("-lc"), cmd.join(QLatin1Char(' '))},
                                &code);
    if (code != 0) {
        err(QStringLiteral("aster: nie udało się uruchomić w tle: %1\n").arg(res.trimmed()));
        return 1;
    }
    // Chwila na start — model od razu widzi pierwsze logi, port albo błąd
    QString state;
    for (int i = 0; i < 16; ++i) {
        QThread::msleep(500);
        state = unitState(unit);
        if (state != QLatin1String("active") && state != QLatin1String("activating"))
            break;
        if (i >= 5 && portsOf(unit).startsWith(QLatin1String("Porty: ")) && !portsOf(unit).contains(QLatin1String("żaden")))
            break;
    }
    const bool running = state == QLatin1String("active") || state == QLatin1String("activating");
    out(running ? QStringLiteral("Działa w tle: %1 (w %2) · %3\n").arg(name, rel(dir, QString()), portsOf(unit))
                : QStringLiteral("Zakończył się od razu: %1 (stan: %2)\n").arg(name, state));
    out(QStringLiteral("— ostatnie logi —\n") + unitLogs(unit, 25));
    return running ? 0 : 1;
}

// Polecenie uruchomione przez agenta (ASTER_AGENT=1): przy chmurze bez rozmów prowadzonych tylko na tym komputerze
static bool fromAgent() { return qEnvironmentVariableIsSet("ASTER_AGENT"); }

static QString when(qint64 ms)
{
    const QDateTime t = QDateTime::fromMSecsSinceEpoch(ms);
    const qint64 days = t.date().daysTo(QDate::currentDate());
    if (days == 0)
        return QStringLiteral("dziś ") + t.toString(QStringLiteral("HH:mm"));
    if (days == 1)
        return QStringLiteral("wczoraj ") + t.toString(QStringLiteral("HH:mm"));
    return t.toString(QStringLiteral("yyyy-MM-dd HH:mm"));
}

static int history(const QString &phrase)
{
    const QDBusMessage r = call(QStringLiteral("SearchConversations"), {phrase, fromAgent()});
    if (failedCall(r))
        return 1;
    const QJsonArray list = QJsonDocument::fromJson(r.arguments().value(0).toString().toUtf8()).array();
    if (list.isEmpty()) {
        out(phrase.isEmpty() ? QStringLiteral("Brak zapisanych rozmów.\n") : QStringLiteral("Nie znalazłem rozmowy o „%1”.\n").arg(phrase));
        return phrase.isEmpty() ? 0 : 1;
    }
    for (const QJsonValue &v : list) {
        const QJsonObject o = v.toObject();
        out(bold(o.value(QStringLiteral("title")).toString(), g_color) + QStringLiteral("  ")
            + dim(QStringLiteral("%1 · ID %2").arg(when(o.value(QStringLiteral("updated")).toInteger()), o.value(QStringLiteral("id")).toString()), g_color)
            + QStringLiteral("\n  ") + o.value(QStringLiteral("summary")).toString() + QStringLiteral("\n"));
        const QString snip = o.value(QStringLiteral("snippet")).toString();
        if (!snip.isEmpty())
            out(dim(QStringLiteral("  …%1…\n").arg(snip), g_color));
    }
    return 0;
}

static int showConversation(const QString &id)
{
    const QDBusMessage r = call(QStringLiteral("ConversationText"), {id, fromAgent()});
    if (failedCall(r))
        return 1;
    const QJsonObject o = QJsonDocument::fromJson(r.arguments().value(0).toString().toUtf8()).object();
    if (o.isEmpty()) {
        err(QStringLiteral("aster: nie ma rozmowy %1 (lista: aster --historia)\n").arg(id));
        return 1;
    }
    out(bold(o.value(QStringLiteral("title")).toString(), g_color) + QStringLiteral("  ")
        + dim(when(o.value(QStringLiteral("updated")).toInteger()), g_color) + QStringLiteral("\n\n"));
    if (o.value(QStringLiteral("private")).toBool()) {
        // Model w chmurze nie dostaje treści rozmowy, którą prowadził model na tym komputerze
        out(QStringLiteral("Ta rozmowa była prowadzona na tym komputerze — jej treść nie trafia do chmury. "
                           "Użytkownik zobaczy ją w panelu.\n"));
        return 0;
    }
    out(o.value(QStringLiteral("text")).toString());
    return 0;
}

static void printHelp()
{
    out(QStringLiteral(
        "Aster Intelligence w terminalu\n\n"
        "  aster \"pytanie\"            odpowiedź od razu\n"
        "  aster                      rozmowa (wiele pytań)\n"
        "  polecenie | aster \"pytanie\" wynik polecenia jako kontekst, np.\n"
        "                             journalctl -b -p err | aster \"co tu jest nie tak?\"\n"
        "                             git diff | aster \"napisz opis commita\"\n"
        "  aster --stan               kto odpowiada (model lokalny czy chmura)\n"
        "  aster --historia [słowa]   wcześniejsze rozmowy (szukanie po słowach)\n"
        "  aster --rozmowa ID         cała wcześniejsza rozmowa\n"
        "  aster --okna               otwarte okna; --pokaz / --zminimalizuj / --maksymalizuj / --zamknij-okno OKNO\n"
        "  aster --otworz PROGRAM [plik|adres…]  np. aster --otworz \"aster code\" ~/projekt\n"
        "  aster --instaluj PROGRAM   program Aster (code, grafika, montaz, studio…)\n"
        "  aster --tlo start NAZWA [--w FOLDER] -- polecenie   serwer w tle; logi NAZWA, stop NAZWA, lista\n"
        "  aster --punkty [FOLDER]    punkty powrotu projektu; aster --cofnij [PUNKT] — cofa zmiany agenta\n\n"
        "W rozmowie: /nowa — nowa rozmowa, /model — dostawca i model, /wyjdz — koniec.\n"
        "Aster Intelligence sam sprawdza i naprawia: zwykłe polecenia uruchamia od razu, a przed ważnymi\n"
        "(instalacja, usuwanie, hasło administratora, restart) pyta [T/n].\n"
        "Model na tym komputerze: aster --model-lokalny (lista), aster --model-lokalny auto (pobiera polecany).\n"
        "Dostawcę, model i klucz API ustawisz też w Ustawieniach → Aster Intelligence. `ai` to skrót od `aster`.\n"));
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
    err(bold(QStringLiteral("Aster Intelligence"), g_errColor) + dim(QStringLiteral(" · ") + who(s), g_errColor) + QStringLiteral("\n"));
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
    if (!args.isEmpty() && (args.first() == QLatin1String("--model-lokalny") || args.first() == QLatin1String("--local-model")))
        return localModel(args.value(1));
    if (!args.isEmpty() && args.first() == QLatin1String("--zmiany"))
        return applyChanges(args.mid(1));
    if (!args.isEmpty() && args.first() == QLatin1String("--punkty"))
        return listSnapshots(args.value(1));
    if (!args.isEmpty() && args.first() == QLatin1String("--cofnij"))
        return undo(args.mid(1));
    if (!args.isEmpty() && args.first() == QLatin1String("--tlo"))
        return background(args.mid(1));
    if (!args.isEmpty() && args.first() == QLatin1String("--okna"))
        return listWindows();
    if (!args.isEmpty() && (args.first() == QLatin1String("--pokaz") || args.first() == QLatin1String("--zminimalizuj")
                            || args.first() == QLatin1String("--maksymalizuj") || args.first() == QLatin1String("--zamknij-okno")))
        return windowAction(args.first() == QLatin1String("--zamknij-okno") ? QStringLiteral("zamknij") : args.first().mid(2),
                            args.mid(1).join(QLatin1Char(' ')));
    if (!args.isEmpty() && args.first() == QLatin1String("--otworz"))
        return openApp(args.mid(1));
    if (!args.isEmpty() && args.first() == QLatin1String("--instaluj"))
        return installApp(args.mid(1).join(QLatin1Char(' ')));
    if (!args.isEmpty() && args.first() == QLatin1String("--historia"))
        return history(args.mid(1).join(QLatin1Char(' ')));
    if (!args.isEmpty() && args.first() == QLatin1String("--rozmowa")) {
        if (args.value(1).isEmpty()) {
            err(QStringLiteral("aster: podaj ID rozmowy (lista: aster --historia)\n"));
            return 2;
        }
        return showConversation(args.value(1));
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
    return 0;
}

#include "aster.moc"
