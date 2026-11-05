#pragma once

#include <QObject>
#include <QPointer>
#include <QProcess>
#include <QQmlEngine>
#include <QVariantList>

// Agent w Aster Code — klient usługi Aster Intelligence (D-Bus org.aster.Assistant: rozmowy, dostawca,
// klucze w portfelu, polecenia za zgodą). Aster Code dokłada kontekst projektu (otwarty plik, zaznaczenie,
// błędy z serwerów języków, git), uruchamia polecenia agenta w środowisku projektu (kontener) i zamienia
// bloki ```aster-edit / ```aster-file z odpowiedzi na zmiany do przejrzenia plik po pliku.
class Agent : public QObject
{
    Q_OBJECT
    QML_ELEMENT
    QML_SINGLETON
    Q_PROPERTY(bool available READ available NOTIFY availableChanged)
    Q_PROPERTY(QString badge READ badge NOTIFY availableChanged)          // „Na tym komputerze” / „Chmura: …”
    Q_PROPERTY(QString problem READ problem NOTIFY availableChanged)      // np. brak klucza API

public:
    explicit Agent(QObject *parent = nullptr);

    bool available() const { return m_available; }
    QString badge() const { return m_badge; }
    QString problem() const { return m_problem; }

    Q_INVOKABLE void refresh();
    // Pytanie w rozmowie (pusty identyfikator — nowa); zwraca identyfikator rozmowy albo pusty przy błędzie
    Q_INVOKABLE QString ask(const QString &conversation, const QString &prompt, const QString &context);
    Q_INVOKABLE void cancel(const QString &conversation);
    // Polecenie agenta w środowisku projektu; wynik idzie do usługi (ActionResult) i do commandDone
    Q_INVOKABLE void runCommand(const QString &conversation, const QString &action, const QString &command, const QString &cwd);
    Q_INVOKABLE void decline(const QString &conversation, const QString &action);
    // Polecenie sięga po sekrety — nie uruchamia się, model dostaje powód
    Q_INVOKABLE void refuse(const QString &conversation, const QString &action);
    Q_INVOKABLE void stopCommand();

    // Bloki zmian z odpowiedzi: [{ path, kind: edit | file, blocks: [{ search, replace }], content }]
    Q_INVOKABLE QVariantList parseEdits(const QString &text) const;
    // Odpowiedź bez bloków zmian (do pokazania w rozmowie) — w ich miejscu znacznik [[zmiana:ścieżka]]
    Q_INVOKABLE QString stripEdits(const QString &text) const;
    // Nowa treść pliku po zastosowaniu bloków SZUKAJ/ZAMIEŃ: { ok, text, error }
    Q_INVOKABLE QVariantMap applyBlocks(const QString &current, const QVariantList &blocks) const;
    // Różnice wierszy (jak git diff -U3): [{ kind: " " | "+" | "-" | "@", text, old, new }]
    Q_INVOKABLE QVariantList lineDiff(const QString &before, const QString &after) const;
    Q_INVOKABLE QString readFile(const QString &path) const;

Q_SIGNALS:
    void availableChanged();
    void chunk(const QString &conversation, const QString &text);
    void finished(const QString &conversation, const QString &text, const QString &badge);
    void failed(const QString &conversation, const QString &message);
    void actionRequested(const QString &conversation, const QString &action, const QString &command, const QString &description, bool safe);
    void commandOutput(const QString &conversation, const QString &action, const QString &text);
    void commandDone(const QString &conversation, const QString &action, int exitCode, const QString &output);

private Q_SLOTS:
    void onChunk(const QString &c, const QString &t) { Q_EMIT chunk(c, t); }
    void onFinished(const QString &c, const QString &t, const QString &b) { Q_EMIT finished(c, t, b); }
    void onFailed(const QString &c, const QString &m) { Q_EMIT failed(c, m); }
    void onAction(const QString &c, const QString &a, const QString &cmd, const QString &d, bool safe) { Q_EMIT actionRequested(c, a, cmd, d, safe); }
    void onStatus() { refresh(); }

private:
    bool m_available = false;
    QString m_badge, m_problem;
    QPointer<QProcess> m_cmd;
};
