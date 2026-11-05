#pragma once

#include "plugin.h"

#include <atomic>
#include <cstdint>

// Wspólne dla Studia i procesu wtyczki (aster-plugin-host): pamięć jednego bloku dźwięku i rozkazy gniazda.
namespace Remote {

constexpr int MaxBlock = 2048;
constexpr int SocketFd = 3, MemoryFd = 4;      // deskryptory w procesie wtyczki

enum Turn : uint32_t { Idle = 0, Request = 1, Done = 2 };
enum Op : uint32_t { Loaded, Params, SetParam, State, SetState, HasEditor, OpenEditor, CloseEditor };

struct RtParam
{
    uint32_t id;
    double value;
};

struct Shared
{
    std::atomic<uint32_t> turn;       // futex: kto teraz liczy
    std::atomic<int32_t> latency;
    int32_t n, noteCount, hasSide, rtCount;
    Plug::Transport transport;
    Plug::Note notes[512];
    RtParam rt[64];
    float l[MaxBlock], r[MaxBlock], sideL[MaxBlock], sideR[MaxBlock];
};

void futexWait(std::atomic<uint32_t> *word, uint32_t value, long timeoutNs);
void futexWake(std::atomic<uint32_t> *word);
bool writeFrame(int fd, uint32_t op, const QByteArray &data);
bool readFrame(int fd, uint32_t *op, QByteArray *data, int timeoutMs);

}
