#pragma once

#include <QHash>
#include <QJsonArray>
#include <QJsonObject>
#include <QString>
#include <QStringList>

// Obszar roboczy Pulse: zwykły folder z plikami JSON, który można trzymać w repozytorium projektu.
//   <folder>/pulse.json        nazwa, środowiska ze zmiennymi ({{baseUrl}}…), wybrane środowisko
//   <folder>/<kolekcja>.json   kolekcja zapisanych zapytań: { name, requests: [ … ] }
// W projekcie to <projekt>/pulse/, poza projektem — ~/Dokumenty/Pulse. Wartości tajnych zmiennych
// (secret: true) nie trafiają do plików, tylko do portfela systemu (Secret Service).
//
// Zapytanie: { id, name, method, url, params: [{key, value, enabled}], headers: […],
//   body: { mode: none|json|text|urlencoded|form|file, text, form: [{key, value, enabled, type: text|file}], file, contentType },
//   auth: { type: none|bearer|basic, token, user, password }, insecure }
class Workspace
{
public:
    // Folder obszaru dla katalogu startowego: --dir, $PULSE_DIR, a potem w górę od bieżącego katalogu
    // (<katalog>/pulse/pulse.json, <katalog>/.pulse/pulse.json, <katalog>/pulse.json); na końcu ~/Dokumenty/Pulse
    static QString locate(const QString &explicitDir, const QString &startDir);
    static QString defaultDir();
    // Folder wskazany w programie: projekt z podfolderem pulse/ albo sam folder obszaru
    static QString forFolder(const QString &folder);

    bool load(const QString &dir, QString *error = nullptr);
    // Nowy obszar (z przykładowym środowiskiem i kolekcją), gdy folder jest pusty albo go nie ma
    static bool create(const QString &dir, const QString &name, bool examples);

    QString dir() const { return m_dir; }
    QString name() const;
    QJsonArray environments() const { return m_meta.value(QLatin1String("environments")).toArray(); }
    QString activeEnvironment() const { return m_meta.value(QLatin1String("activeEnvironment")).toString(); }
    QJsonObject environment(const QString &name) const;
    QList<QJsonObject> collections() const { return m_collections; }

    void setActiveEnvironment(const QString &name);
    // Zapis środowisk (wartości tajnych zmiennych są czyszczone przed zapisem — idą do portfela osobno)
    bool saveEnvironments(const QJsonArray &envs, QString *error = nullptr);
    bool saveCollection(const QJsonObject &collection, QString *error = nullptr);   // collection.file — nazwa pliku
    QString createCollection(const QString &name, QString *error = nullptr);          // zwraca nazwę pliku
    bool removeCollection(const QString &file);

    // „kolekcja/zapytanie” (nazwa kolekcji albo pliku, nazwa albo id zapytania; wielkość liter bez znaczenia)
    QJsonObject findRequest(const QString &ref, QString *error) const;
    QString refFor(const QJsonObject &collection, const QJsonObject &request) const;

    // Zmienne środowiska; tajne — z portfela (blokuje), brakujące tajne trafiają do missing
    QHash<QString, QString> variables(const QString &env, QStringList *missingSecrets = nullptr, QString *error = nullptr) const;
    static QMap<QString, QString> secretAttributes(const QString &dir, const QString &env, const QString &key);

    // Opis dla agenta: obszar, środowiska (bez wartości tajnych), kolekcje i zapytania z odwołaniami do `run`
    QJsonObject describe() const;

private:
    bool writeMeta(QString *error);
    QString m_dir;
    QJsonObject m_meta;
    QList<QJsonObject> m_collections;   // z polem "file"
};

namespace Vars {
// {{nazwa}} → wartość; {{$timestamp}}, {{$isoTimestamp}}, {{$uuid}}, {{$randomInt}}. Nieznane zostają w tekście.
QString resolve(const QString &text, const QHash<QString, QString> &vars, QStringList *unresolved = nullptr);
// Całe zapytanie (adres, parametry, nagłówki, treść, autoryzacja)
QJsonObject resolveRequest(const QJsonObject &req, const QHash<QString, QString> &vars, QStringList *unresolved = nullptr);
// Pełny adres: url + włączone parametry (bez podstawiania)
QString fullUrl(const QJsonObject &req);
}

// Historia wysłanych zapytań (~/.local/share/aster-pulse/history.json, najnowsze na początku, do 300)
namespace History {
QString path();
QJsonArray load();
void append(const QJsonObject &request, const QJsonObject &result, const QString &env, const QString &source, const QString &workspace);
void clear();
}

// Nowe zapytanie z wartościami domyślnymi (brakujące pola uzupełnione)
QJsonObject normalizedRequest(const QJsonObject &req);
