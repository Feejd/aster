#pragma once

#include <QObject>
#include <QQmlEngine>
#include <QSet>
#include <QStandardPaths>
#include <QTimer>
#include <QVariantList>
#include <functional>

// Zaplecze Ustawień: sieci Wi‑Fi (nmcli), urządzenia Bluetooth (bluetoothctl), wyjścia i wejścia dźwięku (wpctl),
// nocne światło (KWin), ciemny motyw (plasma-apply-colorscheme) i informacje o komputerze (/proc, /sys, os-release).
// Polecenia działają w tle; ASTER_PREVIEW podstawia przykładowe dane (zrzuty w kontenerze).
class System : public QObject
{
    Q_OBJECT
    QML_ELEMENT
    QML_SINGLETON

    Q_PROPERTY(QVariantMap about READ about CONSTANT)
    Q_PROPERTY(QString userName READ userName CONSTANT)
    Q_PROPERTY(QString fullName READ fullName CONSTANT)
    Q_PROPERTY(QString picturesDir READ picturesDir CONSTANT)

    Q_PROPERTY(bool wifiAvailable MEMBER m_wifiAvailable NOTIFY networkChanged)
    Q_PROPERTY(bool wifiOn MEMBER m_wifiOn NOTIFY networkChanged)
    Q_PROPERTY(QVariantList networks MEMBER m_networks NOTIFY networkChanged)
    Q_PROPERTY(QString wiredName MEMBER m_wiredName NOTIFY networkChanged)
    Q_PROPERTY(bool scanning MEMBER m_scanning NOTIFY networkChanged)
    Q_PROPERTY(QString connecting MEMBER m_connecting NOTIFY networkChanged)

    Q_PROPERTY(bool bluetoothAvailable MEMBER m_btAvailable NOTIFY bluetoothChanged)
    Q_PROPERTY(bool bluetoothOn MEMBER m_btOn NOTIFY bluetoothChanged)
    Q_PROPERTY(QVariantList devices MEMBER m_devices NOTIFY bluetoothChanged)
    Q_PROPERTY(bool discovering MEMBER m_discovering NOTIFY bluetoothChanged)

    Q_PROPERTY(QVariantList outputs MEMBER m_outputs NOTIFY audioChanged)
    Q_PROPERTY(QVariantList inputs MEMBER m_inputs NOTIFY audioChanged)
    Q_PROPERTY(double volume MEMBER m_volume NOTIFY audioChanged)
    Q_PROPERTY(bool muted MEMBER m_muted NOTIFY audioChanged)

    Q_PROPERTY(QVariantList streams MEMBER m_streams NOTIFY audioChanged)        // [{ id, name, volume }] — dźwięk programów
    Q_PROPERTY(double inputVolume MEMBER m_inputVolume NOTIFY audioChanged)

    Q_PROPERTY(bool nightLight MEMBER m_nightLight NOTIFY displayChanged)

    // Szczegóły sieci (odczyt na żądanie: refreshNetworkDetails)
    Q_PROPERTY(QVariantMap netInfo MEMBER m_netInfo NOTIFY detailsChanged)       // { connection, device, ip, gateway, dns, mac, customDns }
    Q_PROPERTY(QVariantList vpns MEMBER m_vpns NOTIFY detailsChanged)            // [{ name, type, active }]
    Q_PROPERTY(QVariantList knownNetworks MEMBER m_known NOTIFY detailsChanged)  // [ nazwa ]
    Q_PROPERTY(bool hotspot MEMBER m_hotspot NOTIFY detailsChanged)
    // Bezpieczeństwo
    Q_PROPERTY(int firewall MEMBER m_firewall NOTIFY securityChanged)           // -1 brak, 0 wyłączona, 1 działa

public:
    explicit System(QObject *parent = nullptr);

    QVariantMap about() const;
    QString userName() const;
    QString fullName() const;
    QString picturesDir() const { return QStandardPaths::writableLocation(QStandardPaths::PicturesLocation); }

    Q_INVOKABLE void refresh();
    Q_INVOKABLE void setWifi(bool on);
    Q_INVOKABLE void scanWifi();
    Q_INVOKABLE void connectWifi(const QString &ssid, const QString &password);
    Q_INVOKABLE void disconnectWifi();

    Q_INVOKABLE void setBluetooth(bool on);
    Q_INVOKABLE void discover();
    Q_INVOKABLE void connectDevice(const QString &mac);
    Q_INVOKABLE void disconnectDevice(const QString &mac);
    Q_INVOKABLE void forgetDevice(const QString &mac);

    Q_INVOKABLE void setDefaultDevice(int id);
    Q_INVOKABLE void setVolume(double value);
    Q_INVOKABLE void toggleMute();

    Q_INVOKABLE void setInputVolume(double value);
    Q_INVOKABLE void setStreamVolume(int id, double value);

    Q_INVOKABLE void refreshNetworkDetails();
    Q_INVOKABLE void setDns(const QString &servers);        // "" = automatycznie od routera
    Q_INVOKABLE void setVpn(const QString &name, bool on);
    Q_INVOKABLE void importVpn(const QString &fileUrl);
    Q_INVOKABLE void forgetConnection(const QString &name);
    Q_INVOKABLE void setHotspot(bool on, const QString &ssid, const QString &password);

    Q_INVOKABLE void refreshSecurity();
    Q_INVOKABLE void setFirewall(bool on);
    Q_INVOKABLE void clearRecentFiles();

    Q_INVOKABLE void setNightLight(bool on);
    Q_INVOKABLE void setDarkMode(bool dark);
    Q_INVOKABLE void run(const QString &program, const QStringList &args = {});
    Q_INVOKABLE void testNotification();

Q_SIGNALS:
    void networkChanged();
    void bluetoothChanged();
    void audioChanged();
    void displayChanged();
    void detailsChanged();
    void securityChanged();
    void message(const QString &text);

private:
    void query(const QString &key, const QString &program, const QStringList &args,
               std::function<void(const QString &out, int code)> done);
    void readNetwork();
    void readBluetooth();
    void readAudio();
    void readDisplay();
    void fillPreview();

    bool m_preview = false;
    QSet<QString> m_running;
    QTimer m_poll;
    QTimer m_volumeDelay;

    bool m_wifiAvailable = false, m_wifiOn = false, m_scanning = false;
    QVariantList m_networks;
    QString m_wiredName, m_connecting;
    bool m_btAvailable = false, m_btOn = false, m_discovering = false;
    QVariantList m_devices;
    QVariantList m_outputs, m_inputs;
    double m_volume = 0;
    bool m_muted = false;
    qint64 m_volumeTouched = 0;
    bool m_nightLight = false;
    QVariantList m_streams;
    double m_inputVolume = 0;
    qint64 m_inputTouched = 0;
    QVariantMap m_netInfo;
    QVariantList m_vpns, m_known;
    bool m_hotspot = false;
    int m_firewall = -1;
};
