#pragma once

// Interfejs dla agenta asystenta Aster i skryptów: D-Bus org.aster.Harbor (/org/aster/Harbor)
// i to samo z wiersza poleceń (aster-harbor list|logs|start|stop|restart|images).
// Wyniki w JSON — łatwe do przeczytania przez model językowy i przez programy.

#include <QDBusContext>
#include <QObject>
#include <QString>
#include <QTimer>

class Agent : public QObject, protected QDBusContext
{
    Q_OBJECT
    Q_CLASSINFO("D-Bus Interface", "org.aster.Harbor")
public:
    explicit Agent(QObject *parent = nullptr);

    // Wspólne z CLI: zwracają JSON albo pusty tekst i opis błędu w *err
    static QString list(QString *err);
    static QString images(QString *err);
    static QString logs(const QString &name, int lines, QString *err);
    static QString action(const QString &verb, const QString &name, QString *err);

    void setIdleQuit(int ms);

public Q_SLOTS:
    // [{ name, kind: toolbox|compose|container, state, running, image, ports, project, service, folder, cpu, memory }]
    QString List();
    QString Images();
    QString Logs(const QString &name, int lines);
    QString Start(const QString &name);
    QString Stop(const QString &name);
    QString Restart(const QString &name);
    QString Version() { return QStringLiteral("1"); }

private:
    QString reply(const QString &result, const QString &err);
    QTimer m_idle;
};

// aster-harbor list|logs|start|stop|restart|images … — wynik na stdout, kod wyjścia 0/1
int runCli(const QStringList &args);
