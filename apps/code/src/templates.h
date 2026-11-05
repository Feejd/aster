#pragma once

#include <QObject>
#include <QQmlEngine>
#include <QVariantMap>

// Szablony „Nowa aplikacja” w Aster Code: frontend (Vite + React z Vitest), backend (FastAPI z pytest
// albo Node/Express z node:test), baza (SQLite albo PostgreSQL w kontenerze projektu), .env.example,
// README i pierwsze zatwierdzenie w gicie. Pliki są w zasobach (:/templates), z polami {{name}} itp.
// Frontend i backend razem — w podfolderach frontend/ i backend/, osobno — w folderze projektu.
class Templates : public QObject
{
    Q_OBJECT
    QML_ELEMENT
    QML_SINGLETON

public:
    explicit Templates(QObject *parent = nullptr);

    // opts: { name, parent, frontend: "vite-react"|"", backend: "fastapi"|"node"|"", db: "sqlite"|"postgres"|"", git }
    // Wynik: { ok, error, path, packages: [pakiety Fedory], setup: [{ label, command, cwd }] }
    Q_INVOKABLE QVariantMap create(const QVariantMap &opts) const;
    Q_INVOKABLE QString slug(const QString &name) const;
    Q_INVOKABLE QString defaultParent() const;
    Q_INVOKABLE bool exists(const QString &path) const;
};
