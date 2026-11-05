#pragma once

#include <QObject>
#include <QQmlEngine>

// Aktualizacje systemu: wersja z rpm-ostree, pobieranie przez aster-update.service, restart i powrót do poprzedniej wersji.
class Updates : public QObject
{
    Q_OBJECT
    QML_ELEMENT
    QML_SINGLETON
    Q_PROPERTY(QString version READ version NOTIFY changed)
    Q_PROPERTY(QString installedOn READ installedOn NOTIFY changed)
    Q_PROPERTY(QString readyVersion READ readyVersion NOTIFY changed)        // pobrana, czeka na restart
    Q_PROPERTY(QString previousVersion READ previousVersion NOTIFY changed)
    Q_PROPERTY(bool checking READ checking NOTIFY changed)
    Q_PROPERTY(bool rollbackPending READ rollbackPending NOTIFY changed)
    Q_PROPERTY(QString message READ message NOTIFY changed)

public:
    explicit Updates(QObject *parent = nullptr);

    QString version() const { return m_version; }
    QString installedOn() const { return m_installedOn; }
    QString readyVersion() const { return m_readyVersion; }
    QString previousVersion() const { return m_previousVersion; }
    bool checking() const { return m_checking; }
    bool rollbackPending() const { return m_rollbackPending; }
    QString message() const { return m_message; }

    Q_INVOKABLE void refresh();
    Q_INVOKABLE void check();
    Q_INVOKABLE void restart();
    Q_INVOKABLE void rollback();

Q_SIGNALS:
    void changed();

private:
    QString m_version, m_installedOn, m_readyVersion, m_previousVersion, m_message;
    bool m_checking = false, m_rollbackPending = false;
};
