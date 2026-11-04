#pragma once

// D-Bus org.aster.Launch (/org/aster/Launch) — dla asystenta Aster i innych programów.
// Wdrożenie, przywrócenie i logi zawsze czekają na decyzję użytkownika w oknie Aster Launch
// (plan zmian albo pytanie o zgodę); odpowiedź przychodzi dopiero po wykonaniu albo odmowie.
// Status czyta tylko zapisane dane i sprawdza, czy strona odpowiada (zwykłe zapytanie HTTP) — bez zmian na serwerze.

#include <QDBusContext>
#include <QDBusMessage>
#include <QObject>

class Launch;

class LaunchBus : public QObject, protected QDBusContext
{
    Q_OBJECT
    Q_CLASSINFO("D-Bus Interface", "org.aster.Launch")
public:
    explicit LaunchBus(Launch *launch, QObject *parent = nullptr);

public Q_SLOTS:
    QString Projects();
    QString Status(const QString &project);
    QString Deploy(const QString &project);
    QString Rollback(const QString &project, int version);
    QString Logs(const QString &project, int lines);
    void Activate(const QString &token);

Q_SIGNALS:
    void activated(const QString &token);

private:
    QString resolve(const QString &project);
    void runPlan(const QString &id, const QDBusMessage &msg);
    Launch *m_launch;
};
