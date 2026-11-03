#pragma once

#include <QAtomicInt>
#include <QObject>
#include <QPointer>
#include <QQmlEngine>
#include <QVariantList>

class QFile;
class QNetworkAccessManager;
class QNetworkReply;

// Napisy z mowy: dźwięk klipów z osi czasu → whisper.cpp (offline, na procesorze) → krótkie napisy
// na ścieżce tekstu. Model (ggml) pobiera się raz, przy pierwszym użyciu, do ~/.local/share/Aster/aster-montaz/models.
class Captions : public QObject
{
    Q_OBJECT
    QML_ELEMENT
    QML_SINGLETON
    Q_PROPERTY(bool available READ available CONSTANT)                 // program zbudowany z whisper.cpp
    Q_PROPERTY(QVariantList models READ models NOTIFY modelsChanged)
    Q_PROPERTY(QString state READ state NOTIFY stateChanged)           // "", "downloading", "listening", "done"
    Q_PROPERTY(double progress READ progress NOTIFY progressChanged)
    Q_PROPERTY(QString error READ error NOTIFY stateChanged)
    Q_PROPERTY(int added READ added NOTIFY stateChanged)

public:
    explicit Captions(QObject *parent = nullptr);
    ~Captions() override;

    bool available() const;
    QVariantList models() const;
    QString state() const { return m_state; }
    double progress() const { return m_progress; }
    QString error() const { return m_error; }
    int added() const { return m_added; }

    // model: "base" / "small"; language: "pl", "en", "auto"; style: id stylu napisów
    Q_INVOKABLE void start(const QString &model, const QString &language, const QString &style);
    Q_INVOKABLE void cancel();
    Q_INVOKABLE void reset();

Q_SIGNALS:
    void modelsChanged();
    void stateChanged();
    void progressChanged();

private:
    QString m_state, m_error;
    double m_progress = 0;
    int m_added = 0;
    QAtomicInt m_abort;
    QNetworkAccessManager *m_net = nullptr;
    QPointer<QNetworkReply> m_reply;
    QFile *m_file = nullptr;
    QString m_language, m_style, m_model;

    QString modelsDir() const;
    QString modelPath(const QString &model) const;
    void setState(const QString &state, const QString &error = QString());
    void download(const QString &model);
    void transcribe();
};
