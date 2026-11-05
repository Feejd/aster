#pragma once

#include <QList>
#include <QString>
#include <QStringList>
#include <QVariantMap>

// Dostawcy modeli. Dwa rodzaje API: zgodne z OpenAI (/chat/completions) i Anthropic Messages (/messages).
// region — gdzie stoją serwery (pokazywane wprost w Ustawieniach i w terminalu przed pierwszym użyciem).
struct Provider {
    enum Kind { OpenAI, Anthropic };
    QString id;
    QString name;
    Kind kind = OpenAI;
    QString baseUrl;        // bez końcowego „/”
    QString defaultModel;
    QStringList models;     // podpowiedzi w Ustawieniach (można wpisać inny)
    QString region;         // „USA”, „Chiny”, „UE (Francja)”…; pusty dla modelu lokalnego
    bool needsKey = true;
    bool editableUrl = false;
    QString keyUrl;         // gdzie zdobyć klucz

    bool valid() const { return !id.isEmpty(); }
    QVariantMap toMap() const;
};

namespace Catalog {
const QList<Provider> &all();
Provider find(const QString &id);
// Czy adres wskazuje na ten komputer (127.0.0.1, ::1, localhost)
bool isLoopback(const QString &url);
}
