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
        pk << QStringLiteral("python3") << QStringLiteral("python3-pip") << QStringLiteral("python3-devel");
    if (any(QStringLiteral("Cargo.toml")))
        pk << QStringLiteral("cargo") << QStringLiteral("rust-analyzer");
    if (any(QStringLiteral("go.mod")))
        pk << QStringLiteral("golang") << QStringLiteral("gopls");
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
