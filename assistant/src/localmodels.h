#pragma once

#include <QElapsedTimer>
#include <QFile>
#include <QJsonObject>
#include <QNetworkAccessManager>
#include <QObject>
#include <QPointer>
#include <QTimer>
#include <functional>

class QNetworkReply;

// Modele na tym komputerze: katalog (Gemma 3 1B / 4B / 12B w GGUF), dobór do sprzętu, pobieranie
// (ze wznawianiem), wybór i usuwanie, a także llama-server uruchamiany dopiero przy pytaniu.
//
// llama-server działa jako usługa użytkownika aster-llama.service (assistant/aster-llama.service), która czyta
// ~/.config/aster/llama.env (model i parametry — pisze je ta klasa) oraz opcjonalny llama-local.env (ręczne
// nadpisania, np. inna ścieżka do llama-server). Nie startuje z sesją: ensureRunning() włącza ją przed pytaniem,
// stop() wyłącza, gdy usługa asystenta kończy pracę — model nie zajmuje pamięci, kiedy nikt nie pyta.
class LocalModels : public QObject
{
    Q_OBJECT
public:
    struct Model {
        QString id;
        QString name;
        QString description;
        QString url;
        qint64 size = 0;      // bajty
        int minRam = 0;       // GB — mniej: nie pozwalamy pobrać
        int goodRam = 0;      // GB i rdzenie, od których polecamy
        int goodCores = 0;
    };
    struct Hardware {
        int ramGb = 0;
        int cores = 0;
        QString cpu;
        qint64 freeDisk = 0;  // bajty w katalogu modeli
    };

    explicit LocalModels(QObject *parent = nullptr);

    static QList<Model> catalog();
    static Model find(const QString &id);
    static Hardware hardware();
    static QString recommended(const Hardware &hw);
    static QString modelsDir();
    static QString path(const Model &m);
    static bool installed(const Model &m);

    QString active() const;              // pusty — nic nie wybrano
    QString downloading() const { return m_downloadId; }
    bool busy() const { return !m_downloadId.isEmpty(); }
    QJsonObject toJson() const;

    bool download(const QString &id, QString *error);
    void cancelDownload();
    bool remove(const QString &id);
    bool use(const QString &id);

    // Przed pytaniem do modelu lokalnego: llama-server odpowiada → ready(true); trzeba go włączyć → włącza
    // i czeka, aż wczyta model; nie da się (brak modelu albo programu) → ready(false, powód)
    void ensureRunning(const std::function<void(bool ok, const QString &problem)> &ready);
    void stop();

Q_SIGNALS:
    void changed();
    void progress(const QString &id, qint64 received, qint64 total);
    void finished(const QString &id, bool ok, const QString &message);

private:
    void writeEnv(const Model &m);
    void systemd(const QString &method, const QString &unit);
    void pollHealth(int attempt, const std::function<void(bool, const QString &)> &ready);
    void onDownloadData();
    void onDownloadDone();

    QNetworkAccessManager m_net;
    QPointer<QNetworkReply> m_reply;
    QFile m_file;
    QString m_downloadId;
    qint64 m_offset = 0;            // wznowienie: tyle było już w pliku .part
    QElapsedTimer m_lastProgress;
    bool m_started = false;         // to my włączyliśmy llama-server — wyłączymy go przy końcu
    bool m_cancelled = false;       // przerwał użytkownik (bez ponawiania)
    int m_retries = 0;              // zerwane połączenie: wznawiamy sami, do 5 razy
};
