#include "updates.h"
#include "util.h"

#include <QDateTime>
#include <QJsonArray>
#include <QJsonDocument>
#include <QJsonObject>
#include <QLocale>

Updates::Updates(QObject *parent)
    : QObject(parent)
{
    if (asterPreview()) {
        m_version = QStringLiteral("44.20261104.0");
        m_installedOn = QStringLiteral("4 listopada 2026");
        m_readyVersion = QStringLiteral("44.20261105.0");
        m_previousVersion = QStringLiteral("44.20261103.0 z 3 listopada, 21:40");
        return;
    }
    refresh();
}

void Updates::refresh()
{
    if (asterPreview())
        return;
    runAsync(this, QStringLiteral("rpm-ostree"), {QStringLiteral("status"), QStringLiteral("--json")}, [this](const QString &out, int) {
        const QJsonArray deployments = QJsonDocument::fromJson(out.toUtf8()).object().value(QLatin1String("deployments")).toArray();
        m_version.clear();
        m_installedOn.clear();
        m_readyVersion.clear();
        m_previousVersion.clear();
        // Kolejne obrazy mogą mieć ten sam numer wersji, dlatego poprzednią pokazujemy z datą
        const auto dated = [](const QJsonObject &d) {
            const auto time = QDateTime::fromSecsSinceEpoch(qint64(d.value(QLatin1String("timestamp")).toDouble()));
            return QStringLiteral("%1 z %2").arg(d.value(QLatin1String("version")).toString(), QLocale(QLocale::Polish).toString(time, QStringLiteral("d MMMM, HH:mm")));
        };
        // Kolejność z rpm-ostree: najpierw system, który wystartuje następnym razem
        bool bootedSeen = false;
        for (int i = 0; i < deployments.size(); ++i) {
            const QJsonObject d = deployments.at(i).toObject();
            const QString version = d.value(QLatin1String("version")).toString();
            if (d.value(QLatin1String("staged")).toBool()) {
                m_readyVersion = version;
            } else if (d.value(QLatin1String("booted")).toBool()) {
                bootedSeen = true;
                m_version = version;
                m_rollbackPending = i > 0 && !deployments.at(0).toObject().value(QLatin1String("staged")).toBool();
                const auto time = QDateTime::fromSecsSinceEpoch(qint64(d.value(QLatin1String("timestamp")).toDouble()));
                m_installedOn = QLocale(QLocale::Polish).toString(time, QStringLiteral("d MMMM yyyy"));
            } else if (bootedSeen || m_previousVersion.isEmpty()) {
                m_previousVersion = dated(d);
            }
        }
        Q_EMIT changed();
    });
}

void Updates::check()
{
    if (asterPreview() || m_checking)
        return;
    m_checking = true;
    m_message.clear();
    Q_EMIT changed();
    runAsync(this, QStringLiteral("systemctl"), {QStringLiteral("start"), QStringLiteral("aster-update.service")}, [this](const QString &, int code) {
        m_checking = false;
        m_message = code == 0 ? QStringLiteral("Sprawdzono przed chwilą.") : QStringLiteral("Nie udało się sprawdzić aktualizacji. Sprawdź połączenie z internetem.");
        Q_EMIT changed();
        refresh();
    });
}

void Updates::restart()
{
    if (asterPreview())
        return;
    // Przez sesję KDE: programy kończą się po kolei i mogą zapisać stan
    QDBusConnection::sessionBus().asyncCall(QDBusMessage::createMethodCall(QStringLiteral("org.kde.Shutdown"), QStringLiteral("/Shutdown"),
                                                                           QStringLiteral("org.kde.Shutdown"), QStringLiteral("logoutAndReboot")));
}

void Updates::rollback()
{
    if (asterPreview())
        return;
    runAsync(this, QStringLiteral("pkexec"), {QStringLiteral("bootc"), QStringLiteral("rollback")}, [this](const QString &, int code) {
        if (code != 0) {
            m_message = QStringLiteral("Nie udało się przygotować poprzedniej wersji.");
            Q_EMIT changed();
            return;
        }
        refresh();
    });
}
