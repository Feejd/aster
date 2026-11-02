#pragma once

#include <QAbstractListModel>
#include <QHash>
#include <QQmlEngine>
#include <QSet>
#include <QVariantMap>
#include <QVector>

// Lista procesów jak w Menedżerze zadań Windows: trzy działy (Aplikacje, Procesy w tle, Procesy systemu),
// w Aplikacjach — program z rozwijaną listą swoich procesów (sumy procesora, pamięci i dysku).
// Proces należy do programu, gdy: jego plik to program z menu Start, albo leży w zakresie systemd
// programu (app-<id>-….scope / app-<id>@….service — tak uruchamia powłoka), albo dziedziczy po rodzicu.
class ProcessModel : public QAbstractListModel
{
    Q_OBJECT
    QML_ELEMENT
    QML_UNCREATABLE("Lista procesów jest w Monitor.processes")
    Q_PROPERTY(QString sortKey READ sortKey WRITE setSortKey NOTIFY sortChanged)      // name | cpu | mem | disk
    Q_PROPERTY(bool sortDescending READ sortDescending WRITE setSortDescending NOTIFY sortChanged)
    Q_PROPERTY(QString filter READ filter WRITE setFilter NOTIFY filterChanged)
    Q_PROPERTY(int processCount READ processCount NOTIFY updated)
    Q_PROPERTY(int threadCount READ threadCount NOTIFY updated)
    Q_PROPERTY(double diskTotal READ diskTotal NOTIFY updated)                      // B/s wszystkich procesów

public:
    enum Kind { Header, Group, Process };
    enum Roles {
        KindRole = Qt::UserRole + 1, KeyRole, SectionRole, DepthRole, PidRole, NameRole, IconRole, DesktopIdRole,
        CpuRole, MemRole, DiskRole, CountRole, ExpandedRole, CriticalRole, SystemRole, UserRole
    };

    explicit ProcessModel(QObject *parent = nullptr);

    int rowCount(const QModelIndex &parent = {}) const override;
    QVariant data(const QModelIndex &index, int role) const override;
    QHash<int, QByteArray> roleNames() const override;

    QString sortKey() const { return m_sortKey; }
    void setSortKey(const QString &key);
    bool sortDescending() const { return m_desc; }
    void setSortDescending(bool d);
    QString filter() const { return m_filter; }
    void setFilter(const QString &f);
    int processCount() const { return m_procs.size(); }
    int threadCount() const { return m_threads; }
    double diskTotal() const { return m_diskTotal; }

    // Odczyt /proc i przeliczenie wierszy (woła Monitor co odświeżenie)
    void refresh();

    Q_INVOKABLE void toggle(const QString &key);                        // rozwiń/zwiń program albo dział
    Q_INVOKABLE int indexOf(const QString &key) const;
    Q_INVOKABLE QString keyAt(int row) const { return row >= 0 && row < m_rows.size() ? m_rows.at(row).key : QString(); }
    Q_INVOKABLE QVariantMap info(const QString &key) const;             // nazwa, pid-y, krytyczny, cudzy…
    Q_INVOKABLE QVariantMap details(const QString &key) const;          // szczegóły do okna „Właściwości”
    Q_INVOKABLE void end(const QString &key, bool force);               // Zakończ zadanie / natychmiast
    Q_INVOKABLE void openLocation(const QString &key) const;            // folder z plikiem programu w Plikach

Q_SIGNALS:
    void sortChanged();
    void filterChanged();
    void updated();
    void message(const QString &text);

private:
    struct Proc {
        int pid = 0, ppid = 0;
        uint uid = 0;
        qulonglong start = 0;                 // czas startu (takty) — odróżnia proces od późniejszego o tym samym PID
        QString comm, name, exe, cmdline, scopeApp, exeApp;
        char state = 'S';
        int threads = 1;
        qulonglong ticks = 0, rd = 0, wr = 0;
        double cpu = 0, disk = 0;
        qint64 mem = 0;
    };
    struct App {
        QString id, name, icon;
    };
    struct Row {
        int kind = Process;
        QString key, section, name, icon, desktopId, user;
        int depth = 0, pid = 0, count = 0;
        double cpu = 0, disk = 0;
        qint64 mem = 0;
        bool expanded = false, critical = false, system = false;
    };

    bool readProc(int pid, Proc &p, bool first);
    QString groupOf(int pid, QHash<int, QString> &memo, int depth = 0) const;
    const App *app(const QString &id) const;
    QString appForScope(const QString &cgroupLine) const;
    QString displayName(const Proc &p) const;
    QString userName(uint uid) const;
    bool isCritical(const Proc &p) const;
    QList<int> pidsFor(const QString &key) const;
    void rebuild();
    void apply(const QVector<Row> &rows);

    QHash<int, Proc> m_procs;
    QHash<int, QString> m_group;                    // pid → id programu (po ostatnim odświeżeniu)
    mutable QHash<QString, App> m_apps;             // id → program (z KService), pusty id = brak
    QHash<QString, QString> m_exeMap;               // nazwa pliku programu → id
    mutable QHash<uint, QString> m_users;
    QVector<Row> m_rows;
    QSet<QString> m_expanded, m_collapsed;
    QString m_sortKey = QStringLiteral("cpu");
    bool m_desc = true;
    QString m_filter;
    qint64 m_lastMs = 0;
    int m_threads = 0;
    double m_diskTotal = 0;
    uint m_uid = 0;
    int m_self = 0;
    long m_hz = 100;
    int m_cpus = 1;
};
