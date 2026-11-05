#pragma once

#include <QAbstractItemModel>
#include <QObject>
#include <QPointer>
#include <QQmlEngine>

// Okna i programy dla Aster Intelligence (i `aster --okna` w terminalu): D-Bus org.aster.Shell, obiekt /org/aster/Shell.
//
// Okna bierze z modelu zadań KDE (TaskManager.TasksModel bez grupowania — ustawia go Shell.qml), więc działa z każdym
// programem na Waylandzie: lista, pokazanie na wierzchu, zminimalizowanie, maksymalizacja, zamknięcie.
// OpenApp znajduje program po zwykłej nazwie („aster code”, „przeglądarka”, „firefox”) w bazie programów i go
// uruchamia (z plikami albo adresami); program Aster, którego jeszcze nie ma, zgłasza z poleceniem do instalacji.
class Windows : public QObject
{
    Q_OBJECT
    Q_CLASSINFO("D-Bus Interface", "org.aster.Shell")
    QML_ELEMENT
    QML_SINGLETON
    Q_PROPERTY(QAbstractItemModel *model READ model WRITE setModel NOTIFY modelChanged)

public:
    explicit Windows(QObject *parent = nullptr);
    QAbstractItemModel *model() const { return m_model; }
    void setModel(QAbstractItemModel *m);

public Q_SLOTS:
    // JSON: [{n, title, app, appId, active, minimized}] — n: numer do wskazania okna
    Q_SCRIPTABLE QString ListWindows();
    // action: pokaz | zminimalizuj | maksymalizuj | zamknij; query: numer, tytuł albo nazwa programu (fragment).
    // Pusty wynik — zrobione; inaczej komunikat dla człowieka.
    Q_SCRIPTABLE QString WindowAction(const QString &action, const QString &query);
    // „ok:<nazwa>” — uruchomione; „nie-ma:<id>” — program Aster do doinstalowania; inaczej komunikat
    Q_SCRIPTABLE QString OpenApp(const QString &name, const QStringList &args, const QString &workingDir);

Q_SIGNALS:
    void modelChanged();

private:
    QModelIndex find(const QString &query, QString *problem) const;
    QPointer<QAbstractItemModel> m_model;
};
