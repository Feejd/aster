#include "tasks.h"

#include <QDir>
#include <QFile>
#include <QFileInfo>
#include <QJsonDocument>
#include <QJsonObject>
#include <QRegularExpression>
#include <QStandardPaths>

namespace {

constexpr int MaxLines = 20000;

QString readText(const QString &path, qint64 limit = 512 * 1024)
{
    QFile f(path);
    if (f.size() > limit || !f.open(QIODevice::ReadOnly))
        return {};
    return QString::fromUtf8(f.readAll());
}

QString groupFor(const QString &name)
{
    const QString n = name.toLower();
    if (n.contains(QLatin1String("test")) || n == QLatin1String("check"))
        return QStringLiteral("test");
    if (n.contains(QLatin1String("build")) || n == QLatin1String("all") || n == QLatin1String("compile"))
        return QStringLiteral("build");
    if (n == QLatin1String("start") || n == QLatin1String("dev") || n == QLatin1String("serve") || n == QLatin1String("run")
        || n == QLatin1String("preview") || n == QLatin1String("watch"))
        return QStringLiteral("run");
    return QStringLiteral("other");
}

QVariantMap task(const QString &label, const QString &command, const QString &cwd, const QString &group, const QString &source)
{
    return {{QStringLiteral("label"), label}, {QStringLiteral("command"), command}, {QStringLiteral("cwd"), cwd},
            {QStringLiteral("group"), group}, {QStringLiteral("source"), source}};
}

const QRegularExpression &ansi()
{
    static const QRegularExpression re(QStringLiteral("\\x1B(?:\\[[0-9;?]*[ -/]*[@-~]|\\][^\\x07\\x1B]*(?:\\x07|\\x1B\\\\)|[()][0-9A-Za-z]|[=>78])"));
    return re;
}

} // namespace

Tasks::Tasks(QObject *parent)
    : QObject(parent)
{
    m_notify.setSingleShot(true);
    m_notify.setInterval(80);
    connect(&m_notify, &QTimer::timeout, this, [this] { Q_EMIT outputChanged(); Q_EMIT problemsChanged(); });
}

Tasks::~Tasks()
{
    if (m_proc) {
        m_proc->disconnect(this);
        m_proc->kill();
        m_proc->waitForFinished(500);
    }
}

QVariantList Tasks::detect(const QString &root) const
{
    QVariantList out;
    if (root.isEmpty())
        return out;
    const QDir dir(root);

    // package.json — skrypty przez npm, pnpm albo yarn (wg pliku blokady)
    if (dir.exists(QStringLiteral("package.json"))) {
        const QJsonObject pkg = QJsonDocument::fromJson(readText(dir.filePath(QStringLiteral("package.json"))).toUtf8()).object();
        const QString runner = dir.exists(QStringLiteral("pnpm-lock.yaml")) ? QStringLiteral("pnpm run")
                             : dir.exists(QStringLiteral("yarn.lock")) ? QStringLiteral("yarn")
                             : dir.exists(QStringLiteral("bun.lockb")) ? QStringLiteral("bun run") : QStringLiteral("npm run");
        const QJsonObject scripts = pkg.value(QStringLiteral("scripts")).toObject();
        for (auto it = scripts.begin(); it != scripts.end(); ++it)
            out << task(it.key(), runner + QLatin1Char(' ') + it.key(), root, groupFor(it.key()), QStringLiteral("package.json"));
        if (!dir.exists(QStringLiteral("node_modules")))
            out << task(QStringLiteral("zainstaluj zależności"), runner.section(QLatin1Char(' '), 0, 0) + QStringLiteral(" install"), root,
                        QStringLiteral("other"), QStringLiteral("package.json"));
    }
    // Makefile — cele z definicji (bez zmiennych i celów specjalnych z kropką)
    for (const QString &mk : {QStringLiteral("GNUmakefile"), QStringLiteral("makefile"), QStringLiteral("Makefile")}) {
        if (!dir.exists(mk))
            continue;
        out << task(QStringLiteral("make"), QStringLiteral("make -j$(nproc)"), root, QStringLiteral("build"), mk);
        static const QRegularExpression target(QStringLiteral("^([A-Za-z0-9][A-Za-z0-9_.-]*)\\s*:(?![=:])"), QRegularExpression::MultilineOption);
        QStringList seen;
        auto it = target.globalMatch(readText(dir.filePath(mk)));
        while (it.hasNext() && seen.size() < 40) {
            const QString t = it.next().captured(1);
            if (seen.contains(t) || t.contains(QLatin1Char('.')) || t == QLatin1String("all"))
                continue;
            seen << t;
            out << task(QStringLiteral("make ") + t, QStringLiteral("make ") + t, root, groupFor(t), mk);
        }
        break;
    }
    // CMake — folder build obok źródeł
    if (dir.exists(QStringLiteral("CMakeLists.txt"))) {
        out << task(QStringLiteral("cmake: zbuduj"), QStringLiteral("cmake -S . -B build -DCMAKE_EXPORT_COMPILE_COMMANDS=ON && cmake --build build -j$(nproc)"),
                    root, QStringLiteral("build"), QStringLiteral("CMakeLists.txt"));
        out << task(QStringLiteral("cmake: testy"), QStringLiteral("ctest --test-dir build --output-on-failure"), root, QStringLiteral("test"),
                    QStringLiteral("CMakeLists.txt"));
        out << task(QStringLiteral("cmake: wyczyść"), QStringLiteral("cmake --build build --target clean"), root, QStringLiteral("other"),
                    QStringLiteral("CMakeLists.txt"));
    }
    if (dir.exists(QStringLiteral("meson.build"))) {
        out << task(QStringLiteral("meson: zbuduj"), QStringLiteral("[ -d build ] || meson setup build; meson compile -C build"), root,
                    QStringLiteral("build"), QStringLiteral("meson.build"));
        out << task(QStringLiteral("meson: testy"), QStringLiteral("meson test -C build"), root, QStringLiteral("test"), QStringLiteral("meson.build"));
    }
    if (dir.exists(QStringLiteral("Cargo.toml"))) {
        out << task(QStringLiteral("cargo build"), QStringLiteral("cargo build"), root, QStringLiteral("build"), QStringLiteral("Cargo.toml"));
        out << task(QStringLiteral("cargo run"), QStringLiteral("cargo run"), root, QStringLiteral("run"), QStringLiteral("Cargo.toml"));
        out << task(QStringLiteral("cargo test"), QStringLiteral("cargo test"), root, QStringLiteral("test"), QStringLiteral("Cargo.toml"));
        out << task(QStringLiteral("cargo clippy"), QStringLiteral("cargo clippy"), root, QStringLiteral("other"), QStringLiteral("Cargo.toml"));
    }
    if (dir.exists(QStringLiteral("go.mod"))) {
        out << task(QStringLiteral("go build"), QStringLiteral("go build ./..."), root, QStringLiteral("build"), QStringLiteral("go.mod"));
        out << task(QStringLiteral("go run"), QStringLiteral("go run ."), root, QStringLiteral("run"), QStringLiteral("go.mod"));
        out << task(QStringLiteral("go test"), QStringLiteral("go test ./..."), root, QStringLiteral("test"), QStringLiteral("go.mod"));
    }
    for (const QString &jf : {QStringLiteral("justfile"), QStringLiteral("Justfile")}) {
        if (!dir.exists(jf))
            continue;
        static const QRegularExpression recipe(QStringLiteral("^@?([A-Za-z0-9_-]+)[^:=\\n]*:(?!=)"), QRegularExpression::MultilineOption);
        auto it = recipe.globalMatch(readText(dir.filePath(jf)));
        int n = 0;
        while (it.hasNext() && n++ < 40) {
            const QString r = it.next().captured(1);
            out << task(QStringLiteral("just ") + r, QStringLiteral("just ") + r, root, groupFor(r), jf);
        }
        break;
    }
    // Python: testy (pytest) i główny plik
    const bool py = dir.exists(QStringLiteral("pyproject.toml")) || dir.exists(QStringLiteral("setup.py")) || dir.exists(QStringLiteral("requirements.txt"))
                    || dir.exists(QStringLiteral("main.py")) || dir.exists(QStringLiteral("app.py"));
    if (py) {
        for (const QString &m : {QStringLiteral("main.py"), QStringLiteral("app.py"), QStringLiteral("manage.py")})
            if (dir.exists(m)) {
                out << task(QStringLiteral("python ") + m, QStringLiteral("python3 ") + m, root, QStringLiteral("run"), m);
                break;
            }
        if (dir.exists(QStringLiteral("tests")) || dir.exists(QStringLiteral("test")))
            out << task(QStringLiteral("pytest"), QStringLiteral("python3 -m pytest"), root, QStringLiteral("test"), QStringLiteral("Python"));
    }
    // Kolejność: budowanie, uruchamianie, testy, reszta (w grupie — kolejność z pliku)
    const QStringList order{QStringLiteral("build"), QStringLiteral("run"), QStringLiteral("test"), QStringLiteral("other")};
    std::stable_sort(out.begin(), out.end(), [&](const QVariant &a, const QVariant &b) {
        return order.indexOf(a.toMap().value(QStringLiteral("group")).toString()) < order.indexOf(b.toMap().value(QStringLiteral("group")).toString());
    });
    return out;
}

void Tasks::run(const QString &label, const QString &command, const QString &cwd)
{
    if (m_proc) {
        // Poprzednie zadanie kończy się przed nowym
        m_proc->disconnect(this);
        m_proc->kill();
        m_proc->waitForFinished(1000);
        m_proc->deleteLater();
    }
    m_lines.clear();
    m_partial.clear();
    m_problems.clear();
    m_errors = m_warnings = 0;
    m_pyLine = -1;
    m_title = label;
    m_command = command;
    m_cwd = cwd;
    m_root = cwd;
    m_exitCode = -1;
    m_elapsed = 0;
    m_lines << QStringLiteral("> ") + command;
    auto *p = new QProcess(this);
    m_proc = p;
    p->setWorkingDirectory(cwd);
    p->setProcessChannelMode(QProcess::MergedChannels);
    QProcessEnvironment env = QProcessEnvironment::systemEnvironment();
    // Bez kolorów i pytań — wyjście czyta człowiek w prostym widoku
    env.insert(QStringLiteral("TERM"), QStringLiteral("dumb"));
    env.insert(QStringLiteral("NO_COLOR"), QStringLiteral("1"));
    env.insert(QStringLiteral("CLICOLOR"), QStringLiteral("0"));
    env.insert(QStringLiteral("CARGO_TERM_COLOR"), QStringLiteral("never"));
    env.insert(QStringLiteral("PYTHONUNBUFFERED"), QStringLiteral("1"));
    env.insert(QStringLiteral("GIT_TERMINAL_PROMPT"), QStringLiteral("0"));
    p->setProcessEnvironment(env);
    connect(p, &QProcess::readyRead, this, [this, p] { append(p->readAll()); });
    connect(p, &QProcess::finished, this, [this, p](int code, QProcess::ExitStatus st) {
        append(p->readAll());
        finish(st == QProcess::NormalExit ? code : -2);
    });
    connect(p, &QProcess::errorOccurred, this, [this](QProcess::ProcessError e) {
        if (e == QProcess::FailedToStart) {
            m_lines << QStringLiteral("Nie można uruchomić powłoki");
            finish(127);
        }
    });
    m_clock.start();
    p->start(QStringLiteral("/bin/sh"), {QStringLiteral("-c"), command});
    p->closeWriteChannel();
    Q_EMIT stateChanged();
    Q_EMIT outputChanged();
    Q_EMIT problemsChanged();
}

void Tasks::stop()
{
    if (!running())
        return;
    m_proc->terminate();
    QTimer::singleShot(1500, m_proc, [p = m_proc] { if (p && p->state() != QProcess::NotRunning) p->kill(); });
}

void Tasks::rerun()
{
    if (!m_command.isEmpty())
        run(m_title, m_command, m_cwd);
}

void Tasks::clear()
{
    if (running())
        return;
    m_lines.clear();
    Q_EMIT outputChanged();
}

void Tasks::append(const QByteArray &data)
{
    if (data.isEmpty())
        return;
    QString text = m_partial + QString::fromUtf8(data);
    text.remove(ansi());
    text.remove(QLatin1Char('\r'));
    const int nl = int(text.lastIndexOf(QLatin1Char('\n')));
    m_partial = nl < 0 ? text : text.mid(nl + 1);
    if (nl >= 0) {
        const QStringList parts = text.left(nl).split(QLatin1Char('\n'));
        for (const QString &l : parts) {
            parseLine(l);
            m_lines << l;
        }
        if (m_lines.size() > MaxLines)
            m_lines.remove(1, m_lines.size() - MaxLines);
    }
    if (!m_notify.isActive())
        m_notify.start();
}

void Tasks::finish(int code)
{
    if (!m_partial.isEmpty()) {
        parseLine(m_partial);
        m_lines << m_partial;
        m_partial.clear();
    }
    m_exitCode = code;
    m_elapsed = m_clock.elapsed();
    const QString secs = QString::number(m_elapsed / 1000.0, 'f', 1).replace(QLatin1Char('.'), QLatin1Char(','));
    m_lines << QString();
    m_lines << (code == 0 ? QStringLiteral("✓ Gotowe w %1 s").arg(secs)
                          : code == -2 ? QStringLiteral("■ Przerwano po %1 s").arg(secs)
                                       : QStringLiteral("✗ Zakończone z kodem %1 po %2 s").arg(code).arg(secs));
    m_notify.stop();
    Q_EMIT outputChanged();
    Q_EMIT problemsChanged();
    Q_EMIT stateChanged();
    Q_EMIT finished(m_title, code);
}

QVariantMap Tasks::locate(const QString &line) const
{
    // gcc/clang/go/rustc/eslint: ścieżka:wiersz:kolumna; tsc: ścieżka(wiersz,kolumna); rustc: --> ścieżka:w:k; Python: File "x", line N
    static const QRegularExpression colon(QStringLiteral("^\\s*(?:-->\\s*)?((?:[A-Za-z]:)?[^\\s:()\"'][^:()\"']*?\\.[A-Za-z0-9+]+):(\\d+)(?::(\\d+))?"));
    static const QRegularExpression paren(QStringLiteral("^\\s*([^\\s(]+\\.[A-Za-z0-9]+)\\((\\d+),(\\d+)\\)"));
    static const QRegularExpression python(QStringLiteral("^\\s*File \"([^\"]+)\", line (\\d+)"));
    QRegularExpressionMatch m = colon.match(line);
    if (!m.hasMatch())
        m = paren.match(line);
    if (!m.hasMatch())
        m = python.match(line);
    if (!m.hasMatch())
        return {};
    QString path = m.captured(1);
    if (QFileInfo(path).isRelative())
        path = QDir(m_cwd).absoluteFilePath(path);
    path = QDir::cleanPath(path);
    if (!QFileInfo(path).isFile())
        return {};
    return {{QStringLiteral("path"), path}, {QStringLiteral("line"), std::max(0, m.captured(2).toInt() - 1)},
            {QStringLiteral("col"), std::max(0, m.captured(3).toInt() - 1)}};
}

void Tasks::parseLine(const QString &line)
{
    static const QRegularExpression sev(QStringLiteral("\\b(fatal error|error|warning)(?:\\[[A-Z0-9]+\\])?\\s*(?:TS\\d+\\s*)?:\\s*(.*)$"),
                                        QRegularExpression::CaseInsensitiveOption);
    static const QRegularExpression rustHead(QStringLiteral("^(error|warning)(?:\\[[A-Z0-9]+\\])?: (.*)$"));
    static const QRegularExpression pyErr(QStringLiteral("^([A-Za-z_]+(?:Error|Exception|Warning)): ?(.*)$"));
    static QString rustMsg;
    static int rustSev = 0;

    const auto add = [this](const QVariantMap &loc, int severity, const QString &message, const QString &source) {
        const QString path = loc.value(QStringLiteral("path")).toString();
        QVariantList &list = m_problems[path];
        if (list.size() > 500)
            return;
        list << QVariantMap{{QStringLiteral("line"), loc.value(QStringLiteral("line"))}, {QStringLiteral("col"), loc.value(QStringLiteral("col"))},
                            {QStringLiteral("endLine"), loc.value(QStringLiteral("line"))}, {QStringLiteral("endCol"), loc.value(QStringLiteral("col"))},
                            {QStringLiteral("severity"), severity}, {QStringLiteral("message"), message.trimmed()}, {QStringLiteral("source"), source}};
        if (severity == 1)
            ++m_errors;
        else
            ++m_warnings;
    };

    // Rust: komunikat w wierszu „error: …”, miejsce w następnym „--> plik:w:k”
    if (const auto r = rustHead.match(line); r.hasMatch()) {
        rustMsg = r.captured(2);
        rustSev = r.captured(1) == QLatin1String("error") ? 1 : 2;
        return;
    }
    if (line.trimmed().startsWith(QLatin1String("-->")) && rustSev) {
        const QVariantMap loc = locate(line);
        if (!loc.isEmpty())
            add(loc, rustSev, rustMsg, QStringLiteral("rustc"));
        rustSev = 0;
        return;
    }
    // Python: ostatnie „File …, line N” przed wierszem z wyjątkiem
    if (line.trimmed().startsWith(QLatin1String("File \""))) {
        const QVariantMap loc = locate(line);
        if (!loc.isEmpty()) {
            m_pyFile = loc.value(QStringLiteral("path")).toString();
            m_pyLine = loc.value(QStringLiteral("line")).toInt();
        }
        return;
    }
    if (m_pyLine >= 0) {
        if (const auto p = pyErr.match(line); p.hasMatch()) {
            add({{QStringLiteral("path"), m_pyFile}, {QStringLiteral("line"), m_pyLine}, {QStringLiteral("col"), 0}}, 1,
                p.captured(1) + QStringLiteral(": ") + p.captured(2), QStringLiteral("python"));
            m_pyLine = -1;
        }
        return;
    }
    // gcc/clang/tsc/go: miejsce i „error: …” w jednym wierszu
    const auto s = sev.match(line);
    if (!s.hasMatch())
        return;
    const QVariantMap loc = locate(line);
    if (loc.isEmpty())
        return;
    const bool err = s.captured(1).toLower() != QLatin1String("warning");
    add(loc, err ? 1 : 2, s.captured(2), QStringLiteral("kompilator"));
}

QVariantList Tasks::problems() const
{
    QStringList paths = m_problems.keys();
    std::sort(paths.begin(), paths.end());
    QVariantList out;
    for (const QString &p : std::as_const(paths)) {
        const QString rel = m_root.isEmpty() || !p.startsWith(m_root + QLatin1Char('/')) ? p : p.mid(m_root.size() + 1);
        const int slash = int(rel.lastIndexOf(QLatin1Char('/')));
        out << QVariantMap{{QStringLiteral("path"), p}, {QStringLiteral("name"), rel.mid(slash + 1)},
                           {QStringLiteral("dir"), slash > 0 ? rel.left(slash) : QString()}, {QStringLiteral("items"), m_problems.value(p)},
                           {QStringLiteral("fromTask"), true}};
    }
    return out;
}
