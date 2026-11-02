#pragma once

#include "processmodel.h"

#include <QHash>
#include <QObject>
#include <QQmlEngine>
#include <QTimer>
#include <QVariantList>

// Menedżer zadań: odświeżanie, procesy i wydajność (procesor, pamięć, dyski, sieć) z historią
// do wykresów — wszystko z /proc i /sys, bez dodatkowych usług.
class Monitor : public QObject
{
    Q_OBJECT
    QML_ELEMENT
    QML_SINGLETON
    Q_PROPERTY(ProcessModel *processes READ processes CONSTANT)
    Q_PROPERTY(int interval READ interval WRITE setInterval NOTIFY intervalChanged)      // ms; 0 = wstrzymane
    Q_PROPERTY(QVariantList resources READ resources NOTIFY updated)
    // [{ id, kind: cpu|mem|disk|net, title, subtitle, value (0–100), color, history: [..], history2: [..], max, stats: [{label, value}] , device }]
    Q_PROPERTY(QVariantList cores READ cores NOTIFY updated)                 // [{ value, history }]
    Q_PROPERTY(double cpu READ cpu NOTIFY updated)
    Q_PROPERTY(double memPercent READ memPercent NOTIFY updated)
    Q_PROPERTY(double memTotal READ memTotal NOTIFY updated)
    Q_PROPERTY(double diskPercent READ diskPercent NOTIFY updated)
    Q_PROPERTY(int historyLength READ historyLength CONSTANT)

public:
    explicit Monitor(QObject *parent = nullptr);
    static Monitor *create(QQmlEngine *, QJSEngine *);

    ProcessModel *processes() { return &m_processes; }
    int interval() const { return m_interval; }
    void setInterval(int ms);
    QVariantList resources() const { return m_resources; }
    QVariantList cores() const { return m_coreList; }
    double cpu() const { return m_cpu; }
    double memPercent() const { return m_memTotal > 0 ? m_memUsed * 100.0 / m_memTotal : 0; }
    double memTotal() const { return m_memTotal; }
    double diskPercent() const { return m_diskPercent; }
    int historyLength() const { return 60; }

    Q_INVOKABLE QString bytes(double b) const;                // „1,2 GB”
    Q_INVOKABLE QString rate(double bytesPerSec) const;       // „3,4 MB/s”
    Q_INVOKABLE QString bits(double bytesPerSec) const;       // „8,0 Mb/s” (sieć)
    Q_INVOKABLE QString percent(double v) const;              // „12%”, „0,4%”
    Q_INVOKABLE void launch(const QString &program, const QStringList &args = {}) const;
    Q_INVOKABLE void refreshNow();

Q_SIGNALS:
    void intervalChanged();
    void updated();

private:
    struct Series {
        QList<double> values;
        void push(double v)
        {
            values.append(v);
            while (values.size() > 60)
                values.removeFirst();
        }
        QVariantList list() const;
    };
    struct CpuTimes {
        qulonglong busy = 0, total = 0;
    };
    struct Disk {
        QString name, model, type;
        double size = 0;
        qulonglong read = 0, written = 0, ioMs = 0;
        double readRate = 0, writeRate = 0, active = 0;
        Series history;
        bool seen = false;
    };
    struct Net {
        QString name, type;
        qulonglong rx = 0, tx = 0;
        double rxRate = 0, txRate = 0;
        Series rxHistory, txHistory;
        bool seen = false;
    };

    void tick();
    void readCpu(double secs);
    void readMemory();
    void readDisks(double secs);
    void readNet(double secs);
    void publish();
    QString uptime() const;

    ProcessModel m_processes;
    QTimer m_timer;
    int m_interval = 1000;
    qint64 m_lastMs = 0;

    QString m_cpuName;
    int m_cores = 1, m_threads = 1;
    double m_maxFreq = 0, m_freq = 0;
    CpuTimes m_total;
    QList<CpuTimes> m_coreTimes;
    QList<Series> m_coreHistory;
    QList<double> m_coreValues;
    double m_cpu = 0;
    Series m_cpuHistory;

    double m_memTotal = 0, m_memUsed = 0, m_memAvail = 0, m_memCached = 0, m_swapTotal = 0, m_swapUsed = 0, m_memCommit = 0;
    Series m_memHistory;

    QHash<QString, Disk> m_disks;
    QStringList m_diskOrder;
    double m_diskPercent = 0;
    QHash<QString, Net> m_nets;
    QStringList m_netOrder;

    QVariantList m_resources, m_coreList;
};
