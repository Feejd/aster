#include "podman.h"

#include <QDateTime>
#include <QDir>
#include <QFile>
#include <QFileInfo>
#include <QJsonArray>
#include <QJsonDocument>
#include <QJsonObject>
#include <QLocale>
#include <QProcess>
#include <QRegularExpression>

namespace Pod {

bool inFlatpak()
{
    static const bool f = qEnvironmentVariableIsSet("FLATPAK_ID");
    return f;
}

Cmd host(const QString &program, const QStringList &args)
{
    if (inFlatpak())
        return { QStringLiteral("flatpak-spawn"), QStringList{ QStringLiteral("--host"), QStringLiteral("--watch-bus"), program } + args };
    return { program, args };
}

static QString envOr(const char *name, const QString &fallback)
{
    const QString v = qEnvironmentVariable(name);
    return v.isEmpty() ? fallback : v;
}

Cmd podman(const QStringList &args) { return host(envOr("ASTER_HARBOR_PODMAN", QStringLiteral("podman")), args); }
Cmd toolbox(const QStringList &args) { return host(envOr("ASTER_HARBOR_TOOLBOX", QStringLiteral("toolbox")), args); }

Cmd compose(const QString &file, const QStringList &args)
{
    // Domyślnie `podman compose` (sam wybiera podman-compose albo docker-compose); ASTER_HARBOR_COMPOSE=podman-compose itp.
    const QString custom = qEnvironmentVariable("ASTER_HARBOR_COMPOSE");
    QStringList base;
    QString program;
    if (custom.isEmpty()) {
        program = envOr("ASTER_HARBOR_PODMAN", QStringLiteral("podman"));
        base << QStringLiteral("compose");
    } else {
        QStringList parts = custom.split(QLatin1Char(' '), Qt::SkipEmptyParts);
        program = parts.takeFirst();
        base = parts;
    }
    base << QStringLiteral("-f") << file;
    return host(program, base + args);
}

int run(const Cmd &cmd, QByteArray *out, QString *err, int timeoutMs)
{
    QProcess p;
    p.start(cmd.program, cmd.args);
    if (!p.waitForStarted(5000)) {
        if (err) *err = QStringLiteral("Nie znaleziono programu „%1”.").arg(cmd.program);
        return -1;
    }
    p.closeWriteChannel();
    if (!p.waitForFinished(timeoutMs)) {
        p.kill();
        p.waitForFinished(1000);
        if (err) *err = QStringLiteral("Polecenie trwało za długo.");
        return -2;
    }
    if (out) *out = p.readAllStandardOutput();
    const QString e = QString::fromUtf8(p.readAllStandardError()).trimmed();
    if (err) *err = e.section(QLatin1Char('\n'), -3);   // ostatnie linie — tam podman pisze, co poszło nie tak
    return p.exitStatus() == QProcess::NormalExit ? p.exitCode() : 1;
}

static QJsonArray asArray(const QByteArray &json)
{
    const QJsonDocument doc = QJsonDocument::fromJson(json);
    if (doc.isArray()) return doc.array();
    // Starsze wersje `podman stats` dają jeden obiekt na linię
    QJsonArray a;
    for (const QByteArray &line : json.split('\n')) {
        const QJsonDocument d = QJsonDocument::fromJson(line);
        if (d.isObject()) a.append(d.object());
        else if (d.isArray()) for (const auto &v : d.array()) a.append(v);
    }
    return a;
}

// Wartość pola bez względu na wielkość liter (podman zmieniał nazwy między wersjami)
static QJsonValue field(const QJsonObject &o, std::initializer_list<const char *> names)
{
    for (const char *n : names) {
        const QString key = QString::fromLatin1(n);
        if (o.contains(key)) return o.value(key);
        for (auto it = o.begin(); it != o.end(); ++it)
            if (it.key().compare(key, Qt::CaseInsensitive) == 0) return it.value();
    }
    return {};
}

static QString portsText(const QJsonValue &v, QVariantList *list)
{
    QStringList parts;
    for (const QJsonValue &pv : v.toArray()) {
        const QJsonObject p = pv.toObject();
        const int hostPort = field(p, { "host_port", "hostPort" }).toInt();
        const int ctPort = field(p, { "container_port", "containerPort" }).toInt();
        const int range = qMax(1, field(p, { "range" }).toInt());
        const QString proto = field(p, { "protocol" }).toString(QStringLiteral("tcp"));
        if (!hostPort) continue;
        QString s = QString::number(hostPort);
        if (range > 1) s += QLatin1Char('-') + QString::number(hostPort + range - 1);
        s += QStringLiteral("→") + QString::number(ctPort);
        if (proto != QLatin1String("tcp")) s += QLatin1Char('/') + proto;
        parts << s;
        if (list) list->append(QVariantMap{ { QStringLiteral("host"), hostPort }, { QStringLiteral("container"), ctPort }, { QStringLiteral("protocol"), proto } });
    }
    return parts.join(QStringLiteral(", "));
}

QVariantList parseContainers(const QByteArray &json)
{
    QVariantList out;
    for (const QJsonValue &v : asArray(json)) {
        const QJsonObject o = v.toObject();
        const QJsonValue names = field(o, { "Names" });
        const QString name = names.isArray() ? names.toArray().first().toString() : names.toString();
        const QJsonObject labels = field(o, { "Labels" }).toObject();
        const QString state = field(o, { "State" }).toString().toLower();
        const bool running = state == QLatin1String("running");
        QVariantList portList;
        const QString ports = portsText(field(o, { "Ports" }), &portList);
        const qint64 started = field(o, { "StartedAt" }).toVariant().toLongLong();
        const qint64 exited = field(o, { "ExitedAt" }).toVariant().toLongLong();
        const qint64 created = field(o, { "Created" }).toVariant().toLongLong();
        const bool toolbox = labels.value(QStringLiteral("com.github.containers.toolbox")).toString() == QLatin1String("true")
            || labels.contains(QStringLiteral("com.github.debarshiray.toolbox"));
        QString project = labels.value(QStringLiteral("com.docker.compose.project")).toString();
        if (project.isEmpty()) project = labels.value(QStringLiteral("io.podman.compose.project")).toString();

        QString status;
        if (running) status = QStringLiteral("Działa ") + since(started);
        else if (state == QLatin1String("paused")) status = QStringLiteral("Wstrzymany");
        else if (state == QLatin1String("created") || started <= 0) status = QStringLiteral("Jeszcze nie uruchomiony");
        else if (exited > 0) {
            const int code = field(o, { "ExitCode" }).toInt();
            status = QStringLiteral("Zatrzymany ") + ago(exited) + (code && code != 137 && code != 143 ? QStringLiteral(" · błąd %1").arg(code) : QString());
        } else status = QStringLiteral("Zatrzymany");

        out.append(QVariantMap{
            { QStringLiteral("id"), field(o, { "Id", "ID" }).toString().left(12) },
            { QStringLiteral("name"), name },
            { QStringLiteral("image"), field(o, { "Image" }).toString() },
            { QStringLiteral("state"), state },
            { QStringLiteral("running"), running },
            { QStringLiteral("status"), status },
            { QStringLiteral("ports"), ports },
            { QStringLiteral("portList"), portList },
            { QStringLiteral("toolbox"), toolbox },
            { QStringLiteral("project"), project },
            { QStringLiteral("service"), labels.value(QStringLiteral("com.docker.compose.service")).toString() },
            { QStringLiteral("workdir"), labels.value(QStringLiteral("com.docker.compose.project.working_dir")).toString() },
            { QStringLiteral("configFile"), labels.value(QStringLiteral("com.docker.compose.project.config_files")).toString().section(QLatin1Char(','), 0, 0) },
            { QStringLiteral("created"), created },
            { QStringLiteral("startedAt"), started },
        });
    }
    return out;
}

// „12.5MB / 8GB” → bajty pierwszej liczby
static qint64 parseSize(QString s)
{
    s = s.section(QLatin1Char('/'), 0, 0).trimmed();
    static const QRegularExpression re(QStringLiteral("^([0-9.]+)\\s*([kKMGT]?i?B?)"));
    const auto m = re.match(s);
    if (!m.hasMatch()) return 0;
    double n = m.captured(1).toDouble();
    const QString u = m.captured(2).toUpper();
    const double base = u.contains(QLatin1Char('I')) ? 1024.0 : 1000.0;
    if (u.startsWith(QLatin1Char('K'))) n *= base;
    else if (u.startsWith(QLatin1Char('M'))) n *= base * base;
    else if (u.startsWith(QLatin1Char('G'))) n *= base * base * base;
    else if (u.startsWith(QLatin1Char('T'))) n *= base * base * base * base;
    return qint64(n);
}

QHash<QString, QVariantMap> parseStats(const QByteArray &json)
{
    QHash<QString, QVariantMap> out;
    for (const QJsonValue &v : asArray(json)) {
        const QJsonObject o = v.toObject();
        const QString name = field(o, { "name", "Name" }).toString();
        if (name.isEmpty()) continue;
        QJsonValue cpuV = field(o, { "cpu_percent", "CPUPerc", "CPU" });
        double cpu = cpuV.isString() ? cpuV.toString().remove(QLatin1Char('%')).trimmed().toDouble() : cpuV.toDouble();
        QJsonValue memV = field(o, { "mem_usage", "MemUsage" });
        qint64 mem = memV.isString() ? parseSize(memV.toString()) : qint64(memV.toDouble());
        if (!mem) mem = qint64(field(o, { "MemUsageBytes" }).toDouble());
        out.insert(name, QVariantMap{
            { QStringLiteral("cpu"), cpu },
            { QStringLiteral("mem"), mem },
            { QStringLiteral("memText"), formatBytes(mem) },
        });
    }
    return out;
}

QVariantList parseImages(const QByteArray &json)
{
    QVariantList out;
    for (const QJsonValue &v : asArray(json)) {
        const QJsonObject o = v.toObject();
        QStringList tags;
        for (const QJsonValue &t : field(o, { "Names" }).toArray()) tags << t.toString();
        if (tags.isEmpty())
            for (const QJsonValue &t : field(o, { "RepoTags" }).toArray()) tags << t.toString();
        const QString full = tags.value(0);
        QString name = full, tag;
        const int colon = full.lastIndexOf(QLatin1Char(':'));
        if (colon > full.lastIndexOf(QLatin1Char('/'))) { name = full.left(colon); tag = full.mid(colon + 1); }
        // Krótsza nazwa: bez rejestru i „library/”
        QString shortName = name;
        if (shortName.count(QLatin1Char('/')) >= 1 && shortName.section(QLatin1Char('/'), 0, 0).contains(QLatin1Char('.')))
            shortName = shortName.section(QLatin1Char('/'), 1);
        if (shortName.startsWith(QLatin1String("library/"))) shortName = shortName.mid(8);
        const int containers = field(o, { "Containers" }).toInt();
        out.append(QVariantMap{
            { QStringLiteral("id"), field(o, { "Id", "ID" }).toString().left(12) },
            { QStringLiteral("fullName"), full },
            { QStringLiteral("name"), shortName.isEmpty() ? QStringLiteral("(bez nazwy)") : shortName },
            { QStringLiteral("registry"), name.section(QLatin1Char('/'), 0, 0).contains(QLatin1Char('.')) ? name.section(QLatin1Char('/'), 0, 0) : QString() },
            { QStringLiteral("tag"), tag },
            { QStringLiteral("size"), field(o, { "Size" }).toVariant().toLongLong() },
            { QStringLiteral("sizeText"), formatBytes(field(o, { "Size" }).toVariant().toLongLong()) },
            { QStringLiteral("created"), field(o, { "Created" }).toVariant().toLongLong() },
            { QStringLiteral("createdText"), ago(field(o, { "Created" }).toVariant().toLongLong()) },
            { QStringLiteral("containers"), containers },
            { QStringLiteral("unused"), containers == 0 },
        });
    }
    return out;
}

QString findComposeFile(const QString &folder)
{
    for (const char *n : { "compose.yaml", "compose.yml", "docker-compose.yaml", "docker-compose.yml", "podman-compose.yaml", "podman-compose.yml", "container-compose.yml" }) {
        const QString f = QDir(folder).filePath(QString::fromLatin1(n));
        if (QFileInfo::exists(f)) return f;
    }
    return {};
}

QStringList composeServices(const QString &file)
{
    // Wystarczy prosty odczyt wcięć: klucze na pierwszym poziomie pod `services:`
    QFile f(file);
    QStringList out;
    if (!f.open(QIODevice::ReadOnly)) return out;
    bool inServices = false;
    int indent = -1;
    static const QRegularExpression keyRe(QStringLiteral("^(\\s*)([\"']?)([A-Za-z0-9_.-]+)\\2\\s*:"));
    while (!f.atEnd()) {
        QString raw = QString::fromUtf8(f.readLine());
        raw.chop(raw.endsWith(QLatin1Char('\n')) ? 1 : 0);
        if (raw.trimmed().isEmpty() || raw.trimmed().startsWith(QLatin1Char('#'))) continue;
        const auto m = keyRe.match(raw);
        const int lead = int(raw.indexOf(raw.trimmed()));
        if (lead == 0) {
            inServices = m.hasMatch() && m.captured(3) == QLatin1String("services");
            indent = -1;
            continue;
        }
        if (!inServices || !m.hasMatch()) continue;
        if (indent < 0) indent = lead;
        if (lead == indent) out << m.captured(3);
    }
    return out;
}

QString formatBytes(qint64 b)
{
    const QLocale pl(QLocale::Polish);
    if (b < 1000) return QString::number(b) + QStringLiteral(" B");
    if (b < 1000 * 1000) return pl.toString(b / 1000.0, 'f', 0) + QStringLiteral(" kB");
    if (b < 1000LL * 1000 * 1000) return pl.toString(b / 1e6, 'f', b < 10e6 ? 1 : 0) + QStringLiteral(" MB");
    return pl.toString(b / 1e9, 'f', b < 10e9 ? 2 : 1) + QStringLiteral(" GB");
}

static QString span(qint64 secs)
{
    if (secs < 60) return QStringLiteral("chwilę");
    if (secs < 3600) return QStringLiteral("%1 min").arg(secs / 60);
    if (secs < 86400) return QStringLiteral("%1 godz.").arg(secs / 3600);
    const qint64 d = secs / 86400;
    if (d == 1) return QStringLiteral("1 dzień");
    if (d < 60) return QStringLiteral("%1 dni").arg(d);
    return QStringLiteral("%1 mies.").arg(d / 30);
}

QString ago(qint64 t)
{
    if (t <= 0) return {};
    const qint64 s = QDateTime::currentSecsSinceEpoch() - t;
    return s < 60 ? QStringLiteral("przed chwilą") : span(s) + QStringLiteral(" temu");
}

QString since(qint64 t)
{
    if (t <= 0) return {};
    const qint64 s = QDateTime::currentSecsSinceEpoch() - t;
    return s < 60 ? QStringLiteral("od chwili") : QStringLiteral("od ") + span(s);
}

QString stripAnsi(QString line)
{
    static const QRegularExpression re(QStringLiteral("\x1b\\[[0-9;?]*[A-Za-z]|\x1b\\][^\x07]*\x07"));
    line.remove(re);
    // Paski postępu nadpisują linię znakiem \r — zostaje ostatni stan
    const int cr = line.lastIndexOf(QLatin1Char('\r'), line.size() - 2);
    if (cr >= 0) line = line.mid(cr + 1);
    line.remove(QLatin1Char('\r'));
    return line;
}

bool validName(const QString &name)
{
    static const QRegularExpression re(QStringLiteral("^[a-zA-Z0-9][a-zA-Z0-9_.-]{0,62}$"));
    return re.match(name).hasMatch();
}

}
