#pragma once

#include <QCameraDevice>
#include <QCameraFormat>
#include <QMediaFormat>
#include <QObject>
#include <QQmlEngine>
#include <QUrl>

// Pliki Kamery: zdjęcia trafiają do Obrazy/Z aparatu, filmy do Wideo/Z aparatu (jak „Z aparatu” w Windows).
// Pamięta ostatnie ujęcie (miniatura w rogu), dobiera format nagrywania i najlepszy tryb kamery.
class Roll : public QObject
{
    Q_OBJECT
    QML_ELEMENT
    QML_SINGLETON
    Q_PROPERTY(QString lastPath READ lastPath NOTIFY lastChanged)
    Q_PROPERTY(QString lastThumb READ lastThumb NOTIFY lastChanged)     // adres obrazka miniatury
    Q_PROPERTY(bool lastIsVideo READ lastIsVideo NOTIFY lastChanged)
    Q_PROPERTY(QString previewImage READ previewImage CONSTANT)         // ASTER_PREVIEW: zdjęcie udające obraz z kamery
    Q_PROPERTY(QMediaFormat recordFormat READ recordFormat CONSTANT)

public:
    explicit Roll(QObject *parent = nullptr);

    QString lastPath() const { return m_lastPath; }
    QString lastThumb() const { return m_lastThumb; }
    bool lastIsVideo() const { return m_lastIsVideo; }
    QString previewImage() const;
    QMediaFormat recordFormat() const;

    Q_INVOKABLE QString photoPath() const;                 // nowa, wolna ścieżka zdjęcia
    Q_INVOKABLE QString videoPath() const;                 // … filmu (rozszerzenie z formatu nagrywania)
    Q_INVOKABLE QString thumbPath() const;                 // miniatura nagrywanego filmu (pamięć podręczna)
    Q_INVOKABLE void photoSaved(const QString &path);
    Q_INVOKABLE void videoSaved(const QUrl &location, const QString &thumb);
    Q_INVOKABLE QUrl fileUrl(const QString &path) const { return QUrl::fromLocalFile(path); }
    Q_INVOKABLE void openLast() const;                     // Zdjęcia / Wideo
    Q_INVOKABLE void openFolder() const;
    Q_INVOKABLE void showLastInFolder() const;
    Q_INVOKABLE QString deviceKey(const QCameraDevice &device) const { return QString::fromUtf8(device.id()); }
    Q_INVOKABLE QCameraFormat bestFormat(const QCameraDevice &device) const;
    Q_INVOKABLE QString time(qint64 ms) const;             // 0:07 / 1:02:03

Q_SIGNALS:
    void lastChanged();

private:
    QString photosDir() const;
    QString videosDir() const;
    QString uniqueName(const QString &dir, const QString &prefix, const QString &ext) const;
    void findLast();

    QString m_lastPath, m_lastThumb;
    bool m_lastIsVideo = false;
};
