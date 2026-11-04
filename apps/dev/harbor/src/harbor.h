#pragma once

// Harbor — stan dla okna: kontenery i toolboxy, projekty compose, obrazy, logi na żywo i zadania
// w tle (tworzenie środowiska, compose up/down, sprzątanie obrazów). Wszystko asynchronicznie przez QProcess,
// odświeżanie co kilka sekund tylko wtedy, gdy okno jest widoczne.

#include <QHash>
#include <QObject>
#include <QProcess>
#include <QQmlEngine>
#include <QSettings>
#include <QTimer>
#include <QVariantList>
#include <functional>

#include "linemodel.h"
#include "podman.h"

class Harbor : public QObject
{
    Q_OBJECT
    QML_ELEMENT
    QML_SINGLETON

    Q_PROPERTY(bool ready READ ready NOTIFY changed)
    Q_PROPERTY(bool available READ available NOTIFY changed)
    Q_PROPERTY(QString error READ error NOTIFY changed)
    Q_PROPERTY(QVariantList containers READ containers NOTIFY changed)
    Q_PROPERTY(QVariantList projects READ projects NOTIFY changed)
    Q_PROPERTY(QVariantList images READ images NOTIFY imagesChanged)
    Q_PROPERTY(QVariantMap summary READ summary NOTIFY changed)
    Q_PROPERTY(QVariantMap imageSummary READ imageSummary NOTIFY imagesChanged)
    Q_PROPERTY(QStringList busy READ busy NOTIFY busyChanged)
    Q_PROPERTY(bool active READ active WRITE setActive NOTIFY activeChanged)
    Q_PROPERTY(QVariantList kinds READ kinds CONSTANT)

    Q_PROPERTY(QString logName READ logName NOTIFY logChanged)
    Q_PROPERTY(LineModel *logLines READ logLines CONSTANT)
    Q_PROPERTY(bool logLive READ logLive NOTIFY logChanged)

    Q_PROPERTY(QString taskTitle READ taskTitle NOTIFY taskChanged)
    Q_PROPERTY(QStringList taskSteps READ taskSteps NOTIFY taskChanged)
    Q_PROPERTY(int taskStep READ taskStep NOTIFY taskChanged)
    Q_PROPERTY(LineModel *taskLines READ taskLines CONSTANT)
    Q_PROPERTY(QString taskState READ taskState NOTIFY taskChanged)     // "" | running | done | failed
    Q_PROPERTY(QVariantMap taskResult READ taskResult NOTIFY taskChanged)

public:
    explicit Harbor(QObject *parent = nullptr);
    static Harbor *instance;
    static Harbor *create(QQmlEngine *, QJSEngine *) { QJSEngine::setObjectOwnership(instance, QJSEngine::CppOwnership); return instance; }

    bool ready() const { return m_ready; }
    bool available() const { return m_available; }
    QString error() const { return m_error; }
    QVariantList containers() const { return m_containers; }
    QVariantList projects() const { return m_projects; }
    QVariantList images() const { return m_images; }
    QVariantMap summary() const { return m_summary; }
    QVariantMap imageSummary() const { return m_imageSummary; }
    QStringList busy() const { return m_busy.values(); }
    bool active() const { return m_active; }
    void setActive(bool a);
    QVariantList kinds() const;

    QString logName() const { return m_logName; }
    LineModel *logLines() const { return m_logLines; }
    bool logLive() const { return m_logProc != nullptr; }

    QString taskTitle() const { return m_taskTitle; }
    QStringList taskSteps() const { return m_taskSteps; }
    int taskStep() const { return m_taskStep; }
    LineModel *taskLines() const { return m_taskLines; }
    QString taskState() const { return m_taskState; }
    QVariantMap taskResult() const { return m_taskResult; }

    // Pakiety dla rodzaju środowiska (też dla CLI)
    static QStringList packagesFor(const QString &kind);

public Q_SLOTS:
    void refresh();
    void refreshImages();

    void start(const QString &name);
    void stop(const QString &name);
    void restart(const QString &name);
    void remove(const QString &name);
    void openTerminal(const QString &name);
    QVariantMap info(const QString &name) const;

    void openLogs(const QString &name);
    void followLogs();
    void closeLogs();
    void copyLogs();

    void composeUp(const QString &folder);
    void composeDown(const QString &folder);
    void addProject(const QUrl &folder);
    void forgetProject(const QString &folder);

    void removeImage(const QString &id);
    void pruneImages();

    QString defaultFolder(const QString &name) const;
    bool validName(const QString &name) const { return Pod::validName(name); }
    bool nameTaken(const QString &name) const;
    void createEnvironment(const QString &kind, const QString &name, const QString &folder);
    void closeTask();

    void openFolder(const QString &path);
    void openInCode(const QString &path);
    QString homePath(const QString &path) const;

Q_SIGNALS:
    void changed();
    void imagesChanged();
    void busyChanged();
    void activeChanged();
    void logChanged();
    void taskChanged();
    void message(const QString &text);

private:
    void runAsync(const Pod::Cmd &cmd, std::function<void(int, const QByteArray &, const QString &)> done);
    void containerAction(const QString &name, const QString &verb, const QString &okText);
    void rebuild();
    void readStats();
    void appendLog(const QByteArray &data);

    // Zadanie z krokami: każdy krok to polecenie; wyjście trafia do taskLines
    struct Step { QString title; Pod::Cmd cmd; std::function<void()> before; };
    void startTask(const QString &title, const QList<Step> &steps, const QVariantMap &result, std::function<void(bool)> finished = {});
    void runStep();
    void taskOutput(const QByteArray &data);

    QSettings m_settings;
    QTimer m_timer;
    bool m_active = true;
    bool m_ready = false;
    bool m_available = true;
    QString m_error;
    bool m_psRunning = false, m_statsRunning = false;
    QVariantList m_raw;                     // z `podman ps`
    QHash<QString, QVariantMap> m_stats;
    QVariantList m_containers, m_projects, m_images;
    QVariantMap m_summary, m_imageSummary;
    QSet<QString> m_busy;

    QString m_logName;
    LineModel *m_logLines;
    QProcess *m_logProc = nullptr;
    QByteArray m_logRest;

    QString m_taskTitle, m_taskState;
    QStringList m_taskSteps;
    LineModel *m_taskLines;
    int m_taskStep = -1;
    QList<Step> m_steps;
    QVariantMap m_taskResult;
    QProcess *m_taskProc = nullptr;
    QByteArray m_taskRest;
    std::function<void(bool)> m_taskFinished;
};
