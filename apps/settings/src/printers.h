#pragma once

#include <QObject>
#include <QQmlEngine>
#include <QTimer>
#include <QVariantList>

// Drukarki (CUPS): zainstalowane i wykryte w sieci (drukarki IPP Everywhere / AirPrint działają bez sterowników),
// drukarka domyślna, strona testowa, dodawanie wykrytej i usuwanie (polkit pyta o hasło).
// Drukarka: { name, label, state: idle|printing|stopped, isDefault, installed, uri }
class Printers : public QObject
{
    Q_OBJECT
    QML_ELEMENT
    QML_SINGLETON
    Q_PROPERTY(QVariantList printers MEMBER m_printers NOTIFY changed)
    Q_PROPERTY(bool available MEMBER m_available NOTIFY changed)
    Q_PROPERTY(bool searching MEMBER m_searching NOTIFY changed)

public:
    explicit Printers(QObject *parent = nullptr);

    Q_INVOKABLE void refresh();
    Q_INVOKABLE void setDefault(const QString &name);
    Q_INVOKABLE void printTestPage(const QString &name);
    Q_INVOKABLE void add(const QString &name);
    Q_INVOKABLE void remove(const QString &name);

Q_SIGNALS:
    void changed();
    void message(const QString &text);

private:
    bool m_preview = false;
    bool m_available = false, m_searching = false;
    QVariantList m_printers;
    QTimer m_poll;
};
