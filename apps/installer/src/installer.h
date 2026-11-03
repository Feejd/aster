#pragma once

#include <QObject>
#include <QProcess>
#include <QQmlEngine>
#include <QTimer>
#include <QVariantList>

// Instalator Aster: listy do wyboru (języki, klawiatury, strefy czasowe, dyski, sieci Wi‑Fi), podgląd układu
// klawiatury na żywo i sama instalacja — skrypt aster-install (bootc install to-disk + ustawienia w nowym systemie).
// Konto użytkownika zakłada przy pierwszym starcie aster-firstboot (dane czeka w /etc/aster/firstboot.env).
class Installer : public QObject
{
    Q_OBJECT
    QML_ELEMENT
    QML_SINGLETON
    Q_PROPERTY(QVariantList languages READ languages CONSTANT)       // [{ id, name, native, keyboard, timezone }]
    Q_PROPERTY(QVariantList keyboards READ keyboards CONSTANT)       // [{ id, layout, variant, name, keymap }]
    Q_PROPERTY(QVariantList timezones READ timezones CONSTANT)       // [{ id, city, region, offset }]
    Q_PROPERTY(QVariantList disks READ disks NOTIFY disksChanged)    // [{ path, name, sizeText, size, kind, windows, partitions }]
    Q_PROPERTY(QVariantList networks READ networks NOTIFY networksChanged) // [{ ssid, signal, secure, active }]
    Q_PROPERTY(bool wired READ wired NOTIFY networksChanged)
    Q_PROPERTY(bool online READ online NOTIFY networksChanged)
    Q_PROPERTY(bool scanning READ scanning NOTIFY networksChanged)
    Q_PROPERTY(QString state READ state NOTIFY stateChanged)        // idle | installing | done | failed
    Q_PROPERTY(qreal progress READ progress NOTIFY progressChanged)
    Q_PROPERTY(QString stage READ stage NOTIFY progressChanged)
    Q_PROPERTY(QString log READ log NOTIFY logChanged)
    Q_PROPERTY(QString error READ error NOTIFY stateChanged)
    Q_PROPERTY(bool preview READ preview CONSTANT)

public:
    explicit Installer(QObject *parent = nullptr);

    QVariantList languages() const;
    QVariantList keyboards() const;
    QVariantList timezones() const { return m_timezones; }
    QVariantList disks() const { return m_disks; }
    QVariantList networks() const { return m_networks; }
    bool wired() const { return m_wired; }
    bool online() const { return m_wired || !m_activeSsid.isEmpty(); }
    bool scanning() const { return m_scanning; }
    QString state() const { return m_state; }
    qreal progress() const { return m_progress; }
    QString stage() const { return m_stage; }
    QString log() const { return m_log; }
    QString error() const { return m_error; }
    bool preview() const { return m_preview; }

    Q_INVOKABLE void refreshDisks();
    Q_INVOKABLE void scanWifi();
    Q_INVOKABLE void connectWifi(const QString &ssid, const QString &password);
    Q_INVOKABLE void setKeyboard(const QString &layout, const QString &variant);   // od razu w instalatorze
    Q_INVOKABLE QString usernameFor(const QString &fullName) const;
    Q_INVOKABLE QString hostnameFor(const QString &username) const;
    Q_INVOKABLE QString timeIn(const QString &zone) const;
    Q_INVOKABLE void install(const QVariantMap &settings);
    Q_INVOKABLE void reset();                       // po błędzie: z powrotem do ustawień
    Q_INVOKABLE void reboot();
    Q_INVOKABLE void powerOff();

Q_SIGNALS:
    void disksChanged();
    void networksChanged();
    void stateChanged();
    void progressChanged();
    void logChanged();
    void wifiResult(bool ok, const QString &message);

private:
    void readNetworks(const QByteArray &out);
    void checkWired();
    void handleLine(const QString &line);
    void finish(bool ok);
    void simulate();
    QVariantList loadTimezones() const;

    bool m_preview = false;
    QVariantList m_timezones, m_disks, m_networks;
    bool m_wired = false, m_scanning = false;
    QString m_activeSsid;
    QString m_state = QStringLiteral("idle");
    qreal m_progress = 0;
    qreal m_cap = 0;            // do ilu postęp może sam dorastać przed następnym krokiem skryptu
    QTimer m_creep;
    QString m_stage, m_log, m_error;
    QProcess *m_proc = nullptr;
    QTimer m_fake;
};
