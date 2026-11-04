#pragma once

#include <QJsonArray>
#include <QObject>
#include <QQmlEngine>
#include <QTimer>
#include <QVariantList>

// Porty: kto nasłuchuje na którym porcie (TCP i UDP, IPv4 i IPv6) — prosto z /proc/net, bez ss.
// Program, PID i folder roboczy (zwykle folder projektu) widać dla własnych procesów; cudzych (systemowych) — tylko port.
// Zakładka „Porty” w Menedżerze zadań i polecenie `aster-tasks porty` dla terminala i Aster Intelligence.
class Ports : public QObject
{
    Q_OBJECT
    QML_ELEMENT
    QML_SINGLETON
    // [{port, proto, pid, program, command, folder, local, mine}] — od najniższego portu
    Q_PROPERTY(QVariantList ports READ ports NOTIFY changed)
    Q_PROPERTY(bool active READ active WRITE setActive NOTIFY activeChanged)   // odświeżanie co 2 s, gdy zakładka widoczna

public:
    explicit Ports(QObject *parent = nullptr);
    QVariantList ports() const { return m_ports; }
    bool active() const { return m_timer.isActive(); }
    void setActive(bool on);

    Q_INVOKABLE void refresh();
    // Kończy proces nasłuchujący na porcie (tylko własny); force — od razu (SIGKILL)
    Q_INVOKABLE bool end(int pid, bool force);
    Q_INVOKABLE void openInBrowser(int port) const;

    static QJsonArray scan();
    static int runCli(const QStringList &args);   // aster-tasks porty [--json] | zakoncz-port PORT [--teraz]

Q_SIGNALS:
    void changed();
    void activeChanged();

private:
    QVariantList m_ports;
    QTimer m_timer;
};
