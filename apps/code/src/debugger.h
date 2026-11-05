#pragma once

#include <QHash>
#include <QJsonObject>
#include <QObject>
#include <QPointer>
#include <QProcess>
#include <QQmlEngine>
#include <QSet>
#include <QStringList>
#include <QVariantList>
#include <functional>

// Debugowanie w Aster Code przez Debug Adapter Protocol (jak w VS Code): gdb -i dap (gdb ≥ 14)
// albo lldb-dap dla programów w C/C++/Rust/Go, debugpy dla Pythona. Punkty przerwania na wiersz,
// zatrzymanie z pozycją w pliku, stos wywołań, zmienne (rozwijane), konsola z wyrażeniami.
class Debugger : public QObject
{
    Q_OBJECT
    QML_ELEMENT
    QML_SINGLETON
    Q_PROPERTY(QString state READ state NOTIFY stateChanged)               // "" | starting | running | stopped
    Q_PROPERTY(QString stopPath READ stopPath NOTIFY stopChanged)          // plik i wiersz (od 0) wybranej ramki
    Q_PROPERTY(int stopLine READ stopLine NOTIFY stopChanged)
    Q_PROPERTY(QString stopReason READ stopReason NOTIFY stopChanged)
    Q_PROPERTY(QVariantList frames READ frames NOTIFY stopChanged)         // [{ id, name, path, file, line }]
    Q_PROPERTY(int currentFrame READ currentFrame NOTIFY stopChanged)
    Q_PROPERTY(QVariantList scopes READ scopes NOTIFY variablesChanged)    // [{ name, ref, items: [{ name, value, type, ref }] }]
    Q_PROPERTY(QStringList console READ console NOTIFY consoleChanged)
    Q_PROPERTY(int revision READ revision NOTIFY breakpointsChanged)
    Q_PROPERTY(QString adapter READ adapter NOTIFY stateChanged)           // nazwa debugera w użyciu

public:
    explicit Debugger(QObject *parent = nullptr);
    ~Debugger() override;

    QString state() const { return m_state; }
    QString stopPath() const { return m_stopPath; }
    int stopLine() const { return m_stopLine; }
    QString stopReason() const { return m_stopReason; }
    QVariantList frames() const { return m_frames; }
    int currentFrame() const { return m_currentFrame; }
    QVariantList scopes() const { return m_scopes; }
    QStringList console() const { return m_console; }
    int revision() const { return m_revision; }
    QString adapter() const { return m_adapterName; }

    // Punkty przerwania (wiersze od 0)
    Q_INVOKABLE QVariantList breakpoints(const QString &path) const;
    Q_INVOKABLE void toggleBreakpoint(const QString &path, int line);
    Q_INVOKABLE void clearBreakpoints();
    Q_INVOKABLE int breakpointCount() const;

    // { available, name, install } — czy jest debuger dla rodzaju programu ("native" | "python")
    Q_INVOKABLE QVariantMap adapterFor(const QString &kind) const;
    // Najnowszy plik wykonywalny ELF w projekcie (build/, folder główny) — propozycja programu
    Q_INVOKABLE QString guessProgram(const QString &root) const;
    Q_INVOKABLE bool start(const QString &kind, const QString &program, const QString &args, const QString &cwd);
    Q_INVOKABLE void resume();
    Q_INVOKABLE void next();
    Q_INVOKABLE void stepIn();
    Q_INVOKABLE void stepOut();
    Q_INVOKABLE void pause();
    Q_INVOKABLE void stop();
    Q_INVOKABLE void selectFrame(int index);
    Q_INVOKABLE int expand(int ref);                     // wynik: childrenReady(ref, lista)
    Q_INVOKABLE void evaluate(const QString &expression);
    Q_INVOKABLE void clearConsole();

Q_SIGNALS:
    void stateChanged();
    void stopChanged();
    void variablesChanged();
    void consoleChanged();
    void breakpointsChanged();
    void childrenReady(int ref, const QVariantList &items);
    void message(const QString &text);
    void ended(int exitCode);

private:
    using Reply = std::function<void(bool ok, const QJsonObject &body, const QString &error)>;
    void send(const QString &command, const QJsonObject &args, Reply reply = {});
    void onData();
    void onMessage(const QJsonObject &msg);
    void sendBreakpoints(const QString &path);
    void loadStack();
    void loadScopes(int frameId);
    void print(const QString &text, const QString &category = QString());
    void setState(const QString &s);
    void finish();
    static QVariantList toItems(const QJsonArray &vars);

    QPointer<QProcess> m_proc;
    QByteArray m_buffer;
    int m_seq = 0, m_threadId = 1, m_currentFrame = 0, m_revision = 0, m_exitCode = -1;
    QHash<int, Reply> m_replies;
    QHash<QString, QList<int>> m_bps;
    QString m_state, m_stopPath, m_stopReason, m_adapterName, m_kind;
    int m_stopLine = -1;
    QVariantList m_frames, m_scopes;
    QStringList m_console;
    QJsonObject m_launch;
};
