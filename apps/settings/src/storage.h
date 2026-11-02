#pragma once

#include <QObject>
#include <QQmlEngine>
#include <QVariantList>

// Pamięć (zamiast Filelight): co zajmuje miejsce na dysku systemowym — kategorie jak w Windows
// (Aplikacje i system, Dokumenty, Obrazy, Wideo, Muzyka, Pobrane, Pliki tymczasowe, Kosz, Inne),
// największe foldery i porządkowanie (pliki tymczasowe, kosz). Liczone w tle.
class Storage : public QObject
{
    Q_OBJECT
    QML_ELEMENT
    QML_SINGLETON
    Q_PROPERTY(bool scanning READ scanning NOTIFY changed)
    Q_PROPERTY(QVariantList categories READ categories NOTIFY changed)   // [{ id, name, size, sizeText, color, path, icon }]
    Q_PROPERTY(QVariantList largest READ largest NOTIFY changed)         // [{ name, path, size, sizeText }]
    Q_PROPERTY(QVariantList drives READ drives NOTIFY changed)           // [{ name, path, freeText, usedRatio, system }]
    Q_PROPERTY(qint64 total READ total NOTIFY changed)
    Q_PROPERTY(qint64 used READ used NOTIFY changed)
    Q_PROPERTY(QString summary READ summary NOTIFY changed)              // „62 GB zajęte z 105 GB”

public:
    explicit Storage(QObject *parent = nullptr);

    bool scanning() const { return m_scanning; }
    QVariantList categories() const { return m_categories; }
    QVariantList largest() const { return m_largest; }
    QVariantList drives() const;
    qint64 total() const { return m_total; }
    qint64 used() const { return m_used; }
    QString summary() const;

    Q_INVOKABLE void scan();
    Q_INVOKABLE void cleanTemp();       // ~/.cache
    Q_INVOKABLE void emptyTrash();
    Q_INVOKABLE void open(const QString &path) const;
    Q_INVOKABLE QString size(qint64 bytes) const;

Q_SIGNALS:
    void changed();
    void message(const QString &text);

private:
    bool m_scanning = false;
    QVariantList m_categories, m_largest;
    qint64 m_total = 0, m_used = 0;
};
