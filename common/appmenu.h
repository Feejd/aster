#pragma once

#include <QDBusAbstractAdaptor>
#include <QJSValue>
#include <QObject>
#include <QQmlEngine>
#include <QVector>

// Menu programu Aster na górnym pasku. Program opisuje je w QML:
//   AppMenu.menus = [{ title: "Plik", items: [{ text: "Nowe okno", key: "Ctrl+N", run: () => … },
//                                             { separator: true },
//                                             { text: "Wklej", enabled: () => canPaste, checked: () => … }] }]
// `enabled` i `checked` mogą być funkcjami, bo powłoka pyta o nie przy każdym otwarciu menu.
// Powłoka rozpoznaje program po identyfikatorze .desktop, nie po numerze procesu, więc działa to też w Flatpaku.
class AppMenu : public QObject
{
    Q_OBJECT
    Q_CLASSINFO("D-Bus Interface", "org.aster.AppMenu")
    QML_ELEMENT
    QML_SINGLETON
    Q_PROPERTY(QJSValue menus READ menus WRITE setMenus NOTIFY menusChanged)

public:
    explicit AppMenu(QObject *parent = nullptr);

    QJSValue menus() const { return m_menus; }
    void setMenus(const QJSValue &menus);

public Q_SLOTS:
    Q_SCRIPTABLE QString Menus();
    Q_SCRIPTABLE void Trigger(int id);

Q_SIGNALS:
    void menusChanged();
    Q_SCRIPTABLE void Changed();

private:
    void announce();

    QJSValue m_menus;
    QVector<QJSValue> m_actions;
    bool m_exported = false;
};
