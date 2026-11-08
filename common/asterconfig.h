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
    Q_PROPERTY(bool dockAutoHide READ dockAutoHide WRITE setDockAutoHide NOTIFY changed)
    // Powiadomienia poszczególnych programów: wyciszone (bez dymków) i lista programów, które już coś wysłały
    // (zapisuje ją powłoka): [{ id, name, icon }]
    Q_PROPERTY(QStringList mutedApps READ mutedApps WRITE setMutedApps NOTIFY changed)
    Q_PROPERTY(QVariantList notifyApps READ notifyApps NOTIFY changed)
    // Katalog z zasobami Aster (tapety) — ASTER_DATA_DIR nadpisuje przy pracy nad kodem
    Q_PROPERTY(QString dataDir READ dataDir CONSTANT)

public:
    explicit AsterConfig(QObject *parent = nullptr);

    QColor accent() const { return m_values.value(QStringLiteral("accent"), QStringLiteral("#3456E8")).value<QColor>(); }
    QString wallpaper() const
    {
        const QString id = m_values.value(QStringLiteral("wallpaper"), QStringLiteral("swit")).toString();
        // Tapety sprzed nowego wyglądu już nie istnieją
        static const QStringList old{QStringLiteral("aura"), QStringLiteral("bloom"), QStringLiteral("szczyty"), QStringLiteral("jezioro")};
        return old.contains(id) ? QStringLiteral("swit") : id;
    }
    bool desktopClock() const { return m_values.value(QStringLiteral("desktopClock"), true).toBool(); }
    bool batteryPercent() const { return m_values.value(QStringLiteral("batteryPercent"), true).toBool(); }
    bool doNotDisturb() const { return m_values.value(QStringLiteral("doNotDisturb"), false).toBool(); }
    bool dockAutoHide() const { return m_values.value(QStringLiteral("dockAutoHide"), true).toBool(); }
    QStringList mutedApps() const { return m_values.value(QStringLiteral("notifications/muted")).toStringList(); }
    QVariantList notifyApps() const;
    QString dataDir() const;

    void setAccent(const QColor &c) { write(QStringLiteral("accent"), c.name()); }
    void setWallpaper(const QString &w) { write(QStringLiteral("wallpaper"), w); }
    void setDesktopClock(bool on) { write(QStringLiteral("desktopClock"), on); }
    void setBatteryPercent(bool on) { write(QStringLiteral("batteryPercent"), on); }
    void setDoNotDisturb(bool on) { write(QStringLiteral("doNotDisturb"), on); }
    void setDockAutoHide(bool on) { write(QStringLiteral("dockAutoHide"), on); }
    void setMutedApps(const QStringList &ids) { write(QStringLiteral("notifications/muted"), ids); }
    Q_INVOKABLE void setAppMuted(const QString &id, bool muted);

    // Dla powłoki: czy pokazywać dymek programu; zapamiętuje program na liście (bez obiektu — działa wszędzie)
    static bool notificationAllowed(const QString &id, const QString &name, const QString &icon);

Q_SIGNALS:
    void changed();

private:
    QString path() const;
    void load();
    void write(const QString &key, const QVariant &value);

    QVariantMap m_values;
    QFileSystemWatcher m_watcher;
};
