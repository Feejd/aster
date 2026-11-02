#pragma once

#include <QObject>
#include <QQmlEngine>
#include <QQuickAsyncImageProvider>
#include <QUrl>
#include <QVariantList>

// Wideo: ostatnio oglądane (z miejscem, w którym przerwano), filmy z folderu Wideo, sąsiednie pliki
// (następny odcinek) i napisy z pliku obok filmu — SRT, WebVTT oraz popularne w Polsce MicroDVD
// i MPL2, także w kodowaniu Windows-1250.
class Video : public QObject
{
    Q_OBJECT
    QML_ELEMENT
    QML_SINGLETON
    Q_PROPERTY(QVariantList recent READ recent NOTIFY recentChanged)
    Q_PROPERTY(QString startFile READ startFile CONSTANT)

public:
    explicit Video(QObject *parent = nullptr);

    QVariantList recent() const;
    QString startFile() const { return s_startFile; }
    static inline QString s_startFile;            // z wiersza poleceń, ustawiane w main()

    Q_INVOKABLE void remember(const QString &path, qint64 position, qint64 duration);
    Q_INVOKABLE void forget(const QString &path);
    Q_INVOKABLE void clearRecent();
    Q_INVOKABLE qint64 resumePosition(const QString &path) const;   // 0 — od początku

    Q_INVOKABLE QVariantList library() const;                       // filmy z Wideo (i Pobranych)
    Q_INVOKABLE QStringList siblings(const QString &path) const;     // filmy z tego samego folderu
    Q_INVOKABLE bool isVideo(const QString &path) const;
    Q_INVOKABLE QStringList subtitleFiles(const QString &video) const;
    // [{ s, e, t }] w ms; fps — dla MicroDVD (klatki zamiast czasu)
    Q_INVOKABLE QVariantList loadSubtitles(const QString &path, double fps) const;

    Q_INVOKABLE QString toPath(const QString &pathOrUrl) const;
    Q_INVOKABLE QUrl url(const QString &path) const;
    Q_INVOKABLE QString language(int language) const;                // QLocale::Language → „Polski”
    Q_INVOKABLE QString fileName(const QString &path) const;         // bez rozszerzenia
    Q_INVOKABLE QString thumb(const QString &path) const;            // image://vthumb/…
    Q_INVOKABLE QString time(qint64 ms) const;                       // 1:02:03 / 4:05
    Q_INVOKABLE QString when(qint64 msecsSinceEpoch) const;          // „dziś”, „wczoraj”, „12 marca”
    Q_INVOKABLE void showInFolder(const QString &path) const;
    Q_INVOKABLE QString videosDir() const;

Q_SIGNALS:
    void recentChanged();

private:
    QVariantList m_recent;
    void save();
};

// Miniatura filmu: klatka z ok. 15% długości, pamiętana w ~/.cache/aster/thumbnails
class VideoThumbProvider : public QQuickAsyncImageProvider
{
public:
    QQuickImageResponse *requestImageResponse(const QString &id, const QSize &requestedSize) override;
};
