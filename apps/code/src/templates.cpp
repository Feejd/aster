#include "templates.h"
#include "projectenv.h"

#include <QDir>
#include <QDirIterator>
#include <QFile>
#include <QJsonArray>
#include <QJsonDocument>
#include <QJsonObject>
#include <QProcess>
#include <QRegularExpression>
#include <QStandardPaths>

namespace {

bool writeText(const QString &path, const QString &text)
{
    QDir().mkpath(QFileInfo(path).absolutePath());
    QFile f(path);
    if (!f.open(QIODevice::WriteOnly | QIODevice::Truncate))
        return false;
    f.write(text.toUtf8());
    return true;
}

// Kopia szablonu z zasobów: _gitignore → .gitignore, wariant bazy plik.<db>.ext → plik.ext (pozostałe warianty pomijane)
bool copyTemplate(const QString &id, const QString &target, const QString &db, const QHash<QString, QString> &vars)
{
    const QString base = QStringLiteral(":/templates/") + id;
    QDirIterator it(base, QDir::Files | QDir::Hidden, QDirIterator::Subdirectories);
    static const QRegularExpression variant(QStringLiteral("^(.+)\\.(sqlite|postgres)(\\.[^.]+)$"));
    while (it.hasNext()) {
        const QString src = it.next();
        QString rel = src.mid(base.size() + 1);
        QString name = QFileInfo(rel).fileName();
        const QString dir = QFileInfo(rel).path() == QLatin1String(".") ? QString() : QFileInfo(rel).path() + QLatin1Char('/');
        if (const auto m = variant.match(name); m.hasMatch()) {
            if (m.captured(2) != (db.isEmpty() ? QStringLiteral("sqlite") : db))
                continue;
            name = m.captured(1) + m.captured(3);
        }
        if (name == QLatin1String("_gitignore"))
            name = QStringLiteral(".gitignore");
        QFile f(src);
        if (!f.open(QIODevice::ReadOnly))
            return false;
        QString text = QString::fromUtf8(f.readAll());
        for (auto v = vars.cbegin(); v != vars.cend(); ++v)
            text.replace(QStringLiteral("{{") + v.key() + QStringLiteral("}}"), v.value());
        if (!writeText(target + QLatin1Char('/') + dir + name, text))
            return false;
    }
    return true;
}

} // namespace

Templates::Templates(QObject *parent)
    : QObject(parent)
{
}

QString Templates::slug(const QString &name) const
{
    QString s = name.toLower().normalized(QString::NormalizationForm_KD);
    s.remove(QRegularExpression(QStringLiteral("[\\x{0300}-\\x{036f}]")));
    s.replace(QStringLiteral("ł"), QStringLiteral("l"));
    s.replace(QRegularExpression(QStringLiteral("[^a-z0-9]+")), QStringLiteral("-"));
    s.remove(QRegularExpression(QStringLiteral("^-+|-+$")));
    return s.isEmpty() ? QStringLiteral("aplikacja") : s.left(50);
}

QString Templates::defaultParent() const
{
    return QDir::homePath() + QStringLiteral("/Projekty");
}

bool Templates::exists(const QString &path) const
{
    return QFileInfo::exists(path);
}

QVariantMap Templates::create(const QVariantMap &opts) const
{
    const QString name = opts.value(QStringLiteral("name")).toString().trimmed();
    const QString fe = opts.value(QStringLiteral("frontend")).toString(), be = opts.value(QStringLiteral("backend")).toString();
    const QString db = be.isEmpty() ? QString() : opts.value(QStringLiteral("db")).toString();
    const auto fail = [](const QString &e) { return QVariantMap{{QStringLiteral("ok"), false}, {QStringLiteral("error"), e}}; };
    if (name.isEmpty())
        return fail(QStringLiteral("Wpisz nazwę aplikacji"));
    if (fe.isEmpty() && be.isEmpty())
        return fail(QStringLiteral("Wybierz frontend albo backend"));
    const QString root = QDir::cleanPath(opts.value(QStringLiteral("parent")).toString() + QLatin1Char('/') + slug(name));
    if (QFileInfo::exists(root) && !QDir(root).isEmpty())
        return fail(QStringLiteral("Folder %1 już istnieje i nie jest pusty").arg(root));

    const bool both = !fe.isEmpty() && !be.isEmpty();
    const QString feDir = both ? root + QStringLiteral("/frontend") : root;
    const QString beDir = both ? root + QStringLiteral("/backend") : root;
    const QString port = be == QLatin1String("node") ? QStringLiteral("3000") : QStringLiteral("8000");
    QHash<QString, QString> vars{{QStringLiteral("name"), name}, {QStringLiteral("slug"), slug(name)}, {QStringLiteral("backendPort"), port},
                                {QStringLiteral("nodeDbDep"), db == QLatin1String("postgres") ? QStringLiteral(",\n    \"pg\": \"^8.13.0\"") : QString()}};
    QStringList packages{QStringLiteral("git")};
    QVariantList setup;
    const auto step = [&](const QString &label, const QString &cmd, const QString &cwd) {
        setup << QVariantMap{{QStringLiteral("label"), label}, {QStringLiteral("command"), cmd}, {QStringLiteral("cwd"), cwd}};
    };
    QDir().mkpath(root);

    if (!fe.isEmpty()) {
        if (!copyTemplate(QStringLiteral("frontend-vite-react"), feDir, db, vars))
            return fail(QStringLiteral("Nie udało się zapisać plików frontendu"));
        packages << QStringLiteral("nodejs") << QStringLiteral("npm");
        step(both ? QStringLiteral("frontend: npm install") : QStringLiteral("npm install"), QStringLiteral("npm install --no-fund --no-audit"), feDir);
    }
    if (be == QLatin1String("fastapi")) {
        if (!copyTemplate(QStringLiteral("backend-fastapi"), beDir, db, vars))
            return fail(QStringLiteral("Nie udało się zapisać plików backendu"));
        packages << QStringLiteral("python3") << QStringLiteral("python3-pip");
        step(both ? QStringLiteral("backend: zależności (.venv)") : QStringLiteral("zależności (.venv)"),
             QStringLiteral("python3 -m venv .venv && .venv/bin/pip install -q -r requirements.txt"), beDir);
    } else if (be == QLatin1String("node")) {
        if (!copyTemplate(QStringLiteral("backend-node"), beDir, db, vars))
            return fail(QStringLiteral("Nie udało się zapisać plików backendu"));
        packages << QStringLiteral("nodejs") << QStringLiteral("npm");
        step(both ? QStringLiteral("backend: npm install") : QStringLiteral("npm install"), QStringLiteral("npm install --no-fund --no-audit"), beDir);
    }

    // Baza: SQLite — plik obok backendu; PostgreSQL — serwer w kontenerze projektu (zadanie „baza danych”)
    QString dbUrl;
    QJsonArray tasks;
    if (db == QLatin1String("postgres")) {
        packages << QStringLiteral("postgresql-server") << QStringLiteral("postgresql");
        dbUrl = QStringLiteral("postgresql://postgres@localhost:5432/postgres");
        tasks << QJsonObject{{"label", "baza danych (PostgreSQL)"}, {"group", "run"},
                             {"command", "[ -d .aster/pgdata ] || initdb -D .aster/pgdata -U postgres --auth=trust -E UTF8 >/dev/null; "
                                         "exec postgres -D .aster/pgdata -k /tmp -p 5432 -c listen_addresses=localhost"}};
    } else if (db == QLatin1String("sqlite")) {
        dbUrl = QStringLiteral("sqlite:///dane.db");
    }
    if (!fe.isEmpty())
        tasks << QJsonObject{{"label", both ? "frontend: testy" : "testy (Vitest)"}, {"group", "test"}, {"command", "npm test"},
                             {"cwd", both ? "frontend" : "."}};
    if (be == QLatin1String("fastapi"))
        tasks << QJsonObject{{"label", both ? "backend: testy" : "testy (pytest)"}, {"group", "test"}, {"command", ".venv/bin/python -m pytest -q"},
                             {"cwd", both ? "backend" : "."}};
    else if (be == QLatin1String("node"))
        tasks << QJsonObject{{"label", both ? "backend: testy" : "testy (node --test)"}, {"group", "test"}, {"command", "npm test"},
                             {"cwd", both ? "backend" : "."}};
    writeText(root + QStringLiteral("/.aster/zadania.json"), QString::fromUtf8(QJsonDocument(tasks).toJson()));

    // .env.example (bez sekretów — prawdziwe wartości w portfelu: Aster Code → Sekrety projektu)
    QString env = QStringLiteral("# Zmienne środowiska. Wartości (hasła, klucze API) trzymaj w portfelu: Aster Code → Sekrety projektu.\n");
    if (!be.isEmpty())
        env += QStringLiteral("PORT=") + port + QLatin1Char('\n');
    if (!dbUrl.isEmpty())
        env += QStringLiteral("DATABASE_URL=") + dbUrl + QLatin1Char('\n');
    if (both)
        env += QStringLiteral("BACKEND_URL=http://localhost:") + port + QLatin1Char('\n');
    writeText(root + QStringLiteral("/.env.example"), env);
    writeText(root + QStringLiteral("/.gitignore"), QStringLiteral(".env\n.aster/pgdata/\n*.db\nnode_modules/\n.venv/\n__pycache__/\n"));

    QString readme = QStringLiteral("# %1\n\nUtworzone w Aster Code z szablonu „Nowa aplikacja”.\n\n").arg(name);
    readme += QStringLiteral("## Części\n\n");
    if (!fe.isEmpty())
        readme += QStringLiteral("- **%1** — Vite + React, testy: Vitest (`npm test`), serwer: `npm run dev` (http://localhost:5173)\n").arg(both ? QStringLiteral("frontend/") : QStringLiteral("Frontend"));
    if (be == QLatin1String("fastapi"))
        readme += QStringLiteral("- **%1** — FastAPI, testy: pytest, serwer: `.venv/bin/python -m uvicorn app.main:app --reload` (http://localhost:8000/docs)\n").arg(both ? QStringLiteral("backend/") : QStringLiteral("Backend"));
    else if (be == QLatin1String("node"))
        readme += QStringLiteral("- **%1** — Node + Express, testy: `npm test`, serwer: `npm run dev` (http://localhost:3000)\n").arg(both ? QStringLiteral("backend/") : QStringLiteral("Backend"));
    if (db == QLatin1String("postgres"))
        readme += QStringLiteral("- **Baza** — PostgreSQL w kontenerze projektu (zadanie „baza danych”, dane w `.aster/pgdata`)\n");
    else if (db == QLatin1String("sqlite"))
        readme += QStringLiteral("- **Baza** — SQLite (plik `dane.db`)\n");
    readme += QStringLiteral("\n## Uruchamianie\n\nW Aster Code: ▶ Uruchom (Ctrl+F5) startuje wszystko naraz, podgląd strony otwiera się sam.\n"
                             "Testy: Ctrl+Shift+P → Uruchom zadanie… → testy.\n");
    writeText(root + QStringLiteral("/README.md"), readme);

    // Git: repozytorium i pierwsze zatwierdzenie (bez autora w konfiguracji — samo repozytorium)
    if (opts.value(QStringLiteral("git"), true).toBool()) {
        // Bez autora w konfiguracji gita — nazwa użytkownika systemu (jak domyślnie robi git, gdy ma skąd ją wziąć)
        const QString cmd = QStringLiteral("git init -q -b main && git add -A && "
                                           "(git commit -q -m 'Nowy projekt z szablonu Aster Code' 2>/dev/null || "
                                           "git -c user.name=\"$(id -un)\" -c user.email=\"$(id -un)@$(uname -n)\" commit -q -m 'Nowy projekt z szablonu Aster Code')");
        QStringList argv = ProjectEnv::instance()->hostShell(cmd, root);
        if (argv.isEmpty())
            argv = {QStringLiteral("/bin/sh"), QStringLiteral("-c"), cmd};
        QProcess p;
        p.setWorkingDirectory(root);
        p.start(argv.first(), argv.mid(1));
        p.waitForFinished(15000);
    }
    packages.removeDuplicates();
    return {{QStringLiteral("ok"), true}, {QStringLiteral("path"), root}, {QStringLiteral("packages"), packages}, {QStringLiteral("setup"), setup}};
}
