#include "inputs.h"

#include "util.h"

#include <KConfigGroup>
#include <KSharedConfig>
#include <QCollator>
#include <QDBusReply>

static const QString kwin = QStringLiteral("org.kde.KWin");
static const QString devIface = QStringLiteral("org.kde.KWin.InputDevice");

// Polskie nazwy najczęstszych układów (reszta — angielska nazwa z XKB)
static QString polishLayout(const QString &id)
{
    static const QHash<QString, QString> names{
        {QStringLiteral("pl"), QStringLiteral("Polski")}, {QStringLiteral("us"), QStringLiteral("Angielski (USA)")},
        {QStringLiteral("gb"), QStringLiteral("Angielski (Wielka Brytania)")}, {QStringLiteral("de"), QStringLiteral("Niemiecki")},
        {QStringLiteral("fr"), QStringLiteral("Francuski")}, {QStringLiteral("es"), QStringLiteral("Hiszpański")},
        {QStringLiteral("it"), QStringLiteral("Włoski")}, {QStringLiteral("ua"), QStringLiteral("Ukraiński")},
        {QStringLiteral("ru"), QStringLiteral("Rosyjski")}, {QStringLiteral("by"), QStringLiteral("Białoruski")},
        {QStringLiteral("cz"), QStringLiteral("Czeski")}, {QStringLiteral("sk"), QStringLiteral("Słowacki")},
        {QStringLiteral("lt"), QStringLiteral("Litewski")}, {QStringLiteral("lv"), QStringLiteral("Łotewski")},
        {QStringLiteral("ee"), QStringLiteral("Estoński")}, {QStringLiteral("hu"), QStringLiteral("Węgierski")},
        {QStringLiteral("ro"), QStringLiteral("Rumuński")}, {QStringLiteral("pt"), QStringLiteral("Portugalski")},
        {QStringLiteral("br"), QStringLiteral("Portugalski (Brazylia)")}, {QStringLiteral("nl"), QStringLiteral("Niderlandzki")},
        {QStringLiteral("se"), QStringLiteral("Szwedzki")}, {QStringLiteral("no"), QStringLiteral("Norweski")},
        {QStringLiteral("dk"), QStringLiteral("Duński")}, {QStringLiteral("fi"), QStringLiteral("Fiński")},
        {QStringLiteral("gr"), QStringLiteral("Grecki")}, {QStringLiteral("tr"), QStringLiteral("Turecki")},
        {QStringLiteral("jp"), QStringLiteral("Japoński")}, {QStringLiteral("cn"), QStringLiteral("Chiński")},
        {QStringLiteral("kr"), QStringLiteral("Koreański")}, {QStringLiteral("il"), QStringLiteral("Hebrajski")},
        {QStringLiteral("ara"), QStringLiteral("Arabski")}, {QStringLiteral("ch"), QStringLiteral("Szwajcarski")},
        {QStringLiteral("at"), QStringLiteral("Austriacki")}, {QStringLiteral("hr"), QStringLiteral("Chorwacki")},
        {QStringLiteral("si"), QStringLiteral("Słoweński")}, {QStringLiteral("rs"), QStringLiteral("Serbski")},
        {QStringLiteral("bg"), QStringLiteral("Bułgarski")}, {QStringLiteral("vn"), QStringLiteral("Wietnamski")},
    };
    return names.value(id);
}

Inputs::Inputs(QObject *parent)
    : QObject(parent)
    , m_preview(asterPreview())
{
    m_mouse = {{QStringLiteral("speed"), 0.0}, {QStringLiteral("natural"), false}, {QStringLiteral("leftHanded"), false}};
    m_touchpad = {{QStringLiteral("speed"), 0.2}, {QStringLiteral("natural"), true}, {QStringLiteral("tapToClick"), true},
                  {QStringLiteral("disableWhileTyping"), true}, {QStringLiteral("leftHanded"), false}};
    readLayouts();
    if (!m_preview)
        refresh();
}

QVariantList Inputs::allLayouts() const
{
    if (!m_allLayouts.isEmpty())
        return m_allLayouts;
    // Sekcja „! layout” w evdev.lst: „  pl              Polish”
    const QStringList lines = readTextFile(QStringLiteral("/usr/share/X11/xkb/rules/evdev.lst")).split(QLatin1Char('\n'));
    bool in = false;
    QList<QPair<QString, QString>> list;
    for (const QString &line : lines) {
        if (line.startsWith(QLatin1Char('!'))) {
            in = line.trimmed() == QLatin1String("! layout");
            continue;
        }
        if (!in || line.trimmed().isEmpty())
            continue;
        const QString id = line.trimmed().section(QLatin1Char(' '), 0, 0);
        const QString name = line.trimmed().section(QLatin1Char(' '), 1).trimmed();
        list << qMakePair(id, polishLayout(id).isEmpty() ? name : polishLayout(id));
    }
    if (list.isEmpty())
        for (const char *id : {"pl", "us", "gb", "de", "ua", "fr", "es", "it", "cz", "sk"})
            list << qMakePair(QString::fromLatin1(id), polishLayout(QString::fromLatin1(id)));
    QCollator c(QLocale(QStringLiteral("pl_PL")));
    std::sort(list.begin(), list.end(), [&c](const auto &a, const auto &b) { return c.compare(a.second, b.second) < 0; });
    for (const auto &p : list)
        m_allLayouts << QVariantMap{{QStringLiteral("id"), p.first}, {QStringLiteral("name"), p.second}};
    return m_allLayouts;
}

QString Inputs::layoutName(const QString &id) const
{
    for (const QVariant &v : allLayouts())
        if (v.toMap().value(QStringLiteral("id")).toString() == id)
            return v.toMap().value(QStringLiteral("name")).toString();
    return id;
}

void Inputs::readLayouts()
{
    QStringList ids = {QStringLiteral("pl")};
    if (!m_preview) {
        KSharedConfig::Ptr c = KSharedConfig::openConfig(QStringLiteral("kxkbrc"), KConfig::NoGlobals);
        c->reparseConfiguration();
        const KConfigGroup g = c->group(QStringLiteral("Layout"));
        const QStringList saved = g.readEntry("LayoutList", QString()).split(QLatin1Char(','), Qt::SkipEmptyParts);
        if (g.readEntry("Use", false) && !saved.isEmpty())
            ids = saved;
    } else {
        ids = {QStringLiteral("pl"), QStringLiteral("us")};
    }
    m_layouts.clear();
    for (const QString &id : ids)
        m_layouts << QVariantMap{{QStringLiteral("id"), id}, {QStringLiteral("name"), layoutName(id)}};
}

void Inputs::setLayouts(const QStringList &ids)
{
    if (ids.isEmpty())
        return;
    KSharedConfig::Ptr c = KSharedConfig::openConfig(QStringLiteral("kxkbrc"), KConfig::NoGlobals);
    KConfigGroup g = c->group(QStringLiteral("Layout"));
    g.writeEntry("Use", true, KConfig::Notify);
    g.writeEntry("LayoutList", ids.join(QLatin1Char(',')), KConfig::Notify);
    g.writeEntry("VariantList", QStringList(ids.size(), QString()).join(QLatin1Char(',')), KConfig::Notify);
    // Przełączanie Super+Spacja (jak w Windows), zostają inne opcje użytkownika
    QStringList options = g.readEntry("Options", QString()).split(QLatin1Char(','), Qt::SkipEmptyParts);
    options.erase(std::remove_if(options.begin(), options.end(), [](const QString &o) { return o.startsWith(QLatin1String("grp:")); }), options.end());
    if (ids.size() > 1)
        options << QStringLiteral("grp:win_space_toggle");
    g.writeEntry("Options", options.join(QLatin1Char(',')), KConfig::Notify);
    g.writeEntry("ResetOldOptions", true, KConfig::Notify);
    c->sync();
    readLayouts();
    Q_EMIT changed();
    if (!m_preview) {
        QDBusConnection::sessionBus().send(QDBusMessage::createSignal(QStringLiteral("/Layouts"), QStringLiteral("org.kde.keyboard"), QStringLiteral("reloadConfig")));
        QDBusConnection::sessionBus().send(dbusMethod(kwin, QStringLiteral("/KWin"), kwin, QStringLiteral("reconfigure")));
    }
}

void Inputs::refresh()
{
    if (m_preview)
        return;
    QDBusMessage m = dbusMethod(kwin, QStringLiteral("/org/kde/KWin/InputDevice"), QStringLiteral("org.freedesktop.DBus.Properties"), QStringLiteral("Get"),
                                {QStringLiteral("org.kde.KWin.InputDeviceManager"), QStringLiteral("devicesSysNames")});
    dbusCall(this, m, false, false, [this](const QDBusMessage &r) {
        if (r.type() != QDBusMessage::ReplyMessage || r.arguments().isEmpty())
            return;
        const QStringList names = qvariant_cast<QDBusVariant>(r.arguments().first()).variant().toStringList();
        m_mouseDevices.clear();
        m_touchpadDevices.clear();
        for (const QString &sys : names) {
            dbusGetAll(this, kwin, QStringLiteral("/org/kde/KWin/InputDevice/") + sys, devIface, false, [this, sys](const QVariantMap &p) {
                if (!p.value(QStringLiteral("pointer")).toBool())
                    return;
                const Device d{sys, p.value(QStringLiteral("name")).toString(), p.value(QStringLiteral("vendor")).toUInt(), p.value(QStringLiteral("product")).toUInt()};
                const bool touchpad = p.value(QStringLiteral("touchpad")).toBool();
                QVariantMap &target = touchpad ? m_touchpad : m_mouse;
                (touchpad ? m_touchpadDevices : m_mouseDevices) << d;
                // Odczyt z pierwszego urządzenia danego rodzaju
                if ((touchpad ? m_touchpadDevices : m_mouseDevices).size() == 1) {
                    target.insert(QStringLiteral("speed"), p.value(QStringLiteral("pointerAcceleration")).toDouble());
                    target.insert(QStringLiteral("natural"), p.value(QStringLiteral("naturalScroll")).toBool());
                    target.insert(QStringLiteral("leftHanded"), p.value(QStringLiteral("leftHanded")).toBool());
                    if (touchpad) {
                        target.insert(QStringLiteral("tapToClick"), p.value(QStringLiteral("tapToClick")).toBool());
                        target.insert(QStringLiteral("disableWhileTyping"), p.value(QStringLiteral("disableWhileTyping")).toBool());
                    }
                }
                Q_EMIT changed();
            });
        }
    });
}

void Inputs::set(const QString &kind, const QString &key, const QVariant &value)
{
    const bool touchpad = kind == QLatin1String("touchpad");
    (touchpad ? m_touchpad : m_mouse).insert(key, value);
    Q_EMIT changed();
    if (m_preview)
        return;
    // Nazwa właściwości KWin i klucz w kcminputrc
    static const QHash<QString, QPair<QString, QString>> map{
        {QStringLiteral("speed"), {QStringLiteral("pointerAcceleration"), QStringLiteral("PointerAcceleration")}},
        {QStringLiteral("natural"), {QStringLiteral("naturalScroll"), QStringLiteral("NaturalScroll")}},
        {QStringLiteral("leftHanded"), {QStringLiteral("leftHanded"), QStringLiteral("LeftHanded")}},
        {QStringLiteral("tapToClick"), {QStringLiteral("tapToClick"), QStringLiteral("TapToClick")}},
        {QStringLiteral("disableWhileTyping"), {QStringLiteral("disableWhileTyping"), QStringLiteral("DisableWhileTyping")}},
    };
    if (!map.contains(key))
        return;
    const auto [prop, confKey] = map.value(key);
    KSharedConfig::Ptr c = KSharedConfig::openConfig(QStringLiteral("kcminputrc"), KConfig::NoGlobals);
    for (const Device &d : touchpad ? m_touchpadDevices : m_mouseDevices) {
        dbusSetProperty(this, kwin, QStringLiteral("/org/kde/KWin/InputDevice/") + d.sysName, devIface, prop, value, false);
        KConfigGroup g = c->group(QStringLiteral("Libinput")).group(QString::number(d.vendor)).group(QString::number(d.product)).group(d.name);
        if (key == QLatin1String("speed"))
            g.writeEntry(confKey, QString::number(value.toDouble(), 'f', 3));
        else
            g.writeEntry(confKey, value.toBool());
    }
    c->sync();
}
