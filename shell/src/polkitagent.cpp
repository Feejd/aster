#include "polkitagent.h"

#include <PolkitQt1/Details>
#include <PolkitQt1/Subject>
#include <QFile>
#include <QFileInfo>
#include <QTimer>

#include <pwd.h>
#include <unistd.h>

namespace {

// Nazwa programu, który prosi o uprawnienia — po identyfikatorze procesu z polkit
QString programName(const PolkitQt1::Details &details)
{
    QString pid = details.lookup(QStringLiteral("polkit.subject-pid"));
    if (pid.isEmpty())
        pid = details.lookup(QStringLiteral("polkit.caller-pid"));
    QFile comm(QStringLiteral("/proc/%1/comm").arg(pid));
    if (pid.isEmpty() || !comm.open(QIODevice::ReadOnly))
        return {};
    const QString name = QString::fromUtf8(comm.readAll()).trimmed();
    static const QHash<QString, QString> known{
        {QStringLiteral("aster-settings"), QStringLiteral("Ustawienia")},
        {QStringLiteral("aster-store"), QStringLiteral("Sklep")},
        {QStringLiteral("aster-files"), QStringLiteral("Pliki")},
        {QStringLiteral("aster-terminal"), QStringLiteral("Terminal")},
        {QStringLiteral("aster-shell"), QStringLiteral("Aster")},
        {QStringLiteral("bash"), QStringLiteral("Terminal")},
        {QStringLiteral("zsh"), QStringLiteral("Terminal")},
        {QStringLiteral("fish"), QStringLiteral("Terminal")},
    };
    return known.value(name, name);
}

QVariantMap userInfo(const PolkitQt1::Identity &identity)
{
    PolkitQt1::Identity copy = identity;
    const PolkitQt1::UnixUserIdentity user = copy.toUnixUserIdentity();
    QString name = identity.toString(), real;
    if (const passwd *pw = ::getpwuid(user.uid())) {
        name = QString::fromLocal8Bit(pw->pw_name);
        real = QString::fromLocal8Bit(pw->pw_gecos).section(QLatin1Char(','), 0, 0);
    }
    const QString icon = QStringLiteral("/var/lib/AccountsService/icons/") + name;
    return {{QStringLiteral("name"), name},
            {QStringLiteral("realName"), real.isEmpty() ? name : real},
            {QStringLiteral("icon"), QFileInfo::exists(icon) ? QStringLiteral("file://") + icon : QString()},
            {QStringLiteral("uid"), uint(user.uid())}};
}

} // namespace

PolkitAgent::PolkitAgent(QObject *parent)
    : PolkitQt1::Agent::Listener(parent)
{
    // Podgląd w trakcie pracy nad wyglądem: przykładowa prośba zamiast prawdziwego agenta
    if (qEnvironmentVariableIsSet("ASTER_POLKIT_DEMO")) {
        m_active = true;
        m_appName = QStringLiteral("Ustawienia");
        m_message = QStringLiteral("Do zmiany strefy czasowej systemu wymagane jest uwierzytelnienie.");
        m_actionId = QStringLiteral("org.freedesktop.timedate1.set-timezone");
        m_users = {QVariantMap{{QStringLiteral("name"), QStringLiteral("dominik")}, {QStringLiteral("realName"), QStringLiteral("Dominik Nowak")}, {QStringLiteral("icon"), QString()}}};
        m_prompt = QStringLiteral("Hasło:");
        if (qEnvironmentVariableIsSet("ASTER_POLKIT_ERROR"))
            m_error = QStringLiteral("Nieprawidłowe hasło. Spróbuj jeszcze raz.");
        return;
    }
    if (qEnvironmentVariableIsSet("ASTER_PREVIEW"))
        return;
    const PolkitQt1::UnixSessionSubject session(::getpid());
    if (!registerListener(session, QStringLiteral("/org/aster/PolicyKit1/AuthenticationAgent")))
        qWarning("Nie udało się zarejestrować agenta polkit (działa już inny agent?)");
}

PolkitAgent::~PolkitAgent() = default;

void PolkitAgent::initiateAuthentication(const QString &actionId, const QString &message, const QString &,
                                         const PolkitQt1::Details &details, const QString &cookie,
                                         const PolkitQt1::Identity::List &identities, PolkitQt1::Agent::AsyncResult *result)
{
    if (m_result || identities.isEmpty()) {
        // Jedna prośba naraz; kolejna dostaje odmowę i program może spróbować ponownie
        result->setError(QStringLiteral("Trwa już inne uwierzytelnianie"));
        result->setCompleted();
        return;
    }
    m_result = result;
    m_cookie = cookie;
    m_actionId = actionId;
    m_message = message;
    m_appName = programName(details);
    m_identities = identities;
    m_users.clear();
    m_userIndex = 0;
    for (int i = 0; i < identities.size(); ++i) {
        const QVariantMap u = userInfo(identities[i]);
        if (u.value(QStringLiteral("uid")).toUInt() == ::getuid())
            m_userIndex = i;             // domyślnie ja, jeśli jestem administratorem
        m_users << u;
    }
    m_error.clear();
    m_attempt = 0;
    m_cancelled = false;
    m_active = true;
    emit changed();
    startSession();
}

void PolkitAgent::startSession()
{
    if (m_session) {
        m_session->disconnect(this);
        m_session->deleteLater();
    }
    m_waiting = false;
    m_busy = false;
    m_prompt.clear();
    m_session = new PolkitQt1::Agent::Session(m_identities.value(m_userIndex), m_cookie, m_result, this);
    connect(m_session, &PolkitQt1::Agent::Session::request, this, &PolkitAgent::onRequest);
    connect(m_session, &PolkitQt1::Agent::Session::completed, this, &PolkitAgent::onCompleted);
    connect(m_session, &PolkitQt1::Agent::Session::showError, this, [this](const QString &text) {
        m_error = text;
        emit changed();
    });
    m_session->initiate();
    emit changed();
}

void PolkitAgent::onRequest(const QString &request, bool echo)
{
    m_prompt = request;
    m_echo = echo;
    m_waiting = true;
    m_busy = false;
    emit changed();
}

void PolkitAgent::respond(const QString &password)
{
    if (!m_session || !m_waiting)
        return;
    m_waiting = false;
    m_busy = true;
    m_error.clear();
    emit changed();
    m_session->setResponse(password);
}

void PolkitAgent::onCompleted(bool gained)
{
    if (gained || m_cancelled) {
        finish();
        return;
    }
    // Złe hasło: nowa próba w tej samej prośbie
    m_error = QStringLiteral("Nieprawidłowe hasło. Spróbuj jeszcze raz.");
    ++m_attempt;
    startSession();
}

void PolkitAgent::finish()
{
    if (m_result) {
        m_result->setCompleted();
        m_result = nullptr;
    }
    if (m_session) {
        m_session->disconnect(this);
        m_session->deleteLater();
    }
    m_active = false;
    m_busy = false;
    m_waiting = false;
    emit changed();
}

void PolkitAgent::cancel()
{
    if (!m_active)
        return;
    if (!m_result) {                 // podgląd
        m_active = false;
        emit changed();
        return;
    }
    m_cancelled = true;
    if (m_session)
        m_session->cancel();         // kończy się sygnałem completed(false) → finish()
    else
        finish();
}

void PolkitAgent::cancelAuthentication()
{
    cancel();
}

bool PolkitAgent::initiateAuthenticationFinish()
{
    return true;
}

void PolkitAgent::selectUser(int index)
{
    if (index < 0 || index >= m_identities.size() || index == m_userIndex)
        return;
    m_userIndex = index;
    m_error.clear();
    startSession();
}
