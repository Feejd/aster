#include "emoji.h"
#include "fakeinput.h"

#include <KSystemClipboard>

#include <QFile>
#include <QGuiApplication>
#include <QJsonArray>
#include <QJsonDocument>
#include <QJsonObject>
#include <QMimeData>
#include <QSettings>
#include <QTimer>

static const int maxRecent = 36;

Emoji::Emoji(QObject *parent)
    : QObject(parent)
{
    QFile f(QStringLiteral(":/emoji/emoji.json"));
    if (f.open(QIODevice::ReadOnly)) {
        const QJsonArray groups = QJsonDocument::fromJson(f.readAll()).array();
        for (const QJsonValue &g : groups) {
            QVariantMap group = g.toObject().toVariantMap();
            QVariantList list;
            const QJsonArray items = g.toObject().value(QStringLiteral("emoji")).toArray();
            for (const QJsonValue &v : items) {
                const QJsonArray e = v.toArray();
                const QString ch = e.at(0).toString(), name = e.at(1).toString();
                m_names.insert(ch, name);
                // c — znak, n — nazwa, t — odcienie skóry (albo pusta lista), s — tekst do szukania
                list << QVariantMap{{QStringLiteral("c"), ch}, {QStringLiteral("n"), name},
                                    {QStringLiteral("t"), e.size() > 3 ? e.at(3).toArray().toVariantList() : QVariantList()},
                                    {QStringLiteral("s"), fold(name + QLatin1Char(' ') + e.at(2).toString())}};
            }
            group.insert(QStringLiteral("emoji"), list);
            m_groups << group;
        }
    }
    QSettings s;
    m_recent = s.value(QStringLiteral("recent")).toStringList();
    m_tone = s.value(QStringLiteral("tone"), 0).toInt();
    if (QGuiApplication::platformName() == QLatin1String("wayland"))
        m_input = new FakeInput;
}

Emoji::~Emoji()
{
    delete m_input;
}

void Emoji::setTone(int t)
{
    if (t == m_tone)
        return;
    m_tone = t;
    QSettings().setValue(QStringLiteral("tone"), t);
    Q_EMIT toneChanged();
}

QString Emoji::fold(const QString &text) const
{
    QString s = text.toLower().normalized(QString::NormalizationForm_D);
    QString out;
    out.reserve(s.size());
    for (const QChar c : std::as_const(s)) {
        if (c.category() == QChar::Mark_NonSpacing)
            continue;
        out += c == QChar(0x0142) ? QLatin1Char('l') : c;      // ł nie rozkłada się na l + znak
    }
    return out;
}

QString Emoji::nameOf(const QString &emoji) const
{
    return m_names.value(emoji);
}

void Emoji::Toggle()
{
    Q_EMIT toggleRequested();
}

void Emoji::insert(const QString &text, bool remember)
{
    if (text.isEmpty())
        return;
    if (remember) {
        m_recent.removeAll(text);
        m_recent.prepend(text);
        while (m_recent.size() > maxRecent)
            m_recent.removeLast();
        QSettings().setValue(QStringLiteral("recent"), m_recent);
        Q_EMIT recentChanged();
    }

    // Schowek przez KSystemClipboard (wlr/ext-data-control) — działa też bez aktywnego okna,
    // więc da się potem przywrócić to, co w nim było
    auto *clip = KSystemClipboard::instance();
    QMimeData *previous = nullptr;
    if (const QMimeData *old = clip->mimeData(QClipboard::Clipboard)) {
        previous = new QMimeData;
        for (const QString &fmt : old->formats())
            previous->setData(fmt, old->data(fmt));
    }
    auto *mime = new QMimeData;
    mime->setText(text);
    clip->setMimeData(mime, QClipboard::Clipboard);

    if (!m_input || !m_input->isActive()) {
        delete previous;
        Q_EMIT copied(text);
        return;
    }
    Q_EMIT hideRequested();
    // Chwila na powrót aktywności do poprzedniego okna, potem Ctrl+V i przywrócenie schowka
    QTimer::singleShot(160, this, [this, previous] {
        m_input->paste(false);
        QTimer::singleShot(450, this, [previous] {
            if (previous)
                KSystemClipboard::instance()->setMimeData(previous, QClipboard::Clipboard);
        });
    });
}
