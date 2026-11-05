#pragma once

#include <QHash>
#include <QJSValue>
#include <QNetworkAccessManager>
#include <QObject>
#include <QQmlEngine>
#include <QQmlNetworkAccessManagerFactory>

// Pobieranie danych katalogu z pamięcią na dysku: dane z pamięci idą od razu (sklep otwiera się natychmiast,
// także bez internetu), a jeśli są starsze niż maxAge, w tle przychodzą świeże i wywołanie powtarza się z nowymi.
// Odpowiedzi są odchudzane przed zapisaniem (bez tłumaczeń na sto języków) — mniej pamięci na słabym sprzęcie.
class Net : public QObject
{
    Q_OBJECT
    QML_ELEMENT
    QML_SINGLETON
    Q_PROPERTY(bool online READ online NOTIFY onlineChanged)

public:
    explicit Net(QObject *parent = nullptr);

    bool online() const { return m_online; }

    // cb(dane JS albo null); może zostać wywołane dwa razy: z pamięci i ze świeżymi danymi
    Q_INVOKABLE void get(const QString &url, int maxAgeSeconds, const QJSValue &cb);
    Q_INVOKABLE void post(const QString &url, const QVariantMap &body, int maxAgeSeconds, const QJSValue &cb);

Q_SIGNALS:
    void onlineChanged();

private:
    struct Waiting {
        QJSValue cb;
        QByteArray known;       // co już dostało z pamięci (bez ponownego wywołania, gdy nic się nie zmieniło)
    };
    void request(const QString &url, const QByteArray &body, int maxAge, const QJSValue &cb);
    void deliver(QJSValue cb, const QByteArray &json);
    void setOnline(bool online);
    QString cacheFile(const QByteArray &key) const;

    QNetworkAccessManager m_net;
    QHash<QByteArray, QList<Waiting>> m_pending;
    QString m_dir;
    bool m_online = true;
};

// Obrazki (ikony, zrzuty) przez trwałą pamięć na dysku: raz pobrane nie idą drugi raz przez sieć
class ImageCacheFactory : public QQmlNetworkAccessManagerFactory
{
public:
    QNetworkAccessManager *create(QObject *parent) override;
};
