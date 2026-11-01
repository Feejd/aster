#pragma once

#include <QDBusConnection>
#include <QDBusMessage>
#include <QDBusPendingCallWatcher>
#include <QDBusPendingReply>
#include <QDBusVariant>
#include <QFile>
#include <QObject>
#include <QProcess>
#include <QStandardPaths>
#include <functional>

// Wspólne drobiazgi zaplecza Ustawień: tryb podglądu, polecenia w tle, wywołania D-Bus

// ASTER_PREVIEW: zrzuty w kontenerze — zaplecze podstawia przykładowe dane i niczego nie zmienia w systemie
inline bool asterPreview()
{
    return !qEnvironmentVariableIsEmpty("ASTER_PREVIEW");
}

inline QString readTextFile(const QString &path)
{
    QFile f(path);
    return f.open(QIODevice::ReadOnly) ? QString::fromUtf8(f.readAll()).trimmed() : QString();
}

// Polecenie w tle (z angielskimi komunikatami — łatwiej je czytać); done(wyjście, kod wyjścia)
inline void runAsync(QObject *context, const QString &program, const QStringList &args,
                     std::function<void(const QString &out, int code)> done = {}, const QByteArray &input = {})
{
    if (QStandardPaths::findExecutable(program).isEmpty()) {
        if (done)
            done(QString(), -1);
        return;
    }
    auto *p = new QProcess(context);
    auto env = QProcessEnvironment::systemEnvironment();
    env.insert(QStringLiteral("LC_ALL"), QStringLiteral("C"));
    p->setProcessEnvironment(env);
    QObject::connect(p, &QProcess::finished, context, [p, done](int code) {
        if (done)
            done(QString::fromUtf8(p->readAllStandardOutput()), code);
        p->deleteLater();
    });
    QObject::connect(p, &QProcess::errorOccurred, context, [p, done](QProcess::ProcessError e) {
        if (e == QProcess::FailedToStart) {
            if (done)
                done(QString(), -1);
            p->deleteLater();
        }
    });
    p->start(program, args);
    if (!input.isEmpty()) {
        p->write(input);
        p->closeWriteChannel();
    }
}

// Asynchroniczne wywołanie D-Bus; interactive = polkit może zapytać o hasło (wtedy dłuższy czas oczekiwania)
inline void dbusCall(QObject *context, QDBusMessage msg, bool systemBus, bool interactive,
                     std::function<void(const QDBusMessage &reply)> done = {})
{
    msg.setInteractiveAuthorizationAllowed(interactive);
    QDBusConnection bus = systemBus ? QDBusConnection::systemBus() : QDBusConnection::sessionBus();
    auto *w = new QDBusPendingCallWatcher(bus.asyncCall(msg, interactive ? 180000 : 8000), context);
    QObject::connect(w, &QDBusPendingCallWatcher::finished, context, [w, done](QDBusPendingCallWatcher *) {
        if (done)
            done(w->reply());
        w->deleteLater();
    });
}

inline QDBusMessage dbusMethod(const QString &service, const QString &path, const QString &iface, const QString &method, const QVariantList &args = {})
{
    QDBusMessage m = QDBusMessage::createMethodCall(service, path, iface, method);
    m.setArguments(args);
    return m;
}

// Wszystkie właściwości obiektu (org.freedesktop.DBus.Properties.GetAll)
inline void dbusGetAll(QObject *context, const QString &service, const QString &path, const QString &iface, bool systemBus,
                       std::function<void(const QVariantMap &)> done)
{
    dbusCall(context, dbusMethod(service, path, QStringLiteral("org.freedesktop.DBus.Properties"), QStringLiteral("GetAll"), {iface}), systemBus, false,
             [done](const QDBusMessage &r) {
                 QVariantMap out;
                 if (r.type() == QDBusMessage::ReplyMessage && !r.arguments().isEmpty())
                     qvariant_cast<QDBusArgument>(r.arguments().first()) >> out;
                 done(out);
             });
}

inline void dbusSetProperty(QObject *context, const QString &service, const QString &path, const QString &iface, const QString &name,
                            const QVariant &value, bool systemBus, std::function<void(const QDBusMessage &)> done = {})
{
    dbusCall(context, dbusMethod(service, path, QStringLiteral("org.freedesktop.DBus.Properties"), QStringLiteral("Set"),
                                 {iface, name, QVariant::fromValue(QDBusVariant(value))}),
             systemBus, true, done);
}
