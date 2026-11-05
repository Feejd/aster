#include "github.h"
#include "projectenv.h"
#include "secretstore.h"

#include <QDesktopServices>
#include <QJsonDocument>
#include <QJsonObject>
#include <QNetworkAccessManager>
#include <QNetworkReply>
#include <QRegularExpression>
#include <QUrl>

namespace {

QString s_token;
bool s_tokenLoaded = false;

QStringList ghArgv(const QStringList &args)
{
    return ProjectEnv::instance()->program(QStringList{QStringLiteral("gh")} + args);
}

} // namespace

QString GitHub::token()
{
    if (!s_tokenLoaded) {
        s_token = SecretStore::globalGet(QStringLiteral("GITHUB_TOKEN"));
        s_tokenLoaded = true;
    }
    return s_token;
}

GitHub::GitHub(QObject *parent)
    : QObject(parent)
    , m_net(new QNetworkAccessManager(this))
{
}

bool GitHub::hasGh() const
{
    return ProjectEnv::instance()->has(QStringLiteral("gh"));
}

void GitHub::refresh()
{
    // Najpierw gh (logowanie przez przeglądarkę), potem token z portfela
    if (hasGh()) {
        const QStringList argv = ghArgv({QStringLiteral("api"), QStringLiteral("user"), QStringLiteral("--jq"), QStringLiteral(".login")});
        QProcess p;
        p.start(argv.first(), argv.mid(1));
        if (p.waitForFinished(10000) && p.exitCode() == 0) {
            const QString l = QString::fromUtf8(p.readAllStandardOutput()).trimmed();
            if (!l.isEmpty()) {
                m_login = l;
                m_method = QStringLiteral("gh");
                Q_EMIT changed();
                return;
            }
        }
    }
    if (const QString t = token(); !t.isEmpty()) {
        checkToken(t, false);
        return;
    }
    m_login.clear();
    m_method.clear();
    Q_EMIT changed();
}

void GitHub::loginBrowser()
{
    if (!hasGh()) {
        Q_EMIT message(QStringLiteral("Logowanie przez przeglądarkę potrzebuje programu gh — zainstaluj go w kontenerze projektu albo użyj tokenu"));
        return;
    }
    cancelLogin();
    auto *p = new QProcess(this);
    m_proc = p;
    p->setProcessChannelMode(QProcess::MergedChannels);
    QProcessEnvironment env = QProcessEnvironment::systemEnvironment();
    env.insert(QStringLiteral("BROWSER"), QStringLiteral("true"));      // stronę otwiera Aster Code
    env.insert(QStringLiteral("GH_NO_UPDATE_NOTIFIER"), QStringLiteral("1"));
    p->setProcessEnvironment(env);
    m_code.clear();
    setBusy(true);
    connect(p, &QProcess::readyRead, this, [this, p] {
        const QString t = QString::fromUtf8(p->readAll());
        static const QRegularExpression code(QStringLiteral("one-time code:\\s*([A-Z0-9]{4}-[A-Z0-9]{4})"));
        if (const auto m = code.match(t); m.hasMatch() && m_code.isEmpty()) {
            m_code = m.captured(1);
            Q_EMIT changed();
            QDesktopServices::openUrl(QUrl(QStringLiteral("https://github.com/login/device")));
        }
        // „Press Enter to open github.com in your browser…”
        if (t.contains(QLatin1String("Press Enter")))
            p->write("\n");
    });
    connect(p, &QProcess::finished, this, [this, p](int code) {
        p->deleteLater();
        m_code.clear();
        setBusy(false);
        if (code == 0) {
            // git push/pull przez gh — bez pytań o hasło
            const QStringList argv = ghArgv({QStringLiteral("auth"), QStringLiteral("setup-git")});
            QProcess::execute(argv.first(), argv.mid(1));
            refresh();
            Q_EMIT message(QStringLiteral("Zalogowano do GitHuba jako ") + m_login);
        } else if (code != 15 && code != 9) {
            Q_EMIT message(QStringLiteral("Logowanie do GitHuba nie powiodło się"));
        }
    });
    const QStringList argv = ghArgv({QStringLiteral("auth"), QStringLiteral("login"), QStringLiteral("--hostname"), QStringLiteral("github.com"),
                                     QStringLiteral("--git-protocol"), QStringLiteral("https"), QStringLiteral("--web"),
                                     QStringLiteral("--scopes"), QStringLiteral("repo,workflow")});
    p->start(argv.first(), argv.mid(1));
}

void GitHub::cancelLogin()
{
    if (m_proc && m_proc->state() != QProcess::NotRunning) {
        m_proc->kill();
        m_proc->waitForFinished(1000);
    }
    m_code.clear();
    if (m_busy)
        setBusy(false);
}

void GitHub::checkToken(const QString &token, bool save)
{
    QNetworkRequest req(QUrl(QStringLiteral("https://api.github.com/user")));
    req.setRawHeader("Authorization", "Bearer " + token.toUtf8());
    req.setRawHeader("Accept", "application/vnd.github+json");
    req.setHeader(QNetworkRequest::UserAgentHeader, QStringLiteral("Aster-Code"));
    setBusy(true);
    QNetworkReply *r = m_net->get(req);
    connect(r, &QNetworkReply::finished, this, [this, r, token, save] {
        r->deleteLater();
        setBusy(false);
        const QString l = QJsonDocument::fromJson(r->readAll()).object().value(QStringLiteral("login")).toString();
        if (r->error() != QNetworkReply::NoError || l.isEmpty()) {
            if (save)
                Q_EMIT message(QStringLiteral("GitHub nie przyjął tokenu — sprawdź, czy jest ważny i ma uprawnienie „repo”"));
            return;
        }
        if (save) {
            if (!SecretStore::globalSet(QStringLiteral("GITHUB_TOKEN"), token)) {
                Q_EMIT message(QStringLiteral("Nie udało się zapisać tokenu w portfelu"));
                return;
            }
            s_token = token;
            s_tokenLoaded = true;
            Q_EMIT message(QStringLiteral("Zalogowano do GitHuba jako ") + l);
        }
        m_login = l;
        m_method = QStringLiteral("token");
        Q_EMIT changed();
    });
}

void GitHub::loginToken(const QString &token)
{
    if (!token.trimmed().isEmpty())
        checkToken(token.trimmed(), true);
}

void GitHub::logout()
{
    if (m_method == QLatin1String("gh")) {
        const QStringList argv = ghArgv({QStringLiteral("auth"), QStringLiteral("logout"), QStringLiteral("--hostname"), QStringLiteral("github.com")});
        QProcess::execute(argv.first(), argv.mid(1));
    }
    SecretStore::globalSet(QStringLiteral("GITHUB_TOKEN"), QString());
    s_token.clear();
    m_login.clear();
    m_method.clear();
    Q_EMIT changed();
}

void GitHub::createRepo(const QString &root, const QString &name, bool isPrivate)
{
    if (m_method == QLatin1String("gh")) {
        auto *p = new QProcess(this);
        p->setWorkingDirectory(root);
        p->setProcessChannelMode(QProcess::MergedChannels);
        setBusy(true);
        connect(p, &QProcess::finished, this, [this, p](int code) {
            p->deleteLater();
            setBusy(false);
            const QString out = QString::fromUtf8(p->readAll());
            static const QRegularExpression url(QStringLiteral("https://github\\.com/[^\\s]+"));
            if (code == 0)
                Q_EMIT repoCreated(url.match(out).captured(0));
            else
                Q_EMIT message(QStringLiteral("Nie udało się utworzyć repozytorium: ") + out.trimmed().section(QLatin1Char('\n'), -1).left(200));
        });
        const QStringList argv = ghArgv({QStringLiteral("repo"), QStringLiteral("create"), name, isPrivate ? QStringLiteral("--private") : QStringLiteral("--public"),
                                         QStringLiteral("--source"), QStringLiteral("."), QStringLiteral("--remote"), QStringLiteral("origin"), QStringLiteral("--push")});
        // gh w kontenerze musi zacząć w folderze projektu
        QStringList a = argv;
        if (ProjectEnv::instance()->state() == QLatin1String("ready"))
            a = ProjectEnv::instance()->shell(QStringLiteral("gh repo create '%1' %2 --source . --remote origin --push").arg(name, isPrivate ? QStringLiteral("--private") : QStringLiteral("--public")), root);
        p->start(a.first(), a.mid(1));
        return;
    }
    // Token: API GitHuba, potem origin i wysłanie przez Project (pomocnik haseł z tokenem)
    QNetworkRequest req(QUrl(QStringLiteral("https://api.github.com/user/repos")));
    req.setRawHeader("Authorization", "Bearer " + token().toUtf8());
    req.setRawHeader("Accept", "application/vnd.github+json");
    req.setHeader(QNetworkRequest::ContentTypeHeader, QStringLiteral("application/json"));
    req.setHeader(QNetworkRequest::UserAgentHeader, QStringLiteral("Aster-Code"));
    setBusy(true);
    QNetworkReply *r = m_net->post(req, QJsonDocument(QJsonObject{{"name", name}, {"private", isPrivate}}).toJson());
    connect(r, &QNetworkReply::finished, this, [this, r] {
        r->deleteLater();
        setBusy(false);
        const QJsonObject o = QJsonDocument::fromJson(r->readAll()).object();
        if (r->error() != QNetworkReply::NoError) {
            Q_EMIT message(QStringLiteral("Nie udało się utworzyć repozytorium: ") + o.value(QStringLiteral("message")).toString(r->errorString()));
            return;
        }
        Q_EMIT repoCreated(o.value(QStringLiteral("html_url")).toString());
    });
}
