#include "projectenv.h"

#include <QDir>
#include <QFile>
#include <QFileInfo>
#include <QProcess>
#include <QRegularExpression>
#include <QSettings>
#include <QStandardPaths>

namespace {

QString quote(const QString &s)
{
    QString q = s;
    q.replace(QLatin1Char('\''), QLatin1String("'\\''"));
    return QLatin1Char('\'') + q + QLatin1Char('\'');
}

QString settingsKey(const QString &root)
{
    return QStringLiteral("code/environments/") + QString::fromLatin1(root.toUtf8().toBase64(QByteArray::Base64UrlEncoding | QByteArray::OmitTrailingEquals));
}

} // namespace

ProjectEnv *ProjectEnv::instance()
{
    static ProjectEnv *env = new ProjectEnv;
    return env;
}

ProjectEnv *ProjectEnv::create(QQmlEngine *, QJSEngine *)
{
    QJSEngine::setObjectOwnership(instance(), QJSEngine::CppOwnership);
    return instance();
}

ProjectEnv::ProjectEnv(QObject *parent)
    : QObject(parent)
    , m_flatpak(qEnvironmentVariableIsSet("FLATPAK_ID"))
{
    // Narzędzie do kontenerów w systemie (Aster/Kinoite ma toolbox i podmana)
    if (hostRun({QStringLiteral("sh"), QStringLiteral("-c"), QStringLiteral("command -v toolbox")}))
        m_tool = QStringLiteral("toolbox");
    else if (hostRun({QStringLiteral("sh"), QStringLiteral("-c"), QStringLiteral("command -v distrobox")}))
        m_tool = QStringLiteral("distrobox");
}

QStringList ProjectEnv::host(const QStringList &argv) const
{
    return m_flatpak ? QStringList{QStringLiteral("flatpak-spawn"), QStringLiteral("--host")} + argv : argv;
}

bool ProjectEnv::hostRun(const QStringList &argv, QString *out, int timeout) const
{
    const QStringList a = host(argv);
    QProcess p;
    p.start(a.first(), a.mid(1));
    if (!p.waitForFinished(timeout) || p.exitStatus() != QProcess::NormalExit)
        return false;
    if (out)
        *out = QString::fromUtf8(p.readAllStandardOutput());
    return p.exitCode() == 0;
}

QString ProjectEnv::defaultName() const
{
    // aster-<nazwa folderu>, tylko znaki dozwolone w nazwach kontenerów
    QString n = QFileInfo(m_root).fileName().toLower();
    n.replace(QRegularExpression(QStringLiteral("[^a-z0-9_.-]+")), QStringLiteral("-"));
    n.remove(QRegularExpression(QStringLiteral("^[-.]+|[-.]+$")));
    return QStringLiteral("aster-") + (n.isEmpty() ? QStringLiteral("projekt") : n.left(40));
}

void ProjectEnv::setRoot(const QString &r)
{
    if (r == m_root)
        return;
    m_root = r;
    m_container = r.isEmpty() ? QString() : QSettings().value(settingsKey(r)).toString();
    refresh();
}

void ProjectEnv::refresh()
{
    m_has.clear();
    if (m_container.isEmpty())
        m_state = QStringLiteral("off");
    else if (m_tool.isEmpty())
        m_state = QStringLiteral("missing");
    else
        m_state = hostRun({QStringLiteral("podman"), QStringLiteral("container"), QStringLiteral("exists"), m_container})
                      ? QStringLiteral("ready") : QStringLiteral("none");
    Q_EMIT changed();
    checkReadiness();
}

void ProjectEnv::checkReadiness()
{
    if (m_check) {
        m_check->disconnect(this);
        m_check->kill();
        m_check->deleteLater();
    }
    if (m_root.isEmpty()) {
        m_readiness.clear();
        Q_EMIT readinessChanged();
        return;
    }
    // Czego potrzebuje projekt: program → co to dla człowieka i pakiet Fedory
    struct Need { QString program, label, package; };
    QList<Need> needs;
    QVariantList setup;
    QStringList items;
    QStringList dirs{m_root};
    for (const QFileInfo &f : QDir(m_root).entryInfoList(QDir::Dirs | QDir::NoDotAndDotDot))
        if (!f.fileName().startsWith(QLatin1Char('.')) && f.fileName() != QLatin1String("node_modules"))
            dirs << f.absoluteFilePath();
    const auto has = [](const QString &dir, const QString &file) { return QFileInfo::exists(dir + QLatin1Char('/') + file); };
    const auto step = [&](const QString &label, const QString &cmd, const QString &cwd) {
        const QString name = cwd == m_root ? label : QFileInfo(cwd).fileName() + QStringLiteral(": ") + label;
        setup << QVariantMap{{QStringLiteral("label"), name}, {QStringLiteral("command"), cmd}, {QStringLiteral("cwd"), cwd}};
    };
    bool node = false, python = false;
    for (const QString &d : std::as_const(dirs)) {
        if (has(d, QStringLiteral("package.json"))) {
            node = true;
            if (!has(d, QStringLiteral("node_modules")))
                step(QStringLiteral("zależności npm"), QStringLiteral("npm install --no-fund --no-audit"), d);
        }
        if (has(d, QStringLiteral("requirements.txt")) || has(d, QStringLiteral("pyproject.toml"))) {
            python = true;
            if (!has(d, QStringLiteral(".venv")))
                step(QStringLiteral("zależności Pythona"),
                     has(d, QStringLiteral("requirements.txt")) ? QStringLiteral("python3 -m venv .venv && .venv/bin/pip install -q -r requirements.txt")
                                                                : QStringLiteral("python3 -m venv .venv && .venv/bin/pip install -q -e ."), d);
        }
        if (has(d, QStringLiteral("main.py")) || has(d, QStringLiteral("app.py")))
            python = true;
        if (has(d, QStringLiteral("Cargo.toml")))
            needs << Need{QStringLiteral("cargo"), QStringLiteral("Rust"), QStringLiteral("cargo")} << Need{QStringLiteral("rust-analyzer"), QStringLiteral("podpowiedzi Rust"), QStringLiteral("rust-analyzer")};
        if (has(d, QStringLiteral("go.mod")))
            needs << Need{QStringLiteral("go"), QStringLiteral("Go"), QStringLiteral("golang")} << Need{QStringLiteral("gopls"), QStringLiteral("podpowiedzi Go"), QStringLiteral("golang-x-tools-gopls")};
        if (has(d, QStringLiteral("CMakeLists.txt")) || has(d, QStringLiteral("Makefile")) || has(d, QStringLiteral("meson.build")))
            needs << Need{QStringLiteral("g++"), QStringLiteral("kompilator C/C++"), QStringLiteral("gcc-c++")} << Need{QStringLiteral("make"), QStringLiteral("make"), QStringLiteral("make")}
                  << Need{QStringLiteral("clangd"), QStringLiteral("podpowiedzi C/C++"), QStringLiteral("clang-tools-extra")} << Need{QStringLiteral("gdb"), QStringLiteral("debuger"), QStringLiteral("gdb")};
        if (has(d, QStringLiteral("CMakeLists.txt")))
            needs << Need{QStringLiteral("cmake"), QStringLiteral("CMake"), QStringLiteral("cmake")};
    }
    if (node)
        needs << Need{QStringLiteral("npm"), QStringLiteral("Node.js"), QStringLiteral("nodejs npm")};
    if (python)
        needs << Need{QStringLiteral("python3"), QStringLiteral("Python"), QStringLiteral("python3 python3-pip")}
              << Need{QStringLiteral("pylsp"), QStringLiteral("podpowiedzi Python"), QStringLiteral("python3-lsp-server")};
    if (needs.isEmpty() && setup.isEmpty()) {
        m_readiness.clear();
        Q_EMIT readinessChanged();
        return;
    }
    QStringList names;
    for (const Need &n : std::as_const(needs))
        if (!names.contains(n.program))
            names << n.program;
    if (node)
        names << QStringLiteral("typescript-language-server");
    // Jedno polecenie na wszystko — w kontenerze każde uruchomienie kosztuje sekundę
    QString cmd = QStringLiteral("for p in ") + names.join(QLatin1Char(' ')) + QStringLiteral("; do command -v \"$p\" >/dev/null 2>&1 && echo \"$p\"; done; true");
    QStringList argv = shell(cmd, m_root);
    if (argv.isEmpty())
        argv = {QStringLiteral("/bin/sh"), QStringLiteral("-c"), cmd};
    auto *p = new QProcess(this);
    m_check = p;
    connect(p, &QProcess::finished, this, [this, p, needs, names, setup, items, node]() mutable {
        p->deleteLater();
        const QStringList found = QString::fromUtf8(p->readAllStandardOutput()).split(QLatin1Char('\n'), Qt::SkipEmptyParts);
        for (const QString &n : names)
            m_has.insert(n, found.contains(n));
        QStringList packages;
        for (const Need &n : std::as_const(needs))
            if (!found.contains(n.program)) {
                if (!items.contains(n.label))
                    items << n.label;
                packages += n.package.split(QLatin1Char(' '));
            }
        if (node && !found.contains(QStringLiteral("typescript-language-server"))) {
            items << QStringLiteral("podpowiedzi JavaScript");
            setup << QVariantMap{{QStringLiteral("label"), QStringLiteral("serwer języka JavaScript")},
                                 {QStringLiteral("command"), QStringLiteral("sudo npm install -g --no-fund --no-audit typescript-language-server typescript@5")},
                                 {QStringLiteral("cwd"), m_root}};
        }
        for (const QVariant &v : std::as_const(setup)) {
            const QString l = v.toMap().value(QStringLiteral("label")).toString();
            if (l.contains(QStringLiteral("zależności")) && !items.contains(QStringLiteral("zależności projektu")))
                items << QStringLiteral("zależności projektu");
        }
        packages.removeDuplicates();
        m_readiness = items.isEmpty() ? QVariantMap()
                                      : QVariantMap{{QStringLiteral("items"), items}, {QStringLiteral("packages"), packages}, {QStringLiteral("setup"), setup}};
        Q_EMIT readinessChanged();
    });
    p->setWorkingDirectory(m_root);
    p->start(argv.first(), argv.mid(1));
}

void ProjectEnv::useContainer(bool on)
{
    if (m_root.isEmpty())
        return;
    m_container = on ? (m_container.isEmpty() ? defaultName() : m_container) : QString();
    QSettings s;
    if (on)
        s.setValue(settingsKey(m_root), m_container);
    else
        s.remove(settingsKey(m_root));
    refresh();
}

QStringList ProjectEnv::hostShell(const QString &command, const QString &cwd) const
{
    if (!m_flatpak)
        return {};
    return {QStringLiteral("flatpak-spawn"), QStringLiteral("--host"), QStringLiteral("--directory=") + cwd, QStringLiteral("sh"), QStringLiteral("-c"), command};
}

QStringList ProjectEnv::hostProgram(const QStringList &argv, const QString &cwd, const QStringList &env) const
{
    if (!m_flatpak)
        return argv;
    QStringList a{QStringLiteral("flatpak-spawn"), QStringLiteral("--host")};
    if (!cwd.isEmpty())
        a << QStringLiteral("--directory=") + cwd;
    for (const QString &e : env)
        a << QStringLiteral("--env=") + e;
    return a + argv;
}

QStringList ProjectEnv::shell(const QString &command, const QString &cwd) const
{
    if (m_state != QLatin1String("ready"))
        return hostShell(command, cwd);
    const QString inner = QStringLiteral("cd ") + quote(cwd) + QStringLiteral(" && ") + command;
    if (m_tool == QLatin1String("distrobox"))
        return host({QStringLiteral("distrobox"), QStringLiteral("enter"), m_container, QStringLiteral("--"), QStringLiteral("sh"), QStringLiteral("-c"), inner});
    return host({QStringLiteral("toolbox"), QStringLiteral("run"), QStringLiteral("-c"), m_container, QStringLiteral("sh"), QStringLiteral("-c"), inner});
}

QStringList ProjectEnv::program(const QStringList &argv) const
{
    if (m_state != QLatin1String("ready"))
        return host(argv);
    if (m_tool == QLatin1String("distrobox"))
        return host(QStringList{QStringLiteral("distrobox"), QStringLiteral("enter"), m_container, QStringLiteral("--")} + argv);
    return host(QStringList{QStringLiteral("toolbox"), QStringLiteral("run"), QStringLiteral("-c"), m_container} + argv);
}

bool ProjectEnv::has(const QString &name) const
{
    if (m_state != QLatin1String("ready") && !m_flatpak)
        return !QStandardPaths::findExecutable(name).isEmpty() || QFileInfo(name).isExecutable();
    if (auto it = m_has.find(name); it != m_has.end())
        return *it;
    const QStringList argv = shell(QStringLiteral("command -v ") + quote(name), m_root.isEmpty() ? QDir::homePath() : m_root);
    QProcess p;
    p.start(argv.first(), argv.mid(1));
    const bool ok = p.waitForFinished(15000) && p.exitStatus() == QProcess::NormalExit && p.exitCode() == 0;
    m_has.insert(name, ok);
    return ok;
}

QStringList ProjectEnv::terminalCommand() const
{
    if (m_state == QLatin1String("ready"))
        return m_tool == QLatin1String("distrobox") ? host({QStringLiteral("distrobox"), QStringLiteral("enter"), m_container})
                                                     : host({QStringLiteral("toolbox"), QStringLiteral("enter"), m_container});
    if (m_flatpak)
        return host({qEnvironmentVariable("SHELL", QStringLiteral("/bin/bash")), QStringLiteral("-l")});
    return {};
}

QString ProjectEnv::createCommand(const QStringList &packages) const
{
    const QString name = m_container.isEmpty() ? defaultName() : m_container;
    QString cmd = m_tool == QLatin1String("distrobox")
        ? QStringLiteral("distrobox create -Y -n %1 -i registry.fedoraproject.org/fedora-toolbox:latest").arg(name)
        : QStringLiteral("toolbox create -y -c %1").arg(name);
    cmd = QStringLiteral("(podman container exists %1 || %2)").arg(name, cmd);
    if (!packages.isEmpty())
        cmd += QStringLiteral(" && ") + installCommand(packages).replace(m_container.isEmpty() ? QString() : m_container, name);
    return cmd;
}

QString ProjectEnv::installCommand(const QStringList &packages) const
{
    const QString name = m_container.isEmpty() ? defaultName() : m_container;
    const QString dnf = QStringLiteral("sudo dnf install -y --setopt=install_weak_deps=False ") + packages.join(QLatin1Char(' '));
    return m_tool == QLatin1String("distrobox") ? QStringLiteral("distrobox enter %1 -- %2").arg(name, dnf)
                                                 : QStringLiteral("toolbox run -c %1 %2").arg(name, dnf);
}

QString ProjectEnv::removeCommand() const
{
    return QStringLiteral("podman rm -f %1").arg(m_container.isEmpty() ? defaultName() : m_container);
}

QStringList ProjectEnv::suggestPackages() const
{
    const QDir d(m_root);
    QStringList pk{QStringLiteral("git")};
    // Folder projektu i podfoldery jeden poziom niżej (frontend/, backend/)
    QStringList dirs{m_root};
    for (const QFileInfo &f : d.entryInfoList(QDir::Dirs | QDir::NoDotAndDotDot))
        if (!f.fileName().startsWith(QLatin1Char('.')) && f.fileName() != QLatin1String("node_modules"))
            dirs << f.absoluteFilePath();
    const auto any = [&](const QString &file) {
        for (const QString &p : std::as_const(dirs))
            if (QFileInfo::exists(p + QLatin1Char('/') + file))
                return true;
        return false;
    };
    if (any(QStringLiteral("package.json")))
        pk << QStringLiteral("nodejs") << QStringLiteral("npm");
    if (any(QStringLiteral("pnpm-lock.yaml")))
        pk << QStringLiteral("pnpm");
    if (any(QStringLiteral("pyproject.toml")) || any(QStringLiteral("requirements.txt")) || any(QStringLiteral("main.py")))
        pk << QStringLiteral("python3") << QStringLiteral("python3-pip") << QStringLiteral("python3-devel") << QStringLiteral("python3-lsp-server");
    if (any(QStringLiteral("Cargo.toml")))
        pk << QStringLiteral("cargo") << QStringLiteral("rust-analyzer");
    if (any(QStringLiteral("go.mod")))
        pk << QStringLiteral("golang") << QStringLiteral("golang-x-tools-gopls");
    if (any(QStringLiteral("CMakeLists.txt")) || any(QStringLiteral("Makefile")) || any(QStringLiteral("meson.build")))
        pk << QStringLiteral("gcc-c++") << QStringLiteral("make") << QStringLiteral("cmake") << QStringLiteral("gdb") << QStringLiteral("clang-tools-extra");
    if (any(QStringLiteral("meson.build")))
        pk << QStringLiteral("meson");
    // Baza danych z pliku .env albo docker-compose
    const QString envText = [&] { QFile f(m_root + QStringLiteral("/.env.example")); return f.open(QIODevice::ReadOnly) ? QString::fromUtf8(f.readAll()) : QString(); }();
    if (envText.contains(QLatin1String("postgres")))
        pk << QStringLiteral("postgresql-server") << QStringLiteral("postgresql");
    pk.removeDuplicates();
    return pk;
}
