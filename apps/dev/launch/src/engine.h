#pragma once

// Silnik Aster Launch — wspólny dla okna, polecenia w terminalu i D-Bus:
//  • projekty (folder z kodem, wykryty typ, cel wdrożenia) w ~/.local/share/Aster/aster-launch/projekty.json,
//  • plan wdrożenia / przywrócenia jako lista kroków z dokładnymi poleceniami — pokazywany przed wykonaniem,
//  • wykonanie planu (QProcess: ssh, rsync, curl, CLI hostingów), historia wersji, logi produkcji na żywo,
//  • sprawdzenie serwera, DNS domeny, klucze SSH, CLI hostingów (Netlify, Vercel, Cloudflare Pages).
// Na serwerze: /srv/aster-launch/<nazwa>/releases/vN + dowiązanie „current”, usługa aster-<nazwa> (systemd)
// albo kontener aster-<nazwa> (podman/docker), Caddy z plikiem /etc/caddy/Caddyfile.d/aster-<nazwa>.caddyfile.

#include <functional>
#include <QAbstractListModel>
#include <QJsonArray>
#include <QJsonObject>
#include <QObject>
#include <QPointer>
#include <QProcess>
#include <QStringList>
#include <QTimer>
#include <QVariant>
#include <QtQml/qqmlregistration.h>

class QQmlEngine;
class QJSEngine;

// Wiersze wyjścia (przebieg wdrożenia, logi produkcji) — dopisywane na bieżąco, z limitem
class LogModel : public QAbstractListModel
{
    Q_OBJECT
    QML_ELEMENT
    QML_UNCREATABLE("z Launch")
    Q_PROPERTY(int count READ rowCount NOTIFY countChanged)
public:
    enum Roles { TextRole = Qt::UserRole + 1, LevelRole };
    using QAbstractListModel::QAbstractListModel;
    int rowCount(const QModelIndex &parent = {}) const override { return parent.isValid() ? 0 : int(m_lines.size()); }
    QVariant data(const QModelIndex &index, int role) const override;
    QHash<int, QByteArray> roleNames() const override { return {{TextRole, "text"}, {LevelRole, "level"}}; }
    void append(const QString &line);
    Q_INVOKABLE void clear();
    Q_INVOKABLE QString text() const { return m_lines.join(QLatin1Char('\n')); }
    QStringList lines() const { return m_lines; }
Q_SIGNALS:
    void countChanged();
    void appended(const QString &line);
private:
    QStringList m_lines;
};

struct Step {
    QString id;        // build, prepare, upload, install, switch, proxy, cleanup, health, hosting…
    QString title;     // „Wysłanie plików na serwer”
    QString detail;    // jedno zdanie po ludzku
    QString where;     // „Na tym komputerze” / „Na serwerze root@…” / „Netlify”
    QString program;
    QStringList args;
    QByteArray input;  // skrypt podawany przez stdin (ssh … sh -s)
    QString shown;     // dokładnie to, co zostanie wykonane (pokazywane przed potwierdzeniem)
    QString workDir;
    bool change = true; // zmienia coś na serwerze / w hostingu
    QString state = QStringLiteral("pending"); // pending | running | done | failed | skipped
};

class Launch : public QObject
{
    Q_OBJECT
    QML_ELEMENT
    QML_SINGLETON
    Q_PROPERTY(QVariantList projects READ projects NOTIFY projectsChanged)
    Q_PROPERTY(QVariantList plan READ plan NOTIFY planChanged)
    Q_PROPERTY(QString planTitle READ planTitle NOTIFY planChanged)
    Q_PROPERTY(QString planProject READ planProject NOTIFY planChanged)
    Q_PROPERTY(QString planOrigin READ planOrigin NOTIFY planChanged)
    Q_PROPERTY(bool running READ running NOTIFY runningChanged)
    Q_PROPERTY(QString runResult READ runResult NOTIFY runningChanged)
    Q_PROPERTY(bool preparing READ preparing NOTIFY preparingChanged)
    Q_PROPERTY(LogModel *output READ output CONSTANT)
    Q_PROPERTY(LogModel *liveLog READ liveLog CONSTANT)
    Q_PROPERTY(QString liveLogProject READ liveLogProject NOTIFY liveLogChanged)
    Q_PROPERTY(bool liveLogRunning READ liveLogRunning NOTIFY liveLogChanged)
    Q_PROPERTY(bool flatpak READ flatpak CONSTANT)
    Q_PROPERTY(QVariantMap ask READ ask NOTIFY askChanged)   // pytanie z D-Bus (np. asystent chce logów)
public:
    // Jeden egzemplarz na proces (okno, D-Bus i terminal widzą ten sam plan) — bez konstruktora domyślnego,
    // żeby QML brał go przez create(), a nie tworzył własnego
    explicit Launch(QObject *parent);
    ~Launch() override;
    static Launch *instance();
    static Launch *create(QQmlEngine *, QJSEngine *);

    QVariantList projects() const;
    QVariantList plan() const;
    QString planTitle() const { return m_planTitle; }
    QString planProject() const { return m_planProject; }
    QString planOrigin() const { return m_planOrigin; }
    bool running() const { return m_running; }
    QString runResult() const { return m_runResult; }
    bool preparing() const { return m_preparing; }
    LogModel *output() { return &m_output; }
    LogModel *liveLog() { return &m_live; }
    QString liveLogProject() const { return m_liveProject; }
    bool liveLogRunning() const { return m_liveProc && m_liveProc->state() != QProcess::NotRunning; }
    bool flatpak() const;

    // ——— Projekty ———
    Q_INVOKABLE QVariantMap detect(const QString &path) const;      // typ, polecenia, port — bez zapisu
    Q_INVOKABLE QString addProject(const QString &path);             // id nowego (albo istniejącego) projektu
    Q_INVOKABLE void updateProject(const QString &id, const QVariantMap &changes);
    Q_INVOKABLE void removeProject(const QString &id);
    Q_INVOKABLE QVariantMap project(const QString &id) const;
    Q_INVOKABLE QString findProject(const QString &nameOrId) const; // dla CLI i D-Bus: nazwa, id albo ścieżka
    Q_INVOKABLE QString urlFor(const QString &id) const;
    Q_INVOKABLE int previousVersion(const QString &id) const;      // najnowsza wcześniejsza wersja do przywrócenia (0 = brak)

    // ——— Serwer i domena (tylko odczyt — bez potwierdzenia) ———
    Q_INVOKABLE void probe(const QString &id);         // → probed(id, ok, message)
    Q_INVOKABLE void checkDns(const QString &id);      // → dnsChecked(id, result)
    Q_INVOKABLE void checkHealth(const QString &id);   // → healthChecked(id, result)
    Q_INVOKABLE QVariantList sshKeys() const;
    Q_INVOKABLE QVariantMap createKey(const QString &name);
    Q_INVOKABLE QString publicKey(const QString &privatePath) const;
    Q_INVOKABLE void copyKeyInTerminal(const QString &id); // ssh-copy-id w Terminalu (hasło wpisuje użytkownik)
    Q_INVOKABLE void copyText(const QString &text);
    Q_INVOKABLE void openFolder(const QString &path);
    Q_INVOKABLE void openUrl(const QString &url);

    // ——— Hostingi przez ich CLI ———
    Q_INVOKABLE QVariantMap hostingInfo(const QString &kind) const;  // name, cli, installed, path, install, login
    Q_INVOKABLE void checkHostingLogin(const QString &kind);         // → hostingChecked(kind, loggedIn, who)
    Q_INVOKABLE void hostingLogin(const QString &kind);              // logowanie w przeglądarce (CLI otwiera stronę)
    Q_INVOKABLE void installHostingCli(const QString &kind);         // npm i -g --prefix ~/.local … (na tym komputerze)

    // ——— Plany: przygotuj → pokaż → potwierdź ———
    Q_INVOKABLE void prepareDeploy(const QString &id, const QString &origin = {});
    Q_INVOKABLE void prepareRollback(const QString &id, int version, const QString &origin = {});
    Q_INVOKABLE void confirmPlan();
    Q_INVOKABLE void cancelPlan();
    Q_INVOKABLE void stopRun();
    Q_INVOKABLE void closeRun();     // zamyka widok przebiegu po zakończeniu

    // ——— Logi produkcji ———
    Q_INVOKABLE void startLiveLog(const QString &id, int lines = 200);
    Q_INVOKABLE void stopLiveLog();
    void fetchLogs(const QString &id, int lines);    // jednorazowo (CLI / D-Bus) → logsFetched

    // Pytania do użytkownika od agenta (D-Bus): odpowiedź przez answer()
    QVariantMap ask() const { return m_ask; }
    Q_INVOKABLE int requestPermission(const QString &title, const QString &text, const QString &button);
    Q_INVOKABLE void answer(int token, bool ok);

    // Tekst planu do terminala / D-Bus
    QString planText() const;
    QJsonObject statusJson(const QString &id) const;
    QString describeType(const QString &type) const;
    void reload();

Q_SIGNALS:
    void projectsChanged();
    void planChanged();
    void planReady(const QString &id);
    void planFailed(const QString &id, const QString &message);
    void runningChanged();
    void preparingChanged();
    void runFinished(const QString &id, bool ok, const QString &message);
    void probed(const QString &id, bool ok, const QString &message);
    void dnsChecked(const QString &id, const QVariantMap &result);
    void healthChecked(const QString &id, const QVariantMap &result);
    void hostingChecked(const QString &kind, bool loggedIn, const QString &who);
    void hostingMessage(const QString &kind, const QString &message);
    void liveLogChanged();
    void logsFetched(const QString &id, bool ok, const QString &text);
    void message(const QString &text);
    void askChanged();
    void answered(int token, bool ok);
    void wantsAttention();
    void stepChanged(int index, const QString &title, const QString &state);

private:
    QJsonObject *find(const QString &id);
    const QJsonObject *find(const QString &id) const;
    void load();
    void save();
    QString dataDir() const;

    // Polecenia na komputerze — w Flatpaku przez flatpak-spawn --host (ssh, rsync, CLI hostingów są w systemie)
    void hostCommand(QString &program, QStringList &args) const;
    QString which(const QString &program) const;
    QStringList sshOptions(const QJsonObject &p) const;
    QString sshDest(const QJsonObject &p) const;
    Step remoteStep(const QJsonObject &p, const QString &id, const QString &title, const QString &detail, const QString &script, bool change = true) const;
    void runRemote(const QJsonObject &p, const QString &script, std::function<void(int, QString)> done);
    QStringList healthCurl(const QJsonObject &p, bool insecure) const;
    QString serverIp(const QJsonObject &p) const;

    QList<Step> deploySteps(const QJsonObject &p, int version, QString &error) const;
    QList<Step> rollbackSteps(const QJsonObject &p, int version, QString &error) const;
    QString caddySite(const QJsonObject &p) const;
    QString unitFile(const QJsonObject &p) const;
    QString startCommand(const QJsonObject &p) const;

    void setPlan(const QString &id, const QString &title, const QList<Step> &steps, const QString &kind, int version);
    void runStep(int i);
    void runHealthStep(int i, int attempt);
    void finishRun(bool ok, const QString &message);
    void setPreparing(bool p);

    QJsonArray m_projects;
    QList<Step> m_plan;
    QString m_planTitle, m_planProject, m_planKind, m_planOrigin;
    int m_planVersion = 0;
    bool m_running = false;
    bool m_preparing = false;
    QString m_runResult;
    int m_step = -1;
    QPointer<QProcess> m_proc;
    QString m_stepOutput;
    LogModel m_output;
    LogModel m_live;
    QPointer<QProcess> m_liveProc;
    QString m_liveProject;
    QVariantMap m_ask;
    int m_askToken = 0;
};
