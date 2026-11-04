#pragma once

#include <QObject>
#include <QQmlEngine>
#include <QVariantList>

// Ustawienia → Asystent: dostawca i model, klucz API (w portfelu), adres modelu lokalnego, historia.
// Wszystko przez usługę aster-assistant (D-Bus org.aster.Assistant) — ona jedna zna klucze i rozmowy.
class Assistant : public QObject
{
    Q_OBJECT
    QML_ELEMENT
    QML_SINGLETON
    Q_PROPERTY(bool available READ available NOTIFY changed)            // usługa odpowiada
    // [{id, name, kind, region, needsKey, editableUrl, keyUrl, hasKey, model, models, url, defaultModel}]
    Q_PROPERTY(QVariantList providers READ providers NOTIFY changed)
    Q_PROPERTY(QVariantMap status READ status NOTIFY changed)            // jak Status() usługi
    Q_PROPERTY(int conversations READ conversations NOTIFY changed)
    Q_PROPERTY(bool busy READ busy NOTIFY changed)
    // Modele na tym komputerze: {hardware: {ramGb, cores, cpu, freeDisk}, recommended, active, downloading, models: […]}
    Q_PROPERTY(QVariantMap local READ local NOTIFY localChanged)
    Q_PROPERTY(QString downloadId READ downloadId NOTIFY progressChanged)
    Q_PROPERTY(double downloadReceived READ downloadReceived NOTIFY progressChanged)
    Q_PROPERTY(double downloadTotal READ downloadTotal NOTIFY progressChanged)

public:
    explicit Assistant(QObject *parent = nullptr);

    bool available() const { return m_available; }
    QVariantList providers() const { return m_providers; }
    QVariantMap status() const { return m_status; }
    int conversations() const { return m_conversations; }
    bool busy() const { return m_busy; }
    QVariantMap local() const { return m_local; }
    QString downloadId() const { return m_downloadId; }
    double downloadReceived() const { return double(m_received); }
    double downloadTotal() const { return double(m_total); }

    Q_INVOKABLE void refresh();
    Q_INVOKABLE void setProvider(const QString &id);
    Q_INVOKABLE void setModel(const QString &provider, const QString &model);
    Q_INVOKABLE void setBaseUrl(const QString &provider, const QString &url);
    Q_INVOKABLE void setHistory(bool on);
    // Pusty klucz usuwa go z portfela
    Q_INVOKABLE void setApiKey(const QString &provider, const QString &key);
    Q_INVOKABLE void clearHistory();
    Q_INVOKABLE void refreshLocal();
    Q_INVOKABLE void downloadModel(const QString &id);
    Q_INVOKABLE void cancelDownload();
    Q_INVOKABLE void useModel(const QString &id);
    Q_INVOKABLE void deleteModel(const QString &id);

Q_SIGNALS:
    void changed();
    void message(const QString &text);
    void localChanged();
    void progressChanged();

private Q_SLOTS:
    void onProgress(const QString &id, qlonglong received, qlonglong total);
    void onDownloadFinished(const QString &id, bool ok, const QString &message);

private:
    void configure(const QVariantMap &settings);
    bool m_available = false;
    bool m_busy = false;
    QVariantList m_providers;
    QVariantMap m_status;
    int m_conversations = 0;
    QVariantMap m_local;
    QString m_downloadId;
    qint64 m_received = 0;
    qint64 m_total = 0;
};
