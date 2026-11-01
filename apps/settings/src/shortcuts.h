#pragma once

#include <QObject>
#include <QQmlEngine>
#include <QVariantList>

// Skróty klawiszowe całego systemu (usługa kglobalaccel — z niej korzystają KWin, zrzuty ekranu, głośność…).
// Grupa: { id, name, actions: [{ id, name, keys: "Meta+D", defaultKeys: "Meta+D" }] }
class Shortcuts : public QObject
{
    Q_OBJECT
    QML_ELEMENT
    QML_SINGLETON
    Q_PROPERTY(QVariantList groups MEMBER m_groups NOTIFY changed)
    Q_PROPERTY(bool available MEMBER m_available NOTIFY changed)

public:
    explicit Shortcuts(QObject *parent = nullptr);

    Q_INVOKABLE void refresh();
    // keys: połączone kody klawiszy (key | modyfikatory) jak w zdarzeniu klawiatury; [] = brak skrótu
    Q_INVOKABLE void setKeys(const QString &component, const QString &action, const QVariantList &keys);
    Q_INVOKABLE void resetKeys(const QString &component, const QString &action);
    Q_INVOKABLE QString keyText(int key, int modifiers) const;
    // Kto już używa tego skrótu (nazwa czynności) — puste, gdy wolny
    Q_INVOKABLE QString conflict(int combined) const;

Q_SIGNALS:
    void changed();
    void message(const QString &text);

private:
    bool m_preview = false;
    bool m_available = false;
    QVariantList m_groups;
    QHash<QString, QStringList> m_ids;          // "komponent|czynność" → actionId dla kglobalaccel
    QHash<QString, QList<int>> m_defaults;
};
