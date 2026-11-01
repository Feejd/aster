#pragma once

#include <QObject>
#include <QQmlEngine>
#include <QVariantList>

// Mysz, touchpad i klawiatura.
//  • mysz i touchpad: urządzenia KWin (D-Bus org.kde.KWin.InputDevice) — zmiana działa od razu,
//    a zapis w kcminputrc ([Libinput][producent][model][nazwa]) zostaje po ponownym zalogowaniu,
//  • układy klawiatury: lista z XKB (evdev.lst), wybrane w kxkbrc, przełączanie Super+Spacja.
class Inputs : public QObject
{
    Q_OBJECT
    QML_ELEMENT
    QML_SINGLETON
    Q_PROPERTY(bool hasMouse READ hasMouse NOTIFY changed)
    Q_PROPERTY(bool hasTouchpad READ hasTouchpad NOTIFY changed)
    // ustawienia (wspólne dla wszystkich urządzeń danego rodzaju): speed −1…1, natural, leftHanded, tapToClick, disableWhileTyping
    Q_PROPERTY(QVariantMap mouse MEMBER m_mouse NOTIFY changed)
    Q_PROPERTY(QVariantMap touchpad MEMBER m_touchpad NOTIFY changed)
    Q_PROPERTY(QVariantList allLayouts READ allLayouts CONSTANT)           // [{ id, name }]
    Q_PROPERTY(QVariantList layouts MEMBER m_layouts NOTIFY changed)       // wybrane, po kolei

public:
    explicit Inputs(QObject *parent = nullptr);

    bool hasMouse() const { return !m_mouseDevices.isEmpty() || m_preview; }
    bool hasTouchpad() const { return !m_touchpadDevices.isEmpty() || m_preview; }
    QVariantList allLayouts() const;

    Q_INVOKABLE void refresh();
    // kind: "mouse" | "touchpad"; key: speed | natural | leftHanded | tapToClick | disableWhileTyping
    Q_INVOKABLE void set(const QString &kind, const QString &key, const QVariant &value);
    Q_INVOKABLE void setLayouts(const QStringList &ids);
    Q_INVOKABLE QString layoutName(const QString &id) const;

Q_SIGNALS:
    void changed();

private:
    struct Device {
        QString sysName, name;
        uint vendor = 0, product = 0;
    };
    void readLayouts();

    bool m_preview = false;
    QList<Device> m_mouseDevices, m_touchpadDevices;
    QVariantMap m_mouse, m_touchpad;
    QVariantList m_layouts;
    mutable QVariantList m_allLayouts;
};
