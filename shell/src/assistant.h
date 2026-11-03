#pragma once

#include <QAbstractListModel>
#include <QObject>
#include <QQmlEngine>
#include <QVariantMap>

// Wiadomości bieżącej rozmowy (wyspa i panel asystenta). Odpowiedź rośnie kawałek po kawałku.
class AssistantMessages : public QAbstractListModel
{
    Q_OBJECT
    QML_ANONYMOUS
public:
    enum Role { RoleRole = Qt::UserRole + 1, TextRole, BadgeRole, ErrorRole, PendingRole };
    struct Message {
        QString role;       // user | assistant
        QString text;
        QString badge;      // „Na tym komputerze” / „Chmura: DeepSeek”
        bool error = false;
        bool pending = false;
    };
    using QAbstractListModel::QAbstractListModel;
    int rowCount(const QModelIndex &parent = {}) const override { return parent.isValid() ? 0 : int(m_items.size()); }
    QVariant data(const QModelIndex &index, int role) const override;
    QHash<int, QByteArray> roleNames() const override;

    void reset(const QList<Message> &items);
    void append(const Message &m);
    Message &last() { return m_items.last(); }
    bool isEmpty() const { return m_items.isEmpty(); }
    void lastChanged();
    void removeLast();
    const QList<Message> &items() const { return m_items; }

private:
    QList<Message> m_items;
};

// Asystent w powłoce: most do usługi aster-assistant (D-Bus org.aster.Assistant).
// Super+Spacja (globalny skrót przez kglobalaccel) → toggleRequested.
class Assistant : public QObject
{
    Q_OBJECT
    QML_ELEMENT
    QML_SINGLETON
    Q_PROPERTY(AssistantMessages *messages READ messages CONSTANT)
    Q_PROPERTY(int count READ count NOTIFY changed)
    Q_PROPERTY(int exchanges READ exchanges NOTIFY changed)             // liczba pytań w rozmowie
    Q_PROPERTY(bool busy READ busy NOTIFY changed)
    Q_PROPERTY(QString conversation READ conversation NOTIFY changed)
    Q_PROPERTY(QString lastAnswer READ lastAnswer NOTIFY changed)
    Q_PROPERTY(QString lastBadge READ lastBadge NOTIFY changed)
    Q_PROPERTY(bool lastError READ lastError NOTIFY changed)
    // {provider, providerName, model, local, badge, region, ready, problem, history}
    Q_PROPERTY(QVariantMap status READ status NOTIFY statusChanged)
    Q_PROPERTY(bool available READ available NOTIFY statusChanged)

public:
    explicit Assistant(QObject *parent = nullptr);

    AssistantMessages *messages() { return &m_messages; }
    int count() const { return m_messages.rowCount(); }
    int exchanges() const;
    bool busy() const { return m_busy; }
    QString conversation() const { return m_conversation; }
    QString lastAnswer() const;
    QString lastBadge() const;
    bool lastError() const;
    QVariantMap status() const { return m_status; }
    bool available() const { return m_available; }

    // source: wyspa | panel
    Q_INVOKABLE void ask(const QString &text, const QString &source);
    Q_INVOKABLE void cancel();
    Q_INVOKABLE void newConversation();
    Q_INVOKABLE void openConversation(const QString &id);
    Q_INVOKABLE void deleteConversation(const QString &id);
    // [{id, title, updated, count}] — od najnowszej
    Q_INVOKABLE QVariantList history() const;
    Q_INVOKABLE void refreshStatus();
    Q_INVOKABLE void copy(const QString &text) const;
    Q_INVOKABLE void openSettings() const;

Q_SIGNALS:
    void changed();
    void statusChanged();
    void toggleRequested();
    void answered();            // odpowiedź skończona (albo błąd)

private Q_SLOTS:
    void onChunk(const QString &conversation, const QString &text);
    void onFinished(const QString &conversation, const QString &text, const QString &badge);
    void onFailed(const QString &conversation, const QString &message);
    void onShortcut(const QString &component, const QString &action, qlonglong timestamp);

private:
    void registerShortcut();
    AssistantMessages m_messages;
    QString m_conversation;
    bool m_busy = false;
    bool m_available = false;
    QVariantMap m_status;
};
