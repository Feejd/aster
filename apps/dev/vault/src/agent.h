#pragma once

#include <QJsonObject>
#include <QObject>
#include <QTimer>

// Dostęp spoza okna — dla asystenta Aster i terminala. Zawsze tylko do odczytu: połączenie otwierane
// w trybie READ ONLY bazy (SQLite: plik do odczytu, PostgreSQL/MySQL: transakcje tylko do odczytu, limit 30 s)
// i dodatkowo tylko polecenia SELECT/WITH/SHOW/EXPLAIN/DESCRIBE/PRAGMA. Połączenie musi mieć włączony
// „dostęp spoza okna” (pole agent, domyślnie tak). Hasło z portfela — tylko gdy zapisane.
namespace Agent {
QJsonObject list();
QJsonObject schema(const QString &connection, const QString &table);
QJsonObject query(const QString &connection, const QString &sql, int limit);

int runCli(const QStringList &args);   // aster-vault --list / --schema / --query
}

// org.aster.Vault na szynie sesji (/org/aster/Vault). Uruchamiane przez D-Bus na żądanie
// (aster-vault --service), kończy się po 5 minutach bez wywołań. Odpowiedzi to JSON w napisie.
class VaultService : public QObject
{
    Q_OBJECT
    Q_CLASSINFO("D-Bus Interface", "org.aster.Vault")
public:
    explicit VaultService(QObject *parent = nullptr);
public Q_SLOTS:
    QString Connections();
    QString Schema(const QString &connection, const QString &table);
    QString Query(const QString &connection, const QString &sql, int limit);
    QString Version() { return QStringLiteral("1"); }
private:
    QTimer m_idle;
};
