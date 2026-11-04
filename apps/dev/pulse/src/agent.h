#pragma once

#include <QDBusContext>
#include <QHash>
#include <QJsonObject>
#include <QObject>
#include <QTimer>

#include <functional>

class QNetworkAccessManager;

// Dla agenta (Asystent Aster, skrypty, CI): uruchomienie zapisanego albo podanego zapytania i wynik jako JSON.
// Używa tego polecenie `aster-pulse run|send|list|curl` i usługa D-Bus org.aster.pulse (interfejs org.aster.Pulse).
//
// Opcje (JSON): { env, dir, vars: {nazwa: wartość}, timeout (s), insecure, maxBody (bajty treści w wyniku) }
// Wynik: { ok, ref, environment, workspace, request: {method, url, headers}, status, statusText, timeMs, size,
//          headers: {nazwa: wartość}, contentType, body (JSON albo tekst), bodyTruncated, bodyBase64, error }
namespace AgentRun {
using Done = std::function<void(const QJsonObject &)>;
// ref — „kolekcja/zapytanie”; gdy request niepuste, wysyła je zamiast zapisanego (ref tylko do opisu)
void start(QNetworkAccessManager *nam, const QString &ref, const QJsonObject &request, const QJsonObject &options,
           const QString &source, QObject *context, const Done &done);
// Wynik zapytania + treść → odpowiedź dla agenta
QJsonObject output(const QJsonObject &result, const QByteArray &body, qint64 maxBody);
// Treść jako JSON, jeśli się da (application/json, *+json albo poprawny JSON)
bool parseJsonBody(const QByteArray &body, const QString &contentType, QJsonValue *out);
}

// Obiekt /org/aster/Pulse na szynie sesji (nazwa org.aster.pulse). Wystawia go okno programu, a gdy okna nie ma —
// `aster-pulse --dbus` (start na żądanie z pliku usługi D-Bus; kończy się po 10 min bezczynności).
class PulseService : public QObject, protected QDBusContext
{
    Q_OBJECT
    Q_CLASSINFO("D-Bus Interface", "org.aster.Pulse")
public:
    explicit PulseService(QNetworkAccessManager *nam, bool window, QObject *parent = nullptr);
    static const QString busName;
    static const QString objectPath;

public Q_SLOTS:
    // Zapisane zapytanie „kolekcja/zapytanie”; puste env/dir — wybrane środowisko / obszar z ~/Dokumenty/Pulse
    QString Run(const QString &ref, const QString &env, const QString &dir);
    QString RunWith(const QString &ref, const QString &optionsJson);
    // Dowolne zapytanie w formacie Pulse albo {"curl": "curl …"}
    QString Send(const QString &requestJson, const QString &optionsJson);
    QString List(const QString &dir);
    QString Curl(const QString &ref, const QString &env, const QString &dir);
    QString ImportCurl(const QString &command);
    // Okno programu: przywołaj (zwraca false w usłudze bez okna)
    bool Activate(const QString &token);

Q_SIGNALS:
    void activated(const QString &token);
    void requestFinished(const QString &resultJson);   // po każdym wywołaniu Run/Send (okno odświeża historię)

private:
    void touch();
    QNetworkAccessManager *m_nam;
    bool m_window;
    QTimer m_idle;
    int m_pending = 0;
};

// Polecenia w terminalu; zwraca kod wyjścia albo -1, gdy argumenty nie są poleceniem (→ okno programu)
int runCommandLine(int argc, char **argv);
