#pragma once

#include <QDBusContext>
#include <QDBusMessage>
#include <QDBusObjectPath>
#include <QObject>
#include <QPointer>
#include <QQmlEngine>
#include <QVariantMap>

class QQmlEngine;
class QQuickWindow;

// Okno „Otwórz / Zapisz” dla całego systemu: backend xdg-desktop-portal
// (interfejs org.freedesktop.impl.portal.FileChooser). Programy — z Flathuba, GTK (Firefox),
// Qt i KDE — proszą portal o plik, a ten woła nas; odpowiadamy, gdy użytkownik wybierze albo anuluje.
class FileChooser : public QObject, protected QDBusContext
{
    Q_OBJECT
    Q_CLASSINFO("D-Bus Interface", "org.freedesktop.impl.portal.FileChooser")

public:
    explicit FileChooser(QQmlEngine *engine, QObject *parent = nullptr);

    // Okno bez D-Bus (podgląd wyglądu, testy): mode "open" | "save" | "folder"
    QQuickWindow *showDemo(const QString &mode);

public Q_SLOTS:
    uint OpenFile(const QDBusObjectPath &handle, const QString &app_id, const QString &parent_window,
                  const QString &title, const QVariantMap &options, QVariantMap &results);
    uint SaveFile(const QDBusObjectPath &handle, const QString &app_id, const QString &parent_window,
                  const QString &title, const QVariantMap &options, QVariantMap &results);
    uint SaveFiles(const QDBusObjectPath &handle, const QString &app_id, const QString &parent_window,
                   const QString &title, const QVariantMap &options, QVariantMap &results);

Q_SIGNALS:
    void busyChanged(bool busy);

private:
    QQuickWindow *openDialog(const QVariantMap &props);
    void request(const QDBusObjectPath &handle, const QString &mode, const QString &title, const QVariantMap &options);

    QQmlEngine *m_engine;
    int m_open = 0;
};

// Obiekt prośby (org.freedesktop.impl.portal.Request) — program może ją anulować
class PortalRequest : public QObject
{
    Q_OBJECT
    Q_CLASSINFO("D-Bus Interface", "org.freedesktop.impl.portal.Request")
public:
    using QObject::QObject;
public Q_SLOTS:
    void Close() { Q_EMIT closeRequested(); }
protected Q_SLOTS:
    void accept() { Q_EMIT acceptRequested(); }      // z okna QML (nie przez D-Bus)
Q_SIGNALS:
    void closeRequested();
    void acceptRequested();
};

// Pomocnicze dla QML: miejsca, ścieżki, nowy folder, ostatni folder
class PortalHelper : public QObject
{
    Q_OBJECT
    QML_NAMED_ELEMENT(Portal)
    QML_SINGLETON
    Q_PROPERTY(QString home READ home CONSTANT)
public:
    using QObject::QObject;
    QString home() const;
    Q_INVOKABLE QVariantList places() const;
    Q_INVOKABLE QVariantList crumbs(const QString &path) const;
    Q_INVOKABLE QString parentPath(const QString &path) const;
    Q_INVOKABLE bool exists(const QString &path) const;
    Q_INVOKABLE bool isDir(const QString &path) const;
    Q_INVOKABLE QString makeFolder(const QString &dir, const QString &name) const;   // ścieżka albo ""
    Q_INVOKABLE QString lastFolder() const;
    Q_INVOKABLE void rememberFolder(const QString &path) const;
    Q_INVOKABLE QString sizeText(qint64 bytes) const;
};
