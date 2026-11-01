#include "displays.h"

#include "util.h"

#include <QJsonArray>
#include <QJsonDocument>
#include <QJsonObject>
#include <cmath>

static const QString brightnessService = QStringLiteral("org.kde.ScreenBrightness");
static const QString brightnessPath = QStringLiteral("/org/kde/ScreenBrightness");

Displays::Displays(QObject *parent)
    : QObject(parent)
    , m_preview(asterPreview())
{
    m_brightnessDelay.setSingleShot(true);
    m_brightnessDelay.setInterval(60);
    connect(&m_brightnessDelay, &QTimer::timeout, this, [this] {
        if (m_display.isEmpty() || m_maxBrightness <= 0)
            return;
        QDBusMessage m = dbusMethod(brightnessService, brightnessPath + QLatin1Char('/') + m_display, QStringLiteral("org.kde.ScreenBrightness.Display"),
                                    QStringLiteral("SetBrightness"), {int(qRound(m_brightness * m_maxBrightness)), uint(0)});
        QDBusConnection::sessionBus().send(m);
    });
    if (m_preview) {
        const auto mode = [](const QString &id, int w, int h, double hz) {
            return QVariantMap{{QStringLiteral("id"), id}, {QStringLiteral("width"), w}, {QStringLiteral("height"), h}, {QStringLiteral("refresh"), hz}};
        };
        m_outputs = {
            QVariantMap{{QStringLiteral("name"), QStringLiteral("eDP-1")}, {QStringLiteral("label"), QStringLiteral("Ekran wbudowany")},
                        {QStringLiteral("enabled"), true}, {QStringLiteral("primary"), true}, {QStringLiteral("scale"), 1.25},
                        {QStringLiteral("rotation"), QStringLiteral("normal")}, {QStringLiteral("x"), 0}, {QStringLiteral("y"), 0},
                        {QStringLiteral("width"), 2560}, {QStringLiteral("height"), 1600}, {QStringLiteral("modeId"), QStringLiteral("1")},
                        {QStringLiteral("refresh"), 120.0}, {QStringLiteral("builtin"), true},
                        {QStringLiteral("modes"), QVariantList{mode(QStringLiteral("1"), 2560, 1600, 120), mode(QStringLiteral("2"), 2560, 1600, 60),
                                                               mode(QStringLiteral("3"), 1920, 1200, 60), mode(QStringLiteral("4"), 1680, 1050, 60),
                                                               mode(QStringLiteral("5"), 1280, 800, 60)}}},
            QVariantMap{{QStringLiteral("name"), QStringLiteral("DP-2")}, {QStringLiteral("label"), QStringLiteral("Dell U2723QE")},
                        {QStringLiteral("enabled"), true}, {QStringLiteral("primary"), false}, {QStringLiteral("scale"), 1.5},
                        {QStringLiteral("rotation"), QStringLiteral("normal")}, {QStringLiteral("x"), 2048}, {QStringLiteral("y"), -200},
                        {QStringLiteral("width"), 3840}, {QStringLiteral("height"), 2160}, {QStringLiteral("modeId"), QStringLiteral("1")},
                        {QStringLiteral("refresh"), 60.0}, {QStringLiteral("builtin"), false},
                        {QStringLiteral("modes"), QVariantList{mode(QStringLiteral("1"), 3840, 2160, 60), mode(QStringLiteral("2"), 2560, 1440, 60),
                                                               mode(QStringLiteral("3"), 1920, 1080, 60)}}},
        };
        m_brightnessAvailable = true;
        m_brightness = 0.72;
        return;
    }
    refresh();
    readBrightness();
}

static QString rotationName(int r)
{
    switch (r) {
    case 2: return QStringLiteral("left");
    case 4: return QStringLiteral("inverted");
    case 8: return QStringLiteral("right");
    default: return QStringLiteral("normal");
    }
}

void Displays::refresh()
{
    if (m_preview)
        return;
    runAsync(this, QStringLiteral("kscreen-doctor"), {QStringLiteral("-j")}, [this](const QString &out, int) {
        const QJsonArray outputs = QJsonDocument::fromJson(out.toUtf8()).object().value(QStringLiteral("outputs")).toArray();
        QVariantList list;
        for (const QJsonValue &v : outputs) {
            const QJsonObject o = v.toObject();
            if (!o.value(QStringLiteral("connected")).toBool(true))
                continue;
            QVariantList modes;
            QVariantMap current;
            const QString currentId = o.value(QStringLiteral("currentModeId")).toVariant().toString();
            for (const QJsonValue &mv : o.value(QStringLiteral("modes")).toArray()) {
                const QJsonObject m = mv.toObject();
                const QJsonObject size = m.value(QStringLiteral("size")).toObject();
                const QVariantMap mode{{QStringLiteral("id"), m.value(QStringLiteral("id")).toVariant().toString()},
                                       {QStringLiteral("width"), size.value(QStringLiteral("width")).toInt()},
                                       {QStringLiteral("height"), size.value(QStringLiteral("height")).toInt()},
                                       {QStringLiteral("refresh"), m.value(QStringLiteral("refreshRate")).toDouble()}};
                modes << mode;
                if (mode.value(QStringLiteral("id")).toString() == currentId)
                    current = mode;
            }
            // Od największej rozdzielczości i najszybszego odświeżania
            std::sort(modes.begin(), modes.end(), [](const QVariant &a, const QVariant &b) {
                const QVariantMap x = a.toMap(), y = b.toMap();
                const qint64 ax = qint64(x.value(QStringLiteral("width")).toInt()) * x.value(QStringLiteral("height")).toInt();
                const qint64 bx = qint64(y.value(QStringLiteral("width")).toInt()) * y.value(QStringLiteral("height")).toInt();
                if (ax != bx)
                    return ax > bx;
                return x.value(QStringLiteral("refresh")).toDouble() > y.value(QStringLiteral("refresh")).toDouble();
            });
            const QString name = o.value(QStringLiteral("name")).toString();
            const bool builtin = name.startsWith(QLatin1String("eDP")) || name.startsWith(QLatin1String("LVDS")) || name.startsWith(QLatin1String("DSI"));
            const QJsonObject pos = o.value(QStringLiteral("pos")).toObject();
            QString label = (o.value(QStringLiteral("model")).toString()).trimmed();
            if (label.isEmpty())
                label = builtin ? QStringLiteral("Ekran wbudowany") : name;
            list << QVariantMap{{QStringLiteral("name"), name}, {QStringLiteral("label"), label},
                                {QStringLiteral("enabled"), o.value(QStringLiteral("enabled")).toBool()},
                                {QStringLiteral("primary"), o.value(QStringLiteral("priority")).toInt() == 1 || o.value(QStringLiteral("primary")).toBool()},
                                {QStringLiteral("scale"), o.value(QStringLiteral("scale")).toDouble(1)},
                                {QStringLiteral("rotation"), rotationName(o.value(QStringLiteral("rotation")).toInt(1))},
                                {QStringLiteral("x"), pos.value(QStringLiteral("x")).toInt()}, {QStringLiteral("y"), pos.value(QStringLiteral("y")).toInt()},
                                {QStringLiteral("width"), current.value(QStringLiteral("width"), 1920)}, {QStringLiteral("height"), current.value(QStringLiteral("height"), 1080)},
                                {QStringLiteral("refresh"), current.value(QStringLiteral("refresh"), 60.0)}, {QStringLiteral("modeId"), currentId},
                                {QStringLiteral("builtin"), builtin}, {QStringLiteral("modes"), modes}};
        }
        m_outputs = list;
        Q_EMIT changed();
    });
}

void Displays::apply(const QStringList &args)
{
    if (m_preview) {
        Q_EMIT message(QStringLiteral("W podglądzie ekran się nie zmienia"));
        return;
    }
    m_busy = true;
    Q_EMIT changed();
    runAsync(this, QStringLiteral("kscreen-doctor"), args, [this](const QString &, int code) {
        m_busy = false;
        if (code != 0)
            Q_EMIT message(QStringLiteral("Nie udało się zmienić ustawień ekranu"));
        refresh();
    });
}

void Displays::setMode(const QString &output, const QString &modeId)
{
    apply({QStringLiteral("output.%1.mode.%2").arg(output, modeId)});
}

void Displays::setScale(const QString &output, double scale)
{
    apply({QStringLiteral("output.%1.scale.%2").arg(output, QString::number(scale, 'g', 4))});
}

void Displays::setRotation(const QString &output, const QString &rotation)
{
    apply({QStringLiteral("output.%1.rotation.%2").arg(output, rotation)});
}

void Displays::setEnabled(const QString &output, bool on)
{
    apply({QStringLiteral("output.%1.%2").arg(output, on ? QStringLiteral("enable") : QStringLiteral("disable"))});
}

void Displays::setPrimary(const QString &output)
{
    apply({QStringLiteral("output.%1.priority.1").arg(output)});
}

void Displays::setPosition(const QString &output, int x, int y)
{
    apply({QStringLiteral("output.%1.position.%2,%3").arg(output).arg(x).arg(y)});
}

void Displays::readBrightness()
{
    dbusGetAll(this, brightnessService, brightnessPath, brightnessService, false, [this](const QVariantMap &p) {
        const QStringList displays = p.value(QStringLiteral("DisplaysDBusNames")).toStringList();
        if (displays.isEmpty())
            return;
        m_display = displays.first();
        dbusGetAll(this, brightnessService, brightnessPath + QLatin1Char('/') + m_display, QStringLiteral("org.kde.ScreenBrightness.Display"), false,
                   [this](const QVariantMap &d) {
                       m_maxBrightness = d.value(QStringLiteral("MaxBrightness")).toInt();
                       m_brightnessAvailable = m_maxBrightness > 0;
                       if (m_brightnessAvailable)
                           m_brightness = d.value(QStringLiteral("Brightness")).toDouble() / m_maxBrightness;
                       Q_EMIT brightnessChanged();
                   });
    });
}

void Displays::setBrightness(double value)
{
    m_brightness = qBound(0.02, value, 1.0);
    Q_EMIT brightnessChanged();
    if (!m_preview)
        m_brightnessDelay.start();
}
