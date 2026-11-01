#include "printers.h"

#include "util.h"

#include <QFile>
#include <QRegularExpression>

Printers::Printers(QObject *parent)
    : QObject(parent)
    , m_preview(asterPreview())
{
    if (m_preview) {
        m_available = true;
        m_printers = {QVariantMap{{QStringLiteral("name"), QStringLiteral("HP_LaserJet_M140w")}, {QStringLiteral("label"), QStringLiteral("HP LaserJet M140w")},
                                  {QStringLiteral("state"), QStringLiteral("idle")}, {QStringLiteral("isDefault"), true}, {QStringLiteral("installed"), true}},
                      QVariantMap{{QStringLiteral("name"), QStringLiteral("Brother_DCP_L2530DW")}, {QStringLiteral("label"), QStringLiteral("Brother DCP-L2530DW")},
                                  {QStringLiteral("state"), QStringLiteral("idle")}, {QStringLiteral("isDefault"), false}, {QStringLiteral("installed"), false}}};
        return;
    }
    m_poll.setInterval(8000);
    connect(&m_poll, &QTimer::timeout, this, &Printers::refresh);
    m_poll.start();
    refresh();
}

static QString pretty(QString name)
{
    name.replace(QLatin1Char('_'), QLatin1Char(' '));
    return name.simplified();
}

void Printers::refresh()
{
    if (m_preview || m_searching)
        return;
    m_searching = true;
    // lpstat -e: wszystkie miejsca druku (też wykryte w sieci), -p: zainstalowane z ich stanem, -d: domyślna
    runAsync(this, QStringLiteral("lpstat"), {QStringLiteral("-e")}, [this](const QString &all, int code) {
        m_available = code >= 0;
        runAsync(this, QStringLiteral("lpstat"), {QStringLiteral("-p"), QStringLiteral("-d")}, [this, all](const QString &out, int) {
            QHash<QString, QString> states;
            QString def;
            static const QRegularExpression printer(QStringLiteral("^printer (\\S+) (?:is )?(\\w+)"));
            for (const QString &line : out.split(QLatin1Char('\n'), Qt::SkipEmptyParts)) {
                const auto m = printer.match(line);
                if (m.hasMatch())
                    states.insert(m.captured(1), m.captured(2) == QLatin1String("idle") ? QStringLiteral("idle")
                                                 : m.captured(2) == QLatin1String("printing") || line.contains(QLatin1String("now printing")) ? QStringLiteral("printing")
                                                                                                                                                  : QStringLiteral("stopped"));
                if (line.startsWith(QLatin1String("system default destination:")))
                    def = line.section(QLatin1Char(':'), 1).trimmed();
            }
            QVariantList list;
            QSet<QString> seen;
            const QStringList names = all.split(QLatin1Char('\n'), Qt::SkipEmptyParts) + states.keys();
            for (const QString &n : names) {
                const QString name = n.trimmed();
                if (name.isEmpty() || seen.contains(name))
                    continue;
                seen.insert(name);
                list << QVariantMap{{QStringLiteral("name"), name}, {QStringLiteral("label"), pretty(name)},
                                    {QStringLiteral("state"), states.value(name, QStringLiteral("idle"))}, {QStringLiteral("isDefault"), name == def},
                                    {QStringLiteral("installed"), states.contains(name)}};
            }
            std::sort(list.begin(), list.end(), [](const QVariant &a, const QVariant &b) {
                return a.toMap().value(QStringLiteral("installed")).toBool() > b.toMap().value(QStringLiteral("installed")).toBool();
            });
            m_searching = false;
            if (list != m_printers)
                m_printers = list;
            Q_EMIT changed();
        });
    });
}

void Printers::setDefault(const QString &name)
{
    if (m_preview)
        return;
    runAsync(this, QStringLiteral("lpoptions"), {QStringLiteral("-d"), name}, [this, name](const QString &, int code) {
        Q_EMIT message(code == 0 ? QStringLiteral("„%1” jest teraz domyślna").arg(pretty(name)) : QStringLiteral("Nie udało się ustawić drukarki domyślnej"));
        refresh();
    });
}

void Printers::printTestPage(const QString &name)
{
    if (m_preview)
        return;
    QString page = QStringLiteral("/usr/share/cups/data/testprint");
    if (!QFile::exists(page))
        page = QStringLiteral("/usr/share/cups/data/default-testpage.pdf");
    runAsync(this, QStringLiteral("lp"), {QStringLiteral("-d"), name, QStringLiteral("-t"), QStringLiteral("Strona testowa Aster"), page},
             [this](const QString &, int code) {
                 Q_EMIT message(code == 0 ? QStringLiteral("Wysłano stronę testową") : QStringLiteral("Nie udało się wysłać strony testowej"));
             });
}

void Printers::add(const QString &name)
{
    if (m_preview)
        return;
    // Wykryta drukarka sieciowa: kolejka bez sterownika (IPP Everywhere); adres z lpstat -v
    runAsync(this, QStringLiteral("lpstat"), {QStringLiteral("-v"), name}, [this, name](const QString &out, int) {
        const QString uri = out.section(QLatin1Char(':'), 1).trimmed();
        if (uri.isEmpty()) {
            Q_EMIT message(QStringLiteral("Nie znaleziono adresu drukarki"));
            return;
        }
        runAsync(this, QStringLiteral("pkexec"), {QStringLiteral("lpadmin"), QStringLiteral("-p"), name, QStringLiteral("-E"), QStringLiteral("-v"), uri,
                                                  QStringLiteral("-m"), QStringLiteral("everywhere")},
                 [this, name](const QString &, int code) {
                     Q_EMIT message(code == 0 ? QStringLiteral("Dodano „%1”").arg(pretty(name)) : QStringLiteral("Nie udało się dodać drukarki"));
                     refresh();
                 });
    });
}

void Printers::remove(const QString &name)
{
    if (m_preview)
        return;
    runAsync(this, QStringLiteral("pkexec"), {QStringLiteral("lpadmin"), QStringLiteral("-x"), name}, [this, name](const QString &, int code) {
        Q_EMIT message(code == 0 ? QStringLiteral("Usunięto „%1”").arg(pretty(name)) : QStringLiteral("Nie udało się usunąć drukarki"));
        refresh();
    });
}
