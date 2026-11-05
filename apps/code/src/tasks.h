#pragma once

#include <QElapsedTimer>
#include <QObject>
#include <QPointer>
#include <QProcess>
#include <QQmlEngine>
#include <QStringList>
#include <QTimer>
#include <QVariantList>
#include <functional>

// Zadania projektu w Aster Code (jak „Tasks” w VS Code): wykrywane z plików projektu (package.json,
// Makefile, CMakeLists.txt, meson.build, Cargo.toml, go.mod, justfile, pyproject/Python — także w podfolderach,
// np. frontend/ i backend/) i uruchamiane w tle przez powłokę. Kilka procesów naraz, każdy z własnym
// wyjściem (bez kolorów ANSI); adres serwera z wyjścia (http://localhost:5173) — sprawdzony i zgłoszony
// do podglądu. Błędy kompilatorów (gcc/clang, tsc, rustc, Python) — do panelu Problemy, w kształcie Lsp.problems.
// Właściwości lines/running/title/exitCode dotyczą procesu wybranego w karcie Zadania.
class Tasks : public QObject
{
    Q_OBJECT
    QML_ELEMENT
    QML_SINGLETON
    Q_PROPERTY(QStringList lines READ lines NOTIFY outputChanged)
    Q_PROPERTY(bool running READ running NOTIFY stateChanged)
    Q_PROPERTY(QString title READ title NOTIFY stateChanged)               // etykieta bieżącego / ostatniego zadania
    Q_PROPERTY(int exitCode READ exitCode NOTIFY stateChanged)             // −1 — jeszcze działa albo przerwane
    Q_PROPERTY(qint64 elapsed READ elapsed NOTIFY stateChanged)           // ms ostatniego zadania
    Q_PROPERTY(QVariantList problems READ problems NOTIFY problemsChanged)
    Q_PROPERTY(int errorCount READ errorCount NOTIFY problemsChanged)
    Q_PROPERTY(int warningCount READ warningCount NOTIFY problemsChanged)
    Q_PROPERTY(QVariantList processes READ processes NOTIFY processesChanged)   // [{ id, label, command, running, exitCode, url, errors }]
    Q_PROPERTY(int selected READ selected NOTIFY stateChanged)
    Q_PROPERTY(int runningCount READ runningCount NOTIFY processesChanged)

public:
    explicit Tasks(QObject *parent = nullptr);
    ~Tasks() override;

    QStringList lines() const;
    bool running() const;
    QString title() const;
    int exitCode() const;
    qint64 elapsed() const;
    QVariantList problems() const;
    int errorCount() const;
    int warningCount() const;
    QVariantList processes() const;
    int selected() const { return m_selected; }
    int runningCount() const;

    // [{ label, command, cwd, group: build | test | run | other, source }] — od najważniejszych
    Q_INVOKABLE QVariantList detect(const QString &root) const;
    Q_INVOKABLE QVariantList runTargets(const QString &root) const;
    // Zwraca id procesu; to samo polecenie w tym samym folderze — uruchamia się od nowa w tym samym miejscu
    Q_INVOKABLE int run(const QString &label, const QString &command, const QString &cwd, const QVariantMap &env = QVariantMap());
    Q_INVOKABLE void stop(int id = -1);                // −1 — wybrany
    Q_INVOKABLE void stopAll();
    Q_INVOKABLE void rerun(int id = -1);
    Q_INVOKABLE void clear();
    Q_INVOKABLE void select(int id);
    Q_INVOKABLE void remove(int id);                   // zakończony proces znika z listy
    // Wiersz wyjścia ze wskazaniem miejsca: { path, line, col } (od 0) albo pusty
    Q_INVOKABLE QVariantMap locate(const QString &line) const;
    Q_INVOKABLE QVariantList diagnostics(const QString &path) const;

Q_SIGNALS:
    void outputChanged();
    void stateChanged();
    void problemsChanged();
    void finished(const QString &title, int exitCode);
    void processesChanged();
    void urlDetected(int id, const QString &label, const QString &url);

private:
    struct Proc {
        int id = 0;
        QPointer<QProcess> proc;
        QStringList lines;
        QString partial, title, command, cwd;
        QVariantMap env;
        int exitCode = -1, errors = 0, warnings = 0;
        qint64 elapsed = 0;
        QElapsedTimer clock;
        QHash<QString, QVariantList> problems;
        QString pyFile, rustMsg, url;
        int pyLine = -1, rustSev = 0;
        bool urlPending = false;
    };
    Proc *find(int id) const;
    Proc *current() const { return find(m_selected); }
    void start(Proc *p);
    void append(Proc *p, const QByteArray &data);
    void parseLine(Proc *p, const QString &line);
    void finish(Proc *p, int code);
    void checkUrl(Proc *p, const QString &line);
    void kill(Proc *p);
    QVariantList detectOne(const QString &root) const;
    static QVariantMap locateIn(const QString &line, const QString &cwd);

    QList<Proc *> m_procs;
    int m_selected = 0, m_nextId = 1;
    QString m_root;
    QTimer m_notify;                    // zmiany wyjścia najwyżej co 80 ms
};
