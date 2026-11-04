#include "debugger.h"
#include "projectenv.h"

#include <QDir>
#include <QDirIterator>
#include <QFile>
#include <QFileInfo>
#include <QJsonArray>
#include <QJsonDocument>
#include <QRegularExpression>
#include <QStandardPaths>
#include <QTimer>

namespace {

bool has(const QString &program)
{
    return ProjectEnv::instance()->has(program);
}

bool hasDebugpy()
{
    static int cached = -1;
    if (cached < 0) {
        QProcess p;
        const QStringList argv = ProjectEnv::instance()->program({QStringLiteral("python3"), QStringLiteral("-c"), QStringLiteral("import debugpy")});
        p.start(argv.first(), argv.mid(1));
        cached = p.waitForFinished(3000) && p.exitStatus() == QProcess::NormalExit && p.exitCode() == 0 ? 1 : 0;
    }
    return cached == 1;
}

// gdb obsługuje DAP od wersji 14
bool gdbHasDap()
{
    static int cached = -1;
    if (cached < 0) {
        cached = 0;
        if (has(QStringLiteral("gdb"))) {
            QProcess p;
            const QStringList argv = ProjectEnv::instance()->program({QStringLiteral("gdb"), QStringLiteral("--version")});
            p.start(argv.first(), argv.mid(1));
            if (p.waitForFinished(3000)) {
                const QString v = QString::fromUtf8(p.readAllStandardOutput()).section(QLatin1Char('\n'), 0, 0);
                static const QRegularExpression ver(QStringLiteral("(\\d+)\\.\\d+"));
                const auto m = ver.match(v.section(QLatin1Char(')'), -1));
                cached = m.hasMatch() && m.captured(1).toInt() >= 14 ? 1 : 0;
            }
        }
    }
    return cached == 1;
}

} // namespace

Debugger::Debugger(QObject *parent)
    : QObject(parent)
{
}

Debugger::~Debugger()
{
    if (m_proc) {
        m_proc->disconnect(this);
        m_proc->kill();
        m_proc->waitForFinished(500);
    }
}

// ——— Punkty przerwania ———

QVariantList Debugger::breakpoints(const QString &path) const
{
    QVariantList out;
    for (int l : m_bps.value(path))
        out << l;
    return out;
}

void Debugger::toggleBreakpoint(const QString &path, int line)
{
    QList<int> &list = m_bps[path];
    if (list.contains(line))
        list.removeAll(line);
    else
        list << line;
    if (list.isEmpty())
        m_bps.remove(path);
    ++m_revision;
    Q_EMIT breakpointsChanged();
    if (!m_state.isEmpty())
        sendBreakpoints(path);
}

void Debugger::clearBreakpoints()
{
    const QStringList paths = m_bps.keys();
    m_bps.clear();
    ++m_revision;
    Q_EMIT breakpointsChanged();
    if (!m_state.isEmpty())
        for (const QString &p : paths)
            sendBreakpoints(p);
}

int Debugger::breakpointCount() const
{
    int n = 0;
    for (const QList<int> &l : m_bps)
        n += int(l.size());
    return n;
}

// ——— Uruchamianie ———

QVariantMap Debugger::adapterFor(const QString &kind) const
{
    if (kind == QLatin1String("python"))
        return {{QStringLiteral("available"), has(QStringLiteral("python3")) && hasDebugpy()}, {QStringLiteral("name"), QStringLiteral("debugpy")},
                {QStringLiteral("install"), QStringLiteral("sudo dnf install python3-debugpy")}};
    if (gdbHasDap())
        return {{QStringLiteral("available"), true}, {QStringLiteral("name"), QStringLiteral("gdb")}, {QStringLiteral("install"), QString()}};
    if (has(QStringLiteral("lldb-dap")) || has(QStringLiteral("lldb-vscode")))
        return {{QStringLiteral("available"), true}, {QStringLiteral("name"), QStringLiteral("lldb")}, {QStringLiteral("install"), QString()}};
    return {{QStringLiteral("available"), false}, {QStringLiteral("name"), QStringLiteral("gdb")},
            {QStringLiteral("install"), QStringLiteral("sudo dnf install gdb")}};
}

QString Debugger::guessProgram(const QString &root) const
{
    // Pliki ELF z bitem wykonywania, najnowszy pierwszy; bez .git, node_modules i bibliotek
    QString best;
    QDateTime bestTime;
    QDirIterator it(root, QDir::Files | QDir::Executable | QDir::NoSymLinks, QDirIterator::Subdirectories);
    int seen = 0;
    while (it.hasNext() && seen < 20000) {
        const QString p = it.next();
        ++seen;
        if (p.contains(QLatin1String("/.git/")) || p.contains(QLatin1String("/node_modules/")) || p.contains(QLatin1String("/CMakeFiles/"))
            || p.endsWith(QLatin1String(".so")) || p.contains(QLatin1String(".so.")))
            continue;
        QFile f(p);
        if (!f.open(QIODevice::ReadOnly) || f.read(4) != QByteArray("\x7f" "ELF", 4))
            continue;
        const QDateTime t = it.fileInfo().lastModified();
        if (best.isEmpty() || t > bestTime) {
            best = p;
            bestTime = t;
        }
    }
    return best;
}

bool Debugger::start(const QString &kind, const QString &program, const QString &args, const QString &cwd)
{
    if (!m_state.isEmpty())
        stop();
    QString exe;
    QStringList exeArgs;
    QJsonObject launch;
    const QStringList argv = QProcess::splitCommand(args);
    if (kind == QLatin1String("python")) {
        exe = QStringLiteral("python3");
        exeArgs = {QStringLiteral("-m"), QStringLiteral("debugpy.adapter")};
        m_adapterName = QStringLiteral("debugpy");
        launch = {{"program", program}, {"args", QJsonArray::fromStringList(argv)}, {"cwd", cwd},
                  {"console", "internalConsole"}, {"justMyCode", true}};
    } else if (gdbHasDap()) {
        exe = QStringLiteral("gdb");
        exeArgs = {QStringLiteral("-q"), QStringLiteral("-i"), QStringLiteral("dap")};
        m_adapterName = QStringLiteral("gdb");
        launch = {{"program", program}, {"args", QJsonArray::fromStringList(argv)}, {"cwd", cwd}};
    } else if (has(QStringLiteral("lldb-dap")) || has(QStringLiteral("lldb-vscode"))) {
        exe = has(QStringLiteral("lldb-dap")) ? QStringLiteral("lldb-dap") : QStringLiteral("lldb-vscode");
        m_adapterName = QStringLiteral("lldb");
        launch = {{"program", program}, {"args", QJsonArray::fromStringList(argv)}, {"cwd", cwd}};
    } else {
        Q_EMIT message(QStringLiteral("Brak debugera — zainstaluj gdb (sudo dnf install gdb)"));
        return false;
    }
    if (kind != QLatin1String("python") && !QFileInfo(program).isExecutable()) {
        Q_EMIT message(QStringLiteral("To nie jest program do uruchomienia: ") + program);
        return false;
    }
    m_kind = kind;
    m_launch = launch;
    m_console.clear();
    m_frames.clear();
    m_scopes.clear();
    m_stopPath.clear();
    m_stopLine = -1;
    m_exitCode = -1;
    m_buffer.clear();
    m_replies.clear();
    m_seq = 0;
    Q_EMIT consoleChanged();
    Q_EMIT stopChanged();
    Q_EMIT variablesChanged();

    auto *p = new QProcess(this);
    m_proc = p;
    p->setWorkingDirectory(cwd);
    connect(p, &QProcess::readyReadStandardOutput, this, &Debugger::onData);
    connect(p, &QProcess::readyReadStandardError, this, [this, p] {
        const QString t = QString::fromUtf8(p->readAllStandardError()).trimmed();
        if (!t.isEmpty())
            print(t, QStringLiteral("stderr"));
    });
    connect(p, &QProcess::finished, this, [this] { finish(); });
    connect(p, &QProcess::errorOccurred, this, [this](QProcess::ProcessError e) {
        if (e == QProcess::FailedToStart) {
            Q_EMIT message(QStringLiteral("Nie można uruchomić debugera ") + m_adapterName);
            finish();
        }
    });
    setState(QStringLiteral("starting"));
    print(QStringLiteral("Debugowanie: ") + QFileInfo(program).fileName() + (args.isEmpty() ? QString() : QLatin1Char(' ') + args)
              + QStringLiteral("  (") + m_adapterName + QLatin1Char(')'),
          QStringLiteral("info"));
    // Debuger w kontenerze projektu albo w systemie
    const QStringList adapterArgv = ProjectEnv::instance()->program(QStringList{exe} + exeArgs);
    p->start(adapterArgv.first(), adapterArgv.mid(1));

    // initialize → launch → (zdarzenie initialized) → punkty przerwania → configurationDone
    send(QStringLiteral("initialize"),
         {{"clientID", "aster-code"}, {"clientName", "Aster Code"}, {"adapterID", m_adapterName}, {"locale", "pl"},
          {"linesStartAt1", true}, {"columnsStartAt1", true}, {"pathFormat", "path"}, {"supportsVariableType", true}},
         [this](bool ok, const QJsonObject &, const QString &err) {
             if (!ok) {
                 Q_EMIT message(QStringLiteral("Debuger nie wystartował: ") + err);
                 stop();
                 return;
             }
             send(QStringLiteral("launch"), m_launch, [this](bool ok, const QJsonObject &, const QString &err) {
                 if (!ok) {
                     Q_EMIT message(QStringLiteral("Nie udało się uruchomić programu: ") + err);
                     stop();
                 }
             });
         });
    return true;
}

void Debugger::resume() { if (m_state == QLatin1String("stopped")) { send(QStringLiteral("continue"), {{"threadId", m_threadId}}); setState(QStringLiteral("running")); } }
void Debugger::next() { if (m_state == QLatin1String("stopped")) { send(QStringLiteral("next"), {{"threadId", m_threadId}}); setState(QStringLiteral("running")); } }
void Debugger::stepIn() { if (m_state == QLatin1String("stopped")) { send(QStringLiteral("stepIn"), {{"threadId", m_threadId}}); setState(QStringLiteral("running")); } }
void Debugger::stepOut() { if (m_state == QLatin1String("stopped")) { send(QStringLiteral("stepOut"), {{"threadId", m_threadId}}); setState(QStringLiteral("running")); } }
void Debugger::pause() { if (m_state == QLatin1String("running")) send(QStringLiteral("pause"), {{"threadId", m_threadId}}); }

void Debugger::stop()
{
    if (!m_proc)
        return;
    send(QStringLiteral("disconnect"), {{"terminateDebuggee", true}});
    // Debuger, który nie odpowiada, kończymy po chwili
    QTimer::singleShot(1500, m_proc, [p = m_proc] { if (p && p->state() != QProcess::NotRunning) p->kill(); });
}

void Debugger::finish()
{
    if (m_state.isEmpty())
        return;
    if (m_proc) {
        m_proc->disconnect(this);
        m_proc->deleteLater();
    }
    m_proc = nullptr;
    m_replies.clear();
    m_frames.clear();
    m_scopes.clear();
    m_stopPath.clear();
    m_stopLine = -1;
    print(m_exitCode >= 0 ? QStringLiteral("Program zakończył się z kodem %1").arg(m_exitCode) : QStringLiteral("Debugowanie zakończone"),
          QStringLiteral("info"));
    setState(QString());
    Q_EMIT stopChanged();
    Q_EMIT variablesChanged();
    Q_EMIT ended(m_exitCode);
}

void Debugger::setState(const QString &s)
{
    if (s == m_state)
        return;
    m_state = s;
    Q_EMIT stateChanged();
}

// ——— Protokół ———

void Debugger::send(const QString &command, const QJsonObject &args, Reply reply)
{
    if (!m_proc)
        return;
    const int seq = ++m_seq;
    if (reply)
        m_replies.insert(seq, reply);
    const QByteArray body = QJsonDocument(QJsonObject{{"seq", seq}, {"type", "request"}, {"command", command}, {"arguments", args}})
                                .toJson(QJsonDocument::Compact);
    m_proc->write("Content-Length: " + QByteArray::number(body.size()) + "\r\n\r\n" + body);
}

void Debugger::onData()
{
    m_buffer += m_proc->readAllStandardOutput();
    for (;;) {
        // Wyjście programu (gdb dzieli z nim strumień) przed nagłówkiem — do konsoli; niepełny wiersz czeka
        const int header = int(m_buffer.indexOf("Content-Length:"));
        const int textEnd = header < 0 ? int(m_buffer.lastIndexOf('\n')) + 1 : header;
        if (textEnd > 0) {
            print(QString::fromUtf8(m_buffer.left(textEnd)), QStringLiteral("stdout"));
            m_buffer.remove(0, textEnd);
            continue;
        }
        const int headerEnd = int(m_buffer.indexOf("\r\n\r\n"));
        if (headerEnd < 0)
            return;
        int length = -1;
        for (const QByteArray &h : m_buffer.left(headerEnd).split('\n'))
            if (h.trimmed().toLower().startsWith("content-length:"))
                length = h.mid(h.indexOf(':') + 1).trimmed().toInt();
        if (length < 0) {
            // Coś spoza protokołu (np. wyjście programu) — do konsoli
            print(QString::fromUtf8(m_buffer.left(headerEnd)), QStringLiteral("stdout"));
            m_buffer.remove(0, headerEnd + 4);
            continue;
        }
        if (m_buffer.size() < headerEnd + 4 + length)
            return;
        const QByteArray body = m_buffer.mid(headerEnd + 4, length);
        m_buffer.remove(0, headerEnd + 4 + length);
        onMessage(QJsonDocument::fromJson(body).object());
    }
}

void Debugger::onMessage(const QJsonObject &msg)
{
    const QString type = msg.value(QStringLiteral("type")).toString();
    const QJsonObject body = msg.value(QStringLiteral("body")).toObject();
    if (type == QLatin1String("response")) {
        if (Reply r = m_replies.take(msg.value(QStringLiteral("request_seq")).toInt()))
            r(msg.value(QStringLiteral("success")).toBool(), body,
              body.value(QStringLiteral("error")).toObject().value(QStringLiteral("format")).toString(msg.value(QStringLiteral("message")).toString()));
        return;
    }
    if (type == QLatin1String("request")) {
        // runInTerminal i podobne — odmowa; program działa w konsoli debugera
        if (m_proc) {
            const QByteArray b = QJsonDocument(QJsonObject{{"seq", ++m_seq}, {"type", "response"}, {"request_seq", msg.value(QStringLiteral("seq"))},
                                                           {"command", msg.value(QStringLiteral("command"))}, {"success", false},
                                                           {"message", "nieobsługiwane"}}).toJson(QJsonDocument::Compact);
            m_proc->write("Content-Length: " + QByteArray::number(b.size()) + "\r\n\r\n" + b);
        }
        return;
    }
    const QString ev = msg.value(QStringLiteral("event")).toString();
    if (ev == QLatin1String("initialized")) {
        for (auto it = m_bps.cbegin(); it != m_bps.cend(); ++it)
            sendBreakpoints(it.key());
        send(QStringLiteral("configurationDone"), {});
        setState(QStringLiteral("running"));
    } else if (ev == QLatin1String("stopped")) {
        m_threadId = body.value(QStringLiteral("threadId")).toInt(m_threadId);
        const QString r = body.value(QStringLiteral("reason")).toString();
        m_stopReason = r == QLatin1String("breakpoint") ? QStringLiteral("punkt przerwania") : r == QLatin1String("step") ? QStringLiteral("krok")
                     : r == QLatin1String("pause") ? QStringLiteral("wstrzymano") : r == QLatin1String("exception") || r == QLatin1String("signal")
                         ? QStringLiteral("wyjątek: ") + body.value(QStringLiteral("description")).toString(body.value(QStringLiteral("text")).toString())
                         : r;
        setState(QStringLiteral("stopped"));
        loadStack();
    } else if (ev == QLatin1String("continued")) {
        setState(QStringLiteral("running"));
    } else if (ev == QLatin1String("output")) {
        const QString cat = body.value(QStringLiteral("category")).toString();
        if (cat != QLatin1String("telemetry"))
            print(body.value(QStringLiteral("output")).toString(), cat);
    } else if (ev == QLatin1String("exited")) {
        m_exitCode = body.value(QStringLiteral("exitCode")).toInt();
    } else if (ev == QLatin1String("terminated")) {
        send(QStringLiteral("disconnect"), {});
        QTimer::singleShot(800, this, [this] { if (m_proc) m_proc->kill(); else finish(); });
    }
}

void Debugger::sendBreakpoints(const QString &path)
{
    QJsonArray bps;
    for (int l : m_bps.value(path))
        bps << QJsonObject{{"line", l + 1}};
    send(QStringLiteral("setBreakpoints"),
         {{"source", QJsonObject{{"path", path}, {"name", QFileInfo(path).fileName()}}}, {"breakpoints", bps}},
         [this, path](bool ok, const QJsonObject &, const QString &err) {
             if (!ok)
                 print(QStringLiteral("Punkt przerwania w ") + QFileInfo(path).fileName() + QStringLiteral(": ") + err, QStringLiteral("stderr"));
         });
}

void Debugger::loadStack()
{
    send(QStringLiteral("stackTrace"), {{"threadId", m_threadId}, {"startFrame", 0}, {"levels", 40}},
         [this](bool ok, const QJsonObject &body, const QString &) {
             m_frames.clear();
             if (ok) {
                 for (const QJsonValue &v : body.value(QStringLiteral("stackFrames")).toArray()) {
                     const QJsonObject f = v.toObject();
                     const QString path = f.value(QStringLiteral("source")).toObject().value(QStringLiteral("path")).toString();
                     m_frames << QVariantMap{{QStringLiteral("id"), f.value(QStringLiteral("id")).toInt()},
                                             {QStringLiteral("name"), f.value(QStringLiteral("name")).toString()},
                                             {QStringLiteral("path"), QFileInfo::exists(path) ? path : QString()},
                                             {QStringLiteral("file"), QFileInfo(path).fileName()},
                                             {QStringLiteral("line"), f.value(QStringLiteral("line")).toInt() - 1}};
                 }
             }
             // Pierwsza ramka z plikiem źródłowym (bez bibliotek bez źródeł)
             int pick = 0;
             for (int i = 0; i < m_frames.size(); ++i)
                 if (!m_frames.at(i).toMap().value(QStringLiteral("path")).toString().isEmpty()) {
                     pick = i;
                     break;
                 }
             selectFrame(pick);
         });
}

void Debugger::selectFrame(int index)
{
    if (index < 0 || index >= m_frames.size()) {
        m_stopPath.clear();
        m_stopLine = -1;
        Q_EMIT stopChanged();
        return;
    }
    m_currentFrame = index;
    const QVariantMap f = m_frames.at(index).toMap();
    m_stopPath = f.value(QStringLiteral("path")).toString();
    m_stopLine = f.value(QStringLiteral("line")).toInt();
    Q_EMIT stopChanged();
    loadScopes(f.value(QStringLiteral("id")).toInt());
}

QVariantList Debugger::toItems(const QJsonArray &vars)
{
    QVariantList out;
    for (const QJsonValue &v : vars) {
        const QJsonObject o = v.toObject();
        out << QVariantMap{{QStringLiteral("name"), o.value(QStringLiteral("name")).toString()},
                           {QStringLiteral("value"), o.value(QStringLiteral("value")).toString().isEmpty() && o.value(QStringLiteral("variablesReference")).toInt() > 0
                                                         ? QStringLiteral("{…}") : o.value(QStringLiteral("value")).toString().simplified().left(300)},
                           {QStringLiteral("type"), o.value(QStringLiteral("type")).toString()},
                           {QStringLiteral("ref"), o.value(QStringLiteral("variablesReference")).toInt()}};
        if (out.size() >= 300)
            break;
    }
    return out;
}

void Debugger::loadScopes(int frameId)
{
    send(QStringLiteral("scopes"), {{"frameId", frameId}}, [this](bool ok, const QJsonObject &body, const QString &) {
        m_scopes.clear();
        if (!ok) {
            Q_EMIT variablesChanged();
            return;
        }
        const QJsonArray scopes = body.value(QStringLiteral("scopes")).toArray();
        for (const QJsonValue &v : scopes) {
            const QJsonObject s = v.toObject();
            const QString name = s.value(QStringLiteral("name")).toString();
            m_scopes << QVariantMap{{QStringLiteral("name"), name == QLatin1String("Locals") ? QStringLiteral("Zmienne lokalne")
                                                             : name == QLatin1String("Arguments") ? QStringLiteral("Argumenty")
                                                             : name == QLatin1String("Registers") ? QStringLiteral("Rejestry")
                                                             : name == QLatin1String("Globals") ? QStringLiteral("Globalne") : name},
                                    {QStringLiteral("ref"), s.value(QStringLiteral("variablesReference")).toInt()},
                                    {QStringLiteral("expensive"), s.value(QStringLiteral("expensive")).toBool()
                                                                      || name == QLatin1String("Registers")},
                                    {QStringLiteral("items"), QVariantList()}};
        }
        // Treść tańszych zakresów od razu (rejestry i globalne — po rozwinięciu)
        for (int i = 0; i < m_scopes.size(); ++i) {
            const QVariantMap s = m_scopes.at(i).toMap();
            if (s.value(QStringLiteral("expensive")).toBool())
                continue;
            const int ref = s.value(QStringLiteral("ref")).toInt();
            send(QStringLiteral("variables"), {{"variablesReference", ref}}, [this, i, ref](bool ok, const QJsonObject &body, const QString &) {
                if (!ok || i >= m_scopes.size() || m_scopes.at(i).toMap().value(QStringLiteral("ref")).toInt() != ref)
                    return;
                QVariantMap s = m_scopes.at(i).toMap();
                s.insert(QStringLiteral("items"), toItems(body.value(QStringLiteral("variables")).toArray()));
                m_scopes[i] = s;
                Q_EMIT variablesChanged();
            });
        }
        Q_EMIT variablesChanged();
    });
}

int Debugger::expand(int ref)
{
    if (ref <= 0)
        return -1;
    send(QStringLiteral("variables"), {{"variablesReference", ref}}, [this, ref](bool ok, const QJsonObject &body, const QString &) {
        Q_EMIT childrenReady(ref, ok ? toItems(body.value(QStringLiteral("variables")).toArray()) : QVariantList());
    });
    return ref;
}

void Debugger::evaluate(const QString &expression)
{
    const QString e = expression.trimmed();
    if (e.isEmpty() || m_state.isEmpty())
        return;
    print(QStringLiteral("› ") + e, QStringLiteral("input"));
    // Zwykły wpis — wyrażenie w języku programu; „:polecenie” — polecenie debugera (gdb, lldb)
    const bool command = e.startsWith(QLatin1Char(':'));
    QJsonObject args{{"expression", command ? e.mid(1).trimmed() : e}, {"context", command ? "repl" : "watch"}};
    if (m_currentFrame < m_frames.size() && m_state == QLatin1String("stopped"))
        args.insert(QStringLiteral("frameId"), m_frames.at(m_currentFrame).toMap().value(QStringLiteral("id")).toInt());
    send(QStringLiteral("evaluate"), args, [this](bool ok, const QJsonObject &body, const QString &err) {
        print(ok ? body.value(QStringLiteral("result")).toString() : err, ok ? QStringLiteral("result") : QStringLiteral("stderr"));
    });
}

void Debugger::clearConsole()
{
    m_console.clear();
    Q_EMIT consoleChanged();
}

void Debugger::print(const QString &text, const QString &category)
{
    // Wiersze z rodzajem na początku („info\x1f…”) — widok koloruje
    QString t = text;
    if (t.endsWith(QLatin1Char('\n')))
        t.chop(1);
    const QString cat = category.isEmpty() ? QStringLiteral("console") : category;
    for (const QString &l : t.split(QLatin1Char('\n'))) {
        // gdb: punkty ustawione przed wczytaniem programu są „odłożone” i działają — bez szumu w konsoli
        if (m_adapterName == QLatin1String("gdb") && (l.startsWith(QLatin1String("No source file named ")) || l.endsWith(QLatin1String(" pending."))))
            continue;
        m_console << cat + QChar(0x1f) + l;
    }
    if (m_console.size() > 5000)
        m_console.remove(0, m_console.size() - 5000);
    Q_EMIT consoleChanged();
}
