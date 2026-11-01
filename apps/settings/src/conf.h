#pragma once

#include <QObject>
#include <QQmlEngine>
#include <QVariant>

// Pliki ustawień KDE, z których korzysta sesja Aster (kwinrc, kdeglobals, kcminputrc, kxkbrc,
// powerdevilrc, kscreenlockerrc, plasma-localerc, kaccessrc…). Zapis z powiadomieniem
// (KConfig::Notify) — KWin i usługi KDE same zauważają zmianę; tam, gdzie trzeba, dochodzi przeładowanie.
// `revision` rośnie po każdym zapisie, więc wiązania w QML odczytują wartości od nowa.
class Conf : public QObject
{
    Q_OBJECT
    QML_ELEMENT
    QML_SINGLETON
    Q_PROPERTY(int revision READ revision NOTIFY changed)

public:
    explicit Conf(QObject *parent = nullptr);
    int revision() const { return m_revision; }

    // groups: ścieżka grup, np. ["AC", "Display"] → [AC][Display]
    Q_INVOKABLE QVariant read(const QString &file, const QStringList &groups, const QString &key, const QVariant &fallback = {}) const;
    Q_INVOKABLE void write(const QString &file, const QStringList &groups, const QString &key, const QVariant &value);
    Q_INVOKABLE void remove(const QString &file, const QStringList &groups, const QString &key);

    Q_INVOKABLE void reloadKWin();          // efekty, narożniki, okna, nocne światło, klawiatura
    Q_INVOKABLE void reloadKeyboard();      // układy klawiatury (kxkbrc)
    Q_INVOKABLE void reloadPower();         // PowerDevil (powerdevilrc)
    Q_INVOKABLE void notifyGlobals(int what);   // KGlobalSettings: 0 paleta, 3 ustawienia, 5 ikony…

Q_SIGNALS:
    void changed();

private:
    int m_revision = 0;
};
