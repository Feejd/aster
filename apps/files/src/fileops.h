#pragma once

#include <KIO/Global>

#include <QFileSystemWatcher>
#include <QObject>
#include <QQmlEngine>
#include <QQuickWindow>
#include <QUrl>

class KJob;

// Operacje na plikach dla QML: tworzenie, zmiana nazwy, kopiowanie, kosz, schowek, cofanie.
// Wszystko idzie przez KIO (działa w tle, bez blokowania okna) i trafia do wspólnej
// historii cofania KDE (KIO::FileUndoManager).
class Files : public QObject
{
    Q_OBJECT
    QML_ELEMENT
    QML_SINGLETON
    Q_PROPERTY(bool canUndo READ canUndo NOTIFY undoChanged)
    Q_PROPERTY(QString undoText READ undoText NOTIFY undoChanged)
    Q_PROPERTY(int clipboardCount READ clipboardCount NOTIFY clipboardChanged)
    Q_PROPERTY(bool clipboardCut READ clipboardCut NOTIFY clipboardChanged)
    Q_PROPERTY(QStringList clipboardUrls READ clipboardUrls NOTIFY clipboardChanged)
    Q_PROPERTY(int trashCount READ trashCount NOTIFY trashChanged)
    Q_PROPERTY(QString homeUrl READ homeUrl CONSTANT)

public:
    explicit Files(QObject *parent = nullptr);

    static QString formatSize(KIO::filesize_t bytes);

    bool canUndo() const;
    QString undoText() const;
    int clipboardCount() const { return clipboardUrls().size(); }
    bool clipboardCut() const;
    QStringList clipboardUrls() const;
    int trashCount() const;
    QString homeUrl() const;

    // Miejsca w pasku bocznym: [{name, icon, url}]
    Q_INVOKABLE QVariantList places() const;
    // Dysk systemowy: {name, free, total, freeText, usedRatio}
    Q_INVOKABLE QVariantMap systemDrive() const;
    // Nazwa folderu do pokazania (Pulpit, Dokumenty… zamiast surowych nazw katalogów)
    Q_INVOKABLE QString displayName(const QString &url) const;
    // Okruszki ścieżki: [{name, url}] od folderu domowego (albo „/”) do bieżącego
    Q_INVOKABLE QVariantList crumbs(const QString &url) const;
    Q_INVOKABLE QString parentUrl(const QString &url) const;

    // Tworzą element o wolnej nazwie i zwracają ją (żeby od razu włączyć zmianę nazwy)
    Q_INVOKABLE QString newFolder(const QString &dirUrl);
    Q_INVOKABLE QString newTextFile(const QString &dirUrl);
    // Zwraca opis błędu albo pusty tekst
    Q_INVOKABLE QString rename(const QString &url, const QString &newName);

    Q_INVOKABLE void copy(const QStringList &urls, const QString &destDir);
    Q_INVOKABLE void move(const QStringList &urls, const QString &destDir);
    Q_INVOKABLE void trash(const QStringList &urls);
    Q_INVOKABLE void restore(const QStringList &urls);
    Q_INVOKABLE void deletePermanently(const QStringList &urls);
    Q_INVOKABLE void emptyTrash();
    Q_INVOKABLE void undo();

    Q_INVOKABLE void setClipboard(const QStringList &urls, bool cut);
    // Wkleja do folderu; zwraca liczbę wklejanych elementów
    Q_INVOKABLE int paste(const QString &destDir);

    Q_INVOKABLE void open(const QString &url);
    // Początek pliku tekstowego do podglądu (pusty, jeśli to nie tekst)
    Q_INVOKABLE QString previewText(const QString &url) const;

    // Wygląd okna: rozmycie tła KWin i obszar przyjmujący kliknięcia (cień wokół okna ich nie łapie)
    Q_INVOKABLE void setBlur(QQuickWindow *window, const QRectF &rect, qreal radius);
    Q_INVOKABLE void setInputRegion(QQuickWindow *window, const QRectF &rect);

Q_SIGNALS:
    void undoChanged();
    void clipboardChanged();
    void trashChanged();
    void failed(const QString &message);

private:
    void watch(KJob *job);
    static QList<QUrl> toUrls(const QStringList &urls);
    QString freeName(const QUrl &dir, const QString &base, const QString &ext) const;

    QFileSystemWatcher m_trashWatcher;
};
