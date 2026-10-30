#include "flatpak.h"

#include <QRegularExpression>
#include <QStandardPaths>

static const QString remoteUrl = QStringLiteral("https://dl.flathub.org/repo/flathub.flatpakrepo");

Flatpak::Flatpak(QObject *parent)
    : QObject(parent)
{
    refresh();
}

bool Flatpak::available() const
{
    return !QStandardPaths::findExecutable(QStringLiteral("flatpak")).isEmpty();
}

void Flatpak::refresh()
{
    if (!available())
        return;
    // Zainstalowane programy (z obu miejsc: użytkownika i systemu)
    auto *list = new QProcess(this);
    connect(list, &QProcess::finished, this, [this, list] {
        QStringList ids = QString::fromUtf8(list->readAllStandardOutput()).split(QLatin1Char('\n'), Qt::SkipEmptyParts);
        for (QString &id : ids)
            id = id.trimmed();
        ids.removeDuplicates();
        if (ids != m_installed) {
            m_installed = ids;
            Q_EMIT installedChanged();
        }
        list->deleteLater();
    });
    list->start(QStringLiteral("flatpak"), {QStringLiteral("list"), QStringLiteral("--app"), QStringLiteral("--columns=application")});

    // Dostępne aktualizacje
    auto *upd = new QProcess(this);
    connect(upd, &QProcess::finished, this, [this, upd] {
        QStringList ids = QString::fromUtf8(upd->readAllStandardOutput()).split(QLatin1Char('\n'), Qt::SkipEmptyParts);
        for (QString &id : ids)
            id = id.trimmed();
        if (ids != m_updates) {
            m_updates = ids;
            Q_EMIT updatesChanged();
        }
        upd->deleteLater();
    });
    upd->start(QStringLiteral("flatpak"), {QStringLiteral("remote-ls"), QStringLiteral("--updates"), QStringLiteral("--app"),
                                           QStringLiteral("--columns=application")});
}

void Flatpak::install(const QString &appId) { enqueue(QStringLiteral("install"), appId); }
void Flatpak::uninstall(const QString &appId) { enqueue(QStringLiteral("uninstall"), appId); }
void Flatpak::updateAll() { enqueue(QStringLiteral("update"), QString()); }

void Flatpak::launch(const QString &appId)
{
    QProcess::startDetached(QStringLiteral("flatpak"), {QStringLiteral("run"), appId});
}

void Flatpak::setProgress(const QString &appId, double value)
{
    if (appId.isEmpty())
        return;
    if (value < -1.5)
        m_progress.remove(appId);
    else
        m_progress.insert(appId, value);
    Q_EMIT progressChanged();
}

void Flatpak::enqueue(const QString &action, const QString &appId)
{
    for (const Job &j : std::as_const(m_queue))
        if (j.action == action && j.appId == appId)
            return;
    if (m_proc && m_current.action == action && m_current.appId == appId)
        return;
    m_queue.append({action, appId});
    setProgress(appId, -1);
    if (!m_proc)
        startNext();
}

void Flatpak::startNext()
{
    if (m_queue.isEmpty())
        return;
    m_current = m_queue.takeFirst();
    m_lastError.clear();
    setProgress(m_current.appId, 0);

    QStringList args;
    if (m_current.action == QLatin1String("install"))
        args = {QStringLiteral("install"), QStringLiteral("--user"), QStringLiteral("-y"), QStringLiteral("--noninteractive"),
                QStringLiteral("flathub"), m_current.appId};
    else if (m_current.action == QLatin1String("uninstall"))
        args = {QStringLiteral("uninstall"), QStringLiteral("-y"), QStringLiteral("--noninteractive"), m_current.appId};
    else
        args = {QStringLiteral("update"), QStringLiteral("--user"), QStringLiteral("-y"), QStringLiteral("--noninteractive")};

    // Flathub dodajemy do konta użytkownika przy pierwszej instalacji (nic się nie dzieje, gdy już jest)
    if (m_current.action == QLatin1String("install"))
        QProcess::execute(QStringLiteral("flatpak"), {QStringLiteral("remote-add"), QStringLiteral("--user"), QStringLiteral("--if-not-exists"),
                                                      QStringLiteral("flathub"), remoteUrl});

    m_proc = new QProcess(this);
    m_proc->setProcessChannelMode(QProcess::MergedChannels);
    connect(m_proc, &QProcess::readyRead, this, [this] { parseOutput(m_proc->readAll()); });
    connect(m_proc, &QProcess::finished, this, [this](int code, QProcess::ExitStatus status) {
        const bool ok = status == QProcess::NormalExit && code == 0;
        const Job job = m_current;
        m_proc->deleteLater();
        m_proc = nullptr;
        setProgress(job.appId, -2);
        Q_EMIT finished(job.appId, job.action, ok, ok ? QString() : (m_lastError.isEmpty() ? QStringLiteral("Nie udało się.") : m_lastError));
        // Nowe programy od razu w Starcie
        if (ok)
            QProcess::startDetached(QStringLiteral("kbuildsycoca6"), {});
        refresh();
        startNext();
    });
    m_proc->start(QStringLiteral("flatpak"), args);
}

void Flatpak::parseOutput(const QByteArray &chunk)
{
    // Linie typu „Installing 2/3… ███▌ 45%  3,1 MB/s” (odświeżane przez \r)
    const QString text = QString::fromUtf8(chunk);
    static const QRegularExpression stepRe(QStringLiteral("(\\d+)/(\\d+)"));
    static const QRegularExpression pctRe(QStringLiteral("(\\d{1,3})%"));
    static const QRegularExpression errRe(QStringLiteral("(?:error|Error|błąd|Błąd):\\s*(.+)"));
    for (const QString &line : text.split(QRegularExpression(QStringLiteral("[\\r\\n]")), Qt::SkipEmptyParts)) {
        const auto e = errRe.match(line);
        if (e.hasMatch())
            m_lastError = e.captured(1).trimmed();
        auto pm = pctRe.globalMatch(line);
        int pct = -1;
        while (pm.hasNext())
            pct = pm.next().captured(1).toInt();
        if (pct < 0)
            continue;
        double value = pct / 100.0;
        const auto s = stepRe.match(line);
        if (s.hasMatch() && s.captured(2).toInt() > 0) {
            const int step = s.captured(1).toInt(), steps = s.captured(2).toInt();
            value = (step - 1 + value) / steps;
        }
        setProgress(m_current.appId.isEmpty() ? QStringLiteral("*") : m_current.appId, qBound(0.0, value, 1.0));
    }
}
