#pragma once

#include <QNetworkAccessManager>
#include <QObject>
#include <QPointer>
#include <QProcess>
#include <QQmlEngine>
#include <QStringList>
#include <QVariantList>
#include <QVariantMap>

#include <functional>

// Instalator sklepu: programy (Flatpak, tryb użytkownika, bez hasła), paczki aplikacji Aster z wydania „aplikacje”
// i aplikacje webowe (aster-webapps). Jedna kolejka na wszystko: operacje idą po kolei,
// a QML widzi je przez activity i progress. Tu są też fakty o komputerze, z których korzysta karta programu.
class Flatpak : public QObject
{
    Q_OBJECT
    QML_ELEMENT
    QML_SINGLETON
    Q_PROPERTY(QStringList installed READ installed NOTIFY installedChanged)
    // [{id, name, version, size (bajty), origin, installation, runtime}]
    Q_PROPERTY(QVariantList installedApps READ installedApps NOTIFY installedChanged)
    // [{id, version, size}] — do pobrania
    Q_PROPERTY(QVariantList updateInfo READ updateInfo NOTIFY updatesChanged)
    Q_PROPERTY(QStringList updates READ updates NOTIFY updatesChanged)
    // {nazwa/gałąź: bajty} zainstalowanych bibliotek wspólnych
    Q_PROPERTY(QVariantMap runtimes READ runtimes NOTIFY runtimesChanged)
    // {id programu: {data: bajty danych użytkownika, lastUsed: ms lub 0}}
    Q_PROPERTY(QVariantMap usage READ usage NOTIFY usageChanged)
    // {appId: postęp 0..1} dla trwających i oczekujących operacji (-1 = czeka w kolejce, "*" = wszystkie)
    Q_PROPERTY(QVariantMap progress READ progress NOTIFY progressChanged)
    // [{appId, action, value}] w kolejności wykonania
    Q_PROPERTY(QVariantList activity READ activity NOTIFY progressChanged)
    // Zainstalowane aplikacje webowe: {adres: id}
    Q_PROPERTY(QVariantMap webApps READ webApps NOTIFY webAppsChanged)
    // Programy od producentów (aster-get): {id: {name, size, exec, cli}} i id z nowszą wersją
    Q_PROPERTY(QVariantMap getApps READ getApps NOTIFY getAppsChanged)
    Q_PROPERTY(QStringList getUpdates READ getUpdates NOTIFY getAppsChanged)
    Q_PROPERTY(bool available READ available CONSTANT)
    Q_PROPERTY(bool webAppsAvailable READ webAppsAvailable CONSTANT)
    Q_PROPERTY(QString arch READ arch CONSTANT)                 // x86_64 | aarch64
    Q_PROPERTY(double memoryGb READ memoryGb CONSTANT)
    Q_PROPERTY(double diskFree READ diskFree NOTIFY installedChanged)

public:
    explicit Flatpak(QObject *parent = nullptr);

    QStringList installed() const { return m_installed; }
    QVariantList installedApps() const { return m_apps; }
    QStringList updates() const { return m_updates; }
    QVariantList updateInfo() const { return m_updateInfo; }
    QVariantMap runtimes() const { return m_runtimes; }
    QVariantMap usage() const { return m_usage; }
    QVariantMap progress() const { return m_progress; }
    QVariantList activity() const;
    QVariantMap webApps() const { return m_webApps; }
    QVariantMap getApps() const { return m_getApps; }
    QStringList getUpdates() const { return m_getUpdates; }
    bool available() const;
    bool webAppsAvailable() const;
    QString arch() const;
    double memoryGb() const;
    double diskFree() const;

    Q_INVOKABLE void install(const QString &appId);
    // Paczka aplikacji Aster z wydania „aplikacje”: key = grafika, montaz…; id = org.aster.grafika
    Q_INVOKABLE void installBundle(const QString &appId, const QString &key);
    Q_INVOKABLE void uninstall(const QString &appId, bool deleteData = false);
    Q_INVOKABLE void update(const QString &appId);
    Q_INVOKABLE void updateAll();
    // Wraca do poprzedniej wersji programu
    Q_INVOKABLE void rollback(const QString &appId);
    // Usuwa biblioteki, których nie używa już żaden program
    Q_INVOKABLE void pruneRuntimes();
    Q_INVOKABLE void launch(const QString &appId);
    Q_INVOKABLE void addWebApp(const QString &key, const QString &url, const QString &name, const QString &category, const QString &color);
    Q_INVOKABLE void removeWebApp(const QString &key, const QString &id);
    Q_INVOKABLE void launchWebApp(const QString &id);
    // Program od producenta: recipe to przepis z katalogu (JSON), key = „get:id”
    Q_INVOKABLE void installGet(const QString &key, const QString &recipe);
    Q_INVOKABLE void updateGet(const QString &key);
    Q_INVOKABLE void removeGet(const QString &key);
    Q_INVOKABLE void launchGet(const QString &key);
    // Program uruchamiany z parametrem, np. Lutris z adresem instalatora Battle.net
    Q_INVOKABLE void launchWith(const QString &appId, const QString &argument);
    Q_INVOKABLE void launchExecutable(const QString &exec);
    Q_INVOKABLE bool hasExecutable(const QString &exec) const;
    Q_INVOKABLE void refresh();
    Q_INVOKABLE void refreshUsage();

Q_SIGNALS:
    void installedChanged();
    void updatesChanged();
    void runtimesChanged();
    void usageChanged();
    void progressChanged();
    void webAppsChanged();
    void getAppsChanged();
    void finished(const QString &appId, const QString &action, bool ok, const QString &message);

private:
    struct Job {
        QString action;     // install | bundle | uninstall | update | rollback | prune | webadd | webremove | get | getupdate | getremove
        QString appId;
        QStringList args;   // dodatkowe dane operacji
    };
    void enqueue(const Job &job);
    void startNext();
    void runProcess(const QString &program, const QStringList &args);
    void finishJob(bool ok, const QString &message = QString());
    void parseOutput(const QByteArray &chunk);
    void setProgress(const QString &appId, double value);
    void downloadBundle();
    void readWebApps();
    void readGetApps();
    void capture(const QStringList &args, std::function<void(const QString &)> done);

    QStringList m_installed;
    QVariantList m_apps;
    QStringList m_updates;
    QVariantList m_updateInfo;
    QVariantMap m_runtimes;
    QVariantMap m_usage;
    QVariantMap m_progress;
    QVariantMap m_webApps;
    QVariantMap m_getApps;
    QStringList m_getUpdates;
    QList<Job> m_queue;
    QPointer<QProcess> m_proc;
    QNetworkAccessManager m_net;
    Job m_current;
    bool m_running = false;
    QString m_lastError;
};
