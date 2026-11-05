#pragma once

#include "filetree.h"

#include <QFileSystemWatcher>
#include <QObject>
#include <QPointer>
#include <QProcess>
#include <QQmlEngine>
#include <QSettings>
#include <QThread>
#include <QVariantList>
#include <atomic>
#include <functional>
#include <memory>

// Otwarty folder projektu: drzewo plików, ostatnie foldery, wczytywanie i zapis plików,
// operacje na plikach (nowy, zmiana nazwy, kosz), git w tle (gałąź, zmienione pliki, wersja z HEAD
// do znaczników przy marginesie), lista plików do szybkiego otwierania i wyszukiwanie w całym projekcie.
class Project : public QObject
{
    Q_OBJECT
    QML_ELEMENT
    QML_SINGLETON
    Q_PROPERTY(QString root READ root NOTIFY rootChanged)
    Q_PROPERTY(QString name READ name NOTIFY rootChanged)
    Q_PROPERTY(FileTree *tree READ tree CONSTANT)
    Q_PROPERTY(QVariantList recent READ recent NOTIFY recentChanged)
    Q_PROPERTY(QStringList pendingFiles READ pendingFiles CONSTANT)       // pliki z wiersza poleceń
    Q_PROPERTY(QString pendingFolder READ pendingFolder CONSTANT)         // folder z wiersza poleceń

    Q_PROPERTY(bool isGit READ isGit NOTIFY gitChanged)
    Q_PROPERTY(QString branch READ branch NOTIFY gitChanged)
    Q_PROPERTY(QString head READ head NOTIFY gitChanged)
    Q_PROPERTY(int ahead READ ahead NOTIFY gitChanged)
    Q_PROPERTY(int behind READ behind NOTIFY gitChanged)
    Q_PROPERTY(QVariantList changes READ changes NOTIFY gitChanged)        // [{ path, rel, name, dir, status, staged, index, work }]
    Q_PROPERTY(QString upstream READ upstream NOTIFY gitChanged)           // „origin/main” albo pusty
    Q_PROPERTY(QVariantList commits READ commits NOTIFY gitChanged)        // ostatnie: [{ hash, subject, author, time }]
    Q_PROPERTY(QString gitBusy READ gitBusy NOTIFY gitBusyChanged)         // trwająca operacja: commit, push, pull…
    Q_PROPERTY(bool merging READ merging NOTIFY gitChanged)                // trwa łączenie (MERGE_HEAD)

    Q_PROPERTY(QVariantList results READ results NOTIFY resultsChanged)    // [{ path, rel, name, matches: [...] }]
    Q_PROPERTY(int resultCount READ resultCount NOTIFY resultsChanged)
    Q_PROPERTY(bool resultsTruncated READ resultsTruncated NOTIFY resultsChanged)
    Q_PROPERTY(bool searching READ searching NOTIFY searchingChanged)
    Q_PROPERTY(QString searchError READ searchError NOTIFY resultsChanged)
    Q_PROPERTY(int fileCount READ fileCount NOTIFY filesReady)

public:
    explicit Project(QObject *parent = nullptr);
    ~Project() override;

    QString root() const { return m_root; }
    QString name() const;
    FileTree *tree() const { return m_tree; }
    QVariantList recent() const;
    QStringList pendingFiles() const { return s_pendingFiles; }
    QString pendingFolder() const { return s_pendingFolder; }
    static inline QStringList s_pendingFiles;                   // ustawiane w main() przed wczytaniem QML
    static inline QString s_pendingFolder;

    bool isGit() const { return !m_gitTop.isEmpty(); }
    QString branch() const { return m_branch; }
    QString head() const { return m_head; }
    int ahead() const { return m_ahead; }
    int behind() const { return m_behind; }
    QVariantList changes() const { return m_changes; }
    QString upstream() const { return m_upstream; }
    QVariantList commits() const { return m_commits; }
    QString gitBusy() const { return m_gitBusy; }
    bool merging() const { return m_merging; }
    QVariantList results() const { return m_results; }
    int resultCount() const { return m_resultCount; }
    bool resultsTruncated() const { return m_truncated; }
    bool searching() const { return m_searching; }
    QString searchError() const { return m_searchError; }
    int fileCount() const { return int(m_files.size()); }

    // Folder projektu
    Q_INVOKABLE bool open(const QString &pathOrUrl);
    Q_INVOKABLE void close();
    Q_INVOKABLE void forgetRecent(const QString &path);
    Q_INVOKABLE QStringList sessionTabs() const;                 // karty otwarte ostatnio w tym projekcie
    Q_INVOKABLE int sessionCurrent() const;
    Q_INVOKABLE void saveSession(const QStringList &tabs, int current, bool terminal, int sidebarView);
    Q_INVOKABLE QVariantMap sessionLayout() const;               // { terminal, sidebarView }

    // Pliki
    // { ok, path, text, encoding, eol, error, readOnly }
    Q_INVOKABLE QVariantMap load(const QString &pathOrUrl) const;
    Q_INVOKABLE bool save(const QString &path, const QString &text, const QString &encoding, const QString &eol);
    Q_INVOKABLE QString toPath(const QString &pathOrUrl) const;
    Q_INVOKABLE QString fileName(const QString &path) const;
    Q_INVOKABLE QString folder(const QString &path) const;
    Q_INVOKABLE QString relative(const QString &path) const;      // względem folderu projektu
    Q_INVOKABLE QString pretty(const QString &path) const;        // ~/Projekty/aster
    Q_INVOKABLE bool exists(const QString &path) const;
    Q_INVOKABLE bool isDir(const QString &path) const;
    Q_INVOKABLE QString createFile(const QString &dir, const QString &name);     // nowa ścieżka albo pusty (komunikat)
    Q_INVOKABLE QString createFolder(const QString &dir, const QString &name);
    Q_INVOKABLE QString rename(const QString &path, const QString &newName);
    Q_INVOKABLE bool trash(const QString &path);
    Q_INVOKABLE void watch(const QStringList &paths);
    Q_INVOKABLE void showInFiles(const QString &path) const;
    Q_INVOKABLE void copyText(const QString &text) const;
    // Kopia niezapisanej treści na wypadek awarii; backups() — kopie plików tego projektu: [{ path, text }]
    Q_INVOKABLE void backupWrite(const QString &path, const QString &text);
    Q_INVOKABLE void backupRemove(const QString &path);
    Q_INVOKABLE QVariantList backups() const;
    Q_INVOKABLE QString clipboardText() const;
    Q_INVOKABLE QString number(int n) const;                     // „12 345”

    // Git
    Q_INVOKABLE void refreshGit();
    Q_INVOKABLE void requestBase(const QString &path);           // wynik: baseReady
    // Zatwierdzanie i synchronizacja — wynik: gitDone(operacja, ok, komunikat)
    Q_INVOKABLE void stage(const QStringList &paths);
    Q_INVOKABLE void unstage(const QStringList &paths);
    Q_INVOKABLE void discard(const QStringList &paths);
    Q_INVOKABLE void commit(const QString &message, bool amend, bool all);
    Q_INVOKABLE void push();
    Q_INVOKABLE void pull();
    Q_INVOKABLE void fetch(bool quiet = false);                   // quiet — w tle, bez komunikatu o błędzie
    Q_INVOKABLE QString lastCommitMessage() const;
    Q_INVOKABLE QVariantList diff(const QString &path, bool staged) const;
    // Historia pliku (git log --follow); wynik: historyReady(ścieżka, [{ hash, short, subject, author, time, body, added, removed, rel }])
    Q_INVOKABLE void requestHistory(const QString &path);
    // Zatwierdzenie: { hash, short, subject, author, time, body, files: [{ path, rel, name, dir, added, removed, exists }] }
    Q_INVOKABLE QVariantMap commitInfo(const QString &hash) const;
    Q_INVOKABLE QVariantList commitDiff(const QString &hash, const QString &rel) const;
    Q_INVOKABLE QVariantMap fileAt(const QString &hash, const QString &rel) const;        // { ok, text }
    // Jeden fragment różnic (numer z diff): stage | unstage | discard
    Q_INVOKABLE void applyHunk(const QString &path, bool staged, int index, const QString &action);
    // Gałęzie: lokalne i zdalne bez lokalnej kopii, od ostatnio zmienianej: [{ name, remote, current, upstream, time, subject }]
    Q_INVOKABLE QVariantList branches() const;
    Q_INVOKABLE void checkout(const QString &name, bool remote);
    Q_INVOKABLE void createBranch(const QString &name);
    Q_INVOKABLE void mergeBranch(const QString &name);
    Q_INVOKABLE void deleteBranch(const QString &name);
    Q_INVOKABLE void stash(bool pop);
    Q_INVOKABLE QString mergeMessage() const;                    // opis z .git/MERGE_MSG
    Q_INVOKABLE void mergeAbort();
    // Autor każdego wiersza (treść z edytora); wynik: blameReady(ścieżka, zatwierdzenia, indeks zatwierdzenia na wiersz)
    Q_INVOKABLE void blame(const QString &path, const QString &text);

    // Szybkie otwieranie i szukanie
    Q_INVOKABLE void refreshFiles();
    Q_INVOKABLE QVariantList quickOpen(const QString &query, int limit = 60) const;   // [{ path, rel, name, dir, html }]
    Q_INVOKABLE void search(const QString &query, bool matchCase, bool wholeWord, bool regex, const QVariantMap &buffers = QVariantMap());
    Q_INVOKABLE void cancelSearch();
    // Zamiana w pliku na dysku (dla plików bez otwartej karty); zwraca liczbę zamian
    Q_INVOKABLE int replaceInFile(const QString &path, const QString &query, bool matchCase, bool wholeWord, bool regex, const QString &replacement);

Q_SIGNALS:
    void rootChanged();
    void recentChanged();
    void gitChanged();
    void resultsChanged();
    void searchingChanged();
    void filesReady();
    void message(const QString &text);
    void fileChanged(const QString &path);
    void baseReady(const QString &path, const QString &text, bool ok);
    void gitDone(const QString &op, bool ok, const QString &message);
    void gitBusyChanged();
    void blameReady(const QString &path, const QVariantList &commits, const QVariantList &lines);
    void historyReady(const QString &path, const QVariantList &entries);

private:
    void addRecent(const QString &path);
    void parseStatus(const QByteArray &out);
    QString gitRelative(const QString &path) const;
    QStringList gitPaths(const QStringList &paths) const;
    QString rawDiff(const QString &path, bool staged) const;
    static QVariantList parseDiff(const QString &raw);
    void runGit(const QString &op, const QStringList &args, const QByteArray &input, std::function<void(bool, const QString &)> done);
    void loadCommits();
    static QStringList listFiles(const QString &root, bool git);

    QString m_root, m_gitTop;
    FileTree *m_tree;
    mutable QSettings m_settings;
    QFileSystemWatcher m_watcher;

    QPointer<QProcess> m_status;
    bool m_statusAgain = false;
    QString m_branch, m_head, m_upstream, m_gitBusy, m_gitDir;
    bool m_merging = false;
    QVariantList m_commits;
    int m_ahead = 0, m_behind = 0;
    QVariantList m_changes;

    QStringList m_files;                                          // względne ścieżki plików projektu
    QPointer<QThread> m_filesThread;
    QPointer<QThread> m_searchThread;
    std::shared_ptr<std::atomic<int>> m_searchGen = std::make_shared<std::atomic<int>>(0);
    QVariantList m_results;
    int m_resultCount = 0;
    bool m_truncated = false;
    bool m_searching = false;
    QString m_searchError;
};
