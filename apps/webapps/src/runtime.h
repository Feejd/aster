#pragma once

#include <QHash>
#include <QLocalServer>
#include <QObject>
#include <QQmlEngine>

// Zaplecze okna aplikacji webowej: jedna kopia na aplikację (drugie uruchomienie tylko ją
// przywołuje), systemowe powiadomienia zamiast przeglądarkowych i liczba nieprzeczytanych
// na ikonie w doku (sygnał com.canonical.Unity.LauncherEntry — ten sam co w KDE i GNOME).
class Runtime : public QObject
{
    Q_OBJECT
    QML_ELEMENT
    QML_UNCREATABLE("Tworzony przez aster-webapps --run")
    Q_PROPERTY(QString appId READ appId CONSTANT)

public:
    explicit Runtime(const QString &id, QObject *parent = nullptr);

    QString appId() const { return m_id; }
    // Gdy aplikacja już działa: każe jej się pokazać i zwraca true (to uruchomienie można zakończyć)
    bool forwardToRunning();

    // Pokazuje systemowe powiadomienie; zwraca jego numer (0, gdy się nie udało)
    Q_INVOKABLE uint notify(const QString &title, const QString &body, const QString &iconPath);
    Q_INVOKABLE void closeNotification(uint id);
    Q_INVOKABLE void setBadge(int count);

Q_SIGNALS:
    void activateRequested();
    void notificationClicked(uint id);
    void notificationClosed(uint id);

private Q_SLOTS:
    void onActionInvoked(uint id, const QString &action);
    void onNotificationClosed(uint id, uint reason);

private:
    QString m_id;
    QLocalServer m_server;
    QHash<uint, bool> m_ours;
    int m_badge = -1;
};
