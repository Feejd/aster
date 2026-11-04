#pragma once

#include <QObject>
#include <QSocketNotifier>
#include <QStringList>
#include <memory>

typedef struct _snd_seq snd_seq_t;

// Wejście MIDI przez sekwencer ALSA (PipeWire udostępnia przez niego wszystkie urządzenia MIDI).
// Studio samo podłącza się do każdej klawiatury — także wpiętej w trakcie pracy — i podaje nuty
// do wątku interfejsu (odsłuch i nagrywanie w piano rollu). Bez sekwencera po prostu nic nie robi.
class MidiInput : public QObject
{
    Q_OBJECT
public:
    explicit MidiInput(QObject *parent = nullptr);
    ~MidiInput() override;

    bool available() const { return m_seq != nullptr; }
    QStringList devices() const { return m_devices; }

signals:
    void noteOn(int pitch, int velocity);
    void noteOff(int pitch);
    void devicesChanged();

private:
    void read();
    void connectAll();
    void connectPort(int client, int port);

    snd_seq_t *m_seq = nullptr;
    int m_port = -1;
    std::unique_ptr<QSocketNotifier> m_notifier;
    QStringList m_devices;
};
