#pragma once

#include <QObject>
#include <QQmlEngine>

// Aster Intelligence w sklepie: rozumie, co ktoś chce zrobić, gdy lokalne dopasowanie nie wystarcza.
// To dodatek: sklep działa w pełni bez asystenta, a gdy usługi nie ma, opcja po prostu się nie pojawia.
class Intelligence : public QObject
{
    Q_OBJECT
    QML_ELEMENT
    QML_SINGLETON
    Q_PROPERTY(bool available READ available NOTIFY availableChanged)
    Q_PROPERTY(bool busy READ busy NOTIFY busyChanged)
    Q_PROPERTY(QString badge READ badge NOTIFY availableChanged)

public:
    explicit Intelligence(QObject *parent = nullptr);

    bool available() const { return m_available; }
    bool busy() const { return !m_conversation.isEmpty() || m_starting; }
    QString badge() const { return m_badge; }

    // Pytanie z katalogiem w kontekście; odpowiedź w answered(pytanie, tekst, znaczek)
    Q_INVOKABLE void ask(const QString &question, const QString &prompt, const QString &catalog);
    Q_INVOKABLE void cancel();

Q_SIGNALS:
    void availableChanged();
    void busyChanged();
    void answered(const QString &question, const QString &text, const QString &badge);
    void failed(const QString &question, const QString &message);

private Q_SLOTS:
    void onFinished(const QString &conversation, const QString &text, const QString &badge);
    void onFailed(const QString &conversation, const QString &message);
    void onAction(const QString &conversation, const QString &action, const QString &command, const QString &description, bool safe);

private:
    void checkStatus();
    void cleanup();

    bool m_available = false;
    bool m_starting = false;
    QString m_badge;
    QString m_conversation;
    QString m_question;
};
