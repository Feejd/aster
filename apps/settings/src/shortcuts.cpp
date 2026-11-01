#include "shortcuts.h"

#include "util.h"

#include <QCollator>
#include <QDBusArgument>
#include <QDBusMetaType>
#include <QDBusObjectPath>
#include <QKeySequence>

static const QString ka = QStringLiteral("org.kde.kglobalaccel");

// Sekwencja klawiszy na szynie: struktura z listą kodów — „(ai)”
struct KeySeq {
    QList<int> keys;
};
Q_DECLARE_METATYPE(KeySeq)
QDBusArgument &operator<<(QDBusArgument &a, const KeySeq &s)
{
    a.beginStructure();
    a << s.keys;
    a.endStructure();
    return a;
}
const QDBusArgument &operator>>(const QDBusArgument &a, KeySeq &s)
{
    a.beginStructure();
    a >> s.keys;
    a.endStructure();
    return a;
}

// Lista skrótów zapisana jako „ai” (starsze KDE) albo „a(ai)” (KDE 6): pierwszy klawisz każdej sekwencji
static QList<int> readKeys(const QDBusArgument &a)
{
    QList<int> out;
    const QString sig = a.currentSignature();
    if (sig == QLatin1String("ai")) {
        a >> out;
    } else {
        a.beginArray();
        while (!a.atEnd()) {
            KeySeq s;
            a >> s;
            if (!s.keys.isEmpty() && s.keys.first() != 0)
                out << s.keys.first();
        }
        a.endArray();
    }
    return out;
}

static QString keysText(const QList<int> &keys)
{
    QStringList parts;
    for (int k : keys)
        if (k)
            parts << QKeySequence(k).toString(QKeySequence::NativeText);
    return parts.join(QStringLiteral(", "));
}

// Najpierw najważniejsze grupy, potem reszta alfabetycznie
static int rank(const QString &component)
{
    static const QStringList order{QStringLiteral("kwin"), QStringLiteral("ksmserver"), QStringLiteral("org_kde_powerdevil"), QStringLiteral("kmix"),
                                   QStringLiteral("mediacontrol"), QStringLiteral("org.kde.spectacle.desktop"), QStringLiteral("KDE Keyboard Layout Switcher")};
    const int i = order.indexOf(component);
    return i < 0 ? 100 : i;
}

static QString polishGroup(const QString &component, const QString &name)
{
    static const QHash<QString, QString> m{
        {QStringLiteral("kwin"), QStringLiteral("Okna i pulpit")}, {QStringLiteral("ksmserver"), QStringLiteral("Sesja")},
        {QStringLiteral("org_kde_powerdevil"), QStringLiteral("Zasilanie i jasność")}, {QStringLiteral("kmix"), QStringLiteral("Głośność")},
        {QStringLiteral("mediacontrol"), QStringLiteral("Odtwarzanie")}, {QStringLiteral("org.kde.spectacle.desktop"), QStringLiteral("Zrzuty ekranu")},
        {QStringLiteral("KDE Keyboard Layout Switcher"), QStringLiteral("Układ klawiatury")},
    };
    return m.value(component, name);
}

Shortcuts::Shortcuts(QObject *parent)
    : QObject(parent)
    , m_preview(asterPreview())
{
    qDBusRegisterMetaType<KeySeq>();
    qDBusRegisterMetaType<QList<KeySeq>>();
    if (m_preview) {
        m_available = true;
        const auto act = [](const QString &id, const QString &name, const QString &keys) {
            return QVariantMap{{QStringLiteral("id"), id}, {QStringLiteral("name"), name}, {QStringLiteral("keys"), keys}, {QStringLiteral("defaultKeys"), keys}};
        };
        m_groups = {QVariantMap{{QStringLiteral("id"), QStringLiteral("kwin")}, {QStringLiteral("name"), QStringLiteral("Okna i pulpit")},
                                {QStringLiteral("actions"), QVariantList{act(QStringLiteral("a"), QStringLiteral("Przegląd okien"), QStringLiteral("Meta+W")),
                                                                         act(QStringLiteral("b"), QStringLiteral("Pokaż pulpit"), QStringLiteral("Meta+D")),
                                                                         act(QStringLiteral("c"), QStringLiteral("Zamknij okno"), QStringLiteral("Alt+F4")),
                                                                         act(QStringLiteral("d"), QStringLiteral("Zmaksymalizuj okno"), QStringLiteral("Meta+PgUp")),
                                                                         act(QStringLiteral("e"), QStringLiteral("Okno do lewej połowy ekranu"), QStringLiteral("Meta+Left"))}}},
                    QVariantMap{{QStringLiteral("id"), QStringLiteral("ksmserver")}, {QStringLiteral("name"), QStringLiteral("Sesja")},
                                {QStringLiteral("actions"), QVariantList{act(QStringLiteral("f"), QStringLiteral("Zablokuj ekran"), QStringLiteral("Meta+L")),
                                                                         act(QStringLiteral("g"), QStringLiteral("Wyloguj"), QStringLiteral("Ctrl+Alt+Del"))}}},
                    QVariantMap{{QStringLiteral("id"), QStringLiteral("spectacle")}, {QStringLiteral("name"), QStringLiteral("Zrzuty ekranu")},
                                {QStringLiteral("actions"), QVariantList{act(QStringLiteral("h"), QStringLiteral("Zrzut obszaru"), QStringLiteral("Meta+Shift+S")),
                                                                         act(QStringLiteral("i"), QStringLiteral("Zrzut całego ekranu"), QStringLiteral("Print"))}}}};
        return;
    }
    refresh();
}

void Shortcuts::refresh()
{
    if (m_preview)
        return;
    dbusCall(this, dbusMethod(ka, QStringLiteral("/kglobalaccel"), QStringLiteral("org.kde.KGlobalAccel"), QStringLiteral("allComponents")), false, false,
             [this](const QDBusMessage &r) {
                 if (r.type() != QDBusMessage::ReplyMessage) {
                     m_available = false;
                     Q_EMIT changed();
                     return;
                 }
                 m_available = true;
                 QList<QDBusObjectPath> paths;
                 qvariant_cast<QDBusArgument>(r.arguments().value(0)) >> paths;
                 m_groups.clear();
                 m_ids.clear();
                 auto *pending = new int(int(paths.size()));
                 for (const QDBusObjectPath &p : paths) {
                     dbusCall(this, dbusMethod(ka, p.path(), QStringLiteral("org.kde.kglobalaccel.Component"), QStringLiteral("allShortcutInfos")), false, false,
                              [this, pending](const QDBusMessage &cr) {
                                  if (cr.type() == QDBusMessage::ReplyMessage) {
                                      const QDBusArgument arg = qvariant_cast<QDBusArgument>(cr.arguments().value(0));
                                      QString compId, compName;
                                      QVariantList actions;
                                      arg.beginArray();
                                      while (!arg.atEnd()) {
                                          QString unique, friendly, cUnique, cFriendly, ctxUnique, ctxFriendly;
                                          arg.beginStructure();
                                          arg >> unique >> friendly >> cUnique >> cFriendly >> ctxUnique >> ctxFriendly;
                                          const QList<int> keys = readKeys(arg);
                                          const QList<int> defaults = readKeys(arg);
                                          arg.endStructure();
                                          if (friendly.isEmpty())
                                              continue;
                                          compId = cUnique;
                                          compName = cFriendly;
                                          m_ids.insert(cUnique + QLatin1Char('|') + unique, {cUnique, unique, cFriendly, friendly});
                                          m_defaults.insert(cUnique + QLatin1Char('|') + unique, defaults);
                                          actions << QVariantMap{{QStringLiteral("id"), unique}, {QStringLiteral("name"), friendly},
                                                                 {QStringLiteral("keys"), keysText(keys)}, {QStringLiteral("defaultKeys"), keysText(defaults)},
                                                                 {QStringLiteral("codes"), QVariant::fromValue(QVariantList(keys.cbegin(), keys.cend()))}};
                                      }
                                      arg.endArray();
                                      if (!actions.isEmpty()) {
                                          QCollator c(QLocale(QStringLiteral("pl_PL")));
                                          std::sort(actions.begin(), actions.end(), [&c](const QVariant &a, const QVariant &b) {
                                              return c.compare(a.toMap().value(QStringLiteral("name")).toString(), b.toMap().value(QStringLiteral("name")).toString()) < 0;
                                          });
                                          m_groups << QVariantMap{{QStringLiteral("id"), compId}, {QStringLiteral("name"), polishGroup(compId, compName)},
                                                                  {QStringLiteral("actions"), actions}};
                                      }
                                  }
                                  if (--*pending == 0) {
                                      delete pending;
                                      QCollator c(QLocale(QStringLiteral("pl_PL")));
                                      std::sort(m_groups.begin(), m_groups.end(), [&c](const QVariant &a, const QVariant &b) {
                                          const QVariantMap x = a.toMap(), y = b.toMap();
                                          const int rx = rank(x.value(QStringLiteral("id")).toString()), ry = rank(y.value(QStringLiteral("id")).toString());
                                          if (rx != ry)
                                              return rx < ry;
                                          return c.compare(x.value(QStringLiteral("name")).toString(), y.value(QStringLiteral("name")).toString()) < 0;
                                      });
                                      Q_EMIT changed();
                                  }
                              });
                 }
                 if (paths.isEmpty()) {
                     delete pending;
                     Q_EMIT changed();
                 }
             });
}

void Shortcuts::setKeys(const QString &component, const QString &action, const QVariantList &keys)
{
    QList<int> codes;
    for (const QVariant &k : keys)
        codes << k.toInt();
    // Od razu na liście
    for (QVariant &g : m_groups) {
        QVariantMap gm = g.toMap();
        if (gm.value(QStringLiteral("id")) != component && !m_preview)
            continue;
        QVariantList acts = gm.value(QStringLiteral("actions")).toList();
        for (QVariant &a : acts) {
            QVariantMap am = a.toMap();
            if (am.value(QStringLiteral("id")) == action) {
                am.insert(QStringLiteral("keys"), keysText(codes));
                a = am;
            }
        }
        gm.insert(QStringLiteral("actions"), acts);
        g = gm;
    }
    Q_EMIT changed();
    if (m_preview)
        return;
    const QStringList id = m_ids.value(component + QLatin1Char('|') + action);
    if (id.isEmpty())
        return;
    QList<KeySeq> seqs;
    for (int c : codes)
        seqs << KeySeq{{c}};
    QDBusMessage m = dbusMethod(ka, QStringLiteral("/kglobalaccel"), QStringLiteral("org.kde.KGlobalAccel"), QStringLiteral("setForeignShortcutKeys"));
    m << id << QVariant::fromValue(seqs);
    dbusCall(this, m, false, false, [this, id, codes](const QDBusMessage &r) {
        if (r.type() == QDBusMessage::ReplyMessage)
            return;
        // Starsze KDE: lista kodów „ai”
        QDBusMessage old = dbusMethod(ka, QStringLiteral("/kglobalaccel"), QStringLiteral("org.kde.KGlobalAccel"), QStringLiteral("setForeignShortcut"));
        old << id << QVariant::fromValue(codes);
        dbusCall(this, old, false, false, [this](const QDBusMessage &r2) {
            if (r2.type() != QDBusMessage::ReplyMessage)
                Q_EMIT message(QStringLiteral("Nie udało się zmienić skrótu"));
        });
    });
}

void Shortcuts::resetKeys(const QString &component, const QString &action)
{
    const QList<int> d = m_defaults.value(component + QLatin1Char('|') + action);
    setKeys(component, action, QVariantList(d.cbegin(), d.cend()));
}

QString Shortcuts::keyText(int key, int modifiers) const
{
    return QKeySequence(QKeyCombination(Qt::KeyboardModifiers(modifiers), Qt::Key(key))).toString(QKeySequence::NativeText);
}

QString Shortcuts::conflict(int combined) const
{
    const QString text = QKeySequence(combined).toString(QKeySequence::NativeText);
    for (const QVariant &g : m_groups)
        for (const QVariant &a : g.toMap().value(QStringLiteral("actions")).toList()) {
            const QStringList parts = a.toMap().value(QStringLiteral("keys")).toString().split(QStringLiteral(", "));
            if (parts.contains(text))
                return a.toMap().value(QStringLiteral("name")).toString();
        }
    return QString();
}
