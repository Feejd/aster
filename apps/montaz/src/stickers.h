#pragma once

#include <QObject>
#include <QQmlEngine>
#include <QVariantList>

// Naklejki: własne wzory Aster (rysowane w programie: „Subskrybuj”, strzałka, kółko, dymek…) i wszystkie
// emoji z polskimi nazwami (dane panelu emoji Aster). Każda naklejka to obraz PNG z przezroczystością
// w pamięci programu — trafia na oś czasu jako zwykła nakładka (położenie, obrót, animacje).
class Stickers : public QObject
{
    Q_OBJECT
    QML_ELEMENT
    QML_SINGLETON
    Q_PROPERTY(QVariantList builtins READ builtins CONSTANT)       // [{ id, name, url }]
    Q_PROPERTY(QVariantList groups READ groups CONSTANT)           // [{ id, name, icon }]

public:
    explicit Stickers(QObject *parent = nullptr);

    QVariantList builtins();
    QVariantList groups();

    Q_INVOKABLE QVariantList emoji(const QString &group) const;   // [{ c, n }]
    Q_INVOKABLE QVariantList search(const QString &text) const;   // po polskich nazwach, także bez ogonków
    Q_INVOKABLE QString emojiFile(const QString &emoji);          // PNG z emoji (rysowany raz)
    Q_INVOKABLE QString builtinFile(const QString &id);           // PNG z wzorem Aster
    Q_INVOKABLE QString builtinName(const QString &id) const;
    Q_INVOKABLE QString emojiName(const QString &emoji) const;

private:
    struct Item { QString c, n, s; };
    struct Group { QString id, name; QList<Item> items; };
    QList<Group> m_groups;
    QVariantList m_builtins;
    void load();
    QString dir() const;
};
