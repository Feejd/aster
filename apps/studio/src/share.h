#pragma once

#include <QImage>
#include <QString>
#include <QStringList>
#include <QVariantList>
#include <vector>

// Udostępnianie piosenki i projektu (bez serwera): okładka, MP3 z tagami, paczka projektu do remiksu,
// wysyłka na telefon (KDE Connect), e-mailem i przez schowek.
namespace Share {

// Okładka 1200×1200: gradient z kolorów zależnych od tytułu, kształt fali piosenki, tytuł i wykonawca
QImage cover(const QString &title, const QString &artist, const std::vector<float> &wave);

// Tytuł, wykonawca, album i okładka w tagach ID3v2 pliku MP3 (TagLib)
bool tagMp3(const QString &path, const QString &title, const QString &artist, const QImage &cover);

// Paczka projektu (ZIP: folder projektu bez eksportów) i jej rozpakowanie — zwraca folder nowego projektu
bool packProject(const QString &folder, const QStringList &files, const QString &zipPath, QString *error);
QString unpackProject(const QString &zipPath, const QString &projectsFolder, QString *error);

// KDE Connect: sparowane i osiągalne telefony [{ id, name }] oraz wysłanie pliku
QVariantList phones();
bool sendToPhone(const QString &id, const QString &path);

}
