#pragma once

#include <QObject>
#include <QQmlEngine>
#include <QTimer>
#include <QVariantMap>

// Bateria (/sys/class/power_supply: poziom, ładowanie, kondycja, cykle, pozostały czas)
// i tryb zasilania (power-profiles-daemon: oszczędzanie, zrównoważony, wydajność).
// Czasy wygaszania, usypiania i działanie przycisków zapisuje strona przez Conf (powerdevilrc).
class Power : public QObject
{
    Q_OBJECT
    QML_ELEMENT
    QML_SINGLETON
    Q_PROPERTY(bool hasBattery MEMBER m_hasBattery NOTIFY changed)
    Q_PROPERTY(int level MEMBER m_level NOTIFY changed)
    Q_PROPERTY(bool charging MEMBER m_charging NOTIFY changed)
    Q_PROPERTY(bool pluggedIn MEMBER m_pluggedIn NOTIFY changed)
    Q_PROPERTY(int health MEMBER m_health NOTIFY changed)           // % pojemności fabrycznej, -1 = nie wiadomo
    Q_PROPERTY(int cycles MEMBER m_cycles NOTIFY changed)           // -1 = nie wiadomo
    Q_PROPERTY(int minutesLeft MEMBER m_minutesLeft NOTIFY changed) // do rozładowania albo naładowania, -1 = nie wiadomo
    Q_PROPERTY(QStringList profiles MEMBER m_profiles NOTIFY changed)
    Q_PROPERTY(QString profile MEMBER m_profile NOTIFY changed)

public:
    explicit Power(QObject *parent = nullptr);
    Q_INVOKABLE void setProfile(const QString &profile);

Q_SIGNALS:
    void changed();

private:
    void readBattery();
    void readProfiles();

    bool m_preview = false;
    QTimer m_poll;
    bool m_hasBattery = false, m_charging = false, m_pluggedIn = true;
    int m_level = 100, m_health = -1, m_cycles = -1, m_minutesLeft = -1;
    QStringList m_profiles;
    QString m_profile;
    QString m_ppdService;
};
