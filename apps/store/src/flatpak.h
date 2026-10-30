#pragma once

#include <QObject>
#include <QProcess>
#include <QQmlEngine>
#include <QStringList>
#include <QVariantMap>

// Zaplecze sklepu: programy z Flathub instalowane przez flatpak w trybie użytkownika
// (bez hasła administratora). Operacje idą po kolei (flatpak i tak blokuje równoległe),
// postęp w procentach czytany z wyjścia flatpaka.
class Flatpak : public QObject
{
    Q_OBJECT
    QML_ELEMENT
    QML_SINGLETON
    Q_PROPERTY(QStringList installed READ installed NOTIFY installedChanged)
    Q_PROPERTY(QStringList updates READ updates NOTIFY updatesChanged)
    // {appId: postęp 0..1} dla trwających i oczekujących operacji (-1 = czeka w kolejce)
    Q_PROPERTY(QVariantMap progress READ progress NOTIFY progressChanged)
    Q_PROPERTY(bool available READ available CONSTANT)

public:
    explicit Flatpak(QObject *parent = nullptr);

    QStringList installed() const { return m_installed; }
    QStringList updates() const { return m_updates; }
    QVariantMap progress() const { return m_progress; }
    bool available() const;

    Q_INVOKABLE void install(const QString &appId);
    Q_INVOKABLE void uninstall(const QString &appId);
    Q_INVOKABLE void updateAll();
    Q_INVOKABLE void launch(const QString &appId);
    Q_INVOKABLE void refresh();

Q_SIGNALS:
    void installedChanged();
    void updatesChanged();
    void progressChanged();
    void finished(const QString &appId, const QString &action, bool ok, const QString &message);

private:
    struct Job {
        QString action;     // install | uninstall | update
        QString appId;
    };
    void enqueue(const QString &action, const QString &appId);
    void startNext();
    void parseOutput(const QByteArray &chunk);
    void setProgress(const QString &appId, double value);

    QStringList m_installed;
    QStringList m_updates;
    QVariantMap m_progress;
    QList<Job> m_queue;
    QProcess *m_proc = nullptr;
    Job m_current;
    QString m_lastError;
};
