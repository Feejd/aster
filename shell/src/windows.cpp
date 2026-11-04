#include "windows.h"

#include <KApplicationTrader>
#include <KIO/ApplicationLauncherJob>
#include <KService>

#include <QDBusConnection>
#include <QDir>
#include <QJsonArray>
#include <QJsonDocument>
#include <QJsonObject>
#include <QRegularExpression>
#include <QUrl>

namespace {

// Bez wielkości liter i polskich znaków („Montaż” = „montaz”)
QString fold(const QString &t)
{
    QString n = t.toLower().normalized(QString::NormalizationForm_D);
    n.remove(QRegularExpression(QStringLiteral("\\p{Mn}")));
    n.replace(QChar(0x0142), QLatin1Char('l'));
    return n.simplified();
}

int role(const QAbstractItemModel *m, const char *name)
{
    const auto names = m->roleNames();
    for (auto it = names.begin(); it != names.end(); ++it)
        if (it.value() == name)
            return it.key();
    return -1;
}

// Programy Aster rozprowadzane jako Flatpaki (tools/install-apps.sh) — mogą jeszcze nie być zainstalowane
struct AsterApp {
    const char *id;
    const char *name;
    QStringList aliases;
};
const QList<AsterApp> &asterApps()
{
    static const QList<AsterApp> apps{
        {"code", "Aster Code", {QStringLiteral("code"), QStringLiteral("aster code"), QStringLiteral("kod"), QStringLiteral("edytor kodu"), QStringLiteral("vscode"), QStringLiteral("visual studio code")}},
        {"grafika", "Grafika", {QStringLiteral("grafika"), QStringLiteral("aster grafika"), QStringLiteral("canva"), QStringLiteral("plakat")}},
        {"montaz", "Montaż", {QStringLiteral("montaz"), QStringLiteral("aster montaz"), QStringLiteral("edytor wideo"), QStringLiteral("capcut")}},
        {"studio", "Studio", {QStringLiteral("studio"), QStringLiteral("aster studio"), QStringLiteral("studio muzyczne")}},
        {"editor", "Edytor tekstu", {QStringLiteral("editor"), QStringLiteral("edytor"), QStringLiteral("edytor tekstu")}},
        {"calculator", "Kalkulator", {QStringLiteral("calculator"), QStringLiteral("kalkulator")}},
        {"photos", "Zdjęcia", {QStringLiteral("photos"), QStringLiteral("zdjecia")}},
        {"music", "Muzyka", {QStringLiteral("music"), QStringLiteral("muzyka")}},
        {"video", "Wideo", {QStringLiteral("video"), QStringLiteral("wideo"), QStringLiteral("odtwarzacz")}},
        {"pdf", "Podgląd PDF", {QStringLiteral("pdf"), QStringLiteral("podglad pdf")}},
        {"camera", "Kamera", {QStringLiteral("camera"), QStringLiteral("kamera")}},
    };
    return apps;
}

} // namespace

Windows::Windows(QObject *parent)
    : QObject(parent)
{
    QDBusConnection bus = QDBusConnection::sessionBus();
    bus.registerObject(QStringLiteral("/org/aster/Shell"), this, QDBusConnection::ExportScriptableSlots);
    bus.registerService(QStringLiteral("org.aster.Shell"));
}

void Windows::setModel(QAbstractItemModel *m)
{
    if (m_model == m)
        return;
    m_model = m;
    Q_EMIT modelChanged();
}

QString Windows::ListWindows()
{
    QJsonArray out;
    if (!m_model)
        return QStringLiteral("[]");
    const int rWin = role(m_model, "IsWindow"), rApp = role(m_model, "AppName"), rId = role(m_model, "AppId"),
              rAct = role(m_model, "IsActive"), rMin = role(m_model, "IsMinimized");
    int n = 0;
    for (int i = 0; i < m_model->rowCount(); ++i) {
        const QModelIndex ix = m_model->index(i, 0);
        if (!ix.data(rWin).toBool())
            continue;
        out.append(QJsonObject{{QStringLiteral("n"), ++n},
                               {QStringLiteral("title"), ix.data(Qt::DisplayRole).toString()},
                               {QStringLiteral("app"), ix.data(rApp).toString()},
                               {QStringLiteral("appId"), ix.data(rId).toString()},
                               {QStringLiteral("active"), ix.data(rAct).toBool()},
                               {QStringLiteral("minimized"), ix.data(rMin).toBool()}});
    }
    return QString::fromUtf8(QJsonDocument(out).toJson(QJsonDocument::Compact));
}

// Okno po numerze z listy, albo po fragmencie tytułu / nazwy programu (najpierw nazwa programu)
QModelIndex Windows::find(const QString &query, QString *problem) const
{
    if (!m_model) {
        *problem = QStringLiteral("Lista okien jest niedostępna");
        return {};
    }
    const int rWin = role(m_model, "IsWindow"), rApp = role(m_model, "AppName"), rId = role(m_model, "AppId");
    const QString q = fold(query);
    bool isNumber = false;
    const int wanted = query.trimmed().toInt(&isNumber);
    QModelIndex byApp, byTitle;
    int matches = 0, n = 0;
    for (int i = 0; i < m_model->rowCount(); ++i) {
        const QModelIndex ix = m_model->index(i, 0);
        if (!ix.data(rWin).toBool())
            continue;
        ++n;
        if (isNumber) {
            if (n == wanted)
                return ix;
            continue;
        }
        const QString app = fold(ix.data(rApp).toString()), id = fold(ix.data(rId).toString());
        if (!q.isEmpty() && (app.contains(q) || id.contains(q) || q.contains(app))) {
            if (!byApp.isValid())
                byApp = ix;
            ++matches;
        } else if (!q.isEmpty() && fold(ix.data(Qt::DisplayRole).toString()).contains(q) && !byTitle.isValid()) {
            byTitle = ix;
        }
    }
    if (byApp.isValid())
        return byApp;
    if (byTitle.isValid())
        return byTitle;
    *problem = n == 0 ? QStringLiteral("Nie ma otwartych okien") : QStringLiteral("Nie ma okna „%1” (lista: aster --okna)").arg(query);
    return {};
}

QString Windows::WindowAction(const QString &action, const QString &query)
{
    QString problem;
    const QModelIndex ix = find(query, &problem);
    if (!ix.isValid())
        return problem;
    const char *method = nullptr;
    if (action == QLatin1String("pokaz")) {
        method = "requestActivate";
    } else if (action == QLatin1String("zminimalizuj")) {
        if (ix.data(role(m_model, "IsMinimized")).toBool())
            return {};
        method = "requestToggleMinimized";
    } else if (action == QLatin1String("maksymalizuj")) {
        if (ix.data(role(m_model, "IsMaximized")).toBool())
            return {};
        method = "requestToggleMaximized";
    } else if (action == QLatin1String("zamknij")) {
        method = "requestClose";
    } else {
        return QStringLiteral("Nieznane działanie: %1 (pokaz, zminimalizuj, maksymalizuj, zamknij)").arg(action);
    }
    QMetaObject::invokeMethod(m_model, method, Q_ARG(QModelIndex, QModelIndex(ix)));
    return {};
}

QString Windows::OpenApp(const QString &name, const QStringList &args, const QString &workingDir)
{
    QString q = fold(name);
    q.remove(QRegularExpression(QStringLiteral("^(program|aplikacja|aplikacje)\\s+")));
    if (q.isEmpty())
        return QStringLiteral("Podaj nazwę programu");
    // Program Aster z listy podpowiada swój identyfikator (org.aster.<id>), nawet gdy nazwa jest „ludzka”
    QString asterId;
    for (const AsterApp &a : asterApps())
        if (a.aliases.contains(q) || fold(QString::fromUtf8(a.name)) == q)
            asterId = QString::fromLatin1(a.id);

    KService::Ptr best;
    int bestScore = 0;
    const KService::List all = KApplicationTrader::query([](const KService::Ptr &) { return true; });
    for (const KService::Ptr &s : all) {
        if (s->noDisplay())
            continue;
        const QString desk = fold(s->desktopEntryName());
        const QString last = desk.section(QLatin1Char('.'), -1);
        const QString nm = fold(s->name());
        const QString exec = fold(s->exec().section(QLatin1Char(' '), 0, 0).section(QLatin1Char('/'), -1));
        int score = 0;
        if (!asterId.isEmpty() && desk == QStringLiteral("org.aster.") + asterId)
            score = 120;
        else if (desk == q || nm == q || exec == q || QStringLiteral("aster ") + q == nm)
            score = 100;
        else if (last == q || exec == QStringLiteral("aster-") + q)
            score = 90;
        else if (nm.startsWith(q))
            score = 60;
        else if (nm.contains(q) || q.contains(nm))
            score = 45;
        else if (fold(s->genericName()).contains(q))
            score = 35;
        else if (const QStringList kw = s->keywords(); std::any_of(kw.begin(), kw.end(), [&](const QString &k) { return fold(k) == q; }))
            score = 30;
        if (score > bestScore) {
            bestScore = score;
            best = s;
        }
    }
    if (!best || (bestScore < 90 && !asterId.isEmpty() && !best->desktopEntryName().startsWith(QLatin1String("org.aster."))))
        if (!asterId.isEmpty())
            return QStringLiteral("nie-ma:%1").arg(asterId);
    if (!best)
        return QStringLiteral("Nie ma programu „%1” — poszukaj go w Sklepie (flatpak search %1)").arg(name);

    auto *job = new KIO::ApplicationLauncherJob(best);
    QList<QUrl> urls;
    for (const QString &a : args)
        if (!a.trimmed().isEmpty())
            urls << QUrl::fromUserInput(a, workingDir.isEmpty() ? QDir::homePath() : workingDir, QUrl::AssumeLocalFile);
    job->setUrls(urls);
    job->start();
    return QStringLiteral("ok:") + best->name();
}
