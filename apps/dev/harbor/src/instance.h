#pragma once

#include <QObject>

// Jedna kopia okna: drugie uruchomienie tylko przywołuje otwarte okno
class Instance : public QObject
{
    Q_OBJECT
    Q_CLASSINFO("D-Bus Interface", "org.aster.harbor")
public:
    using QObject::QObject;
public Q_SLOTS:
    void Activate(const QString &page, const QString &token) { Q_EMIT activated(page, token); }
Q_SIGNALS:
    void activated(const QString &page, const QString &token);
};
