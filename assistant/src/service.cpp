#include "service.h"
#include "secrets.h"

#include <QCoreApplication>
#include <QDateTime>
#include <QDir>
#include <QFile>
#include <QJsonDocument>
#include <QJsonObject>
#include <QNetworkReply>
#include <QNetworkRequest>
#include <QRandomGenerator>
#include <QSaveFile>
#include <QSettings>
#include <QStandardPaths>
#include <algorithm>

// Ile ostatnich wiadomości rozmowy idzie do modelu (starsze zostają tylko w historii)
static constexpr int kContextMessages = 24;
// Dane z potoku: większe przycinane (początek i — ważniejszy przy logach — koniec)
static constexpr int kMaxContext = 48000;

static QSettings config()
{
    return QSettings(QStandardPaths::writableLocation(QStandardPaths::GenericConfigLocation) + QStringLiteral("/aster/asystent.conf"),
                     QSettings::IniFormat);
}

Service::Service(QObject *parent)
    : QObject(parent)
{
    // Lekko: bez pytań przez kwadrans usługa się kończy (D-Bus uruchomi ją znowu przy następnym wywołaniu)
    m_idle.setSingleShot(true);
    m_idle.setInterval(qEnvironmentVariableIntValue("ASTER_ASSISTANT_IDLE") > 0 ? qEnvironmentVariableIntValue("ASTER_ASSISTANT_IDLE") * 1000
                                                                                 : 15 * 60 * 1000);
    connect(&m_idle, &QTimer::timeout, this, [this] {
        if (m_requests.isEmpty())
            QCoreApplication::quit();
        else
            m_idle.start();
    });
    m_idle.start();
}

void Service::touch()
{
    m_idle.start();
}

// ——— Ustawienia ———

QString Service::providerId() const
{
    // Domyślnie model lokalny: dopóki ktoś nie wybierze chmury, nic nie wychodzi z komputera
    const QString id = config().value(QStringLiteral("provider"), QStringLiteral("lokalny")).toString();
    return Catalog::find(id).valid() ? id : QStringLiteral("lokalny");
}

QString Service::modelFor(const Provider &p) const
{
    const QString m = config().value(p.id + QStringLiteral("/model")).toString().trimmed();
    return m.isEmpty() ? p.defaultModel : m;
}

QString Service::urlFor(const Provider &p) const
{
    // Do testów (atrapa z tools/asystent-atrapa.py): wszystkie zapytania pod wskazany adres
    const QString test = qEnvironmentVariable("ASTER_ASSISTANT_URL");
    if (!test.isEmpty())
        return test;
    QString u = p.editableUrl ? config().value(p.id + QStringLiteral("/url")).toString().trimmed() : QString();
    if (u.isEmpty())
        u = p.baseUrl;
    while (u.endsWith(QLatin1Char('/')))
        u.chop(1);
    return u;
}

bool Service::historyEnabled() const
{
    return config().value(QStringLiteral("history"), true).toBool();
}

QString Service::apiKey(const Provider &p, QString *error)
{
    if (!p.needsKey)
        return {};
    // Do testów i pracy nad kodem: klucz ze zmiennej środowiska zamiast portfela
    const QString env = qEnvironmentVariable("ASTER_ASSISTANT_API_KEY");
    if (!env.isEmpty())
        return env;
    if (m_keys.contains(p.id))
        return m_keys.value(p.id);
    const QString k = Secrets::read(p.id, error);
    if (!k.isEmpty())
        m_keys.insert(p.id, k);
    return k;
}

QString Service::badgeFor(const Provider &p) const
{
    if (!p.needsKey) {
        const QString url = urlFor(p);
        return Catalog::isLoopback(url) ? QStringLiteral("Na tym komputerze") : QStringLiteral("Serwer: %1").arg(QUrl(url).host());
    }
    return QStringLiteral("Chmura: %1").arg(p.name);
}

QVariantMap Service::Status()
{
    touch();
    const Provider p = Catalog::find(providerId());
    const QString url = urlFor(p);
    QString problem;
    bool hasKey = !p.needsKey;
    if (p.needsKey) {
        // Bez otwierania portfela: tylko to, co już wiemy (klucz z pamięci albo ze środowiska)
        hasKey = m_keys.contains(p.id) || !qEnvironmentVariableIsEmpty("ASTER_ASSISTANT_API_KEY")
              || config().value(p.id + QStringLiteral("/hasKey")).toBool();
        if (!hasKey)
            problem = QStringLiteral("Brak klucza API dla %1 — dodaj go w Ustawieniach → Asystent").arg(p.name);
    }
    return {{QStringLiteral("provider"), p.id},
            {QStringLiteral("providerName"), p.name},
            {QStringLiteral("model"), modelFor(p)},
            {QStringLiteral("baseUrl"), url},
            {QStringLiteral("local"), !p.needsKey && Catalog::isLoopback(url)},
            {QStringLiteral("badge"), badgeFor(p)},
            {QStringLiteral("region"), p.region},
            {QStringLiteral("ready"), problem.isEmpty()},
            {QStringLiteral("problem"), problem},
            {QStringLiteral("hasKey"), hasKey},
            {QStringLiteral("history"), historyEnabled()}};
}

QString Service::Providers()
{
    touch();
    QSettings c = config();
    QJsonArray out;
    for (const Provider &p : Catalog::all()) {
        QVariantMap m = p.toMap();
        m.insert(QStringLiteral("model"), modelFor(p));
        m.insert(QStringLiteral("url"), urlFor(p));
        m.insert(QStringLiteral("hasKey"), !p.needsKey || m_keys.contains(p.id) || c.value(p.id + QStringLiteral("/hasKey")).toBool());
        out.append(QJsonObject::fromVariantMap(m));
    }
    return QString::fromUtf8(QJsonDocument(out).toJson(QJsonDocument::Compact));
}

void Service::Configure(const QVariantMap &s)
{
    touch();
    QSettings c = config();
    if (s.contains(QStringLiteral("provider"))) {
        const QString id = s.value(QStringLiteral("provider")).toString();
        if (!Catalog::find(id).valid()) {
            if (calledFromDBus())
                sendErrorReply(QDBusError::InvalidArgs, QStringLiteral("Nieznany dostawca: %1").arg(id));
            return;
        }
        c.setValue(QStringLiteral("provider"), id);
    }
    const QString target = s.value(QStringLiteral("for"), c.value(QStringLiteral("provider"), QStringLiteral("lokalny"))).toString();
    if (s.contains(QStringLiteral("model")))
        c.setValue(target + QStringLiteral("/model"), s.value(QStringLiteral("model")).toString().trimmed());
    if (s.contains(QStringLiteral("baseUrl")))
        c.setValue(target + QStringLiteral("/url"), s.value(QStringLiteral("baseUrl")).toString().trimmed());
    if (s.contains(QStringLiteral("history"))) {
        c.setValue(QStringLiteral("history"), s.value(QStringLiteral("history")).toBool());
        if (!s.value(QStringLiteral("history")).toBool())
            ClearHistory();
    }
    c.sync();
    Q_EMIT StatusChanged();
}

bool Service::SetApiKey(const QString &provider, const QString &key)
{
    touch();
    const Provider p = Catalog::find(provider);
    if (!p.valid() || !p.needsKey) {
        if (calledFromDBus())
            sendErrorReply(QDBusError::InvalidArgs, QStringLiteral("Ten dostawca nie potrzebuje klucza"));
        return false;
    }
    QString error;
    const QString k = key.trimmed();
    if (!Secrets::write(p.id, p.name, k, &error)) {
        if (calledFromDBus())
            sendErrorReply(QDBusError::Failed, error.isEmpty() ? QStringLiteral("Nie udało się zapisać klucza w portfelu") : error);
        return false;
    }
    if (k.isEmpty())
        m_keys.remove(p.id);
    else
        m_keys.insert(p.id, k);
    // W pliku tylko informacja, że klucz jest (sam klucz — w portfelu)
    QSettings c = config();
    c.setValue(p.id + QStringLiteral("/hasKey"), !k.isEmpty());
    c.sync();
    Q_EMIT StatusChanged();
    return true;
}

// ——— Historia ———

QString Service::historyDir() const
{
    return QStandardPaths::writableLocation(QStandardPaths::GenericDataLocation) + QStringLiteral("/aster/asystent");
}

static QJsonObject toJson(const QString &id, const QString &title, qint64 updated)
{
    return {{QStringLiteral("id"), id}, {QStringLiteral("title"), title}, {QStringLiteral("updated"), updated}};
}

Service::Conv *Service::conversation(const QString &id, bool create)
{
    if (!id.isEmpty()) {
        auto it = m_convs.find(id);
        if (it != m_convs.end())
            return &it.value();
        // Z historii na dysku
        QFile f(historyDir() + QLatin1Char('/') + id + QStringLiteral(".json"));
        if (!id.contains(QLatin1Char('/')) && f.open(QIODevice::ReadOnly)) {
            const QJsonObject o = QJsonDocument::fromJson(f.readAll()).object();
            Conv c;
            c.id = id;
            c.title = o.value(QStringLiteral("title")).toString();
            c.updated = o.value(QStringLiteral("updated")).toInteger();
            for (const QJsonValue &v : o.value(QStringLiteral("messages")).toArray()) {
                const QJsonObject m = v.toObject();
                c.messages.append({m.value(QStringLiteral("role")).toString(), m.value(QStringLiteral("text")).toString(),
                                   m.value(QStringLiteral("context")).toString(), m.value(QStringLiteral("badge")).toString(),
                                   m.value(QStringLiteral("time")).toInteger()});
            }
            return &m_convs.insert(id, c).value();
        }
    }
    if (!create)
        return nullptr;
    Conv c;
    c.id = QDateTime::currentDateTime().toString(QStringLiteral("yyyyMMdd-HHmmss-"))
         + QString::number(QRandomGenerator::global()->bounded(0x10000), 16);
    c.updated = QDateTime::currentMSecsSinceEpoch();
    return &m_convs.insert(c.id, c).value();
}

void Service::save(const Conv &c)
{
    if (!historyEnabled())
        return;
    QDir().mkpath(historyDir());
    QJsonObject o = toJson(c.id, c.title, c.updated);
    QJsonArray msgs;
    for (const Message &m : c.messages) {
        QJsonObject j{{QStringLiteral("role"), m.role}, {QStringLiteral("text"), m.text}, {QStringLiteral("time"), m.time}};
        if (!m.badge.isEmpty())
            j.insert(QStringLiteral("badge"), m.badge);
        if (!m.context.isEmpty())
            j.insert(QStringLiteral("context"), m.context);
        msgs.append(j);
    }
    o.insert(QStringLiteral("messages"), msgs);
    QSaveFile f(historyDir() + QLatin1Char('/') + c.id + QStringLiteral(".json"));
    if (f.open(QIODevice::WriteOnly)) {
        f.write(QJsonDocument(o).toJson(QJsonDocument::Compact));
        f.commit();
        QFile::setPermissions(f.fileName(), QFile::ReadOwner | QFile::WriteOwner);
    }
    Q_EMIT HistoryChanged();
}

QString Service::Conversations()
{
    touch();
    QHash<QString, QJsonObject> found;
    if (historyEnabled()) {
        const QDir dir(historyDir());
        for (const QFileInfo &fi : dir.entryInfoList({QStringLiteral("*.json")}, QDir::Files)) {
            QFile f(fi.filePath());
            if (!f.open(QIODevice::ReadOnly))
                continue;
            const QJsonObject o = QJsonDocument::fromJson(f.readAll()).object();
            QJsonObject e = toJson(fi.completeBaseName(), o.value(QStringLiteral("title")).toString(), o.value(QStringLiteral("updated")).toInteger());
            e.insert(QStringLiteral("count"), o.value(QStringLiteral("messages")).toArray().size());
            found.insert(fi.completeBaseName(), e);
        }
    }
    for (const Conv &c : std::as_const(m_convs)) {
        if (c.messages.isEmpty())
            continue;
        QJsonObject e = toJson(c.id, c.title, c.updated);
        e.insert(QStringLiteral("count"), c.messages.size());
        found.insert(c.id, e);
    }
    QList<QJsonObject> list = found.values();
    std::sort(list.begin(), list.end(), [](const QJsonObject &a, const QJsonObject &b) {
        return a.value(QStringLiteral("updated")).toInteger() > b.value(QStringLiteral("updated")).toInteger();
    });
    QJsonArray out;
    for (const QJsonObject &o : list)
        out.append(o);
    return QString::fromUtf8(QJsonDocument(out).toJson(QJsonDocument::Compact));
}

QString Service::Conversation(const QString &id)
{
    touch();
    const Conv *c = conversation(id, false);
    if (!c)
        return QStringLiteral("{}");
    QJsonObject o = toJson(c->id, c->title, c->updated);
    QJsonArray msgs;
    for (const Message &m : c->messages)
        msgs.append(QJsonObject{{QStringLiteral("role"), m.role}, {QStringLiteral("text"), m.text},
                                {QStringLiteral("badge"), m.badge}, {QStringLiteral("time"), m.time}});
    o.insert(QStringLiteral("messages"), msgs);
    return QString::fromUtf8(QJsonDocument(o).toJson(QJsonDocument::Compact));
}

void Service::DeleteConversation(const QString &id)
{
    touch();
    if (id.isEmpty() || id.contains(QLatin1Char('/')))
        return;
    Cancel(id);
    m_convs.remove(id);
    QFile::remove(historyDir() + QLatin1Char('/') + id + QStringLiteral(".json"));
    Q_EMIT HistoryChanged();
}

void Service::ClearHistory()
{
    touch();
    QDir dir(historyDir());
    for (const QString &f : dir.entryList({QStringLiteral("*.json")}, QDir::Files))
        dir.remove(f);
    // Trwające rozmowy zostają w pamięci (panel ich używa), zakończone znikają
    for (auto it = m_convs.begin(); it != m_convs.end();) {
        bool active = false;
        for (const Request &r : std::as_const(m_requests))
            active |= r.conversation == it.key();
        it = active ? std::next(it) : m_convs.erase(it);
    }
    Q_EMIT HistoryChanged();
}

// ——— Pytania ———

QString Service::systemPrompt(const QString &source) const
{
    QString s = QStringLiteral(
        "Jesteś Asystentem Aster — pomocnikiem wbudowanym w system Aster (Linux oparty na Fedorze 44, atomowy obraz bootc/ostree, "
        "własna powłoka na KWin i Waylandzie). Odpowiadaj w języku pytania (zwykle po polsku), krótko, konkretnie i prostym językiem — "
        "także dla kogoś, kto nie zna Linuksa. System plików systemu jest tylko do odczytu: programy instaluje się jako Flatpaki "
        "(Sklep Aster albo `flatpak install`), narzędzia deweloperskie w `toolbox`; nie proponuj `dnf install` bez wyjaśnienia. "
        "Komendę do terminala proponuj tylko wtedy, gdy użytkownik chce coś zrobić w systemie albo w terminalu — na pytania, "
        "obliczenia i tłumaczenia odpowiadaj wprost, zwykłym tekstem. Komendę umieść w osobnym bloku ```bash (jedna czynność na blok) "
        "— użytkownik zobaczy ją i sam zdecyduje, czy ją uruchomić. Nie wymyślaj faktów; gdy czegoś nie wiesz, powiedz to.");
    if (source == QLatin1String("terminal"))
        s += QStringLiteral(" Rozmowa toczy się w terminalu: pisz zwykłym tekstem, bez tabel i nagłówków Markdown; komendy w blokach ```bash.");
    else if (source == QLatin1String("wyspa"))
        s += QStringLiteral(" Pytanie zadano z górnego paska: jeśli się da, odpowiedz jednym–dwoma zdaniami, bez wstępów.");
    s += QStringLiteral(" Dzisiaj jest %1.").arg(QDate::currentDate().toString(Qt::ISODate));
    return s;
}

QString Service::Ask(const QString &conversationId, const QString &prompt, const QString &context, const QString &source)
{
    touch();
    Conv *c = conversation(conversationId, true);
    // Nowe pytanie w tej samej rozmowie przerywa poprzednią odpowiedź
    Cancel(c->id);
    QString ctx = context;
    if (ctx.size() > kMaxContext)
        ctx = ctx.left(8000) + QStringLiteral("\n[… pominięto %1 znaków …]\n").arg(ctx.size() - kMaxContext) + ctx.right(kMaxContext - 8000);
    QString text = prompt.trimmed();
    if (text.isEmpty())
        text = ctx.isEmpty() ? QString() : QStringLiteral("Wyjaśnij krótko, co tu jest.");
    if (text.isEmpty()) {
        const QString id = c->id;
        QTimer::singleShot(0, this, [this, id] { fail(id, QStringLiteral("Puste pytanie")); });
        return c->id;
    }
    if (c->title.isEmpty())
        c->title = text.left(80).simplified();
    c->messages.append({QStringLiteral("user"), text, ctx, QString(), QDateTime::currentMSecsSinceEpoch()});
    c->updated = QDateTime::currentMSecsSinceEpoch();
    start(*c, source);
    return c->id;
}

void Service::Cancel(const QString &conversation)
{
    for (auto it = m_requests.begin(); it != m_requests.end(); ++it)
        if (it.value().conversation == conversation) {
            QNetworkReply *r = it.key();
            m_requests.erase(it);
            r->abort();
            r->deleteLater();
            return;
        }
}

void Service::fail(const QString &conversation, const QString &message)
{
    Q_EMIT Failed(conversation, message);
}

void Service::start(Conv &c, const QString &source)
{
    const Provider p = Catalog::find(providerId());
    QString error;
    const QString key = apiKey(p, &error);
    const QString id = c.id;
    if (p.needsKey && key.isEmpty()) {
        const QString msg = QStringLiteral("Brak klucza API dla %1 — dodaj go w Ustawieniach → Asystent%2")
                                .arg(p.name, error.isEmpty() ? QString() : QStringLiteral(" (%1)").arg(error));
        QTimer::singleShot(0, this, [this, id, msg] { fail(id, msg); });
        return;
    }

    // Ostatnie wiadomości rozmowy; dane z potoku dołączone do pytania, którego dotyczą
    QJsonArray messages;
    const int from = std::max(0, int(c.messages.size()) - kContextMessages);
    for (int i = from; i < c.messages.size(); ++i) {
        const Message &m = c.messages.at(i);
        QString content = m.text;
        if (!m.context.isEmpty())
            content += QStringLiteral("\n\nDane wejściowe:\n```\n%1\n```").arg(m.context);
        messages.append(QJsonObject{{QStringLiteral("role"), m.role}, {QStringLiteral("content"), content}});
    }

    const QString base = urlFor(p);
    const QString model = modelFor(p);
    QJsonObject body{{QStringLiteral("model"), model}, {QStringLiteral("stream"), true}};
    QNetworkRequest req;
    req.setHeader(QNetworkRequest::ContentTypeHeader, QStringLiteral("application/json"));
    req.setRawHeader("Accept", "text/event-stream");
    req.setRawHeader("User-Agent", "aster-assistant/0.1");
    req.setTransferTimeout(180000);
    if (p.kind == Provider::Anthropic) {
        req.setUrl(QUrl(base + QStringLiteral("/messages")));
        req.setRawHeader("x-api-key", key.toUtf8());
        req.setRawHeader("anthropic-version", "2023-06-01");
        body.insert(QStringLiteral("system"), systemPrompt(source));
        body.insert(QStringLiteral("max_tokens"), 4096);
        body.insert(QStringLiteral("messages"), messages);
    } else {
        req.setUrl(QUrl(base + QStringLiteral("/chat/completions")));
        if (!key.isEmpty())
            req.setRawHeader("Authorization", "Bearer " + key.toUtf8());
        if (p.id == QLatin1String("openrouter")) {
            req.setRawHeader("X-Title", "Aster");
            req.setRawHeader("HTTP-Referer", "https://github.com/Feejd/Aster");
        }
        messages.prepend(QJsonObject{{QStringLiteral("role"), QStringLiteral("system")}, {QStringLiteral("content"), systemPrompt(source)}});
        body.insert(QStringLiteral("messages"), messages);
    }

    QNetworkReply *reply = m_net.post(req, QJsonDocument(body).toJson(QJsonDocument::Compact));
    Request r;
    r.conversation = id;
    r.badge = badgeFor(p);
    r.providerName = p.name;
    r.url = base;
    r.anthropic = p.kind == Provider::Anthropic;
    r.local = !p.needsKey;
    m_requests.insert(reply, r);
    connect(reply, &QNetworkReply::readyRead, this, [this, reply] { onData(reply); });
    connect(reply, &QNetworkReply::finished, this, [this, reply] { onFinished(reply); });
}

// Strumień SSE: wiersze „data: {…}”; w OpenAI tekst w choices[0].delta.content, w Anthropic — w content_block_delta
void Service::onData(QNetworkReply *reply)
{
    auto it = m_requests.find(reply);
    if (it == m_requests.end())
        return;
    Request &r = it.value();
    const int status = reply->attribute(QNetworkRequest::HttpStatusCodeAttribute).toInt();
    if (status >= 400) {
        r.errorBody += reply->readAll();
        return;
    }
    r.pending += reply->readAll();
    QString delta;
    int nl;
    while ((nl = r.pending.indexOf('\n')) >= 0) {
        const QByteArray line = r.pending.left(nl).trimmed();
        r.pending.remove(0, nl + 1);
        if (!line.startsWith("data:"))
            continue;
        const QByteArray data = line.mid(5).trimmed();
        if (data.isEmpty() || data == "[DONE]")
            continue;
        const QJsonObject o = QJsonDocument::fromJson(data).object();
        if (o.contains(QStringLiteral("error"))) {
            const QJsonValue e = o.value(QStringLiteral("error"));
            r.errorBody = e.isObject() ? e.toObject().value(QStringLiteral("message")).toString().toUtf8() : e.toString().toUtf8();
            continue;
        }
        if (r.anthropic) {
            if (o.value(QStringLiteral("type")).toString() == QLatin1String("content_block_delta"))
                delta += o.value(QStringLiteral("delta")).toObject().value(QStringLiteral("text")).toString();
        } else {
            const QJsonArray choices = o.value(QStringLiteral("choices")).toArray();
            if (!choices.isEmpty())
                delta += choices.at(0).toObject().value(QStringLiteral("delta")).toObject().value(QStringLiteral("content")).toString();
        }
    }
    if (!delta.isEmpty()) {
        r.text += delta;
        Q_EMIT Chunk(r.conversation, delta);
    }
}

static QString httpProblem(int status, const QString &provider, const QString &detail)
{
    QString what;
    switch (status) {
    case 400: what = QStringLiteral("serwer odrzucił zapytanie (może zła nazwa modelu?)"); break;
    case 401:
    case 403: what = QStringLiteral("klucz API jest nieprawidłowy albo nie ma dostępu"); break;
    case 402: what = QStringLiteral("brak środków na koncie"); break;
    case 404: what = QStringLiteral("nie ma takiego modelu albo adresu"); break;
    case 429: what = QStringLiteral("za dużo zapytań albo wyczerpany limit — spróbuj za chwilę"); break;
    default: what = status >= 500 ? QStringLiteral("serwer ma kłopot (%1) — spróbuj za chwilę").arg(status) : QStringLiteral("błąd %1").arg(status);
    }
    QString msg = QStringLiteral("%1: %2").arg(provider, what);
    if (!detail.isEmpty())
        msg += QStringLiteral(" — ") + detail.left(300);
    return msg;
}

void Service::onFinished(QNetworkReply *reply)
{
    reply->deleteLater();
    auto it = m_requests.find(reply);
    if (it == m_requests.end())
        return;           // przerwane (Cancel)
    onData(reply);
    Request r = it.value();
    m_requests.erase(m_requests.find(reply));
    touch();

    const int status = reply->attribute(QNetworkRequest::HttpStatusCodeAttribute).toInt();
    QString problem;
    if (status >= 400) {
        const QJsonObject o = QJsonDocument::fromJson(r.errorBody).object();
        QJsonValue e = o.value(QStringLiteral("error"));
        QString detail = e.isObject() ? e.toObject().value(QStringLiteral("message")).toString() : e.toString();
        if (detail.isEmpty() && o.isEmpty())
            detail = QString::fromUtf8(r.errorBody).simplified();
        problem = httpProblem(status, r.providerName, detail);
    } else if (reply->error() != QNetworkReply::NoError) {
        if (r.local && (reply->error() == QNetworkReply::ConnectionRefusedError || reply->error() == QNetworkReply::HostNotFoundError))
            problem = QStringLiteral("Model lokalny nie odpowiada pod %1 — uruchom llama-server albo Ollamę, "
                                     "albo wybierz dostawcę w Ustawieniach → Asystent").arg(r.url);
        else if (reply->error() == QNetworkReply::OperationCanceledError || reply->error() == QNetworkReply::TimeoutError)
            problem = QStringLiteral("%1 nie odpowiedział na czas").arg(r.providerName);
        else
            problem = QStringLiteral("%1: brak połączenia (%2)").arg(r.providerName, reply->errorString());
    } else if (!r.errorBody.isEmpty()) {
        problem = QStringLiteral("%1: %2").arg(r.providerName, QString::fromUtf8(r.errorBody));
    } else if (r.text.trimmed().isEmpty()) {
        problem = QStringLiteral("%1 nie zwrócił odpowiedzi").arg(r.providerName);
    }

    Conv *c = conversation(r.conversation, false);
    if (!problem.isEmpty()) {
        // Pytanie bez odpowiedzi nie zostaje w rozmowie — można zapytać jeszcze raz
        if (c && !c->messages.isEmpty() && c->messages.last().role == QLatin1String("user") && r.text.isEmpty())
            c->messages.removeLast();
        fail(r.conversation, problem);
        return;
    }
    if (c) {
        c->messages.append({QStringLiteral("assistant"), r.text, QString(), r.badge, QDateTime::currentMSecsSinceEpoch()});
        c->updated = QDateTime::currentMSecsSinceEpoch();
        save(*c);
    }
    Q_EMIT Finished(r.conversation, r.text, r.badge);
}
