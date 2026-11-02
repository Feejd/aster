#pragma once

#include <QObject>
#include <QQmlEngine>
#include <QQuickAsyncImageProvider>
#include <QVariantMap>

// Zdjęcia: pomocnicze dla QML — szczegóły zdjęcia (EXIF przez exiv2), obrót bez utraty jakości,
// kosz z cofaniem, schowek, tapeta, miejsca w bibliotece.
class Photos : public QObject
{
    Q_OBJECT
    QML_ELEMENT
    QML_SINGLETON
    Q_PROPERTY(QVariantList places READ places NOTIFY placesChanged)      // [{ id, name, icon, roots: [..], removable }]

public:
    explicit Photos(QObject *parent = nullptr);

    QVariantList places() const;

    Q_INVOKABLE QVariantMap info(const QString &path) const;
    Q_INVOKABLE bool rotate(const QString &path, bool clockwise);
    Q_INVOKABLE bool trash(const QString &path);
    Q_INVOKABLE QString undoTrash();                          // przywrócona ścieżka albo ""
    Q_INVOKABLE void copy(const QString &path) const;
    Q_INVOKABLE void showInFolder(const QString &path) const;
    Q_INVOKABLE QString wallpaperCopy(const QString &path) const;   // kopia do ~/.local/share/aster — ścieżka dla Config.wallpaper
    Q_INVOKABLE void addFolder(const QString &pathOrUrl);
    Q_INVOKABLE void removeFolder(const QString &path);
    Q_INVOKABLE QString folderName(const QString &path) const;
    Q_INVOKABLE QString plural(int n) const;                  // „1 zdjęcie”, „3 zdjęcia”, „5 zdjęć”

Q_SIGNALS:
    void placesChanged();
    void message(const QString &text);

private:
    QString m_trashed, m_original;
};

// Miniatury (image://thumb/…): krótszy bok 360 px, zapisywane w ~/.cache/aster/thumbnails
class ThumbProvider : public QQuickAsyncImageProvider
{
public:
    QQuickImageResponse *requestImageResponse(const QString &id, const QSize &requestedSize) override;
};
