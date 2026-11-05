#pragma once

#include <QHash>
#include <QObject>
#include <QPointer>
#include <QProcess>
#include <QVariantMap>
#include <QQmlEngine>
#include <QStringList>

// Środowisko projektu w Aster Code. System Aster ma /usr tylko do odczytu, więc Node, Python, PostgreSQL itd.
// trafiają do kontenera przypisanego do projektu (toolbox, a gdy go nie ma — distrobox), który Aster Code
// zakłada sam. Zadania, terminal, serwery języków, debuger i agent działają wtedy w kontenerze; katalog
// domowy i sieć są wspólne, więc pliki projektu i porty serwerów (localhost) widać bez przekierowań.
// Bez kontenera polecenia idą do systemu — z Flatpaka przez flatpak-spawn --host.
class ProjectEnv : public QObject
{
    Q_OBJECT
    QML_ELEMENT
    QML_SINGLETON
    Q_PROPERTY(QString root READ root WRITE setRoot NOTIFY changed)
    Q_PROPERTY(QString container READ container NOTIFY changed)          // nazwa kontenera projektu (pusta — w systemie)
    Q_PROPERTY(QString state READ state NOTIFY changed)                  // off | missing | none | ready
    Q_PROPERTY(QString tool READ tool NOTIFY changed)                    // toolbox | distrobox | ""
    Q_PROPERTY(bool flatpak READ flatpak CONSTANT)
    Q_PROPERTY(QVariantMap readiness READ readiness NOTIFY readinessChanged)  // { items: [co brakuje, po ludzku], packages, setup: [{ label, command, cwd }] }

public:
    static ProjectEnv *instance();
    static ProjectEnv *create(QQmlEngine *, QJSEngine *);

    QString root() const { return m_root; }
    void setRoot(const QString &r);
    QString container() const { return m_container; }
    QString state() const { return m_state; }
    QString tool() const { return m_tool; }
    bool flatpak() const { return m_flatpak; }
    QVariantMap readiness() const { return m_readiness; }

    // Polecenie powłoki w środowisku projektu: argv dla QProcess (pusty — zwykłe /bin/sh)
    QStringList shell(const QString &command, const QString &cwd) const;
    // To samo, ale zawsze w systemie (zakładanie kontenera, instalacja pakietów)
    QStringList hostShell(const QString &command, const QString &cwd) const;
    // Program z argumentami (serwer języka, debuger) w środowisku projektu
    QStringList program(const QStringList &argv) const;
    // Program w systemie (git): z Flatpaka przez flatpak-spawn, env — zmienne do przekazania
    QStringList hostProgram(const QStringList &argv, const QString &cwd, const QStringList &env = QStringList()) const;
    // Czy program jest dostępny w środowisku projektu (wynik zapamiętany do zmiany środowiska)
    bool has(const QString &name) const;
    // Terminal: polecenie zamiast domyślnej powłoki (pusty — domyślna)
    Q_INVOKABLE QStringList terminalCommand() const;

    // Kontener: zakładanie, pakiety, usuwanie — polecenia do uruchomienia jako zadanie w systemie
    Q_INVOKABLE QString createCommand(const QStringList &packages) const;
    Q_INVOKABLE QString installCommand(const QStringList &packages) const;
    Q_INVOKABLE QString removeCommand() const;
    // Pakiety Fedory dla tego, co jest w projekcie (package.json → nodejs, pyproject → python3-pip…)
    Q_INVOKABLE QStringList suggestPackages() const;
    Q_INVOKABLE void useContainer(bool on);           // przypisuje (albo odpina) kontener do projektu
    Q_INVOKABLE void refresh();                       // ponownie sprawdza, czy kontener istnieje
    Q_INVOKABLE bool toolAvailable() const { return !m_tool.isEmpty(); }
    // Czego brakuje, żeby projekt działał: języki, serwery języków, zależności (w tle — wynik w readiness)
    Q_INVOKABLE void checkReadiness();

Q_SIGNALS:
    void changed();
    void readinessChanged();

private:
    explicit ProjectEnv(QObject *parent = nullptr);
    QStringList host(const QStringList &argv) const;
    bool hostRun(const QStringList &argv, QString *out = nullptr, int timeout = 5000) const;
    QString defaultName() const;

    QString m_root, m_container, m_state = QStringLiteral("off"), m_tool;
    bool m_flatpak = false;
    mutable QHash<QString, bool> m_has;
    QVariantMap m_readiness;
    QPointer<QProcess> m_check;
};
