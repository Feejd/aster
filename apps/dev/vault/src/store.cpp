#include "store.h"

#include <QDateTime>
#include <QDir>
#include <QFile>
#include <QFileInfo>
#include <QJsonArray>
#include <QJsonDocument>
#include <QSaveFile>
#include <QStandardPaths>
#include <QUuid>

namespace {

QString configFile()
{
    return QStandardPaths::writableLocation(QStandardPaths::GenericConfigLocation) + QStringLiteral("/aster-vault/connections.json");
}

QString historyFile()
{
    return QStandardPaths::writableLocation(QStandardPaths::GenericDataLocation) + QStringLiteral("/aster-vault/history.json");
}

QVariantList readList(const QString &path)
{
    QFile f(path);
    if (!f.open(QIODevice::ReadOnly))
        return {};
    return QJsonDocument::fromJson(f.readAll()).array().toVariantList();
}

void writeList(const QString &path, const QVariantList &list)
{
    QDir().mkpath(QFileInfo(path).absolutePath());
    QSaveFile f(path);
    if (!f.open(QIODevice::WriteOnly))
        return;
    f.write(QJsonDocument(QJsonArray::fromVariantList(list)).toJson(QJsonDocument::Indented));
    f.commit();
    // Nazwy serwerów i użytkowników to też prywatne dane
    QFile::setPermissions(path, QFileDevice::ReadOwner | QFileDevice::WriteOwner);
}

} // namespace

QVariantList Store::connections() { return readList(configFile()); }

void Store::saveConnections(const QVariantList &list)
{
    // Hasło nigdy nie trafia do pliku
    QVariantList clean;
    for (const QVariant &v : list) {
        QVariantMap m = v.toMap();
        m.remove(QStringLiteral("password"));
        clean << m;
    }
    writeList(configFile(), clean);
}

QVariantMap Store::find(const QString &key)
{
    const QVariantList list = connections();
    for (const QVariant &v : list)
        if (v.toMap().value(QStringLiteral("id")).toString() == key)
            return v.toMap();
    for (const QVariant &v : list)
        if (v.toMap().value(QStringLiteral("name")).toString().compare(key, Qt::CaseInsensitive) == 0)
            return v.toMap();
    const QFileInfo fi(key);
    if (fi.isFile()) {
        const QString path = fi.absoluteFilePath();
        for (const QVariant &v : list)
            if (v.toMap().value(QStringLiteral("file")).toString() == path)
                return v.toMap();
        return {{QStringLiteral("id"), QStringLiteral("file:") + path}, {QStringLiteral("name"), fi.fileName()},
                {QStringLiteral("kind"), QStringLiteral("sqlite")}, {QStringLiteral("file"), path}};
    }
    return {};
}

QString Store::newId() { return QUuid::createUuid().toString(QUuid::WithoutBraces).left(8); }

QVariantList Store::history(const QString &connectionId, int limit)
{
    const QVariantList all = readList(historyFile());
    QVariantList out;
    for (int i = int(all.size()) - 1; i >= 0 && out.size() < limit; --i) {
        const QVariantMap m = all.at(i).toMap();
        if (connectionId.isEmpty() || m.value(QStringLiteral("conn")).toString() == connectionId)
            out << m;
    }
    return out;   // najnowsze pierwsze
}

void Store::addHistory(const QVariantMap &entry)
{
    QVariantList all = readList(historyFile());
    QVariantMap e = entry;
    e.insert(QStringLiteral("time"), QDateTime::currentDateTime().toString(Qt::ISODate));
    // To samo zapytanie drugi raz z rzędu — tylko odświeżamy wpis
    if (!all.isEmpty()) {
        const QVariantMap last = all.last().toMap();
        if (last.value(QStringLiteral("conn")) == e.value(QStringLiteral("conn")) && last.value(QStringLiteral("sql")) == e.value(QStringLiteral("sql")))
            all.removeLast();
    }
    all << e;
    while (all.size() > 1000)
        all.removeFirst();
    writeList(historyFile(), all);
}

void Store::clearHistory(const QString &connectionId)
{
    QVariantList all = readList(historyFile()), keep;
    for (const QVariant &v : std::as_const(all))
        if (v.toMap().value(QStringLiteral("conn")).toString() != connectionId)
            keep << v;
    writeList(historyFile(), keep);
}
