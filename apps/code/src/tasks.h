#pragma once

#include <QElapsedTimer>
#include <QObject>
#include <QPointer>
#include <QProcess>
#include <QQmlEngine>
#include <QStringList>
#include <QTimer>
#include <QVariantList>

// Zadania projektu w Aster Code (jak „Tasks” w VS Code): wykrywane z plików projektu (package.json,
// Makefile, CMakeLists.txt, meson.build, Cargo.toml, go.mod, justfile, Python) i uruchamiane w tle
// przez powłokę. Wyjście bez kolorów ANSI idzie do karty „Zadanie”; błędy kompilatorów (gcc/clang,
// tsc, rustc, Python) — do panelu Problemy, w tym samym kształcie co Lsp.problems.
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

public:
    explicit Tasks(QObject *parent = nullptr);
    ~Tasks() override;

    QStringList lines() const { return m_lines; }
    bool running() const { return m_proc && m_proc->state() != QProcess::NotRunning; }
    QString title() const { return m_title; }
    int exitCode() const { return m_exitCode; }
    qint64 elapsed() const { return m_elapsed; }
    QVariantList problems() const;
    int errorCount() const { return m_errors; }
    int warningCount() const { return m_warnings; }

    // [{ label, command, cwd, group: build | test | run | other, source }] — od najważniejszych
    Q_INVOKABLE QVariantList detect(const QString &root) const;
    Q_INVOKABLE void run(const QString &label, const QString &command, const QString &cwd);
    Q_INVOKABLE void stop();
    Q_INVOKABLE void rerun();
    Q_INVOKABLE void clear();
    // Wiersz wyjścia ze wskazaniem miejsca: { path, line, col } (od 0) albo pusty
    Q_INVOKABLE QVariantMap locate(const QString &line) const;
    Q_INVOKABLE QVariantList diagnostics(const QString &path) const { return m_problems.value(path); }

Q_SIGNALS:
    void outputChanged();
    void stateChanged();
    void problemsChanged();
    void finished(const QString &title, int exitCode);

private:
    void append(const QByteArray &data);
    void flushPartial();
    void parseLine(const QString &line);
    void finish(int code);

    QPointer<QProcess> m_proc;
    QStringList m_lines;
    QString m_partial, m_title, m_command, m_cwd, m_root;
    int m_exitCode = -1, m_errors = 0, m_warnings = 0;
    qint64 m_elapsed = 0;
    QElapsedTimer m_clock;
    QTimer m_notify;                    // zmiany wyjścia najwyżej co 80 ms
    QHash<QString, QVariantList> m_problems;
    QString m_pyFile;                   // Python: „File "x", line N” — komunikat przychodzi w ostatnim wierszu
    int m_pyLine = -1;
};
