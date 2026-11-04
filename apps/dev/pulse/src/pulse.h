#pragma once

#include "jsontree.h"
#include "workspace.h"

#include <QFileSystemWatcher>
#include <QHash>
#include <QObject>
#include <QQmlEngine>
#include <QTimer>
#include <QVariant>

class QNetworkAccessManager;
class Runner;

// Stan programu dla QML (singleton Pulse): obszar roboczy, kolekcje, środowiska, historia i ostatnia odpowiedź.
class PulseApp : public QObject
{
    Q_OBJECT
    QML_NAMED_ELEMENT(Pulse)
    QML_SINGLETON

    Q_PROPERTY(QString workspaceDir READ workspaceDir NOTIFY workspaceChanged)
    Q_PROPERTY(QString workspaceName READ workspaceName NOTIFY workspaceChanged)
    Q_PROPERTY(QStringList recentWorkspaces READ recentWorkspaces NOTIFY workspaceChanged)
    Q_PROPERTY(QVariantList collections READ collections NOTIFY collectionsChanged)
    Q_PROPERTY(QVariantList environments READ environments NOTIFY environmentsChanged)
    Q_PROPERTY(QString activeEnv READ activeEnv WRITE setActiveEnv NOTIFY environmentsChanged)
    Q_PROPERTY(QStringList variableNames READ variableNames NOTIFY environmentsChanged)
    Q_PROPERTY(QVariantList history READ history NOTIFY historyChanged)
    Q_PROPERTY(bool busy READ busy NOTIFY busyChanged)
    Q_PROPERTY(QVariantMap response READ response NOTIFY responseChanged)
    Q_PROPERTY(QString responseText READ responseText NOTIFY responseChanged)
    Q_PROPERTY(JsonTreeModel *tree READ tree CONSTANT)
    Q_PROPERTY(bool walletAvailable READ walletAvailable CONSTANT)
    Q_PROPERTY(QString lastError READ lastError NOTIFY lastErrorChanged)

public:
    explicit PulseApp(QObject *parent = nullptr);
    static PulseApp *create(QQmlEngine *, QJSEngine *);
    static void setInitialFolder(const QString &folder) { s_initialFolder = folder; }
    static void setNetwork(QNetworkAccessManager *nam) { s_nam = nam; }

    QString workspaceDir() const { return m_ws.dir(); }
    QString workspaceName() const { return m_ws.name(); }
    QStringList recentWorkspaces() const;
    QVariantList collections() const;
    QVariantList environments() const { return m_ws.environments().toVariantList(); }
    QString activeEnv() const { return m_ws.activeEnvironment(); }
    void setActiveEnv(const QString &env);
    QStringList variableNames() const;
    QVariantList history() const { return m_history; }
    bool busy() const;
    QVariantMap response() const { return m_response; }
    QString responseText() const { return m_responseText; }
    JsonTreeModel *tree() { return &m_tree; }
    bool walletAvailable() const { return m_wallet; }
    QString lastError() const { return m_lastError; }

    // Folder projektu albo obszaru (ścieżka lub file://); bez pulse.json — tworzy nowy obszar
    Q_INVOKABLE bool openFolder(const QVariant &folder);
    Q_INVOKABLE void reload();

    Q_INVOKABLE void send(const QVariantMap &request);
    Q_INVOKABLE void cancel();
    Q_INVOKABLE void clearResponse();

    Q_INVOKABLE QString createCollection(const QString &name);
    Q_INVOKABLE bool renameCollection(const QString &file, const QString &name);
    Q_INVOKABLE bool deleteCollection(const QString &file);
    // Zapisuje zapytanie (po id; nowe dostaje id) i zwraca je w zapisanej postaci
    Q_INVOKABLE QVariantMap saveRequest(const QString &file, const QVariantMap &request);
    Q_INVOKABLE bool deleteRequest(const QString &file, const QString &id);
    Q_INVOKABLE QVariantMap duplicateRequest(const QString &file, const QString &id);
    Q_INVOKABLE bool moveRequest(const QString &fromFile, const QString &id, const QString &toFile);
    Q_INVOKABLE QVariantMap newRequest() const;

    // Środowiska z wartościami tajnych zmiennych z portfela (do okna edycji) i zapis (tajne → portfel)
    Q_INVOKABLE QVariantList environmentsWithSecrets();
    Q_INVOKABLE bool saveEnvironments(const QVariantList &envs);
    // Podgląd: tekst z podstawionymi zmiennymi wybranego środowiska (tajne jako •••)
    Q_INVOKABLE QString preview(const QString &text) const;
    Q_INVOKABLE QString variableValue(const QString &name) const;

    Q_INVOKABLE QVariantMap importCurl(const QString &command) const;   // { request } albo { error }
    Q_INVOKABLE QString exportCurl(const QVariantMap &request, bool resolve);
    Q_INVOKABLE void copy(const QString &text) const;
    Q_INVOKABLE QString clipboardText() const;
    Q_INVOKABLE bool saveResponse(const QVariant &file);
    Q_INVOKABLE void clearHistory();
    Q_INVOKABLE QString formatJson(const QString &text) const;     // pusty, gdy to nie JSON
    Q_INVOKABLE QString jsonError(const QString &text) const;
    Q_INVOKABLE QString localPath(const QVariant &url) const;
    Q_INVOKABLE QString fileName(const QString &path) const;
    Q_INVOKABLE QString prettyPath(const QString &path) const;    // ~/… zamiast katalogu domowego
    // Polecenie dla agenta/terminala, które wyśle to zapytanie
    Q_INVOKABLE QString cliCommand(const QString &file, const QString &requestName) const;

    // Wyniki z D-Bus i z terminala trafiają do historii — okno odświeża ją od razu
    void externalRequestFinished();

Q_SIGNALS:
    void workspaceChanged();
    void collectionsChanged();
    void environmentsChanged();
    void historyChanged();
    void busyChanged();
    void responseChanged();
    void lastErrorChanged();
    void message(const QString &text);

private:
    void setWorkspace(const QString &dir);
    void loadHistory();
    void watch();
    QJsonObject collectionByFile(const QString &file) const;
    void setError(const QString &e);
    QHash<QString, QString> sendVariables(QStringList *missing);

    static QString s_initialFolder;
    static QNetworkAccessManager *s_nam;
    Workspace m_ws;
    QNetworkAccessManager *m_nam;
    Runner *m_runner = nullptr;
    JsonTreeModel m_tree;
    QVariantMap m_response;
    QString m_responseText;
    QByteArray m_body;
    QVariantList m_history;
    QFileSystemWatcher m_watcher;
    QTimer m_reloadTimer;
    QHash<QString, QHash<QString, QString>> m_secretCache;   // środowisko → tajne zmienne (po pierwszym odczycie)
    bool m_wallet = false;
    QString m_lastError;
};
