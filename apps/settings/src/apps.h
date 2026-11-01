#pragma once

#include <QObject>
#include <QQmlEngine>
#include <QVariantList>

// Programy: domyślne aplikacje (przeglądarka, poczta, pliki, terminal, tekst, zdjęcia, muzyka, wideo, PDF)
// i programy uruchamiane po zalogowaniu (~/.config/autostart).
// Kategoria: { id, name, icon, current, choices: [{ id, name, icon }] }
class Apps : public QObject
{
    Q_OBJECT
    QML_ELEMENT
    QML_SINGLETON
    Q_PROPERTY(QVariantList categories MEMBER m_categories NOTIFY changed)
    Q_PROPERTY(QVariantList autostart MEMBER m_autostart NOTIFY changed)       // [{ file, id, name, icon, enabled }]
    Q_PROPERTY(QVariantList installed READ installed NOTIFY installedChanged)  // [{ id, name, icon }] — do dodania

public:
    explicit Apps(QObject *parent = nullptr);

    QVariantList installed() const;

    Q_INVOKABLE void refresh();
    Q_INVOKABLE void setDefault(const QString &category, const QString &appId);
    Q_INVOKABLE void addAutostart(const QString &appId);
    Q_INVOKABLE void setAutostartEnabled(const QString &file, bool on);
    Q_INVOKABLE void removeAutostart(const QString &file);

Q_SIGNALS:
    void changed();
    void installedChanged();

private:
    void readAutostart();

    bool m_preview = false;
    QVariantList m_categories, m_autostart;
    mutable QVariantList m_installed;
};
