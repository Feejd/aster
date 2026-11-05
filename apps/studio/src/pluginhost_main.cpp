// aster-plugin-host — jedna wtyczka w jednym procesie, sterowana przez Studio.
//   aster-plugin-host --scan PLIK           wypisuje wtyczki z pliku (JSON)
//   aster-plugin-host FORMAT ŚCIEŻKA ID NAZWA CZĘSTOTLIWOŚĆ BLOK   (gniazdo: 3, pamięć: 4)
#include "remote.h"

#include <QCoreApplication>
#include <QDataStream>
#include <QIODevice>
#include <QJsonArray>
#include <QJsonDocument>
#include <QJsonObject>
#include <QSocketNotifier>
#include <QTimer>
#include <cstdio>
#include <pthread.h>
#include <sched.h>
#include <sys/mman.h>
#include <thread>
#include <unistd.h>

using namespace Remote;

static int scan(const QString &file)
{
    QJsonArray out;
    for (const Plug::Info &i : Plug::scanFile(file))
        out.append(QJsonObject{{QStringLiteral("format"), i.format}, {QStringLiteral("path"), i.path}, {QStringLiteral("uid"), i.uid},
                               {QStringLiteral("name"), i.name}, {QStringLiteral("vendor"), i.vendor}, {QStringLiteral("category"), i.category},
                               {QStringLiteral("instrument"), i.instrument}});
    const QByteArray json = "\n@@" + QJsonDocument(out).toJson(QJsonDocument::Compact) + "\n";
    fwrite(json.constData(), 1, size_t(json.size()), stdout);
    fflush(stdout);
    return 0;
}

int main(int argc, char **argv)
{
    QCoreApplication app(argc, argv);
    if (argc == 3 && !strcmp(argv[1], "--scan"))
        return scan(QString::fromUtf8(argv[2]));
    if (argc != 7)
        return 2;
    Plug::Info info;
    info.format = QString::fromUtf8(argv[1]);
    info.path = QString::fromUtf8(argv[2]);
    info.uid = QString::fromUtf8(argv[3]);
    info.name = QString::fromUtf8(argv[4]);
    const double rate = atof(argv[5]);
    const int block = atoi(argv[6]);

    auto *m = static_cast<Shared *>(mmap(nullptr, sizeof(Shared), PROT_READ | PROT_WRITE, MAP_SHARED, MemoryFd, 0));
    if (m == MAP_FAILED)
        return 3;
    QString error;
    std::unique_ptr<Plug::Plugin> plugin = Plug::loadLocal(info, rate, block, &error);
    if (!plugin) {
        writeFrame(SocketFd, Loaded, error.isEmpty() ? QByteArray("Wtyczka nie chce się uruchomić.") : error.toUtf8());
        return 4;
    }
    m->latency.store(plugin->latency());
    writeFrame(SocketFd, Loaded, plugin->hasSidechain() ? "ok+" : "ok");

    // Wątek dźwięku: budzi go Studio, liczy blok, oddaje
    std::atomic<bool> quit{false};
    std::thread audio([&] {
        sched_param sp{};
        sp.sched_priority = 40;
        pthread_setschedparam(pthread_self(), SCHED_FIFO, &sp);    // gdy system pozwoli
        while (!quit.load(std::memory_order_relaxed)) {
            if (m->turn.load(std::memory_order_acquire) != Request) {
                futexWait(&m->turn, m->turn.load(), 200000000);
                continue;
            }
            for (int i = 0; i < m->rtCount; ++i)
                plugin->automate(m->rt[i].id, m->rt[i].value);
            plugin->process(m->l, m->r, m->n, m->notes, m->noteCount, m->transport, m->hasSide ? m->sideL : nullptr, m->hasSide ? m->sideR : nullptr);
            m->turn.store(Done, std::memory_order_release);
            futexWake(&m->turn);
        }
    });

    // Sterowanie
    QSocketNotifier control(SocketFd, QSocketNotifier::Read);
    QObject::connect(&control, &QSocketNotifier::activated, &app, [&] {
        uint32_t op = 0;
        QByteArray in, out;
        if (!readFrame(SocketFd, &op, &in, 5000)) {
            app.quit();                         // Studio zniknęło
            return;
        }
        switch (op) {
        case Params: {
            const QList<Plug::Param> ps = plugin->params();
            QDataStream s(&out, QIODevice::WriteOnly);
            s << int(ps.size());
            for (const Plug::Param &p : ps)
                s << p.id << p.name << p.unit << p.value << p.automatable;
            break;
        }
        case SetParam: {
            unsigned id = 0;
            double v = 0;
            QDataStream(in) >> id >> v;
            plugin->setParam(id, v);
            break;
        }
        case State:
            out = plugin->state();
            break;
        case SetState:
            out = plugin->setState(in) ? "1" : "0";
            break;
        case HasEditor:
            out = plugin->hasEditor() ? "1" : "0";
            break;
        case OpenEditor:
            out = plugin->openEditor() ? "1" : "0";
            break;
        case CloseEditor:
            plugin->closeEditor();
            break;
        default:
            break;
        }
        writeFrame(SocketFd, op, out);
    });
    QTimer latency;
    QObject::connect(&latency, &QTimer::timeout, &app, [&] { m->latency.store(plugin->latency(), std::memory_order_relaxed); });
    latency.start(250);
    const int rc = app.exec();
    quit.store(true);
    m->turn.store(Idle);
    futexWake(&m->turn);
    audio.join();
    plugin.reset();
    return rc;
}
