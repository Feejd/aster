#pragma once

#include <QFileSystemWatcher>
#include <QObject>
#include <QQmlEngine>
#include <QPoint>
#include <QQuickTextDocument>
#include <QVariantMap>

// Edytor tekstu: wczytywanie i zapis plików (kodowanie, końce wierszy), sesja kart (niezapisane
// karty wracają po ponownym otwarciu, jak w Notatniku Windows 11), pilnowanie zmian pliku na dysku.
class Editor : public QObject
{
    Q_OBJECT
    QML_ELEMENT
    QML_SINGLETON
    Q_CLASSINFO("D-Bus Interface", "org.aster.editor")
    Q_PROPERTY(QStringList pendingFiles READ pendingFiles CONSTANT)        // pliki z wiersza poleceń

public:
    explicit Editor(QObject *parent = nullptr);

    // { ok, text, encoding, eol: "\n" | "\r\n", error, readOnly }
    Q_INVOKABLE QVariantMap load(const QString &pathOrUrl) const;
    // true albo komunikat w message()
    Q_INVOKABLE bool save(const QString &path, const QString &text, const QString &encoding, const QString &eol);
    Q_INVOKABLE QString toPath(const QString &pathOrUrl) const;
    Q_INVOKABLE QString fileName(const QString &path) const;
    Q_INVOKABLE QString folder(const QString &path) const;
    Q_INVOKABLE bool exists(const QString &path) const;
    Q_INVOKABLE void watch(const QStringList &paths);
    Q_INVOKABLE void showInFolder(const QString &path) const;
    Q_INVOKABLE QString documentsDir() const;
    Q_INVOKABLE QString number(int n) const;                     // „12 345”
    Q_INVOKABLE QPoint lineColumn(QQuickTextDocument *doc, int position) const;   // (kolumna, wiersz) od 0
    Q_INVOKABLE int positionOfLine(QQuickTextDocument *doc, int line) const;      // początek wiersza (od 0)
    Q_INVOKABLE QString suggestedName(const QString &text) const;                 // nazwa z pierwszej linii

    Q_INVOKABLE void saveSession(const QVariantList &tabs, int current);
    Q_INVOKABLE QVariantMap loadSession() const;                 // { tabs: [...], current }

    QStringList pendingFiles() const { return s_pending; }
    static inline QStringList s_pending;                          // ustawiane w main() przed wczytaniem QML

public Q_SLOTS:
    void openFiles(const QStringList &files);

Q_SIGNALS:
    void message(const QString &text);
    void fileChanged(const QString &path);
    void openRequested(const QStringList &files);

private:
    QFileSystemWatcher m_watcher;
};
