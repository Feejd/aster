#include "service.h"
#include "commands.h"
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
#include <QRegularExpression>
#include <QSaveFile>
#include <QSettings>
#include <QProcess>
#include <QStandardPaths>
#include <algorithm>

// Ile ostatnich wiadomości rozmowy idzie do modelu (starsze zostają tylko w historii)
static constexpr int kContextMessages = 24;
// Dane z potoku: większe przycinane (początek i — ważniejszy przy logach — koniec)
static constexpr int kMaxContext = 48000;
// Agent: ile poleceń najwyżej na jedno pytanie i ile znaków wyniku polecenia trafia do modelu
static constexpr int kMaxSteps = 10;
static constexpr int kMaxOutput = 4000;

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
        if (m_requests.isEmpty() && !m_local.busy()) {
            m_local.stop();     // model lokalny nie zajmuje pamięci, gdy nikt nie pyta
            QCoreApplication::quit();
        } else {
            m_idle.start();
        }
    });
    m_idle.start();
    connect(&m_local, &LocalModels::changed, this, [this] {
        Q_EMIT LocalModelsChanged();
        Q_EMIT StatusChanged();
    });
    connect(&m_local, &LocalModels::progress, this, [this](const QString &id, qint64 got, qint64 total) {
        touch();
        Q_EMIT DownloadProgress(id, got, total);
    });
    connect(&m_local, &LocalModels::finished, this, &Service::DownloadFinished);
    // Streszczenia rozmów w tle — chwilę po ostatniej odpowiedzi, jedno naraz
    m_summarize.setSingleShot(true);
    m_summarize.setInterval(qEnvironmentVariableIntValue("ASTER_SUMMARY_DELAY") > 0 ? qEnvironmentVariableIntValue("ASTER_SUMMARY_DELAY") * 1000 : 20000);
    connect(&m_summarize, &QTimer::timeout, this, &Service::summarizeNext);
}

// ——— Modele na tym komputerze ———

QString Service::LocalModels()
{
    touch();
    return QString::fromUtf8(QJsonDocument(m_local.toJson()).toJson(QJsonDocument::Compact));
}

QString Service::DownloadModel(const QString &id)
{
    touch();
    const QString which = id == QLatin1String("auto") ? LocalModels::recommended(LocalModels::hardware()) : id;
    QString error;
    m_local.download(which, &error);
    return error;
}

void Service::CancelDownload()
{
    m_local.cancelDownload();
}

bool Service::UseModel(const QString &id)
{
    touch();
    return m_local.use(id);
}

bool Service::DeleteModel(const QString &id)
{
    touch();
    return m_local.remove(id);
}

bool Service::managedLocal(const Provider &p) const
{
    return p.id == QLatin1String("lokalny") && qEnvironmentVariableIsEmpty("ASTER_ASSISTANT_URL")
        && urlFor(p) == QLatin1String("http://127.0.0.1:8080/v1");
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

bool Service::memoryEnabled() const
{
    return historyEnabled() && config().value(QStringLiteral("memory"), true).toBool();
}

bool Service::askAlways() const
{
    return config().value(QStringLiteral("confirm")).toString() == QLatin1String("zawsze");
}

// Domyślnie pytamy tylko przed ważnymi sprawami; w trybie ostrożnym — przed wszystkim, co nie jest odczytem
bool Service::runsWithoutAsking(const QString &command) const
{
    return askAlways() ? Commands::readOnly(command) : !Commands::needsConsent(command);
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
            problem = QStringLiteral("Brak klucza API dla %1 — dodaj go w Ustawieniach → Aster Intelligence").arg(p.name);
    }
    QString model = modelFor(p);
    if (managedLocal(p)) {
        const QString act = m_local.active();
        model = act.isEmpty() ? QStringLiteral("brak modelu") : LocalModels::find(act).name;
        if (act.isEmpty())
            problem = QStringLiteral("Nie ma jeszcze modelu na tym komputerze — pobierz go w Ustawieniach → Aster Intelligence");
    }
    return {{QStringLiteral("provider"), p.id},
            {QStringLiteral("providerName"), p.name},
            {QStringLiteral("model"), model},
            {QStringLiteral("baseUrl"), url},
            {QStringLiteral("local"), !p.needsKey && Catalog::isLoopback(url)},
            {QStringLiteral("badge"), badgeFor(p)},
            {QStringLiteral("region"), p.region},
            {QStringLiteral("ready"), problem.isEmpty()},
            {QStringLiteral("problem"), problem},
            {QStringLiteral("hasKey"), hasKey},
            {QStringLiteral("history"), historyEnabled()},
            {QStringLiteral("memory"), memoryEnabled()},
            {QStringLiteral("confirm"), askAlways() ? QStringLiteral("zawsze") : QStringLiteral("wazne")}};
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
    if (s.contains(QStringLiteral("memory")))
        c.setValue(QStringLiteral("memory"), s.value(QStringLiteral("memory")).toBool());
    if (s.contains(QStringLiteral("confirm")))
        c.setValue(QStringLiteral("confirm"), s.value(QStringLiteral("confirm")).toString() == QLatin1String("zawsze")
                                                  ? QStringLiteral("zawsze") : QStringLiteral("wazne"));
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
            c.summary = o.value(QStringLiteral("summary")).toString();
            c.summaryCount = o.value(QStringLiteral("summaryCount")).toInt();
            for (const QJsonValue &v : o.value(QStringLiteral("messages")).toArray()) {
                const QJsonObject m = v.toObject();
                c.messages.append({m.value(QStringLiteral("role")).toString(), m.value(QStringLiteral("text")).toString(),
                                   m.value(QStringLiteral("context")).toString(), m.value(QStringLiteral("badge")).toString(),
                                   m.value(QStringLiteral("time")).toInteger(), m.value(QStringLiteral("command")).toString(),
                                   m.value(QStringLiteral("exit")).toInt()});
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
        if (m.role == QLatin1String("action")) {
            j.insert(QStringLiteral("command"), m.command);
            j.insert(QStringLiteral("exit"), m.exitCode);
            j.insert(QStringLiteral("description"), m.context);
        }
        msgs.append(j);
    }
    o.insert(QStringLiteral("messages"), msgs);
    if (!c.summary.isEmpty()) {
        o.insert(QStringLiteral("summary"), c.summary);
        o.insert(QStringLiteral("summaryCount"), c.summaryCount);
    }
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
    for (const Message &m : c->messages) {
        QJsonObject j{{QStringLiteral("role"), m.role}, {QStringLiteral("text"), m.text},
                      {QStringLiteral("badge"), m.badge}, {QStringLiteral("time"), m.time}};
        if (m.role == QLatin1String("action")) {
            j.insert(QStringLiteral("command"), m.command);
            j.insert(QStringLiteral("exit"), m.exitCode);
            j.insert(QStringLiteral("description"), m.context);
        }
        msgs.append(j);
    }
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

QString Service::systemPrompt(const QString &source, const QString &memory) const
{
    QString s = QStringLiteral(
        "Jesteś Aster Intelligence — agentem wbudowanym w system Aster (Linux oparty na Fedorze 44, atomowy obraz bootc/ostree, "
        "własna powłoka na KWin i Waylandzie). Odpowiadaj w języku użytkownika (zwykle po polsku), krótko i prostym językiem — "
        "także dla kogoś, kto nie zna Linuksa.\n\n"
        "DZIAŁASZ, A NIE TYLKO RADZISZ. Gdy użytkownik ma problem albo chce coś zrobić na komputerze, rozwiąż to sam: "
        "napisz jedno polecenie w bloku ```bash i zakończ odpowiedź (jedno polecenie na odpowiedź). Tuż przed blokiem napisz "
        "jedno zdanie zrozumiałe dla laika, co to polecenie zrobi — użytkownik zobaczy tylko to zdanie, nie polecenie. "
        "System je uruchomi i odeśle ci wynik — dopiero wtedy decydujesz o kolejnym kroku. "
        "%1"
        "Najpierw diagnozuj, potem naprawiaj. "
        "Nigdy nie wymyślaj wyniku polecenia. Gdy skończysz, napisz krótko, co zrobiłeś i jaki jest efekt — już bez bloku kodu. "
        "Na zwykłe pytania, obliczenia i tłumaczenia odpowiadaj wprost, bez poleceń.\n"
        "Zasady poleceń: bez programów interaktywnych (nano, vim, less, top — zamiast tego cat, head, top -b -n1); "
        "uprawnienia administratora przez pkexec (nie sudo); dodawaj --noninteractive / -y, gdzie się da; "
        "nie zgaduj nazw programów ani opcji — jeśli nie wiesz, czy coś istnieje, najpierw sprawdź (command -v, flatpak search); "
        "długie wyniki skracaj (np. `flatpak search chrome | head -5`, `journalctl -b -p err -n 30`).\n\n"
        "SYSTEM ASTER: system plików /usr jest tylko do odczytu — NIE używaj dnf ani rpm-ostree install. "
        "Programy instaluje się jako Flatpaki z Flathub: `flatpak install -y --user flathub <id>` (id sprawdź przez `flatpak search`). "
        "Narzędzia deweloperskie: `toolbox`. Aktualizacje systemu: Ustawienia albo `pkexec bootc upgrade`.\n"
        "NAJPIERW PROGRAMY ASTER — są już w systemie, poleć je i uruchamiaj zamiast innych (GNOME, KDE, Fedora):\n"
        "Pliki (aster-files), Przeglądarka (aster-browser), Terminal (aster-terminal), Ustawienia (aster-settings, np. "
        "`aster-settings wifi`), Sklep z programami (aster-store), Edytor tekstu (aster-editor), Aster Code — projekty i kod "
        "(aster --otworz code), Kalkulator (aster-calculator), Zdjęcia (aster-photos), Muzyka (aster-music), Wideo (aster-video), "
        "Podgląd PDF (aster-pdf), Kamera (aster-camera), Skaner (aster-scanner), Grafika — plakaty, posty, CV (aster --otworz grafika), "
        "Montaż — filmy na TikTok/YouTube (aster --otworz montaz), Studio — nagrywanie muzyki (aster --otworz studio), Menedżer zadań "
        "(aster-tasks), Telefon (aster-phone), Aplikacje webowe (aster-webapps), Emoji (aster-emoji). "
        "Program otwierasz jego poleceniem, np. ```bash\naster-files ~/Pobrane\n```. Programu spoza tej listy szukaj w Sklepie "
        "(Flathub) — nigdy nie polecaj programu, którego istnienia nie jesteś pewien.\n"
        "OKNA I PROGRAMY: `aster --otworz NAZWA [plik|adres…]` otwiera dowolny zainstalowany program po zwykłej nazwie "
        "(np. `aster --otworz \"aster code\" ~/strona`, `aster --otworz grafika`, `aster --otworz firefox`) — używaj tego, gdy nie znasz "
        "dokładnego polecenia. Aster Code, Grafika, Montaż i Studio (oraz inne programy Aster) bywają jeszcze niezainstalowane: "
        "gdy `aster --otworz` odpowie, że programu nie ma, zaproponuj `aster --instaluj code` (grafika, montaz, studio…) — "
        "zapytaj „Zainstalować Aster Code?” — a po instalacji otwórz go i dokończ zadanie. Gdy do zadania brakuje programu, "
        "sam go doinstaluj w ten sposób (albo z Flathub), zamiast tłumaczyć użytkownikowi, jak to zrobić. "
        "`aster --okna` pokazuje otwarte okna; `aster --pokaz OKNO`, `aster --zminimalizuj OKNO`, `aster --maksymalizuj OKNO`, "
        "`aster --zamknij-okno OKNO` (OKNO: numer z listy albo nazwa programu/tytuł). Gdy użytkownik mówi o „tym oknie”, "
        "„przeglądarce”, „otwartym pliku” — najpierw sprawdź `aster --okna`.");
    s = s.arg(askAlways()
                  ? QStringLiteral("Polecenia, które tylko coś sprawdzają, uruchamiają się od razu; wszystko, co cokolwiek zmienia, użytkownik "
                                   "najpierw zatwierdza — wtedy zdanie jest pytaniem, np. „Zainstalować Google Chrome?”. ")
                  : QStringLiteral("Zwykłe rzeczy robisz od razu, bez pytania — otwieranie programów i plików, tworzenie folderów, kopiowanie, "
                                   "zmiana głośności czy jasności, sprawdzanie — a zdanie jest wtedy oznajmujące, np. „Otwieram Pliki.”, "
                                   "„Sprawdzam, ile jest wolnego miejsca.”. Pytasz tylko przed ważnymi sprawami: instalacja i odinstalowanie "
                                   "programów, usuwanie albo nadpisywanie plików, uprawnienia administratora, aktualizacja i restart, zatrzymywanie "
                                   "programów i usług, zmiany sieci, dysków i kont — wtedy zdanie jest pytaniem, np. „Zainstalować Google Chrome?”, "
                                   "„Usunąć pliki tymczasowe (1,2 GB)?”. Pytanie zadaje system — ty tylko piszesz zdanie i polecenie. "));
    if (source != QLatin1String("pisanie"))
        s += QStringLiteral(
            "\n\nPAMIĘĆ ROZMÓW: `aster --historia [słowa]` szuka we wcześniejszych rozmowach z użytkownikiem (bez słów — najnowsze), "
            "`aster --rozmowa ID` pokazuje całą rozmowę%1. Gdy użytkownik nawiązuje do czegoś, o czym już rozmawialiście "
            "(„jak ostatnio”, „ta drukarka”, „wróćmy do…”), skorzystaj z poniższych streszczeń, a gdy trzeba szczegółów albo "
            "użytkownik chce wrócić do rozmowy — znajdź ją i otwórz. Nie wspominaj o pamięci, gdy nie ma związku z pytaniem. "
            "Wszystkie rozmowy z tobą są w panelu Aster Intelligence: przycisk z kolorową kulą na górnym pasku, zaraz za Centrum "
            "sterowania (albo Super+Spacja) — tam zegar pokazuje historię.")
                 .arg(source == QLatin1String("terminal") ? QString() : QStringLiteral(" i otwiera ją użytkownikowi w panelu"));
    if (!memory.isEmpty())
        s += QStringLiteral("\nOstatnie rozmowy (od najnowszej):\n") + memory;
    if (source == QLatin1String("terminal"))
        s += QStringLiteral("\nRozmowa toczy się w terminalu: pisz zwykłym tekstem, bez tabel i nagłówków Markdown. "
                            "Polecenia uruchamiają się w bieżącym folderze użytkownika.");
    else if (source == QLatin1String("wyspa"))
        s += QStringLiteral("\nPytanie zadano z górnego paska: na zwykłe pytania odpowiedz jednym–dwoma zdaniami, bez wstępów.");
    else if (source == QLatin1String("pisanie"))
        s = QStringLiteral(
            "Jesteś Aster Intelligence — narzędziem do pisania. Użytkownik zaznaczył tekst (jest w „Dane wejściowe”) i prosi "
            "o jego przeróbkę. Zwróć wyłącznie gotowy tekst — w języku oryginału, bez wstępu, komentarza, cudzysłowów i bloków kodu. "
            "Zachowaj sens, imiona, liczby i podział na akapity; nie dopisuj niczego od siebie.");
    s += QStringLiteral(" Dzisiaj jest %1.").arg(QDate::currentDate().toString(Qt::ISODate));
    return s;
}

// Zdanie dla człowieka: ostatni wiersz tekstu tuż przed blokiem z poleceniem (albo opis według polecenia)
QString Service::describe(const QString &text, const QString &command, bool asks)
{
    const int at = text.indexOf(QLatin1String("```"));
    QStringList before = text.left(at < 0 ? 0 : at).split(QLatin1Char('\n'), Qt::SkipEmptyParts);
    while (!before.isEmpty() && before.last().trimmed().isEmpty())
        before.removeLast();
    QString d = before.isEmpty() ? QString() : before.last().trimmed();
    d.remove(QRegularExpression(QStringLiteral("[*_`#>]")));
    d = d.trimmed();
    if (d.endsWith(QLatin1Char(':')))
        d = d.chopped(1).trimmed() + QLatin1Char('.');
    if (d.size() >= 6 && d.size() <= 220)
        return d;
    // Model nie napisał zdania — przynajmniej najczęstsze sprawy po ludzku
    static const QRegularExpression install(QStringLiteral("flatpak\\s+install\\b.*?\\s([A-Za-z0-9_.-]+\\.[A-Za-z0-9_.-]+)\\s*$"));
    if (const auto m = install.match(command); m.hasMatch())
        return QStringLiteral("Zainstalować program %1?").arg(m.captured(1).section(QLatin1Char('.'), -1));
    if (command.contains(QLatin1String("flatpak uninstall")))
        return QStringLiteral("Odinstalować program?");
    if (command.startsWith(QLatin1String("aster-")))
        return QStringLiteral("Otwieram program.");
    static const QRegularExpression asterInstall(QStringLiteral("^aster\\s+--instaluj\\s+(\\S+)"));
    if (const auto m = asterInstall.match(command); m.hasMatch()) {
        static const QHash<QString, QString> names{{QStringLiteral("code"), QStringLiteral("Aster Code")}, {QStringLiteral("grafika"), QStringLiteral("Grafikę")},
                                                   {QStringLiteral("montaz"), QStringLiteral("Montaż")}, {QStringLiteral("studio"), QStringLiteral("Studio")}};
        return QStringLiteral("Zainstalować %1?").arg(names.value(m.captured(1), QStringLiteral("program Aster")));
    }
    if (command.startsWith(QLatin1String("aster --otworz")))
        return QStringLiteral("Otwieram program.");
    if (command.startsWith(QLatin1String("aster --okna")))
        return QStringLiteral("Sprawdzam, jakie okna są otwarte.");
    if (command.startsWith(QLatin1String("aster --pokaz")))
        return QStringLiteral("Pokazuję okno.");
    if (command.startsWith(QLatin1String("aster --zamknij-okno")))
        return QStringLiteral("Zamknąć to okno?");
    if (command.startsWith(QLatin1String("aster --historia")))
        return QStringLiteral("Szukam w naszych wcześniejszych rozmowach.");
    if (command.startsWith(QLatin1String("aster --rozmowa")))
        return QStringLiteral("Otwieram wcześniejszą rozmowę.");
    return asks ? QStringLiteral("Wprowadzić tę zmianę w systemie?") : QStringLiteral("Robię to na komputerze.");
}

// Pierwsze polecenie z bloku ```bash/sh/shell/console (wiersze zaczynające się od „$ ” bez znaku zachęty)
QString Service::commandIn(const QString &text)
{
    static const QRegularExpression block(QStringLiteral("```(?:bash|sh|shell|zsh|console)[ \\t]*\\n([\\s\\S]*?)```"));
    const QRegularExpressionMatch m = block.match(text);
    if (!m.hasMatch())
        return {};
    QStringList lines;
    for (QString l : m.captured(1).split(QLatin1Char('\n'))) {
        if (l.startsWith(QLatin1String("$ ")))
            l = l.mid(2);
        if (!l.trimmed().isEmpty() && !l.trimmed().startsWith(QLatin1Char('#')))
            lines << l;
    }
    return lines.join(QLatin1Char('\n')).trimmed();
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
    c->source = source;
    c->steps = 0;
    start(*c, source);
    return c->id;
}

void Service::Cancel(const QString &conversation)
{
    if (auto it = m_convs.find(conversation); it != m_convs.end()) {
        it->pendingAction.clear();
        it->pendingCommand.clear();
    }
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

// Model lokalny Astera najpierw trzeba włączyć (llama-server startuje dopiero przy pytaniu)
void Service::start(Conv &c, const QString &source)
{
    const Provider p = Catalog::find(providerId());
    if (!managedLocal(p))
        return send(c, source);
    const QString id = c.id;
    m_local.ensureRunning([this, id, source](bool ok, const QString &problem) {
        Conv *conv = conversation(id, false);
        if (!conv)
            return;
        if (!ok) {
            if (!conv->messages.isEmpty() && conv->messages.last().role == QLatin1String("user"))
                conv->messages.removeLast();
            return fail(id, problem);
        }
        send(*conv, source);
    });
}

void Service::send(Conv &c, const QString &source)
{
    const Provider p = Catalog::find(providerId());
    QString error;
    const QString key = apiKey(p, &error);
    const QString id = c.id;
    if (p.needsKey && key.isEmpty()) {
        const QString msg = QStringLiteral("Brak klucza API dla %1 — dodaj go w Ustawieniach → Aster Intelligence%2")
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
        QString role = m.role;
        if (m.role == QLatin1String("action")) {
            // Wynik polecenia wraca do modelu jako wiadomość od użytkownika (działa u każdego dostawcy)
            role = QStringLiteral("user");
            if (m.exitCode == -2)
                content = QStringLiteral("[System] Użytkownik nie zgodził się uruchomić polecenia `%1`. Nie proponuj już żadnych poleceń "
                                         "w tej sprawie — odpowiedz jednym–dwoma zdaniami, bez bloku kodu.").arg(m.command);
            else
                content = QStringLiteral("[System] Wynik polecenia `%1` (kod wyjścia %2):\n```\n%3\n```")
                              .arg(m.command).arg(m.exitCode).arg(m.text.isEmpty() ? QStringLiteral("(brak wyjścia)") : m.text);
        } else if (!m.context.isEmpty()) {
            content += QStringLiteral("\n\nDane wejściowe:\n```\n%1\n```").arg(m.context);
        }
        messages.append(QJsonObject{{QStringLiteral("role"), role}, {QStringLiteral("content"), content}});
    }

    const bool cloud = p.needsKey;
    const QString memory = memoryEnabled() && source != QLatin1String("pisanie") ? memoryFor(c, cloud) : QString();
    QNetworkReply *reply = post(p, key, systemPrompt(source, memory), messages, true);
    Request r;
    r.conversation = id;
    r.badge = badgeFor(p);
    r.providerName = p.name;
    r.url = urlFor(p);
    r.anthropic = p.kind == Provider::Anthropic;
    r.local = !p.needsKey;
    r.agent = source != QLatin1String("pisanie");
    m_requests.insert(reply, r);
    connect(reply, &QNetworkReply::readyRead, this, [this, reply] { onData(reply); });
    connect(reply, &QNetworkReply::finished, this, [this, reply] { onFinished(reply); });
}

QNetworkReply *Service::post(const Provider &p, const QString &key, const QString &system, QJsonArray messages, bool stream)
{
    const QString base = urlFor(p);
    QJsonObject body{{QStringLiteral("model"), modelFor(p)}, {QStringLiteral("stream"), stream}};
    QNetworkRequest req;
    req.setHeader(QNetworkRequest::ContentTypeHeader, QStringLiteral("application/json"));
    req.setRawHeader("Accept", "text/event-stream");
    req.setRawHeader("User-Agent", "aster-assistant/0.1");
    req.setTransferTimeout(180000);
    if (p.kind == Provider::Anthropic) {
        req.setUrl(QUrl(base + QStringLiteral("/messages")));
        req.setRawHeader("x-api-key", key.toUtf8());
        req.setRawHeader("anthropic-version", "2023-06-01");
        body.insert(QStringLiteral("system"), system);
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
        messages.prepend(QJsonObject{{QStringLiteral("role"), QStringLiteral("system")}, {QStringLiteral("content"), system}});
        body.insert(QStringLiteral("messages"), messages);
    }
    return m_net.post(req, QJsonDocument(body).toJson(QJsonDocument::Compact));
}

// Strumień SSE: wiersze „data: {…}”; w OpenAI tekst w choices[0].delta.content, w Anthropic — w content_block_delta
void Service::onData(QNetworkReply *reply)
{
    auto it = m_requests.find(reply);
    if (it == m_requests.end())
        return;
    Request &r = it.value();
    if (r.stopped) {
        reply->readAll();
        return;
    }
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
        // Agent: po zamknięciu bloku z poleceniem odpowiedź się urywa — model nie zna jeszcze wyniku,
        // więc dalszy tekst byłby zgadywaniem (a na słabym komputerze to też oszczędność czasu)
        static const QRegularExpression block(QStringLiteral("```(?:bash|sh|shell|zsh|console)[ \\t]*\\n[\\s\\S]*?```"));
        const qsizetype before = r.text.size();
        r.text += delta;
        if (r.agent) {
            if (const auto m = block.match(r.text); m.hasMatch()) {
                r.text.truncate(m.capturedEnd());
                delta = r.text.mid(before);
                r.stopped = true;
                QMetaObject::invokeMethod(reply, &QNetworkReply::abort, Qt::QueuedConnection);
            }
        }
        if (!delta.isEmpty() && !r.summary)
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
    if (r.stopped) {
        // urwana celowo po poleceniu — to nie błąd
    } else if (status >= 400) {
        const QJsonObject o = QJsonDocument::fromJson(r.errorBody).object();
        QJsonValue e = o.value(QStringLiteral("error"));
        QString detail = e.isObject() ? e.toObject().value(QStringLiteral("message")).toString() : e.toString();
        if (detail.isEmpty() && o.isEmpty())
            detail = QString::fromUtf8(r.errorBody).simplified();
        problem = httpProblem(status, r.providerName, detail);
    } else if (reply->error() != QNetworkReply::NoError) {
        if (r.local && (reply->error() == QNetworkReply::ConnectionRefusedError || reply->error() == QNetworkReply::HostNotFoundError))
            problem = QStringLiteral("Model lokalny nie odpowiada pod %1 — uruchom llama-server albo Ollamę, "
                                     "albo wybierz dostawcę w Ustawieniach → Aster Intelligence").arg(r.url);
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
    if (r.summary) {
        // Streszczenie w tle: błąd nie przeszkadza (zostaje szybkie streszczenie z tytułu i odpowiedzi)
        QString sum = r.text.simplified();
        sum.remove(QRegularExpression(QStringLiteral("^(Streszczenie|Podsumowanie)\\s*:\\s*"), QRegularExpression::CaseInsensitiveOption));
        if (c && problem.isEmpty() && !sum.isEmpty()) {
            c->summary = sum.left(400);
            c->summaryCount = r.summaryCount;
            save(*c);
        }
        if (!m_toSummarize.isEmpty())
            m_summarize.start(2000);
        return;
    }
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
        // Agent: polecenie w odpowiedzi → klient je uruchamia i odsyła wynik, a model działa dalej
        const QString command = c->source == QLatin1String("pisanie") ? QString() : commandIn(r.text);
        if (!command.isEmpty() && c->steps < kMaxSteps) {
            c->pendingAction = QString::number(QDateTime::currentMSecsSinceEpoch(), 36) + QString::number(c->steps);
            c->pendingCommand = command;
            const bool now = runsWithoutAsking(command);
            c->pendingDescription = describe(r.text, command, !now);
            Q_EMIT ActionRequested(c->id, c->pendingAction, command, c->pendingDescription, now);
            return;
        }
    }
    Q_EMIT Finished(r.conversation, r.text, r.badge);
    if (c && !c->showAfter.isEmpty()) {
        Q_EMIT ShowConversation(c->id, c->showAfter);
        c->showAfter.clear();
    }
    if (c)
        summarizeLater(c->id);
}

void Service::ActionResult(const QString &conv, const QString &action, int exitCode, const QString &output)
{
    touch();
    Conv *c = conversation(conv, false);
    if (!c || action.isEmpty() || c->pendingAction != action)
        return;
    QString out = output;
    // Model lokalny na słabym komputerze czyta wolno — dostaje krótszy wynik
    const int limit = Catalog::find(providerId()).needsKey ? kMaxOutput : kMaxOutput / 2;
    if (out.size() > limit)
        out = out.left(limit / 4) + QStringLiteral("\n[… pominięto %1 znaków …]\n").arg(out.size() - limit) + out.right(limit * 3 / 4);
    // Agent otworzył wcześniejszą rozmowę — panel pokaże ją, gdy skończy odpowiadać
    static const QRegularExpression show(QStringLiteral("^aster\\s+--rozmowa\\s+['\"]?([0-9A-Za-z-]+)"));
    if (const auto m = show.match(c->pendingCommand); m.hasMatch() && exitCode != -2 && c->source != QLatin1String("terminal")
        && QFile::exists(historyDir() + QLatin1Char('/') + m.captured(1) + QStringLiteral(".json")))
        c->showAfter = m.captured(1);
    Message m{QStringLiteral("action"), out.trimmed(), c->pendingDescription, QString(), QDateTime::currentMSecsSinceEpoch(), c->pendingCommand, exitCode};
    c->messages.append(m);
    c->pendingAction.clear();
    c->pendingCommand.clear();
    // Odmowa kończy działanie: model odpowiada już tylko słowami (bez kolejnych prób tego samego)
    c->steps = exitCode == -2 ? kMaxSteps : c->steps + 1;
    c->updated = QDateTime::currentMSecsSinceEpoch();
    save(*c);
    start(*c, c->source);
}

// ——— Pamięć: streszczenia poprzednich rozmów ———

// Rozmowa z udziałem modelu na tym komputerze (albo własnego serwera) — jej treść nie może trafić do chmury
bool Service::localOnly(const QJsonArray &messages)
{
    for (const QJsonValue &v : messages) {
        const QJsonObject m = v.toObject();
        if (m.value(QStringLiteral("role")).toString() == QLatin1String("assistant")
            && !m.value(QStringLiteral("badge")).toString().startsWith(QLatin1String("Chmura")))
            return true;
    }
    return false;
}

static QString withoutCode(QString t)
{
    static const QRegularExpression code(QStringLiteral("```[\\s\\S]*?(```|$)"));
    t.remove(code);
    t.remove(QRegularExpression(QStringLiteral("[*_#>`]")));
    return t.simplified();
}

// Bez modelu: tytuł i początek ostatniej odpowiedzi (dla rozmów, których nie streszczał model)
QString Service::quickSummary(const QString &title, const QJsonArray &messages)
{
    QString last;
    for (qsizetype i = messages.size() - 1; i >= 0 && last.isEmpty(); --i) {
        const QJsonObject m = messages.at(i).toObject();
        if (m.value(QStringLiteral("role")).toString() == QLatin1String("assistant"))
            last = withoutCode(m.value(QStringLiteral("text")).toString());
    }
    if (last.size() > 180)
        last = last.left(180).section(QLatin1Char(' '), 0, -2) + QStringLiteral("…");
    return last.isEmpty() ? title : QStringLiteral("Pytanie: „%1”. Odpowiedź: %2").arg(title, last);
}

static QJsonObject readConversation(const QString &path)
{
    QFile f(path);
    if (!f.open(QIODevice::ReadOnly))
        return {};
    return QJsonDocument::fromJson(f.readAll()).object();
}

// Najnowsze rozmowy (bez bieżącej): „- [ID] data „tytuł”: streszczenie”. Przy chmurze — bez rozmów tylko z tego komputera.
QString Service::memoryFor(const Conv &current, bool cloud) const
{
    const QDir dir(historyDir());
    QStringList lines;
    int read = 0;
    for (const QFileInfo &fi : dir.entryInfoList({QStringLiteral("*.json")}, QDir::Files, QDir::Time)) {
        if (fi.completeBaseName() == current.id)
            continue;
        if (++read > 30 || lines.size() >= 8)
            break;
        const QJsonObject o = readConversation(fi.filePath());
        const QJsonArray msgs = o.value(QStringLiteral("messages")).toArray();
        if (msgs.isEmpty() || (cloud && localOnly(msgs)))
            continue;
        const QString title = o.value(QStringLiteral("title")).toString();
        QString sum = o.value(QStringLiteral("summary")).toString();
        if (sum.isEmpty())
            sum = quickSummary(title, msgs);
        lines << QStringLiteral("- [%1] %2 „%3”: %4")
                     .arg(fi.completeBaseName(),
                          QDateTime::fromMSecsSinceEpoch(o.value(QStringLiteral("updated")).toInteger()).toString(QStringLiteral("yyyy-MM-dd HH:mm")),
                          title, sum);
    }
    return lines.join(QLatin1Char('\n'));
}

// Streszcza tylko model w chmurze (i tylko rozmowy, które już i tak tam były) — model na słabym komputerze
// nie liczy niczego w tle; jego rozmowy mają szybkie streszczenie bez modelu.
void Service::summarizeLater(const QString &id)
{
    if (!memoryEnabled() || !Catalog::find(providerId()).needsKey || qEnvironmentVariableIsSet("ASTER_NO_SUMMARY"))
        return;
    if (!m_toSummarize.contains(id))
        m_toSummarize << id;
    m_summarize.start();
}

void Service::summarizeNext()
{
    for (const Request &r : std::as_const(m_requests))
        if (r.summary)
            return;          // jedno naraz
    while (!m_toSummarize.isEmpty()) {
        const QString id = m_toSummarize.takeFirst();
        Conv *c = conversation(id, false);
        if (!c || c->messages.size() < 2 || c->messages.size() == c->summaryCount || !c->pendingAction.isEmpty())
            continue;
        bool busy = false;
        for (const Request &r : std::as_const(m_requests))
            busy |= r.conversation == id;
        if (busy) {            // rozmowa trwa — streścimy, gdy się skończy
            m_toSummarize << id;
            m_summarize.start();
            return;
        }
        QJsonArray asJson;
        QString transcript;
        for (const Message &m : std::as_const(c->messages)) {
            asJson.append(QJsonObject{{QStringLiteral("role"), m.role}, {QStringLiteral("badge"), m.badge}});
            if (m.role == QLatin1String("user"))
                transcript += QStringLiteral("Użytkownik: ") + m.text.left(1500) + QLatin1Char('\n');
            else if (m.role == QLatin1String("assistant"))
                transcript += QStringLiteral("Asystent: ") + withoutCode(m.text).left(1500) + QLatin1Char('\n');
            else
                transcript += QStringLiteral("(polecenie `%1`, kod %2)\n").arg(m.command.left(200)).arg(m.exitCode);
        }
        const Provider p = Catalog::find(providerId());
        if (!p.needsKey || localOnly(asJson))
            continue;
        QString error;
        const QString key = apiKey(p, &error);
        if (key.isEmpty())
            return;
        if (transcript.size() > 8000)
            transcript = transcript.left(1500) + QStringLiteral("\n[…]\n") + transcript.right(6500);
        const QString system = QStringLiteral(
            "Streszczasz rozmowę użytkownika z asystentem systemu Aster, żeby asystent pamiętał ją w kolejnych rozmowach. "
            "Napisz po polsku jedno–dwa zdania (najwyżej 300 znaków): czego dotyczyła, co ustalono albo zrobiono na komputerze, "
            "co zostało do zrobienia. Konkretnie (nazwy programów, plików, urządzeń), bez wstępu i bez formatowania.");
        QJsonArray msgs{QJsonObject{{QStringLiteral("role"), QStringLiteral("user")}, {QStringLiteral("content"), transcript}}};
        QNetworkReply *reply = post(p, key, system, msgs, true);
        Request r;
        r.conversation = id;
        r.providerName = p.name;
        r.url = urlFor(p);
        r.anthropic = p.kind == Provider::Anthropic;
        r.summary = true;
        r.summaryCount = int(c->messages.size());
        m_requests.insert(reply, r);
        connect(reply, &QNetworkReply::readyRead, this, [this, reply] { onData(reply); });
        connect(reply, &QNetworkReply::finished, this, [this, reply] { onFinished(reply); });
        return;
    }
}

// Bez polskich znaków i wielkości liter („Żółw” = „zolw”)
static QString fold(const QString &t)
{
    QString n = t.toLower().normalized(QString::NormalizationForm_D);
    n.remove(QRegularExpression(QStringLiteral("\\p{Mn}")));
    n.replace(QChar(0x0142), QLatin1Char('l'));
    return n;
}

QString Service::SearchConversations(const QString &phrase, bool agent)
{
    touch();
    const bool hideLocal = agent && Catalog::find(providerId()).needsKey;
    const QStringList words = fold(phrase).split(QRegularExpression(QStringLiteral("\\W+")), Qt::SkipEmptyParts);
    QJsonArray out;
    if (!historyEnabled())
        return QStringLiteral("[]");
    const QDir dir(historyDir());
    for (const QFileInfo &fi : dir.entryInfoList({QStringLiteral("*.json")}, QDir::Files, QDir::Time)) {
        if (out.size() >= 10)
            break;
        // Rozmowa, w której agent właśnie szuka (czeka na wynik polecenia), to nie „wcześniejsza rozmowa”
        if (const auto it = m_convs.constFind(fi.completeBaseName()); it != m_convs.constEnd() && !it->pendingAction.isEmpty())
            continue;
        const QJsonObject o = readConversation(fi.filePath());
        const QJsonArray msgs = o.value(QStringLiteral("messages")).toArray();
        if (msgs.isEmpty())
            continue;
        const bool local = localOnly(msgs);
        if (hideLocal && local)
            continue;
        const QString title = o.value(QStringLiteral("title")).toString();
        QString sum = o.value(QStringLiteral("summary")).toString();
        if (sum.isEmpty())
            sum = quickSummary(title, msgs);
        QString body;
        for (const QJsonValue &v : msgs)
            body += v.toObject().value(QStringLiteral("text")).toString() + QLatin1Char('\n');
        const QString hay = fold(title + QLatin1Char('\n') + sum + QLatin1Char('\n') + body);
        // Słowa dopasowywane po początku (odmiana: „drukark” znajdzie „drukarka” i „drukarki”)
        bool all = true;
        qsizetype first = -1;
        for (const QString &w : words) {
            const QString stem = w.size() > 5 ? w.left(w.size() - 2) : w;
            const qsizetype at = hay.indexOf(stem);
            all &= at >= 0;
            if (first < 0)
                first = at;
        }
        if (!all)
            continue;
        QString snippet;
        const qsizetype bodyStart = title.size() + sum.size() + 2;
        if (first >= bodyStart) {
            const QString plain = QString(title + QLatin1Char('\n') + sum + QLatin1Char('\n') + body);
            snippet = withoutCode(plain.mid(std::max<qsizetype>(bodyStart, first - 60), 180));
        }
        out.append(QJsonObject{{QStringLiteral("id"), fi.completeBaseName()}, {QStringLiteral("title"), title},
                               {QStringLiteral("updated"), o.value(QStringLiteral("updated"))}, {QStringLiteral("summary"), sum},
                               {QStringLiteral("snippet"), snippet}, {QStringLiteral("local"), local}});
    }
    return QString::fromUtf8(QJsonDocument(out).toJson(QJsonDocument::Compact));
}

QString Service::ConversationText(const QString &id, bool agent)
{
    touch();
    if (id.isEmpty() || id.contains(QLatin1Char('/')))
        return {};
    const QJsonObject o = readConversation(historyDir() + QLatin1Char('/') + id + QStringLiteral(".json"));
    const QJsonArray msgs = o.value(QStringLiteral("messages")).toArray();
    if (msgs.isEmpty())
        return {};
    const bool priv = agent && Catalog::find(providerId()).needsKey && localOnly(msgs);
    QString text;
    if (!priv) {
        for (const QJsonValue &v : msgs) {
            const QJsonObject m = v.toObject();
            const QString role = m.value(QStringLiteral("role")).toString();
            if (role == QLatin1String("user"))
                text += QStringLiteral("Ty: ") + m.value(QStringLiteral("text")).toString().trimmed() + QStringLiteral("\n\n");
            else if (role == QLatin1String("assistant")) {
                const QString t = m.value(QStringLiteral("text")).toString().trimmed();
                const QString plain = withoutCode(t);
                if (!plain.isEmpty())
                    text += QStringLiteral("Aster Intelligence: ") + t.section(QStringLiteral("```"), 0, 0).trimmed() + QStringLiteral("\n\n");
            } else {
                text += QStringLiteral("  [%1 — `%2`, %3]\n\n")
                            .arg(m.value(QStringLiteral("description")).toString(), m.value(QStringLiteral("command")).toString(),
                                 m.value(QStringLiteral("exit")).toInt() == -2 ? QStringLiteral("pominięte")
                                 : m.value(QStringLiteral("exit")).toInt() == 0 ? QStringLiteral("zrobione")
                                                                                : QStringLiteral("nie wyszło"));
            }
        }
        if (text.size() > 8000)
            text = QStringLiteral("[… początek pominięty …]\n") + text.right(8000);
    }
    return QString::fromUtf8(QJsonDocument(QJsonObject{
        {QStringLiteral("id"), id}, {QStringLiteral("title"), o.value(QStringLiteral("title"))},
        {QStringLiteral("updated"), o.value(QStringLiteral("updated"))}, {QStringLiteral("private"), priv},
        {QStringLiteral("summary"), o.value(QStringLiteral("summary")).toString().isEmpty() ? quickSummary(o.value(QStringLiteral("title")).toString(), msgs) : o.value(QStringLiteral("summary")).toString()},
        {QStringLiteral("text"), text}}).toJson(QJsonDocument::Compact));
}
