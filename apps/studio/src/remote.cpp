// Wtyczka w osobnym procesie. Dźwięk: blok w pamięci współdzielonej, budzenie futeksem; gdy wtyczka nie zdąży
// albo padnie, ścieżka gra dalej bez niej. Sterowanie (parametry, stan, okno): gniazdo, tylko z wątku interfejsu.
#include "remote.h"

#include <QCoreApplication>
#include <QDataStream>
#include <QDir>
#include <QFileInfo>
#include <QFile>
#include <QIODevice>
#include <algorithm>
#include <cerrno>
#include <chrono>
#include <cstring>
#include <functional>
#include <linux/futex.h>
#include <poll.h>
#include <signal.h>
#include <spawn.h>
#include <sys/mman.h>
#include <sys/socket.h>
#include <sys/syscall.h>
#include <sys/wait.h>
#include <thread>
#include <time.h>
#include <unistd.h>

extern char **environ;

namespace Remote {

void futexWait(std::atomic<uint32_t> *word, uint32_t value, long timeoutNs)
{
    timespec ts{timeoutNs / 1000000000L, timeoutNs % 1000000000L};
    syscall(SYS_futex, reinterpret_cast<uint32_t *>(word), FUTEX_WAIT, value, &ts, nullptr, 0);
}

void futexWake(std::atomic<uint32_t> *word)
{
    syscall(SYS_futex, reinterpret_cast<uint32_t *>(word), FUTEX_WAKE, 1, nullptr, nullptr, 0);
}

static bool writeAll(int fd, const char *p, size_t n)
{
    while (n > 0) {
        const ssize_t k = ::send(fd, p, n, MSG_NOSIGNAL);
        if (k <= 0) {
            if (k < 0 && errno == EINTR)
                continue;
            return false;
        }
        p += k;
        n -= size_t(k);
    }
    return true;
}

static bool readAll(int fd, char *p, size_t n, int timeoutMs)
{
    while (n > 0) {
        pollfd pf{fd, POLLIN, 0};
        const int r = ::poll(&pf, 1, timeoutMs);
        if (r < 0 && errno == EINTR)
            continue;
        if (r <= 0)
            return false;
        const ssize_t k = ::read(fd, p, n);
        if (k <= 0)
            return false;
        p += k;
        n -= size_t(k);
    }
    return true;
}

bool writeFrame(int fd, uint32_t op, const QByteArray &data)
{
    const uint32_t head[2] = {op, uint32_t(data.size())};
    return writeAll(fd, reinterpret_cast<const char *>(head), sizeof head) && writeAll(fd, data.constData(), size_t(data.size()));
}

bool readFrame(int fd, uint32_t *op, QByteArray *data, int timeoutMs)
{
    uint32_t head[2];
    if (!readAll(fd, reinterpret_cast<char *>(head), sizeof head, timeoutMs))
        return false;
    *op = head[0];
    data->resize(qsizetype(head[1]));
    return head[1] == 0 || readAll(fd, data->data(), head[1], timeoutMs);
}

}

namespace Plug {

using namespace Remote;

class RemotePlugin : public Plugin
{
public:
    RemotePlugin(const Info &info, double rate, bool offline) : m_rate(rate), m_offline(offline) { m_info = info; }
    ~RemotePlugin() override;
    bool start(int maxBlock, QString *error);

    void process(float *l, float *r, int n, const Note *notes, int noteCount, const Transport &t, const float *sideL, const float *sideR) override;
    void automate(unsigned id, double value) override;
    bool hasSidechain() const override { return m_side; }
    int latency() const override { return m_mem ? m_mem->latency.load(std::memory_order_relaxed) : 0; }
    QList<Param> params() const override;
    void setParam(unsigned id, double value) override;
    QByteArray state() const override;
    bool setState(const QByteArray &data) override;
    bool hasEditor() const override;
    bool openEditor() override;
    void closeEditor() override;
    bool crashed() const override;

private:
    bool call(uint32_t op, const QByteArray &in, QByteArray *out, int timeoutMs = 10000) const;
    double m_rate;
    bool m_offline, m_side = false;
    Shared *m_mem = nullptr;
    int m_sock = -1;
    pid_t m_pid = 0;
    mutable std::atomic<bool> m_dead{false};
    int m_rtCount = 0;
    RtParam m_rt[64];
};

bool RemotePlugin::start(int maxBlock, QString *error)
{
    auto fail = [&](const QString &e) {
        if (error)
            *error = e;
        return false;
    };
    const int mem = memfd_create("aster-plugin", MFD_CLOEXEC);
    if (mem < 0 || ftruncate(mem, sizeof(Shared)) != 0)
        return fail(QStringLiteral("Brak pamięci współdzielonej."));
    m_mem = static_cast<Shared *>(mmap(nullptr, sizeof(Shared), PROT_READ | PROT_WRITE, MAP_SHARED, mem, 0));
    if (m_mem == MAP_FAILED) {
        m_mem = nullptr;
        ::close(mem);
        return fail(QStringLiteral("Brak pamięci współdzielonej."));
    }
    int sv[2];
    if (socketpair(AF_UNIX, SOCK_STREAM | SOCK_CLOEXEC, 0, sv) != 0) {
        ::close(mem);
        return fail(QStringLiteral("Nie da się połączyć z procesem wtyczki."));
    }
    m_sock = sv[0];
    QString exe = QCoreApplication::applicationDirPath() + QStringLiteral("/aster-plugin-host");
    if (!QFile::exists(exe))
        exe = QStringLiteral("/usr/libexec/aster-plugin-host");
    const QByteArray bin = exe.toUtf8(), format = (m_info.format.isEmpty() ? QStringLiteral("vst3") : m_info.format).toUtf8(), path = m_info.path.toUtf8(),
                     uid = m_info.uid.toUtf8(), name = m_info.name.toUtf8(), rate = QByteArray::number(m_rate), block = QByteArray::number(maxBlock);
    char *argv[] = {const_cast<char *>(bin.constData()), const_cast<char *>(format.constData()), const_cast<char *>(path.constData()),
                    const_cast<char *>(uid.constData()), const_cast<char *>(name.constData()), const_cast<char *>(rate.constData()),
                    const_cast<char *>(block.constData()), nullptr};
    posix_spawn_file_actions_t fa;
    posix_spawn_file_actions_init(&fa);
    posix_spawn_file_actions_adddup2(&fa, sv[1], SocketFd);
    posix_spawn_file_actions_adddup2(&fa, mem, MemoryFd);
    const int rc = posix_spawn(&m_pid, bin.constData(), &fa, nullptr, argv, environ);
    posix_spawn_file_actions_destroy(&fa);
    ::close(sv[1]);
    ::close(mem);
    if (rc != 0) {
        m_pid = 0;
        return fail(QStringLiteral("Nie ma programu aster-plugin-host."));
    }
    uint32_t op = 0;
    QByteArray reply;
    if (!readFrame(m_sock, &op, &reply, 30000) || op != Loaded)
        return fail(QStringLiteral("Wtyczka nie chce się uruchomić: %1").arg(m_info.name));
    if (!reply.startsWith("ok"))
        return fail(QString::fromUtf8(reply));
    m_side = reply.endsWith('+');
    return true;
}

RemotePlugin::~RemotePlugin()
{
    if (m_sock >= 0)
        ::close(m_sock);                       // proces wtyczki kończy się sam, gdy zniknie gniazdo
    if (m_pid > 0) {
        for (int i = 0; i < 50; ++i) {
            if (waitpid(m_pid, nullptr, WNOHANG) != 0) {
                m_pid = 0;
                break;
            }
            struct timespec t{0, 4000000};
            nanosleep(&t, nullptr);
        }
        if (m_pid > 0) {
            ::kill(m_pid, SIGKILL);
            waitpid(m_pid, nullptr, 0);
        }
    }
    if (m_mem)
        munmap(m_mem, sizeof(Shared));
}

void RemotePlugin::automate(unsigned id, double value)
{
    if (m_rtCount < 64)
        m_rt[m_rtCount++] = {id, value};
}

void RemotePlugin::process(float *l, float *r, int n, const Note *notes, int noteCount, const Transport &t, const float *sideL, const float *sideR)
{
    if (m_dead.load(std::memory_order_relaxed))
        return;
    Shared *m = m_mem;
    uint32_t turn = m->turn.load(std::memory_order_acquire);
    if (turn == Request)
        return;                                 // wtyczka nie skończyła poprzedniego bloku: ten gra bez niej
    n = std::min(n, MaxBlock);
    m->n = n;
    std::memcpy(m->l, l, size_t(n) * sizeof(float));
    std::memcpy(m->r, r, size_t(n) * sizeof(float));
    m->hasSide = sideL != nullptr;
    if (sideL) {
        std::memcpy(m->sideL, sideL, size_t(n) * sizeof(float));
        std::memcpy(m->sideR, sideR, size_t(n) * sizeof(float));
    }
    m->noteCount = std::min(noteCount, 512);
    if (noteCount)
        std::memcpy(m->notes, notes, size_t(m->noteCount) * sizeof(Note));
    m->transport = t;
    m->rtCount = m_rtCount;
    if (m_rtCount)
        std::memcpy(m->rt, m_rt, size_t(m_rtCount) * sizeof(RtParam));
    m_rtCount = 0;
    m->turn.store(Request, std::memory_order_release);
    futexWake(&m->turn);
    // Na żywo czekamy najwyżej tyle, ile trwa blok; eksport czeka, ile trzeba
    const auto deadline = std::chrono::steady_clock::now() + (m_offline ? std::chrono::nanoseconds(30000000000LL)
                                                                        : std::chrono::nanoseconds(long(double(n) / m_rate * 0.9e9)));
    for (int spin = 0; spin < 2000; ++spin) {
        if (m->turn.load(std::memory_order_acquire) == Done)
            break;
    }
    while ((turn = m->turn.load(std::memory_order_acquire)) == Request) {
        const auto left = std::chrono::duration_cast<std::chrono::nanoseconds>(deadline - std::chrono::steady_clock::now()).count();
        if (left <= 0)
            return;                             // spóźniona: ten blok bez wtyczki
        futexWait(&m->turn, Request, long(left));
    }
    std::memcpy(l, m->l, size_t(n) * sizeof(float));
    std::memcpy(r, m->r, size_t(n) * sizeof(float));
}

bool RemotePlugin::call(uint32_t op, const QByteArray &in, QByteArray *out, int timeoutMs) const
{
    uint32_t got = 0;
    QByteArray reply;
    if (m_dead.load() || !writeFrame(m_sock, op, in) || !readFrame(m_sock, &got, &reply, timeoutMs) || got != op) {
        m_dead.store(true);
        return false;
    }
    if (out)
        *out = reply;
    return true;
}

bool RemotePlugin::crashed() const
{
    if (m_dead.load())
        return true;
    if (m_pid <= 0)
        return false;
    int status = 0;
    if (waitpid(m_pid, &status, WNOHANG) == m_pid) {
        const_cast<RemotePlugin *>(this)->m_pid = 0;
        m_dead.store(true);
        return true;
    }
    return false;
}

QList<Param> RemotePlugin::params() const
{
    QList<Param> out;
    QByteArray data;
    if (!call(Params, {}, &data))
        return out;
    QDataStream s(data);
    int n = 0;
    s >> n;
    for (int i = 0; i < n; ++i) {
        Param p;
        s >> p.id >> p.name >> p.unit >> p.value >> p.automatable;
        out << p;
    }
    return out;
}

void RemotePlugin::setParam(unsigned id, double value)
{
    QByteArray b;
    QDataStream(&b, QIODevice::WriteOnly) << id << value;
    call(SetParam, b, nullptr);
}

QByteArray RemotePlugin::state() const
{
    QByteArray out;
    call(State, {}, &out, 20000);
    return out;
}

bool RemotePlugin::setState(const QByteArray &data)
{
    QByteArray out;
    return call(SetState, data, &out, 20000) && out == "1";
}

bool RemotePlugin::hasEditor() const
{
    QByteArray out;
    return call(HasEditor, {}, &out) && out == "1";
}

bool RemotePlugin::openEditor()
{
    QByteArray out;
    return call(OpenEditor, {}, &out, 20000) && out == "1";
}

void RemotePlugin::closeEditor()
{
    call(CloseEditor, {}, nullptr);
}

QStringList pluginFiles()
{
    const QString home = QDir::homePath();
    QStringList vst3{home + QStringLiteral("/.vst3"), QStringLiteral("/usr/lib64/vst3"), QStringLiteral("/usr/lib/vst3"), QStringLiteral("/usr/local/lib/vst3")};
    QStringList clap{home + QStringLiteral("/.clap"), QStringLiteral("/usr/lib64/clap"), QStringLiteral("/usr/lib/clap"), QStringLiteral("/usr/local/lib/clap")};
    vst3 = qEnvironmentVariable("VST3_PATH").split(QLatin1Char(':'), Qt::SkipEmptyParts) + vst3;
    clap = qEnvironmentVariable("CLAP_PATH").split(QLatin1Char(':'), Qt::SkipEmptyParts) + clap;
    QStringList out;
    std::function<void(const QString &, const QString &, int)> walk = [&](const QString &dir, const QString &suffix, int depth) {
        for (const QFileInfo &fi : QDir(dir).entryInfoList(QDir::Dirs | QDir::Files | QDir::NoDotAndDotDot)) {
            if (fi.suffix() == suffix) {
                if (!out.contains(fi.canonicalFilePath()))
                    out << fi.canonicalFilePath();
            } else if (fi.isDir() && depth < 4) {
                walk(fi.filePath(), suffix, depth + 1);
            }
        }
    };
    for (const QString &p : std::as_const(vst3))
        walk(p, QStringLiteral("vst3"), 0);
    for (const QString &p : std::as_const(clap))
        walk(p, QStringLiteral("clap"), 0);
    return out;
}

std::unique_ptr<Plugin> loadRemote(const Info &info, double rate, int maxBlock, bool offline, QString *error)
{
    auto p = std::make_unique<RemotePlugin>(info, rate, offline);
    if (!p->start(maxBlock, error))
        return {};
    return p;
}

}
