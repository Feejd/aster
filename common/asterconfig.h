#pragma once

#include <QColor>
#include <QFileSystemWatcher>
#include <QObject>
#include <QQmlEngine>

// Ustawienia Aster wspólne dla powłoki i aplikacji: ~/.config/aster/aster.conf.
// Każdy program obserwuje plik, więc zmiana w Ustawieniach od razu widać wszędzie
// (kolor akcentu w oknach, tapeta, zegar na pulpicie, „Nie przeszkadzać”).
class AsterConfig : public QObject
{
    Q_OBJECT
    QML_NAMED_ELEMENT(Config)
    QML_SINGLETON

    Q_PROPERTY(QColor accent READ accent WRITE setAccent NOTIFY changed)
    Q_PROPERTY(QString wallpaper READ wallpaper WRITE setWallpaper NOTIFY changed)
    Q_PROPERTY(bool desktopClock READ desktopClock WRITE setDesktopClock NOTIFY changed)
    Q_PROPERTY(bool batteryPercent READ batteryPercent WRITE setBatteryPercent NOTIFY changed)
    Q_PROPERTY(bool doNotDisturb READ doNotDisturb WRITE setDoNotDisturb NOTIFY changed)
    // Katalog z zasobami Aster (tapety) — ASTER_DATA_DIR nadpisuje przy pracy nad kodem
    Q_PROPERTY(QString dataDir READ dataDir CONSTANT)

public:
    explicit AsterConfig(QObject *parent = nullptr);

    QColor accent() const { return m_values.value(QStringLiteral("accent"), QStringLiteral("#3456E8")).value<QColor>(); }
    QString wallpaper() const { return m_values.value(QStringLiteral("wallpaper"), QStringLiteral("aura")).toString(); }
    bool desktopClock() const { return m_values.value(QStringLiteral("desktopClock"), true).toBool(); }
    bool batteryPercent() const { return m_values.value(QStringLiteral("batteryPercent"), true).toBool(); }
    bool doNotDisturb() const { return m_values.value(QStringLiteral("doNotDisturb"), false).toBool(); }
    QString dataDir() const;

    void setAccent(const QColor &c) { write(QStringLiteral("accent"), c.name()); }
    void setWallpaper(const QString &w) { write(QStringLiteral("wallpaper"), w); }
    void setDesktopClock(bool on) { write(QStringLiteral("desktopClock"), on); }
    void setBatteryPercent(bool on) { write(QStringLiteral("batteryPercent"), on); }
    void setDoNotDisturb(bool on) { write(QStringLiteral("doNotDisturb"), on); }

Q_SIGNALS:
    void changed();

private:
    QString path() const;
    void load();
    void write(const QString &key, const QVariant &value);

    QVariantMap m_values;
    QFileSystemWatcher m_watcher;
};
