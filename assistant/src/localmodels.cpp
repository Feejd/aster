#include "localmodels.h"

#include <QDBusConnection>
#include <QDBusMessage>
#include <QDBusPendingCallWatcher>
#include <QDir>
#include <QFileInfo>
#include <QJsonArray>
#include <QNetworkReply>
#include <QSaveFile>
#include <QSettings>
#include <QStandardPaths>
#include <QStorageInfo>
#include <QSysInfo>
#include <QThread>

static const char *kHealth = "http://127.0.0.1:8080/health";
static const QString kUnit = QStringLiteral("aster-llama.service");

static QSettings config()
{
    return QSettings(QStandardPaths::writableLocation(QStandardPaths::GenericConfigLocation) + QStringLiteral("/aster/asystent.conf"),
                     QSettings::IniFormat);
}

LocalModels::LocalModels(QObject *parent)
    : QObject(parent)
{
}

// Gemma 3 (Google) w kwantyzacji Q4_K_M od ggml-org — dobrze mówi po polsku, a 1B mieści się nawet na słabym sprzęcie
QList<LocalModels::Model> LocalModels::catalog()
{
    static const QString hf = QStringLiteral("https://huggingface.co/ggml-org/%1-GGUF/resolve/main/%1-Q4_K_M.gguf");
    return {
        {QStringLiteral("gemma-3-1b"), QStringLiteral("Gemma 3 1B"),
         QStringLiteral("Lekki i szybki — na komputery z 4–8 GB pamięci"),
         hf.arg(QStringLiteral("gemma-3-1b-it")), 806058240, 4, 0, 0},
        {QStringLiteral("gemma-3-4b"), QStringLiteral("Gemma 3 4B"),
         QStringLiteral("Mądrzejszy — płynnie od 12 GB pamięci i 6 rdzeni"),
         hf.arg(QStringLiteral("gemma-3-4b-it")), 2489757856, 8, 12, 6},
        {QStringLiteral("gemma-3-12b"), QStringLiteral("Gemma 3 12B"),
         QStringLiteral("Najmądrzejszy — dla mocnych komputerów (32 GB, 8 rdzeni)"),
         hf.arg(QStringLiteral("gemma-3-12b-it")), 7300574976, 16, 32, 8},
    };
}

LocalModels::Model LocalModels::find(const QString &id)
{
    for (const Model &m : catalog())
        if (m.id == id)
            return m;
    return {};
}

LocalModels::Hardware LocalModels::hardware()
{
    Hardware hw;
    QFile mem(QStringLiteral("/proc/meminfo"));
    if (mem.open(QIODevice::ReadOnly)) {
        for (const QByteArray &line : mem.readAll().split('\n'))
            if (line.startsWith("MemTotal:")) {
                // kB → GB, z zaokrągleniem w górę (8 GB RAM to w MemTotal ok. 7,6 GB)
                const double kb = line.mid(9).trimmed().split(' ').value(0).toDouble();
                hw.ramGb = int(kb / 1024.0 / 1024.0 + 0.7);
            }
    }
    hw.cores = QThread::idealThreadCount();
    QFile cpu(QStringLiteral("/proc/cpuinfo"));
    if (cpu.open(QIODevice::ReadOnly))
        for (const QByteArray &line : cpu.readAll().split('\n'))
            if (line.startsWith("model name")) {
                hw.cpu = QString::fromUtf8(line.mid(line.indexOf(':') + 1)).simplified();
                break;
            }
    if (hw.cpu.isEmpty())
        hw.cpu = QSysInfo::currentCpuArchitecture();
    QDir().mkpath(modelsDir());
    hw.freeDisk = QStorageInfo(modelsDir()).bytesAvailable();
    return hw;
}

QString LocalModels::recommended(const Hardware &hw)
{
    QString best = catalog().first().id;
    for (const Model &m : catalog())
        if (hw.ramGb >= m.goodRam && hw.cores >= m.goodCores)
            best = m.id;
    return best;
}

QString LocalModels::modelsDir()
{
    return QStandardPaths::writableLocation(QStandardPaths::GenericDataLocation) + QStringLiteral("/aster/modele");
}

QString LocalModels::path(const Model &m)
{
    return modelsDir() + QLatin1Char('/') + QUrl(m.url).fileName();
}

bool LocalModels::installed(const Model &m)
{
    const QFileInfo fi(path(m));
    return fi.exists() && fi.size() == m.size;
}

QString LocalModels::active() const
{
    const QString id = config().value(QStringLiteral("lokalny/active")).toString();
    return installed(find(id)) ? id : QString();
}

QJsonObject LocalModels::toJson() const
{
    const Hardware hw = hardware();
    const QString rec = recommended(hw);
    const QString act = active();
    QJsonArray models;
    for (const Model &m : catalog()) {
        const QFileInfo part(path(m) + QStringLiteral(".part"));
        models.append(QJsonObject{
            {QStringLiteral("id"), m.id}, {QStringLiteral("name"), m.name}, {QStringLiteral("description"), m.description},
            {QStringLiteral("size"), m.size}, {QStringLiteral("minRam"), m.minRam}, {QStringLiteral("installed"), installed(m)},
            {QStringLiteral("active"), m.id == act}, {QStringLiteral("recommended"), m.id == rec},
            {QStringLiteral("fits"), hw.ramGb >= m.minRam}, {QStringLiteral("partial"), part.exists() ? part.size() : 0},
        });
    }
    return {
        {QStringLiteral("hardware"), QJsonObject{{QStringLiteral("ramGb"), hw.ramGb}, {QStringLiteral("cores"), hw.cores},
                                                 {QStringLiteral("cpu"), hw.cpu}, {QStringLiteral("freeDisk"), hw.freeDisk}}},
        {QStringLiteral("recommended"), rec},
        {QStringLiteral("active"), act},
        {QStringLiteral("downloading"), m_downloadId},
        {QStringLiteral("models"), models},
    };
}

// ——— Pobieranie (wznawiane od miejsca przerwania: plik .part i nagłówek Range) ———

bool LocalModels::download(const QString &id, QString *error)
{
    const Model m = find(id);
    if (m.id.isEmpty()) {
        *error = QStringLiteral("Nie ma takiego modelu");
        return false;
    }
    if (!m_downloadId.isEmpty()) {
        *error = m_downloadId == id ? QString() : QStringLiteral("Trwa już pobieranie innego modelu");
        return m_downloadId == id;
    }
    if (installed(m)) {
        Q_EMIT finished(id, true, QString());
        return true;
    }
    const Hardware hw = hardware();
    if (hw.ramGb < m.minRam) {
        *error = QStringLiteral("%1 potrzebuje co najmniej %2 GB pamięci, a ten komputer ma %3 GB").arg(m.name).arg(m.minRam).arg(hw.ramGb);
        return false;
    }
    QDir().mkpath(modelsDir());
    m_file.setFileName(path(m) + QStringLiteral(".part"));
    if (!m_file.open(QIODevice::ReadWrite | QIODevice::Append)) {
        *error = QStringLiteral("Nie mogę zapisać w %1").arg(modelsDir());
        return false;
    }
    m_offset = m_file.size();
    if (hw.freeDisk < m.size - m_offset + 200 * 1024 * 1024) {
        m_file.close();
        *error = QStringLiteral("Za mało miejsca na dysku: potrzeba %1 GB").arg(double(m.size - m_offset) / 1e9, 0, 'f', 1);
        return false;
    }
    QNetworkRequest req{QUrl(m.url)};
    req.setRawHeader("User-Agent", "aster-assistant/0.1");
    req.setAttribute(QNetworkRequest::RedirectPolicyAttribute, QNetworkRequest::NoLessSafeRedirectPolicy);
    // HTTP/1.1: przy długim pobieraniu CDN potrafi zamknąć strumień HTTP/2 po kilku minutach
    req.setAttribute(QNetworkRequest::Http2AllowedAttribute, false);
    if (m_offset > 0)
        req.setRawHeader("Range", "bytes=" + QByteArray::number(m_offset) + '-');
    m_downloadId = id;
    m_cancelled = false;
    m_reply = m_net.get(req);
    m_lastProgress.start();
    connect(m_reply, &QNetworkReply::readyRead, this, &LocalModels::onDownloadData);
    connect(m_reply, &QNetworkReply::finished, this, &LocalModels::onDownloadDone);
    Q_EMIT changed();
    Q_EMIT progress(id, m_offset, m.size);
    return true;
}

void LocalModels::onDownloadData()
{
    if (!m_reply)
        return;
    // Serwer nie wznowił (200 zamiast 206) — zaczynamy od zera
    const int status = m_reply->attribute(QNetworkRequest::HttpStatusCodeAttribute).toInt();
    if (m_offset > 0 && status == 200) {
        m_file.resize(0);
        m_offset = 0;
    }
    if (status >= 400)
        return;
    m_file.write(m_reply->readAll());
    if (m_lastProgress.elapsed() > 400) {
        m_lastProgress.restart();
        Q_EMIT progress(m_downloadId, m_file.size(), find(m_downloadId).size);
    }
}

void LocalModels::onDownloadDone()
{
    if (!m_reply)
        return;
    onDownloadData();
    QNetworkReply *r = m_reply;
    r->deleteLater();
    m_reply = nullptr;
    const QString id = m_downloadId;
    m_downloadId.clear();
    const Model m = find(id);
    m_file.close();
    const int status = r->attribute(QNetworkRequest::HttpStatusCodeAttribute).toInt();
    QString problem;
    // Zerwane połączenie (nie przez użytkownika): wznawiamy od miejsca, w którym stanęło
    if (!m_cancelled && status < 400 && r->error() != QNetworkReply::NoError && m_retries < 5) {
        ++m_retries;
        QTimer::singleShot(2000 * m_retries, this, [this, id] {
            QString error;
            if (!download(id, &error)) {
                m_retries = 0;
                Q_EMIT finished(id, false, error);
                Q_EMIT changed();
            }
        });
        return;
    }
    m_retries = 0;
    if (m_cancelled)
        problem = QStringLiteral("Przerwano — następnym razem pobieranie ruszy od tego miejsca");
    else if (status >= 400 || r->error() != QNetworkReply::NoError)
        problem = QStringLiteral("Nie udało się pobrać modelu (%1)").arg(status >= 400 ? QString::number(status) : r->errorString());
    else if (QFileInfo(m_file.fileName()).size() != m.size) {
        problem = QStringLiteral("Plik modelu jest niekompletny — spróbuj jeszcze raz");
        if (QFileInfo(m_file.fileName()).size() > m.size)
            QFile::remove(m_file.fileName());
    } else {
        QFile::remove(path(m));
        QFile::rename(m_file.fileName(), path(m));
        if (active().isEmpty())
            use(id);    // pierwszy pobrany model od razu w użyciu
    }
    Q_EMIT progress(id, QFileInfo(problem.isEmpty() ? path(m) : m_file.fileName()).size(), m.size);
    Q_EMIT finished(id, problem.isEmpty(), problem);
    Q_EMIT changed();
}

void LocalModels::cancelDownload()
{
    m_cancelled = true;
    if (m_reply)
        m_reply->abort();
}

bool LocalModels::remove(const QString &id)
{
    const Model m = find(id);
    if (m.id.isEmpty() || id == m_downloadId)
        return false;
    if (active() == id) {
        systemd(QStringLiteral("StopUnit"), kUnit);
        m_started = false;
        QSettings c = config();
        c.remove(QStringLiteral("lokalny/active"));
    }
    QFile::remove(path(m));
    QFile::remove(path(m) + QStringLiteral(".part"));
    Q_EMIT changed();
    return true;
}

bool LocalModels::use(const QString &id)
{
    const Model m = find(id);
    if (!installed(m))
        return false;
    QSettings c = config();
    c.setValue(QStringLiteral("lokalny/active"), id);
    c.sync();
    writeEnv(m);
    // Następne pytanie włączy llama-server już z nowym modelem
    systemd(QStringLiteral("StopUnit"), kUnit);
    m_started = false;
    Q_EMIT changed();
    return true;
}

// Parametry llama-server dobrane do sprzętu: wątki = rdzenie (bez jednego, gdy jest ich dużo — zostaje
// na pulpit), kontekst 4096 przy ≤ 8 GB pamięci (agent mieści wyniki poleceń), inaczej 8192
void LocalModels::writeEnv(const Model &m)
{
    const Hardware hw = hardware();
    const int threads = hw.cores > 4 ? hw.cores - 1 : std::max(1, hw.cores);
    const int ctx = hw.ramGb <= 8 ? 4096 : 8192;
    const QString dir = QStandardPaths::writableLocation(QStandardPaths::GenericConfigLocation) + QStringLiteral("/aster");
    QDir().mkpath(dir);
    QSaveFile f(dir + QStringLiteral("/llama.env"));
    if (!f.open(QIODevice::WriteOnly))
        return;
    f.write(QStringLiteral("# Zapisuje Aster Intelligence (Ustawienia → Aster Intelligence → Model na tym komputerze)\n"
                           "LLAMA_MODEL=%1\nLLAMA_ARGS=-c %2 -t %3 --jinja --alias %4\n")
                .arg(path(m)).arg(ctx).arg(threads).arg(m.id).toUtf8());
    f.commit();
}

// ——— llama-server na żądanie ———

void LocalModels::systemd(const QString &method, const QString &unit)
{
    QDBusMessage msg = QDBusMessage::createMethodCall(QStringLiteral("org.freedesktop.systemd1"), QStringLiteral("/org/freedesktop/systemd1"),
                                                      QStringLiteral("org.freedesktop.systemd1.Manager"), method);
    msg.setArguments({unit, QStringLiteral("replace")});
    // Zatrzymanie czeka na odpowiedź — usługa asystenta zaraz po nim może się zakończyć
    if (method == QLatin1String("StopUnit"))
        QDBusConnection::sessionBus().call(msg, QDBus::Block, 3000);
    else
        QDBusConnection::sessionBus().asyncCall(msg);
}

void LocalModels::stop()
{
    if (m_started) {
        systemd(QStringLiteral("StopUnit"), kUnit);
        m_started = false;
    }
}

void LocalModels::ensureRunning(const std::function<void(bool, const QString &)> &ready)
{
    QNetworkRequest req{QUrl(QString::fromLatin1(kHealth))};
    req.setTransferTimeout(2000);
    QNetworkReply *r = m_net.get(req);
    connect(r, &QNetworkReply::finished, this, [this, r, ready] {
        r->deleteLater();
        const int status = r->attribute(QNetworkRequest::HttpStatusCodeAttribute).toInt();
        if (status == 200)
            return ready(true, QString());
        if (status == 503)                      // już się wczytuje
            return pollHealth(0, ready);
        // Nic nie słucha: włączamy llama-server z wybranym modelem
        const QString act = active();
        if (act.isEmpty())
            return ready(false, QStringLiteral("Nie ma jeszcze modelu na tym komputerze — pobierz go w Ustawieniach → Aster Intelligence "
                                               "albo poleceniem: aster --model-lokalny auto"));
        writeEnv(find(act));
        QDBusMessage msg = QDBusMessage::createMethodCall(QStringLiteral("org.freedesktop.systemd1"), QStringLiteral("/org/freedesktop/systemd1"),
                                                          QStringLiteral("org.freedesktop.systemd1.Manager"), QStringLiteral("StartUnit"));
        msg.setArguments({kUnit, QStringLiteral("replace")});
        auto *w = new QDBusPendingCallWatcher(QDBusConnection::sessionBus().asyncCall(msg), this);
        connect(w, &QDBusPendingCallWatcher::finished, this, [this, w, ready] {
            w->deleteLater();
            if (w->isError())
                return ready(false, QStringLiteral("Nie mogę uruchomić modelu lokalnego (%1): %2").arg(kUnit, w->error().message()));
            m_started = true;
            pollHealth(0, ready);
        });
    });
}

// Wczytanie modelu trwa od kilku sekund (1B) do minuty (12B na wolnym dysku)
void LocalModels::pollHealth(int attempt, const std::function<void(bool, const QString &)> &ready)
{
    if (attempt > 240)
        return ready(false, QStringLiteral("Model lokalny nie wystartował — szczegóły: journalctl --user -u aster-llama"));
    QTimer::singleShot(attempt == 0 ? 300 : 500, this, [this, attempt, ready] {
        QNetworkRequest req{QUrl(QString::fromLatin1(kHealth))};
        req.setTransferTimeout(2000);
        QNetworkReply *r = m_net.get(req);
        connect(r, &QNetworkReply::finished, this, [this, r, attempt, ready] {
            r->deleteLater();
            if (r->attribute(QNetworkRequest::HttpStatusCodeAttribute).toInt() == 200)
                return ready(true, QString());
            pollHealth(attempt + 1, ready);
        });
    });
}
