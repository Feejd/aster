#pragma once

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
// Znaczek mówi, kto odpowiedział: „Na tym komputerze” albo „Chmura: <dostawca>”.
// Historia rozmów — tylko lokalnie, w ~/.local/share/aster/asystent (do wyłączenia).
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
    // JSON: {id, title, updated, messages: [{role, text, badge, time}]}
    Q_SCRIPTABLE QString Conversation(const QString &id);
    Q_SCRIPTABLE void DeleteConversation(const QString &id);
    Q_SCRIPTABLE void ClearHistory();

Q_SIGNALS:
    Q_SCRIPTABLE void Chunk(const QString &conversation, const QString &text);
    Q_SCRIPTABLE void Finished(const QString &conversation, const QString &text, const QString &badge);
    Q_SCRIPTABLE void Failed(const QString &conversation, const QString &message);
    Q_SCRIPTABLE void StatusChanged();
    Q_SCRIPTABLE void HistoryChanged();

private:
    struct Message {
        QString role;       // user | assistant
        QString text;
        QString context;    // dane dołączone do pytania (np. z potoku) — idą do modelu, w historii są osobno
        QString badge;
        qint64 time = 0;
    };
    struct Conv {
        QString id;
        QString title;
        qint64 updated = 0;
        QList<Message> messages;
    };
    struct Request {
        QString conversation;
        QString text;
        QString badge;
        QString providerName;
        QString url;
        bool anthropic = false;
        bool local = false;
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
    void onData(QNetworkReply *reply);
    void onFinished(QNetworkReply *reply);
    void fail(const QString &conversation, const QString &message);
    QString systemPrompt(const QString &source) const;
    void touch();

    QNetworkAccessManager m_net;
    QHash<QString, Conv> m_convs;
    QHash<QNetworkReply *, Request> m_requests;
    QHash<QString, QString> m_keys;        // klucze odczytane z portfela (w pamięci, do końca działania)
    QTimer m_idle;
};
