#pragma once

#include <QHash>
#include <QJsonArray>
#include <QJsonObject>
#include <QJsonValue>
#include <QObject>
#include <QPointer>
#include <QProcess>
#include <QQmlEngine>
#include <QVariantList>
#include <functional>

// Jeden serwer języka (Language Server Protocol): proces z JSON-RPC na stdin/stdout.
class LspServer : public QObject
{
    Q_OBJECT
public:
    LspServer(const QString &id, const QString &program, const QStringList &args, const QString &root, QObject *parent);
    ~LspServer() override;

    using Reply = std::function<void(const QJsonValue &result, const QJsonObject &error)>;
    int request(const QString &method, const QJsonObject &params, Reply reply);
    void notify(const QString &method, const QJsonObject &params);
    bool ready() const { return m_ready; }
    bool failed() const { return m_failed; }
    QString id() const { return m_id; }
    QString program() const { return m_program; }
    // Czy serwer to potrafi (klucz z capabilities, np. "signatureHelpProvider")
    bool supports(const QString &provider) const { const QJsonValue v = m_caps.value(provider); return !v.isUndefined() && !v.isNull() && v != QJsonValue(false); }
    void shutdown();

Q_SIGNALS:
    void readyChanged();
    void notification(const QString &method, const QJsonObject &params);
    void applyEdit(const QJsonObject &edit);
    void stopped();

private:
    void send(const QJsonObject &msg);
    void readOutput();
    void handle(const QJsonObject &msg);

    QString m_id, m_program;
    QProcess m_proc;
    QByteArray m_buffer;
    int m_seq = 0;
    bool m_ready = false;
    bool m_failed = false;
    QList<QJsonObject> m_queue;                // wiadomości przed odpowiedzią na „initialize”
    QHash<int, Reply> m_replies;
    QJsonObject m_caps;
};

// Serwery języków dla projektu w Aster Code: dobierane po rozszerzeniu pliku (clangd, qmlls, pylsp/pyright,
// typescript-language-server, rust-analyzer, gopls, bash-language-server), uruchamiane przy pierwszym pliku
// danego języka. Treść dokumentu idzie w całości (pełna synchronizacja) — prosto i pewnie dla plików kodu.
class Lsp : public QObject
{
    Q_OBJECT
    QML_ELEMENT
    QML_SINGLETON
    Q_PROPERTY(int revision READ revision NOTIFY diagnosticsChanged)        // rośnie przy każdej zmianie błędów
    Q_PROPERTY(int errorCount READ errorCount NOTIFY diagnosticsChanged)
    Q_PROPERTY(int warningCount READ warningCount NOTIFY diagnosticsChanged)
    Q_PROPERTY(QVariantList problems READ problems NOTIFY diagnosticsChanged)   // [{ path, name, dir, items: [...] }]
    Q_PROPERTY(bool enabled READ enabled WRITE setEnabled NOTIFY enabledChanged)    // ustawienie „Serwery języków”

public:
    explicit Lsp(QObject *parent = nullptr);
    ~Lsp() override;

    int revision() const { return m_revision; }
    int errorCount() const { return m_errors; }
    int warningCount() const { return m_warnings; }
    QVariantList problems() const;

    Q_INVOKABLE void setRoot(const QString &root);
    bool enabled() const { return m_enabled; }
    void setEnabled(bool on);
    // Wszystkie znane serwery do ustawień: [{ id, name, languages, available, running, package }]
    Q_INVOKABLE QVariantList servers() const;
    // { id, name, available, running, package } — serwer dla pliku (pusty id: język bez serwera)
    Q_INVOKABLE QVariantMap serverFor(const QString &path) const;
    Q_INVOKABLE void open(const QString &path, const QString &text);
    Q_INVOKABLE void update(const QString &path, const QString &text);      // nic, gdy treść się nie zmieniła
    Q_INVOKABLE void saved(const QString &path);
    Q_INVOKABLE void close(const QString &path);
    // Zapytania — odpowiedzi przychodzą sygnałami z tym samym numerem
    Q_INVOKABLE int complete(const QString &path, int line, int col);
    Q_INVOKABLE int definition(const QString &path, int line, int col);
    Q_INVOKABLE int hover(const QString &path, int line, int col);
    // Zmiana nazwy symbolu w całym projekcie; wynik: [{ path, edits: [{ sl, sc, el, ec, text }] }]
    Q_INVOKABLE int rename(const QString &path, int line, int col, const QString &newName);
    // Odwołania: [{ path, name, dir, items: [{ line, col, endCol, text }] }]
    Q_INVOKABLE int references(const QString &path, int line, int col);
    Q_INVOKABLE int format(const QString &path, int tabSize, bool insertSpaces);
    // Szybkie poprawki dla zakresu (wiersze/kolumny od 0): [{ title, kind, preferred, index }]; wybór — runCodeAction(index)
    Q_INVOKABLE int codeActions(const QString &path, int sl, int sc, int el, int ec);
    Q_INVOKABLE void runCodeAction(int index);
    // Symbole pliku i projektu: [{ name, detail, kind, line, col, depth, container, path, rel }]
    Q_INVOKABLE int documentSymbols(const QString &path);
    Q_INVOKABLE int workspaceSymbols(const QString &query);
    Q_INVOKABLE int signatureHelp(const QString &path, int line, int col);
    // [{ line, col, endLine, endCol, severity (1 błąd, 2 ostrzeżenie, 3 informacja, 4 podpowiedź), message, source }]
    Q_INVOKABLE QVariantList diagnostics(const QString &path) const;

Q_SIGNALS:
    void enabledChanged();
    void diagnosticsChanged();
    void serversChanged();
    void completionReady(int seq, const QString &path, const QVariantList &items);
    void definitionReady(int seq, const QString &path, int line, int col);
    void definitionMissing(int seq);
    void hoverReady(int seq, const QString &path, const QString &text);
    void renameReady(int seq, const QVariantList &files, const QString &error);
    void referencesReady(int seq, const QVariantList &groups, int total);
    void formatReady(int seq, const QString &path, const QVariantList &edits);
    void codeActionsReady(int seq, const QString &path, const QVariantList &actions);
    void workspaceEditReady(const QVariantList &files);
    void symbolsReady(int seq, const QString &path, const QVariantList &symbols);
    void workspaceSymbolsReady(int seq, const QVariantList &symbols);
    void signatureReady(int seq, const QString &path, const QString &label, int activeStart, int activeEnd);
    void message(const QString &text);

private:
    struct Doc {
        QString server;
        int version = 0;
        size_t hash = 0;
        bool opened = false;
        QString text;
    };
    LspServer *serverForPath(const QString &path);
    QString serverId(const QString &path) const;
    void sendOpen(const QString &path, Doc &doc, LspServer *s);
    void onNotification(const QString &method, const QJsonObject &params);
    void recount();
    static QJsonObject position(const QString &path, int line, int col);
    LspServer *docServer(const QString &path) const;
    QString lineOf(const QString &path, int line, QHash<QString, QStringList> &cache) const;
    QString relative(const QString &path) const;

    QString m_root;
    QHash<QString, LspServer *> m_servers;
    QHash<QString, Doc> m_docs;
    QHash<QString, QVariantList> m_diagnostics;   // ścieżka → lista
    QHash<QString, QJsonArray> m_rawDiag;         // to samo w postaci z serwera (do szybkich poprawek)
    QJsonArray m_actions;                         // ostatnie szybkie poprawki
    QString m_actionsServer;
    bool m_enabled = true;
    int m_seq = 0;
    int m_revision = 0;
    int m_errors = 0, m_warnings = 0;
};
