#pragma once

#include <QHash>
#include <QObject>
#include <QSet>
#include <QStringList>
#include <QVariantList>
#include <QtQml/qqmlregistration.h>

class QNetworkAccessManager;
class QNetworkReply;

// Darmowe zasoby z internetu (bez kont i kluczy):
// - zdjęcia z Wikimedia Commons — CC0, domena publiczna i CC BY (wtedy element pamięta podpis autora),
// - ikony i naklejki z Iconify — tylko zestawy na licencjach MIT / Apache / ISC,
// - czcionki z Google Fonts (lista z Fontsource, pliki TTF z Google) — do ~/.local/share/fonts/aster-grafika.
// Wyszukiwanie po polsku: popularne słowa tłumaczymy na angielski, bo tak opisane są zbiory.
class Online : public QObject
{
    Q_OBJECT
    QML_ELEMENT
    QML_SINGLETON
    Q_PROPERTY(QVariantList fontCatalog READ fontCatalog NOTIFY fontCatalogChanged)
    Q_PROPERTY(bool catalogFailed READ catalogFailed NOTIFY fontCatalogChanged)

public:
    explicit Online(QObject *parent = nullptr);

    QVariantList fontCatalog() const { return m_catalog; }
    bool catalogFailed() const { return m_catalogFailed; }

    Q_INVOKABLE QString translate(const QString &query) const;
    Q_INVOKABLE void searchPhotos(const QString &query, int page);
    // icons | stickers; wyniki: { name, file (SVG do wstawienia), thumb (SVG w kolorze `tint` do podglądu) }
    Q_INVOKABLE void searchGraphics(const QString &query, const QString &kind, const QString &tint = QString());
    Q_INVOKABLE void fetch(const QString &url, const QString &tag);               // pobranie do pamięci podręcznej

    Q_INVOKABLE void loadFontCatalog();
    // Nazwa czcionki (i `text`) jej krojem — sam podgląd, kilka KB
    Q_INVOKABLE void previewFont(const QString &family, const QString &text = QString());
    Q_INVOKABLE void installFont(const QString &family);
    Q_INVOKABLE bool hasPreview(const QString &family) const { return m_previews.contains(family); }

    // Pobrane czcionki: wczytanie przy starcie, pliki do zapisania w projekcie
    static void loadDownloadedFonts();
    static QString fontsDir();
    static QStringList fontFiles(const QString &family);
    static bool previewOnly(const QString &family);

Q_SIGNALS:
    void photosFound(const QString &query, int page, const QVariantList &results, bool more);
    void graphicsFound(const QString &query, const QString &kind, const QVariantList &results);
    void searchFailed(const QString &what);
    void fetched(const QString &tag, const QString &path);
    void fetchFailed(const QString &tag);
    void fontCatalogChanged();
    void fontPreviewReady(const QString &family);
    void fontInstalled(const QString &family);
    void fontFailed(const QString &family);

private:
    QNetworkReply *get(const QString &url);
    void setCatalog(const QByteArray &json);
    void fontFaces(const QString &family, const QString &spec, std::function<void(QList<QPair<QString, QString>>)> done);

    QNetworkAccessManager *m_net;
    QVariantList m_catalog;
    bool m_catalogFailed = false;
    bool m_catalogLoading = false;
    QHash<QString, int> m_previews;          // rodzina → id czcionki z podglądem
    QSet<QString> m_pending;                 // podglądy i instalacje w toku
};
