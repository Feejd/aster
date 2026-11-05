#pragma once

#include <QDBusContext>
#include <QDBusMessage>
#include <QDBusObjectPath>
#include <QObject>
#include <QQmlEngine>
#include <QTimer>
#include <QVariantList>

class Connectivity;

// Agent parowania BlueZ: kody pokazuje panel Bluetooth w centrum sterowania, nie okienko KDE.
class BluetoothAgent : public QObject, protected QDBusContext
{
    Q_OBJECT
    Q_CLASSINFO("D-Bus Interface", "org.bluez.Agent1")
public:
    explicit BluetoothAgent(Connectivity *owner);
    void answer(bool accepted);

public Q_SLOTS:
    void Release();
    QString RequestPinCode(const QDBusObjectPath &device);
    void DisplayPinCode(const QDBusObjectPath &device, const QString &code);
    uint RequestPasskey(const QDBusObjectPath &device);
    void DisplayPasskey(const QDBusObjectPath &device, uint passkey, ushort entered);
    void RequestConfirmation(const QDBusObjectPath &device, uint passkey);
    void RequestAuthorization(const QDBusObjectPath &device);
    void AuthorizeService(const QDBusObjectPath &device, const QString &uuid);
    void Cancel();

private:
    void ask(const QDBusObjectPath &device, const QString &code);

    Connectivity *m_owner;
    QDBusMessage m_pending;
};

// Listy do centrum sterowania: sieci Wi‑Fi (NetworkManager), urządzenia Bluetooth (BlueZ) i wyjścia dźwięku (WirePlumber).
// Skanuje tylko wtedy, gdy dana strona panelu jest otwarta, więc zamknięte centrum niczego nie kosztuje.
class Connectivity : public QObject
{
    Q_OBJECT
    QML_ELEMENT
    QML_SINGLETON

    Q_PROPERTY(QString page READ page WRITE setPage NOTIFY pageChanged)

    Q_PROPERTY(QVariantList wifiNetworks READ wifiNetworks NOTIFY wifiChanged)
    Q_PROPERTY(QString wifiConnecting READ wifiConnecting NOTIFY wifiChanged)
    Q_PROPERTY(QString wifiError READ wifiError NOTIFY wifiChanged)

    Q_PROPERTY(QVariantList bluetoothDevices READ bluetoothDevices NOTIFY bluetoothChanged)
    Q_PROPERTY(QString bluetoothBusy READ bluetoothBusy NOTIFY bluetoothChanged)
    Q_PROPERTY(QString bluetoothError READ bluetoothError NOTIFY bluetoothChanged)

    // Parowanie: kind = "" (nic), "show" (wpisz kod na urządzeniu), "confirm" (potwierdź kod lub połączenie)
    Q_PROPERTY(QString pairingKind READ pairingKind NOTIFY pairingChanged)
    Q_PROPERTY(QString pairingCode READ pairingCode NOTIFY pairingChanged)
    Q_PROPERTY(QString pairingDevice READ pairingDevice NOTIFY pairingChanged)
    Q_PROPERTY(int pairingEntered READ pairingEntered NOTIFY pairingChanged)

    Q_PROPERTY(QVariantList audioOutputs READ audioOutputs NOTIFY audioChanged)
    Q_PROPERTY(QVariantList audioInputs READ audioInputs NOTIFY audioChanged)

public:
    explicit Connectivity(QObject *parent = nullptr);

    QString page() const { return m_page; }
    void setPage(const QString &page);
    QVariantList wifiNetworks() const { return m_wifi; }
    QString wifiConnecting() const { return m_wifiConnecting; }
    QString wifiError() const { return m_wifiError; }
    QVariantList bluetoothDevices() const { return m_bt; }
    QString bluetoothBusy() const { return m_btBusy; }
    QString bluetoothError() const { return m_btError; }
    QString pairingKind() const { return m_pairingKind; }
    QString pairingCode() const { return m_pairingCode; }
    QString pairingDevice() const { return m_pairingDevice; }
    int pairingEntered() const { return m_pairingEntered; }
    QVariantList audioOutputs() const { return m_outputs; }
    QVariantList audioInputs() const { return m_inputs; }

    Q_INVOKABLE void connectWifi(const QString &ssid, const QString &password);
    Q_INVOKABLE void disconnectWifi(const QString &ssid);
    Q_INVOKABLE void forgetWifi(const QString &ssid);
    Q_INVOKABLE void toggleDevice(const QString &path);
    Q_INVOKABLE void forgetDevice(const QString &path);
    Q_INVOKABLE void answerPairing(bool accepted);
    Q_INVOKABLE void setAudioDefault(int id);

    // Wywołuje agent parowania
    void showPairing(const QString &kind, const QString &code, const QString &devicePath, int entered = 0);
    void clearPairing();

Q_SIGNALS:
    void pageChanged();
    void wifiChanged();
    void bluetoothChanged();
    void pairingChanged();
    void audioChanged();

private:
    void poll();
    void readWifi(bool rescan);
    void readBluetooth();
    void readAudio();
    void setDiscovery(bool on);
    void registerAgent();
    void pair(const QString &path);
    void connectDevice(const QString &path);
    void finishDeviceAction(const QString &error);
    void addWifiConnection(const QString &ssid, const QString &password, const QString &security);
    void watchActivation(const QString &active, const QString &settings, const QString &ssid, int attempt);
    void failWifi(const QString &message);
    void fillPreview();

    bool m_preview = false;
    QTimer m_poll;
    QString m_page;

    QVariantList m_wifi;
    QString m_wifiIface, m_wifiConnecting, m_wifiError;

    QVariantList m_bt;
    QString m_btAdapter, m_btBusy, m_btError;
    bool m_discovering = false;
    bool m_agentRegistered = false;
    BluetoothAgent *m_agent = nullptr;
    QString m_pairingKind, m_pairingCode, m_pairingDevice;
    int m_pairingEntered = 0;

    QVariantList m_outputs, m_inputs;
};
