#pragma once

#include <QAbstractListModel>
#include <QTimer>
#include <QtQml/qqmlregistration.h>

// Porty (Radar): kto nasłuchuje na którym porcie — z /proc/net/{tcp,tcp6,udp,udp6} i gniazd w /proc/<pid>/fd.
// Koniec z „port 3000 zajęty”: widać program, PID i można go zakończyć.
class PortModel : public QAbstractListModel
{
    Q_OBJECT
    QML_ELEMENT
    Q_PROPERTY(bool active READ active WRITE setActive NOTIFY activeChanged)        // odświeżanie co 2 s
    Q_PROPERTY(QString filter READ filter WRITE setFilter NOTIFY filterChanged)    // port, program albo PID
    Q_PROPERTY(int count READ rowCount NOTIFY updated)
    Q_PROPERTY(int hidden READ hidden NOTIFY updated)                              // gniazda cudzych procesów bez dostępu

public:
    enum Roles { PortRole = Qt::UserRole + 1, ProtoRole, AddressRole, ScopeRole, PidRole, NameRole, CommandRole, KeyRole, OwnRole };

    explicit PortModel(QObject *parent = nullptr);

    int rowCount(const QModelIndex &parent = {}) const override;
    QVariant data(const QModelIndex &index, int role) const override;
    QHash<int, QByteArray> roleNames() const override;

    bool active() const { return m_timer.isActive(); }
    void setActive(bool on);
    QString filter() const { return m_filter; }
    void setFilter(const QString &f);
    int hidden() const { return m_hidden; }

    Q_INVOKABLE void refresh();
    Q_INVOKABLE void openInBrowser(int port) const;     // http://localhost:<port>

Q_SIGNALS:
    void activeChanged();
    void filterChanged();
    void updated();

private:
    struct Entry {
        int port = 0;
        QString proto;      // TCP / UDP
        QString address;    // 0.0.0.0, ::, 127.0.0.1…
        QString scope;      // „Wszystkie sieci” / „Tylko ten komputer” / adres
        int pid = 0;        // 0 — proces innego użytkownika albo systemu (bez dostępu do jego gniazd)
        QString name;
        QString command;
        bool own = false;
    };
    QList<Entry> m_all, m_rows;
    QString m_filter;
    int m_hidden = 0;
    QTimer m_timer;

    void applyFilter();
};
