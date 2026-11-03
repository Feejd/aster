#pragma once

#include <QObject>
#include <QQmlEngine>
#include <QTimer>
#include <QVariantList>

// Telefon (zamiast okien KDE Connect), jak „Łącze z telefonem” w Windows: rozmawia przez D-Bus z usługą kdeconnectd.
// Urządzenia z baterią i zasięgiem, parowanie z kodem do porównania, znajdowanie telefonu, wysyłanie plików
// i schowka, przeglądanie plików telefonu (SFTP) i powiadomienia z telefonu.
class Phone : public QObject
{
    Q_OBJECT
    QML_ELEMENT
    QML_SINGLETON
    Q_PROPERTY(bool running READ running NOTIFY changed)
    Q_PROPERTY(QString selfName READ selfName NOTIFY changed)
    // [{ id, name, type, reachable, paired, requested, requestedByPeer, verification, battery, charging,
    //    network, strength, plugins, notifications: [{ id, app, title, text, icon, dismissable }] }]
    Q_PROPERTY(QVariantList devices READ devices NOTIFY changed)

public:
    explicit Phone(QObject *parent = nullptr);

    bool running() const { return m_running; }
    QString selfName() const { return m_selfName; }
    QVariantList devices() const { return m_devices; }

    Q_INVOKABLE void reload();
    Q_INVOKABLE void start();                                  // uruchom kdeconnectd (aktywacja D-Bus)
    Q_INVOKABLE void setSelfName(const QString &name);
    Q_INVOKABLE void pair(const QString &id);
    Q_INVOKABLE void accept(const QString &id);
    Q_INVOKABLE void reject(const QString &id);               // odrzuć prośbę albo anuluj własną
    Q_INVOKABLE void unpair(const QString &id);
    Q_INVOKABLE void ring(const QString &id);
    Q_INVOKABLE void ping(const QString &id);
    Q_INVOKABLE void sendFiles(const QString &id, const QStringList &urls);
    Q_INVOKABLE void sendText(const QString &id, const QString &text);
    Q_INVOKABLE void sendClipboard(const QString &id);
    Q_INVOKABLE void browse(const QString &id);                // zamontuj (SFTP) i otwórz w Plikach
    Q_INVOKABLE void dismiss(const QString &id, const QString &notification);

Q_SIGNALS:
    void changed();
    void message(const QString &text);

private Q_SLOTS:
    void scheduleReload();

private:
    QVariantMap readDevice(const QString &id) const;
    QVariantList previewDevices() const;
    bool call(const QString &id, const QString &plugin, const QString &method, const QVariantList &args = {});
    QString deviceName(const QString &id) const;

    QTimer m_debounce, m_poll;
    bool m_running = false;
    bool m_preview = false;
    QString m_selfName;
    QVariantList m_devices;
};
