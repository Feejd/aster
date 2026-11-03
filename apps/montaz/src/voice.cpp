#include "voice.h"

#include <QAudioSource>
#include <QDateTime>
#include <QDir>
#include <QFileInfo>
#include <QtEndian>
#include <QtMath>

VoiceRecorder::VoiceRecorder(QObject *parent)
    : QObject(parent)
{
    m_fakePath = qEnvironmentVariable("ASTER_MONTAZ_FAKE_MIC");
    connect(&m_devices, &QMediaDevices::audioInputsChanged, this, &VoiceRecorder::devicesChanged);
    m_fake.setInterval(50);
    connect(&m_fake, &QTimer::timeout, this, [this] {
        // Udawany poziom głośności (mowa: „falujący” szczyt)
        m_level = 0.35 + 0.3 * std::abs(std::sin(m_clock.elapsed() / 180.0));
        Q_EMIT levelChanged();
    });
}

VoiceRecorder::~VoiceRecorder()
{
    cancel();
    closeSource();
}

bool VoiceRecorder::available() const
{
    return !m_fakePath.isEmpty() || !QMediaDevices::audioInputs().isEmpty();
}

QString VoiceRecorder::device() const
{
    if (!m_fakePath.isEmpty())
        return QStringLiteral("Mikrofon testowy (plik)");
    const QAudioDevice d = QMediaDevices::defaultAudioInput();
    return d.isNull() ? QString() : d.description();
}

double VoiceRecorder::seconds() const
{
    return m_recording ? m_clock.elapsed() / 1000.0 : 0;
}

void VoiceRecorder::openSource()
{
    if (m_source || m_fake.isActive())
        return;
    m_error.clear();
    if (!m_fakePath.isEmpty()) {
        m_clock.start();
        m_fake.start();
        return;
    }
    const QAudioDevice dev = QMediaDevices::defaultAudioInput();
    if (dev.isNull()) {
        m_error = QStringLiteral("Nie znaleziono mikrofonu. Podłącz go i spróbuj ponownie.");
        return;
    }
    // Mowa: 48 kHz, mono, 16 bitów — a gdy mikrofon tego nie umie, to, co lubi
    QAudioFormat f;
    f.setSampleRate(48000);
    f.setChannelCount(1);
    f.setSampleFormat(QAudioFormat::Int16);
    if (!dev.isFormatSupported(f))
        f = dev.preferredFormat();
    if (f.sampleFormat() != QAudioFormat::Int16 && f.sampleFormat() != QAudioFormat::Float)
        f.setSampleFormat(QAudioFormat::Int16);
    m_format = f;
    m_source = new QAudioSource(dev, f, this);
    m_io = m_source->start();
    if (!m_io) {
        m_error = QStringLiteral("Nie udało się włączyć mikrofonu.");
        closeSource();
        return;
    }
    connect(m_io, &QIODevice::readyRead, this, &VoiceRecorder::read);
}

void VoiceRecorder::closeSource()
{
    m_fake.stop();
    if (m_source) {
        m_source->stop();
        m_source->deleteLater();
    }
    m_source = nullptr;
    m_io = nullptr;
    m_level = 0;
    Q_EMIT levelChanged();
}

void VoiceRecorder::listen(bool on)
{
    if (on == m_listening)
        return;
    m_listening = on;
    if (on)
        openSource();
    else if (!m_recording)
        closeSource();
    Q_EMIT stateChanged();
}

void VoiceRecorder::read()
{
    const QByteArray data = m_io->readAll();
    if (data.isEmpty())
        return;
    float peak = 0;
    if (m_format.sampleFormat() == QAudioFormat::Float) {
        const auto *s = reinterpret_cast<const float *>(data.constData());
        for (qsizetype i = 0; i < data.size() / qsizetype(sizeof(float)); ++i)
            peak = qMax(peak, std::abs(s[i]));
    } else {
        const auto *s = reinterpret_cast<const qint16 *>(data.constData());
        for (qsizetype i = 0; i < data.size() / 2; ++i)
            peak = qMax(peak, std::abs(s[i]) / 32768.0f);
    }
    // Wskaźnik opada łagodnie, rośnie od razu
    m_level = qMax(double(peak), m_level * 0.85);
    Q_EMIT levelChanged();
    if (m_recording && m_file.isOpen()) {
        m_file.write(data);
        m_bytes += data.size();
    }
}

void VoiceRecorder::writeHeader()
{
    // Nagłówek WAV (PCM 16 bit albo float 32 bit), rozmiary uzupełniane po zakończeniu
    const quint16 channels = quint16(m_format.channelCount());
    const quint32 rate = quint32(m_format.sampleRate());
    const quint16 bits = m_format.sampleFormat() == QAudioFormat::Float ? 32 : 16;
    const quint16 tag = m_format.sampleFormat() == QAudioFormat::Float ? 3 : 1;
    QByteArray h;
    auto u32 = [&h](quint32 v) { char b[4]; qToLittleEndian(v, b); h.append(b, 4); };
    auto u16 = [&h](quint16 v) { char b[2]; qToLittleEndian(v, b); h.append(b, 2); };
    h += "RIFF";
    u32(quint32(36 + m_bytes));
    h += "WAVEfmt ";
    u32(16);
    u16(tag);
    u16(channels);
    u32(rate);
    u32(rate * channels * bits / 8);
    u16(channels * bits / 8);
    u16(bits);
    h += "data";
    u32(quint32(m_bytes));
    m_file.seek(0);
    m_file.write(h);
}

bool VoiceRecorder::start(const QString &dir)
{
    if (m_recording)
        return false;
    openSource();
    if (!m_source && !m_fake.isActive()) {
        Q_EMIT stateChanged();
        return false;
    }
    QDir().mkpath(dir);
    m_file.setFileName(dir + QStringLiteral("/lektor-%1.wav").arg(QDateTime::currentDateTime().toString(QStringLiteral("yyyyMMdd-HHmmss"))));
    if (m_fakePath.isEmpty()) {
        if (!m_file.open(QIODevice::WriteOnly)) {
            m_error = QStringLiteral("Nie można zapisać nagrania w %1").arg(dir);
            Q_EMIT stateChanged();
            return false;
        }
        m_bytes = 0;
        writeHeader();
    }
    m_recording = true;
    m_clock.start();
    Q_EMIT stateChanged();
    return true;
}

QString VoiceRecorder::stop()
{
    if (!m_recording)
        return QString();
    m_recording = false;
    QString path = m_file.fileName();
    if (!m_fakePath.isEmpty()) {
        QFile::remove(path);
        if (!QFile::copy(m_fakePath, path))
            path.clear();
    } else {
        read();                       // resztka z bufora
        writeHeader();
        m_file.close();
        if (m_bytes < 4800) {         // krócej niż ok. 0,05 s — nic się nie nagrało
            QFile::remove(path);
            path.clear();
            m_error = QStringLiteral("Nagranie jest puste — sprawdź, czy mikrofon nie jest wyciszony.");
        }
    }
    if (!m_listening)
        closeSource();
    Q_EMIT stateChanged();
    return path;
}

void VoiceRecorder::cancel()
{
    if (!m_recording)
        return;
    m_recording = false;
    if (m_file.isOpen())
        m_file.close();
    m_file.remove();
    Q_EMIT stateChanged();
}
