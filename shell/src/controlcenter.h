#pragma once

#include <QObject>
#include <QSet>
#include <functional>
#include <QQmlEngine>
#include <QTimer>

class QProcess;

// Zaplecze centrum sterowania: sieć (nmcli), Bluetooth (bluetoothctl), dźwięk (wpctl / PipeWire),
// jasność ekranu (D-Bus org.kde.ScreenBrightness z PowerDevil), bateria (/sys), odtwarzacz (MPRIS),
// i ciemny motyw (plasma-apply-colorscheme). „Nie przeszkadzać” jest we wspólnym Config (Aster.Ui).
// Stan odświeża się co kilka sekund, a gdy centrum jest otwarte (active) — co sekundę.
// Polecenia idą przez QProcess w tle, więc powłoka nigdy nie czeka na wolny program.
class ControlCenter : public QObject
{
    Q_OBJECT
    QML_ELEMENT
    QML_SINGLETON

    Q_PROPERTY(bool active MEMBER m_active WRITE setActive NOTIFY activeChanged)

    Q_PROPERTY(bool wifiAvailable MEMBER m_wifiAvailable NOTIFY networkChanged)
    Q_PROPERTY(bool wifiOn MEMBER m_wifiOn NOTIFY networkChanged)
    Q_PROPERTY(QString networkName MEMBER m_networkName NOTIFY networkChanged)
    Q_PROPERTY(bool wired MEMBER m_wired NOTIFY networkChanged)

    Q_PROPERTY(bool bluetoothAvailable MEMBER m_btAvailable NOTIFY bluetoothChanged)
    Q_PROPERTY(bool bluetoothOn MEMBER m_btOn NOTIFY bluetoothChanged)
    Q_PROPERTY(QString bluetoothDevice MEMBER m_btDevice NOTIFY bluetoothChanged)

    Q_PROPERTY(bool audioAvailable MEMBER m_audioAvailable NOTIFY audioChanged)
    Q_PROPERTY(double volume MEMBER m_volume NOTIFY audioChanged)
    Q_PROPERTY(bool muted MEMBER m_muted NOTIFY audioChanged)

    Q_PROPERTY(bool brightnessAvailable MEMBER m_brightnessAvailable NOTIFY brightnessChanged)
    Q_PROPERTY(double brightness MEMBER m_brightness NOTIFY brightnessChanged)

    Q_PROPERTY(bool batteryAvailable MEMBER m_batteryAvailable NOTIFY batteryChanged)
    Q_PROPERTY(int battery MEMBER m_battery NOTIFY batteryChanged)
    Q_PROPERTY(bool charging MEMBER m_charging NOTIFY batteryChanged)

    Q_PROPERTY(bool updateReady MEMBER m_updateReady NOTIFY updateChanged)

    Q_PROPERTY(bool playerAvailable MEMBER m_playerAvailable NOTIFY playerChanged)
    Q_PROPERTY(QString playerName MEMBER m_playerName NOTIFY playerChanged)
    Q_PROPERTY(QString title MEMBER m_title NOTIFY playerChanged)
    Q_PROPERTY(QString artist MEMBER m_artist NOTIFY playerChanged)
    Q_PROPERTY(QString artUrl MEMBER m_artUrl NOTIFY playerChanged)
    Q_PROPERTY(bool playing MEMBER m_playing NOTIFY playerChanged)


public:
    explicit ControlCenter(QObject *parent = nullptr);

    void setActive(bool active);

    Q_INVOKABLE void refresh();
    Q_INVOKABLE void setWifi(bool on);
    Q_INVOKABLE void setBluetooth(bool on);
    Q_INVOKABLE void setVolume(double value);
    Q_INVOKABLE void toggleMute();
    Q_INVOKABLE void setBrightness(double value);
    Q_INVOKABLE void setDarkMode(bool dark);
    Q_INVOKABLE void restartForUpdate();
    Q_INVOKABLE void playPause();
    Q_INVOKABLE void next();
    Q_INVOKABLE void previous();

Q_SIGNALS:
    void activeChanged();
    void networkChanged();
    void bluetoothChanged();
    void audioChanged();
    void brightnessChanged();
    void batteryChanged();
    void playerChanged();
    void updateChanged();

private:
    // Uruchamia program w tle i oddaje jego wyjście (pomija, gdy poprzednie wywołanie tego samego klucza jeszcze trwa)
    void query(const QString &key, const QString &program, const QStringList &args, std::function<void(const QString &)> done);
    void readNetwork();
    void readBluetooth();
    void readAudio();
    void readBrightness();
    void readBattery();
    void readUpdate();
    void readPlayer();
    void playerCall(const QString &method);
    void fillPreview();

    QTimer m_poll;
    QTimer m_volumeDelay;
    QTimer m_brightnessDelay;
    QSet<QString> m_running;
    bool m_preview = false;

    bool m_active = false;
    bool m_updateReady = false;
    bool m_wifiAvailable = false, m_wifiOn = false, m_wired = false;
    QString m_networkName;
    bool m_btAvailable = false, m_btOn = false;
    QString m_btDevice;
    bool m_audioAvailable = false, m_muted = false;
    double m_volume = 0;
    bool m_brightnessAvailable = false;
    double m_brightness = 1;
    QString m_display;          // ekran z regulacją jasności (nazwa obiektu D-Bus PowerDevil)
    bool m_batteryAvailable = false, m_charging = false;
    int m_battery = 0;
    bool m_playerAvailable = false, m_playing = false;
    QString m_playerService, m_playerName, m_title, m_artist, m_artUrl;
    // Chwilę po ruchu suwakiem nie nadpisujemy wartości odczytem (żeby suwak nie „skakał”)
    qint64 m_volumeTouched = 0, m_brightnessTouched = 0;
};
