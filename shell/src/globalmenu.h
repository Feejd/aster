#pragma once

#include <QDBusContext>
#include <QHash>
#include <QObject>
#include <QQmlEngine>
#include <QVariantList>

// Menu aktywnego programu na górnym pasku. Programy Aster zgłaszają się przez D-Bus (common/appmenu.h),
// a powłoka pyta je o aktualne menu przy zmianie okna i przy każdym otwarciu.
class GlobalMenu : public QObject, protected QDBusContext
{
    Q_OBJECT
    Q_CLASSINFO("D-Bus Interface", "org.aster.Menu")
    QML_ELEMENT
    QML_SINGLETON
    Q_PROPERTY(QString appId READ appId WRITE setAppId NOTIFY changed)
    Q_PROPERTY(QVariantList menus READ menus NOTIFY changed)

public:
    explicit GlobalMenu(QObject *parent = nullptr);

    QString appId() const { return m_appId; }
    void setAppId(const QString &appId);
    QVariantList menus() const { return m_menus; }

    Q_INVOKABLE void refresh();
    Q_INVOKABLE void trigger(int id);

public Q_SLOTS:
    Q_SCRIPTABLE void RegisterMenu(const QString &appId);

Q_SIGNALS:
    void changed();

private Q_SLOTS:
    void onChanged();

private:
    QString m_appId;
    QVariantList m_menus;
    QHash<QString, QString> m_services;      // identyfikator .desktop → nazwa programu na szynie
};
