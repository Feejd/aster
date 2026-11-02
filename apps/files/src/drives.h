#pragma once

#include <QObject>
#include <QQmlEngine>
#include <QVariantList>

// Pendrive’y, karty pamięci i dodatkowe dyski w pasku bocznym Plików (Solid/UDisks2):
// otwieranie (montowanie przy pierwszym kliknięciu), „Wysuń” (odmontowanie i wyłączenie zasilania
// — można bezpiecznie wyjąć) oraz „Formatuj…” (UDisks2 Block.Format — exFAT, FAT32, NTFS, ext4).
class Drives : public QObject
{
    Q_OBJECT
    QML_ELEMENT
    QML_SINGLETON
    // [{ udi, name, sizeText, url, mounted, removable, freeText, usedRatio, fsName, busy }]
    Q_PROPERTY(QVariantList list READ list NOTIFY changed)

public:
    explicit Drives(QObject *parent = nullptr);

    QVariantList list() const { return m_list; }

    Q_INVOKABLE void open(const QString &udi);        // gotowe → opened(url)
    Q_INVOKABLE void eject(const QString &udi);
    // type: exfat | vfat | ntfs | ext4
    Q_INVOKABLE void format(const QString &udi, const QString &type, const QString &label);
    Q_INVOKABLE int labelLimit(const QString &type) const;

Q_SIGNALS:
    void changed();
    void opened(const QString &url);
    void message(const QString &text);
    void ejected(const QString &url);                 // był otwarty ten folder — wróć gdzie indziej

private:
    void rebuild();
    void setBusy(const QString &udi, const QString &what);
    QString nameOf(const QString &udi) const;

    QVariantList m_list;
    QHash<QString, QString> m_busy;                   // udi → „Formatowanie…”, „Wysuwanie…”
    bool m_preview = false;
};
