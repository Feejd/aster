#pragma once

#include <QObject>
#include <QQmlEngine>
#include <QVariantList>

// Konta użytkowników (AccountsService na szynie systemowej — to samo, czego używają KDE i GNOME):
// imię, zdjęcie i hasło własnego konta, lista innych kont, dodawanie i usuwanie (polkit pyta o hasło),
// oraz nazwa komputera (systemd-hostnamed).
class Accounts : public QObject
{
    Q_OBJECT
    QML_ELEMENT
    QML_SINGLETON
    Q_PROPERTY(QString realName MEMBER m_realName NOTIFY changed)
    Q_PROPERTY(QString userName MEMBER m_userName NOTIFY changed)
    Q_PROPERTY(QString iconUrl MEMBER m_iconUrl NOTIFY changed)       // pusty = inicjał
    Q_PROPERTY(bool admin MEMBER m_admin NOTIFY changed)
    Q_PROPERTY(QVariantList others MEMBER m_others NOTIFY changed)    // [{ uid, userName, realName, iconUrl, admin }]
    Q_PROPERTY(QString hostName MEMBER m_hostName NOTIFY changed)
    Q_PROPERTY(bool busy MEMBER m_busy NOTIFY changed)

public:
    explicit Accounts(QObject *parent = nullptr);

    Q_INVOKABLE void refresh();
    Q_INVOKABLE void setRealName(const QString &name);
    Q_INVOKABLE void setIcon(const QString &fileUrl);
    Q_INVOKABLE void setPassword(const QString &password);
    Q_INVOKABLE void createUser(const QString &userName, const QString &realName, bool admin, const QString &password);
    Q_INVOKABLE void deleteUser(qlonglong uid, bool removeFiles);
    Q_INVOKABLE void setHostName(const QString &name);
    // „Jan Kowalski” → „jan” (propozycja nazwy konta)
    Q_INVOKABLE QString suggestUserName(const QString &realName) const;

Q_SIGNALS:
    void changed();
    void message(const QString &text);

private:
    void readUser(const QString &path, bool self);
    void callUser(const QString &path, const QString &method, const QVariantList &args, const QString &ok, const QString &fail);
    static QString hashPassword(const QString &password);

    bool m_preview = false;
    QString m_path;
    QString m_realName, m_userName, m_iconUrl, m_hostName;
    bool m_admin = false, m_busy = false;
    QVariantList m_others;
};
