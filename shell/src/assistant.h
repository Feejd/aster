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
    enum Role { RoleRole = Qt::UserRole + 1, TextRole, BadgeRole, ErrorRole, PendingRole, CommandRole, StateRole, OutputRole };
    struct Message {
        QString role;       // user | assistant | action
        QString text;       // action: opis po ludzku („Zainstalować Google Chrome?”)
        QString badge;      // „Na tym komputerze” / „Chmura: DeepSeek”
        bool error = false;
        bool pending = false;
        QString command;    // action: polecenie
        QString state;      // action: czeka | dziala | gotowe | blad | odmowa
        QString output;     // action: wynik
        QString actionId;
        QString raw;        // assistant: surowa odpowiedź (z blokami plików) — text to wersja do pokazania
    };
    using QAbstractListModel::QAbstractListModel;
    int rowCount(const QModelIndex &parent = {}) const override { return parent.isValid() ? 0 : int(m_items.size()); }
    QVariant data(const QModelIndex &index, int role) const override;
    QHash<int, QByteArray> roleNames() const override;

    void reset(const QList<Message> &items);
    void append(const Message &m);
    Message &last() { return m_items.last(); }
    Message &at(int i) { return m_items[i]; }
    void changedAt(int i);
    bool isEmpty() const { return m_items.isEmpty(); }
    void lastChanged();
    void removeLast();
    const QList<Message> &items() const { return m_items; }

private:
    QList<Message> m_items;
};

// Aster Intelligence w powłoce: most do usługi aster-assistant (D-Bus org.aster.Assistant).
// Super+Spacja (globalny skrót przez kglobalaccel) → toggleRequested.
// selection: tekst zaznaczony w dowolnym programie (albo ze schowka) — dla narzędzi do pisania.
class Assistant : public QObject
{
    Q_OBJECT
    QML_ELEMENT
    QML_SINGLETON
    Q_PROPERTY(AssistantMessages *messages READ messages CONSTANT)
    Q_PROPERTY(int count READ count NOTIFY changed)
    Q_PROPERTY(int exchanges READ exchanges NOTIFY changed)             // liczba pytań w rozmowie
    Q_PROPERTY(QString title READ title NOTIFY changed)                 // pierwsze pytanie rozmowy (kropla na pasku)
    Q_PROPERTY(bool busy READ busy NOTIFY changed)
    Q_PROPERTY(QString conversation READ conversation NOTIFY changed)
    Q_PROPERTY(QString lastAnswer READ lastAnswer NOTIFY changed)
    Q_PROPERTY(QString lastBadge READ lastBadge NOTIFY changed)
    Q_PROPERTY(bool lastError READ lastError NOTIFY changed)
    Q_PROPERTY(bool acting READ acting NOTIFY changed)                  // agent coś uruchamia albo czeka na zgodę
    Q_PROPERTY(bool waiting READ waiting NOTIFY changed)                // polecenie czeka na zgodę użytkownika
    Q_PROPERTY(bool canUndo READ canUndo NOTIFY changed)                // ostatnia odpowiedź zmieniła pliki — można je cofnąć
    // {provider, providerName, model, local, badge, region, ready, problem, history}
    Q_PROPERTY(QVariantMap status READ status NOTIFY statusChanged)
    Q_PROPERTY(bool available READ available NOTIFY statusChanged)
    Q_PROPERTY(QString selection READ selection NOTIFY selectionChanged)
    Q_PROPERTY(QString selectionSource READ selectionSource NOTIFY selectionChanged)   // zaznaczenie | schowek

public:
    explicit Assistant(QObject *parent = nullptr);

    AssistantMessages *messages() { return &m_messages; }
    int count() const { return m_messages.rowCount(); }
    int exchanges() const;
    QString title() const;
    bool busy() const { return m_busy; }
    QString conversation() const { return m_conversation; }
    QString lastAnswer() const;
    QString lastBadge() const;
    bool lastError() const;
    bool acting() const;
    bool waiting() const { return waitingAction() >= 0; }
    bool canUndo() const { return !m_busy && !undoPoint().isEmpty(); }
    QVariantMap status() const { return m_status; }
    bool available() const { return m_available; }
    QString selection() const { return m_selection; }
    QString selectionSource() const { return m_selectionSource; }

    // source: wyspa | panel | pisanie; context: tekst, na którym ma pracować (narzędzia do pisania)
    Q_INVOKABLE void ask(const QString &text, const QString &source, const QString &context = QString());
    Q_INVOKABLE void refreshSelection();
    // Zgoda (albo odmowa) na polecenie, które agent chce uruchomić
    Q_INVOKABLE void approve(bool yes);
    // Cofa zmiany w plikach z ostatniego pytania (punkt powrotu zrobiony przed zmianami agenta)
    Q_INVOKABLE void undoChanges();
    // Polecenie z karty działania — do Terminala Aster, wpisane, ale nie uruchomione
    Q_INVOKABLE void openInTerminal(const QString &command) const;
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
    void selectionChanged();
    void conversationShown();   // agent otworzył wcześniejszą rozmowę — Shell pokazuje panel

private Q_SLOTS:
    void onChunk(const QString &conversation, const QString &text);
    void onFinished(const QString &conversation, const QString &text, const QString &badge);
    void onFailed(const QString &conversation, const QString &message);
    void onShortcut(const QString &component, const QString &action, qlonglong timestamp);
    void onShowConversation(const QString &conversation, const QString &target);
    void onActionRequested(const QString &conversation, const QString &action, const QString &command, const QString &description, bool safe);

private:
    void registerShortcut();
    void runAction(int index);
    void sendResult(int index, int exitCode, const QString &output);
    int waitingAction() const;
    QString undoPoint() const;
    QStringList m_undone;
    AssistantMessages m_messages;
    QString m_conversation;
    bool m_busy = false;
    bool m_available = false;
    QVariantMap m_status;
    QString m_selection;
    QString m_selectionSource;
};
