#pragma once

// Wspólne dla okna, polecenia CLI i usługi D-Bus: jak uruchomić podmana/toolboxa (także z Flatpaka)
// i jak zamienić ich JSON (`--format json`) na proste mapy dla QML i agenta asystenta.

#include <QByteArray>
#include <QHash>
#include <QString>
#include <QStringList>
#include <QVariantList>
#include <QVariantMap>

namespace Pod {

struct Cmd {
    QString program;
    QStringList args;
};

// Polecenie na komputerze (w Flatpaku przez `flatpak-spawn --host`)
Cmd host(const QString &program, const QStringList &args);
Cmd podman(const QStringList &args);       // ASTER_HARBOR_PODMAN zmienia program (np. podman-remote)
Cmd toolbox(const QStringList &args);      // ASTER_HARBOR_TOOLBOX
Cmd compose(const QString &file, const QStringList &args); // `podman compose -f PLIK …` (ASTER_HARBOR_COMPOSE)
bool inFlatpak();

// Uruchamia i czeka (CLI, D-Bus); zwraca kod wyjścia, -1 gdy programu nie ma, -2 przy przekroczeniu czasu
int run(const Cmd &cmd, QByteArray *out = nullptr, QString *err = nullptr, int timeoutMs = 30000);

// ——— JSON → mapy ———
// Kontener: id, name, image, state, running, status, ports, toolbox, project, service, workdir, configFile, created
QVariantList parseContainers(const QByteArray &json);
// Zużycie: nazwa → { cpu (liczba %), mem (bajty), memText }
QHash<QString, QVariantMap> parseStats(const QByteArray &json);
// Obraz: id, name, tag, size, created, containers, unused
QVariantList parseImages(const QByteArray &json);
// Usługi z pliku compose (klucze najwyższego poziomu w `services:`)
QStringList composeServices(const QString &file);
// Plik compose w folderze ("" gdy brak)
QString findComposeFile(const QString &folder);

// ——— Teksty ———
QString formatBytes(qint64 bytes);
QString ago(qint64 unixSecs);              // „5 min temu”
QString since(qint64 unixSecs);            // „od 5 min”
QString stripAnsi(QString line);
bool validName(const QString &name);

}
