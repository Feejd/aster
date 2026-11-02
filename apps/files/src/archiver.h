#pragma once

#include <QObject>
#include <QQmlEngine>
#include <QVariantList>

#include <atomic>
#include <memory>

// Spakuj / Wypakuj (zamiast Ark): libarchive w osobnym wątku, postęp w oknie Plików.
// Wypakowuje ZIP, 7z, RAR, TAR (gz/xz/zst/bz2), ISO, CAB; pakuje do ZIP (także z hasłem AES-256),
// 7z i TAR. Nazwy z polskich ZIP-ów z Windows (CP852) są czytane poprawnie; ścieżki wychodzące
// poza folder docelowy („../”, „/etc/…”) są odrzucane.
class Archiver : public QObject
{
    Q_OBJECT
    QML_ELEMENT
    QML_SINGLETON
    Q_PROPERTY(QVariantList jobs READ jobs NOTIFY jobsChanged)     // [{ id, title, progress (0–1), extract }]

public:
    explicit Archiver(QObject *parent = nullptr);
    ~Archiver() override;

    QVariantList jobs() const;

    Q_INVOKABLE bool isArchive(const QString &url) const;
    // Archiwum, które Pliki pokażą jak folder (KIO: zip:/ tar:/), albo pusty tekst
    Q_INVOKABLE QString browseUrl(const QString &url) const;
    // Plik archiwum dla adresu zip:/…/plik.zip/wnętrze (pusty, gdy to nie wnętrze archiwum)
    Q_INVOKABLE QString archiveOf(const QString &url) const;
    // Proponowana nazwa: „Raport.zip”, a dla kilku elementów — nazwa pierwszego
    Q_INVOKABLE QString suggestedName(const QStringList &urls, const QString &format) const;

    // dest: folder (url) albo pusty — obok archiwum, w folderze o nazwie archiwum (jeden folder
    // w środku — bez zbędnego zagnieżdżenia). Zwraca numer zadania.
    Q_INVOKABLE int extract(const QString &archiveUrl, const QString &destDirUrl, const QString &password);
    // format: zip | 7z | tar.gz | tar.xz | tar.zst; name — nazwa pliku (bez folderu)
    Q_INVOKABLE int compress(const QStringList &urls, const QString &name, const QString &format, const QString &password);
    Q_INVOKABLE void cancel(int id);

Q_SIGNALS:
    void jobsChanged();
    // ok; resultUrl — utworzony folder/plik do zaznaczenia; message — opis dla użytkownika
    void finished(int id, bool ok, const QString &message, const QString &resultUrl);
    void passwordNeeded(const QString &archiveUrl, const QString &destDirUrl, bool wrong);

private:
    struct Job {
        int id;
        QString title;
        bool extract;
        std::atomic<double> progress{0};
        std::atomic<bool> cancel{false};
    };
    std::shared_ptr<Job> addJob(const QString &title, bool extract);
    void removeJob(int id);

    QList<std::shared_ptr<Job>> m_jobs;
    int m_next = 1;
    class QTimer *m_tick;
};
