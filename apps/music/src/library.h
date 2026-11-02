#pragma once

#include <QObject>
#include <QQmlEngine>
#include <QUrl>
#include <QVariantList>

// Muzyka: biblioteka z folderu Muzyka (i dodanych folderów). Tagi (tytuł, wykonawca, album, numer)
// czyta TagLib; wynik jest pamiętany w ~/.cache/aster/music, więc kolejne uruchomienia czytają tylko
// nowe i zmienione pliki. Okładki — z pliku muzycznego albo z cover.jpg/folder.jpg obok.
class Library : public QObject
{
    Q_OBJECT
    QML_ELEMENT
    QML_SINGLETON
    Q_CLASSINFO("D-Bus Interface", "org.aster.music")
    Q_PROPERTY(QVariantList tracks READ tracks NOTIFY changed)      // posortowane: wykonawca, album, numer
    Q_PROPERTY(QVariantList albums READ albums NOTIFY changed)
    Q_PROPERTY(QVariantList artists READ artists NOTIFY changed)
    Q_PROPERTY(QVariantList folders READ folders NOTIFY foldersChanged)
    Q_PROPERTY(bool loading READ loading NOTIFY loadingChanged)
    Q_PROPERTY(QStringList pendingFiles READ pendingFiles CONSTANT)

public:
    explicit Library(QObject *parent = nullptr);

    QVariantList tracks() const { return m_tracks; }
    QVariantList albums() const { return m_albums; }
    QVariantList artists() const { return m_artists; }
    QVariantList folders() const;
    bool loading() const { return m_loading; }
    QStringList pendingFiles() const { return s_pending; }
    static inline QStringList s_pending;              // pliki z wiersza poleceń (ustawiane w main())

    Q_INVOKABLE void rescan();
    Q_INVOKABLE void addFolder(const QString &pathOrUrl);
    Q_INVOKABLE void removeFolder(const QString &path);
    Q_INVOKABLE QVariantMap album(const QString &key) const;          // z listą utworów
    Q_INVOKABLE QVariantMap artist(const QString &name) const;        // albumy i utwory
    Q_INVOKABLE QVariantList tracksFor(const QStringList &paths) const; // z biblioteki albo wprost z pliku
    Q_INVOKABLE QUrl url(const QString &path) const { return QUrl::fromLocalFile(path); }
    Q_INVOKABLE void showInFolder(const QString &path) const;
    Q_INVOKABLE QString time(qint64 ms) const;                         // 3:45
    Q_INVOKABLE QString total(qint64 ms) const;                        // „1 godz. 12 min”
    Q_INVOKABLE QString songs(int n) const;                            // „5 utworów”
    Q_INVOKABLE QString albumsCount(int n) const;                      // „3 albumy”
    Q_INVOKABLE QString musicDir() const;

public Q_SLOTS:
    void openFiles(const QStringList &files);

Q_SIGNALS:
    void changed();
    void foldersChanged();
    void loadingChanged();
    void openRequested(const QStringList &files);

private:
    void apply(const QVariantList &tracks);
    QStringList roots() const;

    QVariantList m_tracks, m_albums, m_artists;
    QHash<QString, int> m_byPath;
    QHash<QString, int> m_albumIndex;
    QHash<QString, QVariantList> m_albumTracks;
    bool m_loading = false;
    int m_generation = 0;
};
