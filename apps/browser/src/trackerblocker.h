#pragma once

#include <QSet>
#include <QWebEngineUrlRequestInterceptor>

// Blokowanie śledzenia: zapytania strony do znanych serwerów reklam i analityki
// (Google Ads, Meta Pixel, Criteo, Gemius, AdOcean…) nie wychodzą z komputera.
// Działa tylko na zasoby z innych domen — strona sama w sobie zawsze się wczytuje.
class TrackerBlocker : public QWebEngineUrlRequestInterceptor
{
    Q_OBJECT

public:
    explicit TrackerBlocker(QObject *parent = nullptr);

    bool enabled() const { return m_enabled; }
    void setEnabled(bool on) { m_enabled = on; }

    void interceptRequest(QWebEngineUrlRequestInfo &info) override;

    // „sub.example.co.uk” → „example.co.uk” (w przybliżeniu, bez pełnej listy sufiksów)
    static QString siteOf(const QString &host);

Q_SIGNALS:
    // Zablokowano zapytanie wysłane przez stronę z tej domeny (w wątku interfejsu)
    void blocked(const QString &site);

private:
    bool listed(const QString &host) const;

    bool m_enabled = true;
    QSet<QString> m_hosts;
};
