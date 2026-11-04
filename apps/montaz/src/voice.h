#pragma once

#include <QAudioFormat>
#include <QElapsedTimer>
#include <QFile>
#include <QMediaDevices>
#include <QObject>
#include <QQmlEngine>
#include <QTimer>

class QAudioSource;
class QIODevice;

// Nagrywanie lektora: mikrofon (QAudioSource) prosto do pliku WAV, z poziomem głośności na żywo.
// Do testów bez karty dźwiękowej: ASTER_MONTAZ_FAKE_MIC=plik.wav — „mikrofon” odtwarza ten plik.
class VoiceRecorder : public QObject
{
    Q_OBJECT
    QML_ELEMENT
    QML_SINGLETON
    Q_PROPERTY(bool available READ available NOTIFY devicesChanged)
    Q_PROPERTY(QString device READ device NOTIFY devicesChanged)
    Q_PROPERTY(bool listening READ listening NOTIFY stateChanged)
    Q_PROPERTY(bool recording READ recording NOTIFY stateChanged)
    Q_PROPERTY(double level READ level NOTIFY levelChanged)          // 0–1 (szczyt z ostatniej chwili)
    Q_PROPERTY(double seconds READ seconds NOTIFY levelChanged)
    Q_PROPERTY(QString error READ error NOTIFY stateChanged)

public:
    explicit VoiceRecorder(QObject *parent = nullptr);
    ~VoiceRecorder() override;

    bool available() const;
    QString device() const;
    bool listening() const { return m_listening; }
    bool recording() const { return m_recording; }
    double level() const { return m_level; }
    double seconds() const;
    QString error() const { return m_error; }

    Q_INVOKABLE void listen(bool on);                 // mikrofon włączony (poziom), jeszcze bez zapisu
    Q_INVOKABLE bool start(const QString &dir);       // zapis do nowego pliku w katalogu
    Q_INVOKABLE QString stop();                       // ścieżka gotowego pliku albo ""
    Q_INVOKABLE void cancel();

Q_SIGNALS:
    void devicesChanged();
    void stateChanged();
    void levelChanged();

private:
    QMediaDevices m_devices;
    QAudioSource *m_source = nullptr;
    QIODevice *m_io = nullptr;
    QAudioFormat m_format;
    QFile m_file;
    qint64 m_bytes = 0;
    bool m_listening = false, m_recording = false;
    double m_level = 0;
    QString m_error;
    QElapsedTimer m_clock;
    QTimer m_fake;                                    // testowy mikrofon z pliku
    QString m_fakePath;

    void read();
    void openSource();
    void closeSource();
    void writeHeader();
};
