#pragma once

#include <QObject>
#include <QQmlEngine>
#include <QTimer>
#include <QVariantList>

// Data, czas i strefa czasowa (systemd-timedated): automatyczny czas z internetu,
// ręczne ustawienie, wybór strefy z wyszukiwarką. Zmiany zatwierdza polkit.
class DateTime : public QObject
{
    Q_OBJECT
    QML_ELEMENT
    QML_SINGLETON
    Q_PROPERTY(QString timezone MEMBER m_timezone NOTIFY changed)
    Q_PROPERTY(QString timezoneLabel READ timezoneLabel NOTIFY changed)
    Q_PROPERTY(bool ntp MEMBER m_ntp NOTIFY changed)
    Q_PROPERTY(bool canNtp MEMBER m_canNtp NOTIFY changed)
    Q_PROPERTY(QVariantList timezones READ timezones CONSTANT)   // [{ id, city, region, offset }]

public:
    explicit DateTime(QObject *parent = nullptr);

    QString timezoneLabel() const { return label(m_timezone); }
    QVariantList timezones() const;

    Q_INVOKABLE void setTimezone(const QString &tz);
    Q_INVOKABLE void setNtp(bool on);
    Q_INVOKABLE void setTime(const QDateTime &when);
    Q_INVOKABLE QString label(const QString &tz) const;

Q_SIGNALS:
    void changed();
    void message(const QString &text);

private:
    void read();

    bool m_preview = false;
    QString m_timezone;
    bool m_ntp = true, m_canNtp = true;
    mutable QVariantList m_zones;
};
