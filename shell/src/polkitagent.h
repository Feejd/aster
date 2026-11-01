#pragma once

#include <PolkitQt1/Agent/Listener>
#include <PolkitQt1/Agent/Session>
#include <PolkitQt1/Details>
#include <PolkitQt1/Identity>
#include <QPointer>
#include <QQmlEngine>
#include <QVariantList>

// Agent uwierzytelniania polkit w powłoce: gdy program prosi o uprawnienia administratora
// (zmiana strefy czasowej, instalacja, drukarka…), powłoka pokazuje okno hasła Aster
// zamiast okna KDE. Rejestruje się dla bieżącej sesji (agent KDE jest w sesji Aster wyłączony).
class PolkitAgent : public PolkitQt1::Agent::Listener
{
    Q_OBJECT
    QML_NAMED_ELEMENT(Polkit)
    QML_SINGLETON
    Q_PROPERTY(bool active READ active NOTIFY changed)
    Q_PROPERTY(QString appName READ appName NOTIFY changed)          // kto prosi („Ustawienia”)
    Q_PROPERTY(QString message READ message NOTIFY changed)          // opis czynności z polkit
    Q_PROPERTY(QString actionId READ actionId NOTIFY changed)
    Q_PROPERTY(QVariantList users READ users NOTIFY changed)         // [{ name, realName, icon }]
    Q_PROPERTY(int userIndex READ userIndex NOTIFY changed)
    Q_PROPERTY(bool echo READ echo NOTIFY changed)                   // odpowiedź widoczna (np. kod, nie hasło)
    Q_PROPERTY(QString prompt READ prompt NOTIFY changed)
    Q_PROPERTY(QString error READ error NOTIFY changed)
    Q_PROPERTY(bool busy READ busy NOTIFY changed)
    Q_PROPERTY(int attempt READ attempt NOTIFY changed)             // rośnie przy błędnym haśle (potrząśnięcie)

public:
    explicit PolkitAgent(QObject *parent = nullptr);
    ~PolkitAgent() override;

    bool active() const { return m_active; }
    QString appName() const { return m_appName; }
    QString message() const { return m_message; }
    QString actionId() const { return m_actionId; }
    QVariantList users() const { return m_users; }
    int userIndex() const { return m_userIndex; }
    bool echo() const { return m_echo; }
    QString prompt() const { return m_prompt; }
    QString error() const { return m_error; }
    bool busy() const { return m_busy; }
    int attempt() const { return m_attempt; }

    Q_INVOKABLE void respond(const QString &password);
    Q_INVOKABLE void cancel();
    Q_INVOKABLE void selectUser(int index);

public Q_SLOTS:
    void initiateAuthentication(const QString &actionId, const QString &message, const QString &iconName,
                                const PolkitQt1::Details &details, const QString &cookie,
                                const PolkitQt1::Identity::List &identities, PolkitQt1::Agent::AsyncResult *result) override;
    bool initiateAuthenticationFinish() override;
    void cancelAuthentication() override;

Q_SIGNALS:
    void changed();

private:
    void startSession();
    void finish();
    void onRequest(const QString &request, bool echo);
    void onCompleted(bool gained);

    bool m_active = false;
    QString m_appName, m_message, m_actionId, m_cookie, m_prompt, m_error;
    QVariantList m_users;
    PolkitQt1::Identity::List m_identities;
    int m_userIndex = 0;
    bool m_echo = false;
    bool m_busy = false;
    bool m_waiting = false;
    bool m_cancelled = false;
    int m_attempt = 0;
    QPointer<PolkitQt1::Agent::Session> m_session;
    PolkitQt1::Agent::AsyncResult *m_result = nullptr;
};
