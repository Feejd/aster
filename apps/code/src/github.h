#pragma once

#include <QObject>
#include <QPointer>
#include <QProcess>
#include <QQmlEngine>

class QNetworkAccessManager;

// Logowanie do GitHuba bez terminala: przez przeglądarkę (gh auth login --web — kod jednorazowy
// pokazany w Aster Code, strona github.com/login/device otwierana sama) albo tokenem trzymanym
// w portfelu systemu. Po zalogowaniu git push/pull do github.com działa bez pytań o hasło
// (gh auth setup-git albo pomocnik haseł z tokenem w Project), a repozytorium na GitHubie
// tworzy się jednym kliknięciem.
class GitHub : public QObject
{
    Q_OBJECT
    QML_ELEMENT
    QML_SINGLETON
    Q_PROPERTY(QString login READ login NOTIFY changed)              // nazwa konta albo pusta
    Q_PROPERTY(QString method READ method NOTIFY changed)            // gh | token | ""
    Q_PROPERTY(bool busy READ busy NOTIFY changed)
    Q_PROPERTY(QString code READ code NOTIFY changed)                // kod jednorazowy przy logowaniu przez przeglądarkę

public:
    explicit GitHub(QObject *parent = nullptr);
    ~GitHub() override { cancelLogin(); }
    static QString token();                                          // token z portfela (pamiętany w procesie)

    QString login() const { return m_login; }
    QString method() const { return m_method; }
    bool busy() const { return m_busy; }
    QString code() const { return m_code; }

    Q_INVOKABLE void refresh();
    Q_INVOKABLE bool hasGh() const;
    Q_INVOKABLE void loginBrowser();
    Q_INVOKABLE void cancelLogin();
    Q_INVOKABLE void loginToken(const QString &token);
    Q_INVOKABLE void logout();
    // Nowe repozytorium na GitHubie z bieżącego folderu (git) i pierwsze wysłanie
    Q_INVOKABLE void createRepo(const QString &root, const QString &name, bool isPrivate);

Q_SIGNALS:
    void changed();
    void message(const QString &text);
    void repoCreated(const QString &url);

private:
    void setBusy(bool b) { m_busy = b; Q_EMIT changed(); }
    void checkToken(const QString &token, bool save);

    QString m_login, m_method, m_code;
    bool m_busy = false;
    QPointer<QProcess> m_proc;
    QNetworkAccessManager *m_net;
};
