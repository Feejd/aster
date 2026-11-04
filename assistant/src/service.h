#pragma once

#include "localmodels.h"
#include "providers.h"

#include <QDBusContext>
#include <QHash>
#include <QJsonArray>
#include <QNetworkAccessManager>
#include <QObject>
#include <QPointer>
#include <QTimer>

class QNetworkReply;

// Usługa asystenta: jedna dla wyspy, panelu, terminala i Ustawień.
// D-Bus: org.aster.Assistant, obiekt /org/aster/Assistant (sesja użytkownika).
//
// Ask(rozmowa, pytanie, kontekst, źródło) → id rozmowy; odpowiedź przychodzi kawałkami w sygnale Chunk,
// na końcu Finished(rozmowa, cały tekst, znaczek) albo Failed(rozmowa, komunikat).
//
// Aster Intelligence to agent: gdy model chce coś sprawdzić albo zrobić, pisze jedno polecenie w bloku ```bash.
// Usługa wysyła wtedy ActionRequested(rozmowa, id, polecenie, opis po ludzku, bezpieczne) zamiast Finished. Klient (powłoka albo
// `aster` w terminalu) uruchamia polecenie — bezpieczne (tylko odczyt) od razu, resztę po zgodzie użytkownika —
// i odsyła ActionResult(rozmowa, id, kod wyjścia, wynik); kod -2 znaczy „użytkownik odmówił”. Model dostaje wynik
// i działa dalej, aż skończy (Finished) — najwyżej kMaxSteps poleceń na jedno pytanie.
// Znaczek mówi, kto odpowiedział: „Na tym komputerze” albo „Chmura: <dostawca>”.
// Historia rozmów — tylko lokalnie, w ~/.local/share/aster/asystent (do wyłączenia).
// Pamięć: krótkie streszczenia poprzednich rozmów idą w prompcie, żeby agent rozumiał nawiązania; streszczenia
// rozmów prowadzonych na tym komputerze nigdy nie trafiają do chmury.
class Service : public QObject, protected QDBusContext
{
    Q_OBJECT
    Q_CLASSINFO("D-Bus Interface", "org.aster.Assistant")

public:
    explicit Service(QObject *parent = nullptr);

public Q_SLOTS:
    // source: terminal | wyspa | panel (dobiera styl odpowiedzi); context: dane z potoku albo zaznaczony tekst
    Q_SCRIPTABLE QString Ask(const QString &conversation, const QString &prompt, const QString &context, const QString &source);
    Q_SCRIPTABLE void Cancel(const QString &conversation);
    Q_SCRIPTABLE void ActionResult(const QString &conversation, const QString &action, int exitCode, const QString &output);

    // {provider, providerName, model, baseUrl, local, badge, region, ready, problem, history, hasKey}
    Q_SCRIPTABLE QVariantMap Status();
    // JSON: [{id, name, kind, baseUrl, defaultModel, models, region, needsKey, editableUrl, keyUrl, hasKey, model, url}]
    Q_SCRIPTABLE QString Providers();
    // Klucze: provider, model, baseUrl, history (pozostałe bez zmian)
    Q_SCRIPTABLE void Configure(const QVariantMap &settings);
    // Klucz API do portfela; pusty — usuwa
    Q_SCRIPTABLE bool SetApiKey(const QString &provider, const QString &key);

    // JSON: [{id, title, updated, count}] — od najnowszej
    Q_SCRIPTABLE QString Conversations();
    // JSON: {id, title, updated, messages: [{role, text, badge, time, command?, exit?}]} — role: user | assistant | action
    Q_SCRIPTABLE QString Conversation(const QString &id);
    Q_SCRIPTABLE void DeleteConversation(const QString &id);
    Q_SCRIPTABLE void ClearHistory();
    // Szukanie w historii (tytuł, streszczenie, treść); pusta fraza — najnowsze.
    // agent: true, gdy pyta polecenie uruchomione przez agenta — przy chmurze bez rozmów prowadzonych tylko na tym komputerze.
    // JSON: [{id, title, updated, summary, snippet, local}]
    Q_SCRIPTABLE QString SearchConversations(const QString &phrase, bool agent);
    // Rozmowa jako tekst do odczytania (dla `aster --rozmowa`); pusty — nie ma albo prywatna (agent + chmura)
    Q_SCRIPTABLE QString ConversationText(const QString &id, bool agent);

    // Modele na tym komputerze. JSON: {hardware: {ramGb, cores, cpu, freeDisk}, recommended, active, downloading,
    //   models: [{id, name, description, size, minRam, installed, active, recommended, fits, partial}]}
    Q_SCRIPTABLE QString LocalModels();
    // Pobiera model („auto” — polecany dla tego komputera); postęp w DownloadProgress, koniec w DownloadFinished.
    // Pierwszy pobrany model od razu jest w użyciu. Pusty wynik — pobieranie ruszyło; inaczej powód, czemu nie.
    Q_SCRIPTABLE QString DownloadModel(const QString &id);
    Q_SCRIPTABLE void CancelDownload();
    Q_SCRIPTABLE bool UseModel(const QString &id);
    Q_SCRIPTABLE bool DeleteModel(const QString &id);

Q_SIGNALS:
    Q_SCRIPTABLE void Chunk(const QString &conversation, const QString &text);
    Q_SCRIPTABLE void Finished(const QString &conversation, const QString &text, const QString &badge);
    Q_SCRIPTABLE void Failed(const QString &conversation, const QString &message);
    // description: jedno zdanie po ludzku („Zainstalować Google Chrome?”) — to widzi użytkownik, polecenie jest w szczegółach
    Q_SCRIPTABLE void ActionRequested(const QString &conversation, const QString &action, const QString &command,
                                      const QString &description, bool safe);
    Q_SCRIPTABLE void StatusChanged();
    Q_SCRIPTABLE void HistoryChanged();
    // Agent znalazł wcześniejszą rozmowę (`aster --rozmowa ID`) — panel ma ją otworzyć, gdy skończy odpowiadać
    Q_SCRIPTABLE void ShowConversation(const QString &conversation, const QString &target);
    Q_SCRIPTABLE void LocalModelsChanged();
    Q_SCRIPTABLE void DownloadProgress(const QString &id, qlonglong received, qlonglong total);
    Q_SCRIPTABLE void DownloadFinished(const QString &id, bool ok, const QString &message);

private:
    struct Message {
        QString role;       // user | assistant | action (polecenie wykonane przez agenta i jego wynik)
        QString text;       // przy action: wynik polecenia
        QString context;    // dane dołączone do pytania (np. z potoku); przy action — opis polecenia po ludzku
        QString badge;
        qint64 time = 0;
        QString command;    // action: polecenie
        int exitCode = 0;   // action: kod wyjścia (-2: użytkownik odmówił)
    };
    struct Conv {
        QString id;
        QString title;
        qint64 updated = 0;
        QList<Message> messages;
        QString source;          // skąd ostatnie pytanie (styl odpowiedzi agenta w kolejnych krokach)
        int steps = 0;           // polecenia wykonane dla bieżącego pytania
        QString pendingAction;   // id polecenia czekającego na wynik od klienta
        QString pendingCommand;
        QString pendingDescription;
        QString summary;         // krótkie streszczenie — pamięć dla kolejnych rozmów
        int summaryCount = 0;    // przy ilu wiadomościach powstało
        QString showAfter;       // rozmowa do otwarcia w panelu po odpowiedzi
    };
    struct Request {
        QString conversation;
        QString text;
        QString badge;
        QString providerName;
        QString url;
        bool anthropic = false;
        bool local = false;
        bool agent = false;    // odpowiedź może zawierać polecenie (wszędzie poza narzędziami do pisania)
        bool stopped = false;  // urwana po bloku z poleceniem — reszta byłaby zgadywaniem wyniku
        bool summary = false;  // streszczenie rozmowy w tle (nic nie idzie do klientów)
        int summaryCount = 0;
        QByteArray pending;    // niedokończony wiersz strumienia SSE
        QByteArray errorBody;
    };

    QString providerId() const;
    QString modelFor(const Provider &p) const;
    QString urlFor(const Provider &p) const;
    bool historyEnabled() const;
    QString apiKey(const Provider &p, QString *error);
    QString badgeFor(const Provider &p) const;

    QString historyDir() const;
    Conv *conversation(const QString &id, bool create);
    void save(const Conv &c);

    void start(Conv &c, const QString &source);
    void send(Conv &c, const QString &source);
    bool managedLocal(const Provider &p) const;   // model lokalny, którym zarządza Aster (llama-server na 8080)
    void onData(QNetworkReply *reply);
    void onFinished(QNetworkReply *reply);
    void fail(const QString &conversation, const QString &message);
    QString systemPrompt(const QString &source, const QString &memory = QString()) const;
    bool askAlways() const;                       // tryb ostrożny: pytaj przy każdej zmianie
    bool runsWithoutAsking(const QString &command) const;
    bool memoryEnabled() const;
    QString memoryFor(const Conv &current, bool cloud) const;   // streszczenia poprzednich rozmów do promptu
    void summarizeLater(const QString &id);
    void summarizeNext();
    QNetworkReply *post(const Provider &p, const QString &key, const QString &system, QJsonArray messages, bool stream);
public:
    static QString commandIn(const QString &text);     // pierwsze polecenie z bloku ```bash w odpowiedzi
    static QString describe(const QString &text, const QString &command, bool asks);
    static bool localOnly(const QJsonArray &messages); // rozmowa (choć częściowo) tylko na tym komputerze
    static QString quickSummary(const QString &title, const QJsonArray &messages);
private:
    void touch();
    QTimer m_summarize;
    QStringList m_toSummarize;

    QNetworkAccessManager m_net;
    QHash<QString, Conv> m_convs;
    QHash<QNetworkReply *, Request> m_requests;
    QHash<QString, QString> m_keys;        // klucze odczytane z portfela (w pamięci, do końca działania)
    QTimer m_idle;
    ::LocalModels m_local;
};
