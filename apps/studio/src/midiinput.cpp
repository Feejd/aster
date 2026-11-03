#include "midiinput.h"

#include <alsa/asoundlib.h>
#include <poll.h>

// Bez komunikatów ALSA na konsoli (brak sekwencera to zwykła sytuacja, nie błąd)
static void quietAlsa(const char *, int, const char *, int, const char *, ...) {}

MidiInput::MidiInput(QObject *parent) : QObject(parent)
{
    snd_lib_error_set_handler(quietAlsa);
    if (snd_seq_open(&m_seq, "default", SND_SEQ_OPEN_INPUT, SND_SEQ_NONBLOCK) < 0) {
        m_seq = nullptr;
        return;
    }
    snd_seq_set_client_name(m_seq, "Studio");
    m_port = snd_seq_create_simple_port(m_seq, "Wejście nut",
                                        SND_SEQ_PORT_CAP_WRITE | SND_SEQ_PORT_CAP_SUBS_WRITE,
                                        SND_SEQ_PORT_TYPE_MIDI_GENERIC | SND_SEQ_PORT_TYPE_APPLICATION);
    // Zapowiedzi systemu (nowe urządzenia) — żeby podłączyć klawiaturę wpiętą później
    snd_seq_connect_from(m_seq, m_port, SND_SEQ_CLIENT_SYSTEM, SND_SEQ_PORT_SYSTEM_ANNOUNCE);
    connectAll();

    struct pollfd pfd;
    if (snd_seq_poll_descriptors(m_seq, &pfd, 1, POLLIN) == 1) {
        m_notifier = std::make_unique<QSocketNotifier>(pfd.fd, QSocketNotifier::Read);
        connect(m_notifier.get(), &QSocketNotifier::activated, this, &MidiInput::read);
    }
}

MidiInput::~MidiInput()
{
    m_notifier.reset();
    if (m_seq)
        snd_seq_close(m_seq);
}

// Podłącza wszystkie porty, z których da się czytać nuty (klawiatury, kontrolery) — poza systemowymi i własnym
void MidiInput::connectAll()
{
    QStringList devices;
    snd_seq_client_info_t *ci;
    snd_seq_port_info_t *pi;
    snd_seq_client_info_alloca(&ci);
    snd_seq_port_info_alloca(&pi);
    snd_seq_client_info_set_client(ci, -1);
    const int self = snd_seq_client_id(m_seq);
    while (snd_seq_query_next_client(m_seq, ci) >= 0) {
        const int client = snd_seq_client_info_get_client(ci);
        if (client == SND_SEQ_CLIENT_SYSTEM || client == self)
            continue;
        snd_seq_port_info_set_client(pi, client);
        snd_seq_port_info_set_port(pi, -1);
        while (snd_seq_query_next_port(m_seq, pi) >= 0) {
            const unsigned caps = snd_seq_port_info_get_capability(pi);
            const unsigned type = snd_seq_port_info_get_type(pi);
            if ((caps & (SND_SEQ_PORT_CAP_READ | SND_SEQ_PORT_CAP_SUBS_READ)) != (SND_SEQ_PORT_CAP_READ | SND_SEQ_PORT_CAP_SUBS_READ))
                continue;
            if (caps & SND_SEQ_PORT_CAP_NO_EXPORT)
                continue;
            // „Midi Through” to nie klawiatura
            const QString name = QString::fromUtf8(snd_seq_client_info_get_name(ci));
            if (name.contains(QLatin1String("Midi Through")) || !(type & SND_SEQ_PORT_TYPE_MIDI_GENERIC))
                continue;
            connectPort(client, snd_seq_port_info_get_port(pi));
            if (!devices.contains(name))
                devices << name;
        }
    }
    if (devices != m_devices) {
        m_devices = devices;
        emit devicesChanged();
    }
}

void MidiInput::connectPort(int client, int port)
{
    snd_seq_connect_from(m_seq, m_port, client, port);     // już podłączony — ALSA zwraca błąd, nic nie szkodzi
}

void MidiInput::read()
{
    snd_seq_event_t *ev = nullptr;
    bool rescan = false;
    while (snd_seq_event_input(m_seq, &ev) >= 0 && ev) {
        switch (ev->type) {
        case SND_SEQ_EVENT_NOTEON:
            if (ev->data.note.velocity > 0)
                emit noteOn(ev->data.note.note, ev->data.note.velocity);
            else
                emit noteOff(ev->data.note.note);       // wiele klawiatur wysyła „noteon z siłą 0” zamiast noteoff
            break;
        case SND_SEQ_EVENT_NOTEOFF:
            emit noteOff(ev->data.note.note);
            break;
        case SND_SEQ_EVENT_PORT_START:
        case SND_SEQ_EVENT_PORT_EXIT:
        case SND_SEQ_EVENT_CLIENT_START:
        case SND_SEQ_EVENT_CLIENT_EXIT:
            rescan = true;
            break;
        default:
            break;
        }
        if (snd_seq_event_input_pending(m_seq, 0) <= 0)
            break;
    }
    if (rescan)
        connectAll();
}
