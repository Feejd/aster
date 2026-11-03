#include "project.h"
#include "searchregex.h"

#include <QClipboard>
#include <QCryptographicHash>
#include <QDesktopServices>
#include <QDir>
#include <QFile>
#include <QFileInfo>
#include <QGuiApplication>
#include <QLocale>
#include <QRegularExpression>
#include <QSaveFile>
#include <QStandardPaths>
#include <QStringDecoder>
#include <QStringEncoder>
#include <QUrl>

namespace {

constexpr int RecentLimit = 12;
constexpr int MatchLimit = 20000;
constexpr qint64 SearchFileLimit = 2 * 1024 * 1024;

QString projectKey(const QString &root)
{
    return QStringLiteral("projects/") + QString::fromLatin1(QCryptographicHash::hash(root.toUtf8(), QCryptographicHash::Md5).toHex());
}

QString escapeHtml(QStringView s)
{
    QString out;
    out.reserve(s.size());
    for (QChar c : s) {
        if (c == QLatin1Char('<'))
            out += QLatin1String("&lt;");
        else if (c == QLatin1Char('>'))
            out += QLatin1String("&gt;");
        else if (c == QLatin1Char('&'))
            out += QLatin1String("&amp;");
        else
            out += c;
    }
    return out;
}

// Dopasowanie „po kolei” (jak Ctrl+P w VS Code): litery zapytania w tej samej kolejności w ścieżce.
// Wyżej: trafienia w nazwie pliku, ciągłe, na początku słowa. Zwraca −1, gdy nie pasuje.
int fuzzy(const QString &text, int from, const QString &q, QList<int> *positions)
{
    int score = 0, ti = from, prev = -2;
    positions->clear();
    for (QChar qc : q) {
        if (qc == QLatin1Char(' '))
            continue;
        while (ti < text.size() && text.at(ti).toLower() != qc)
            ++ti;
        if (ti >= text.size())
            return -1;
        int s = 1;
        if (ti == prev + 1)
            s += 6;
        if (ti == from || QStringLiteral("/_-. ").contains(text.at(ti - 1)) || (text.at(ti).isUpper() && text.at(ti - 1).isLower()))
            s += 8;
        score += s;
        positions->append(ti);
        prev = ti;
        ++ti;
    }
    return score;
}

} // namespace

Project::Project(QObject *parent)
    : QObject(parent)
    , m_tree(new FileTree(this))
{
    connect(&m_watcher, &QFileSystemWatcher::fileChanged, this, [this](const QString &path) {
        // Zapis przez podmianę pliku zdejmuje obserwację — dodaj ponownie (jak w Edytorze tekstu)
        if (QFileInfo::exists(path) && !m_watcher.files().contains(path))
            m_watcher.addPath(path);
        Q_EMIT fileChanged(path);
    });
    connect(m_tree, &FileTree::expandedChanged, this, [this] {
        if (!m_root.isEmpty())
            m_settings.setValue(projectKey(m_root) + QStringLiteral("/expanded"), m_tree->expandedDirs());
    });
}

Project::~Project()
{
    // Wątki szukania kończą się przy najbliższym pliku
    m_searchGen->fetch_add(1);
    for (QThread *t : {m_searchThread.data(), m_filesThread.data()})
        if (t)
            t->wait(3000);
    // Git w tle przy zamykaniu okna — krótko poczekaj, potem przerwij (bez ostrzeżeń QProcess)
    for (QProcess *p : findChildren<QProcess *>()) {
        p->disconnect(this);
        if (!p->waitForFinished(500)) {
            p->kill();
            p->waitForFinished(500);
        }
    }
}

QString Project::name() const
{
    return m_root.isEmpty() ? QString() : QFileInfo(m_root).fileName();
}

// ——— Folder projektu ———

bool Project::open(const QString &pathOrUrl)
{
    QString path = toPath(pathOrUrl);
    QFileInfo fi(path);
    if (!fi.isDir()) {
        Q_EMIT message(QStringLiteral("Nie ma folderu „%1”").arg(fi.fileName()));
        return false;
    }
    path = QDir::cleanPath(fi.absoluteFilePath());
    if (path == m_root)
        return true;
    cancelSearch();
    m_root = path;
    m_results.clear();
    m_resultCount = 0;
    m_truncated = false;
    m_files.clear();

    // Repozytorium gita (folder projektu może leżeć głębiej niż katalog główny repozytorium)
    m_gitTop.clear();
    QProcess p;
    p.start(QStringLiteral("git"), {QStringLiteral("-C"), m_root, QStringLiteral("rev-parse"), QStringLiteral("--show-toplevel")});
    if (p.waitForFinished(3000) && p.exitStatus() == QProcess::NormalExit && p.exitCode() == 0)
        m_gitTop = QDir::cleanPath(QString::fromUtf8(p.readAllStandardOutput()).trimmed());
    // Katalog .git (w worktree to plik ze wskazaniem) — do sprawdzania, czy trwa łączenie
    m_gitDir.clear();
    if (!m_gitTop.isEmpty()) {
        QProcess d;
        d.start(QStringLiteral("git"), {QStringLiteral("-C"), m_gitTop, QStringLiteral("rev-parse"), QStringLiteral("--absolute-git-dir")});
        if (d.waitForFinished(3000) && d.exitCode() == 0)
            m_gitDir = QString::fromUtf8(d.readAllStandardOutput()).trimmed();
    }
    m_branch.clear();
    m_head.clear();
    m_upstream.clear();
    m_commits.clear();
    m_changes.clear();
    m_ahead = m_behind = 0;

    m_tree->setRoot(m_root);
    m_tree->setExpanded(m_settings.value(projectKey(m_root) + QStringLiteral("/expanded")).toStringList());
    addRecent(m_root);
    Q_EMIT rootChanged();
    Q_EMIT gitChanged();
    Q_EMIT resultsChanged();
    refreshGit();
    refreshFiles();
    return true;
}

void Project::close()
{
    cancelSearch();
    m_root.clear();
    m_gitTop.clear();
    m_tree->setRoot(QString());
    m_changes.clear();
    m_results.clear();
    m_files.clear();
    Q_EMIT rootChanged();
    Q_EMIT gitChanged();
    Q_EMIT resultsChanged();
}

void Project::addRecent(const QString &path)
{
    QStringList list = m_settings.value(QStringLiteral("recent")).toStringList();
    list.removeAll(path);
    list.prepend(path);
    while (list.size() > RecentLimit)
        list.removeLast();
    m_settings.setValue(QStringLiteral("recent"), list);
    Q_EMIT recentChanged();
}

void Project::forgetRecent(const QString &path)
{
    QStringList list = m_settings.value(QStringLiteral("recent")).toStringList();
    list.removeAll(path);
    m_settings.setValue(QStringLiteral("recent"), list);
    Q_EMIT recentChanged();
}

QVariantList Project::recent() const
{
    QVariantList out;
    for (const QString &p : m_settings.value(QStringLiteral("recent")).toStringList()) {
        if (!QFileInfo(p).isDir())
            continue;
        out << QVariantMap{{QStringLiteral("path"), p},
                           {QStringLiteral("name"), QFileInfo(p).fileName()},
                           {QStringLiteral("pretty"), pretty(QFileInfo(p).absolutePath())},
                           {QStringLiteral("git"), QFileInfo::exists(p + QStringLiteral("/.git"))}};
    }
    return out;
}

QStringList Project::sessionTabs() const
{
    if (m_root.isEmpty())
        return {};
    QStringList out;
    for (const QString &p : m_settings.value(projectKey(m_root) + QStringLiteral("/tabs")).toStringList())
        if (QFileInfo(p).isFile())
            out << p;
    return out;
}

int Project::sessionCurrent() const
{
    return m_root.isEmpty() ? 0 : m_settings.value(projectKey(m_root) + QStringLiteral("/current"), 0).toInt();
}

void Project::saveSession(const QStringList &tabs, int current, bool terminal, int sidebarView)
{
    if (m_root.isEmpty())
        return;
    const QString key = projectKey(m_root);
    m_settings.setValue(key + QStringLiteral("/tabs"), tabs);
    m_settings.setValue(key + QStringLiteral("/current"), current);
    m_settings.setValue(key + QStringLiteral("/terminal"), terminal);
    m_settings.setValue(key + QStringLiteral("/view"), sidebarView);
}

QVariantMap Project::sessionLayout() const
{
    const QString key = projectKey(m_root);
    return {{QStringLiteral("terminal"), m_settings.value(key + QStringLiteral("/terminal"), false).toBool()},
            {QStringLiteral("sidebarView"), m_settings.value(key + QStringLiteral("/view"), 0).toInt()}};
}

// ——— Pliki ———

QString Project::toPath(const QString &pathOrUrl) const
{
    const QUrl url(pathOrUrl);
    return QFileInfo(url.isLocalFile() ? url.toLocalFile() : pathOrUrl).absoluteFilePath();
}

QString Project::fileName(const QString &path) const
{
    return QFileInfo(path).fileName();
}

QString Project::folder(const QString &path) const
{
    return QFileInfo(path).absolutePath();
}

QString Project::relative(const QString &path) const
{
    if (m_root.isEmpty() || !path.startsWith(m_root + QLatin1Char('/')))
        return pretty(path);
    return path.mid(m_root.size() + 1);
}

QString Project::pretty(const QString &path) const
{
    const QString home = QDir::homePath();
    if (path == home)
        return QStringLiteral("~");
    if (path.startsWith(home + QLatin1Char('/')))
        return QLatin1Char('~') + path.mid(home.size());
    return path;
}

bool Project::exists(const QString &path) const
{
    return QFileInfo::exists(path);
}

bool Project::isDir(const QString &path) const
{
    return QFileInfo(path).isDir();
}

QString Project::number(int n) const
{
    return QLocale(QLocale::Polish).toString(n);
}

// Wczytywanie i zapis — jak w Edytorze tekstu (apps/editor/src/editor.cpp): BOM, UTF-8, pliki z polskiego Windows w Windows-1250
QVariantMap Project::load(const QString &pathOrUrl) const
{
    const QString path = toPath(pathOrUrl);
    QFile f(path);
    const QFileInfo fi(path);
    if (fi.size() > 32LL * 1024 * 1024)
        return {{QStringLiteral("ok"), false}, {QStringLiteral("error"), QStringLiteral("Plik jest za duży (ponad 32 MB)")}};
    if (!f.open(QIODevice::ReadOnly))
        return {{QStringLiteral("ok"), false}, {QStringLiteral("error"), QStringLiteral("Nie można otworzyć „%1”").arg(fi.fileName())}};
    const QByteArray data = f.readAll();
    if (data.left(8192).contains('\0') && !data.startsWith("\xFF\xFE") && !data.startsWith("\xFE\xFF"))
        return {{QStringLiteral("ok"), false}, {QStringLiteral("binary"), true},
                {QStringLiteral("error"), QStringLiteral("„%1” nie jest plikiem tekstowym").arg(fi.fileName())}};

    QString encoding = QStringLiteral("UTF-8");
    QString text;
    if (const auto bom = QStringConverter::encodingForData(data); bom && *bom != QStringConverter::Utf8) {
        QStringDecoder dec(*bom);
        text = dec(data);
        encoding = QString::fromLatin1(QStringConverter::nameForEncoding(*bom));
    } else {
        QStringDecoder utf8(QStringConverter::Utf8, QStringConverter::Flag::Stateless);
        text = utf8(data);
        if (utf8.hasError()) {
            QStringDecoder cp1250("windows-1250");
            if (cp1250.isValid()) {
                text = cp1250(data);
                encoding = QStringLiteral("Windows-1250");
            } else {
                text = QString::fromLatin1(data);
                encoding = QStringLiteral("ISO-8859-1");
            }
        } else if (data.startsWith("\xEF\xBB\xBF")) {
            encoding = QStringLiteral("UTF-8 BOM");
        }
    }
    if (text.startsWith(QChar(0xFEFF)))
        text.remove(0, 1);
    const QString eol = text.contains(QLatin1String("\r\n")) ? QStringLiteral("\r\n") : QStringLiteral("\n");
    if (eol == QLatin1String("\r\n"))
        text.replace(QLatin1String("\r\n"), QLatin1String("\n"));
    return {{QStringLiteral("ok"), true},
            {QStringLiteral("path"), path},
            {QStringLiteral("text"), text},
            {QStringLiteral("encoding"), encoding},
            {QStringLiteral("eol"), eol},
            {QStringLiteral("readOnly"), !fi.isWritable()}};
}

bool Project::save(const QString &path, const QString &text, const QString &encoding, const QString &eol)
{
    QString out = text;
    if (eol == QLatin1String("\r\n"))
        out.replace(QLatin1Char('\n'), QLatin1String("\r\n"));
    QByteArray data;
    if (encoding.startsWith(QLatin1String("UTF-8"))) {
        data = out.toUtf8();
        if (encoding == QLatin1String("UTF-8 BOM"))
            data.prepend("\xEF\xBB\xBF");
    } else {
        QStringEncoder enc(encoding.toLatin1().constData(), QStringConverter::Flag::WriteBom);
        if (!enc.isValid()) {
            data = out.toUtf8();
        } else {
            data = enc(out);
            if (enc.hasError()) {
                Q_EMIT message(QStringLiteral("Niektórych znaków nie da się zapisać w kodowaniu %1 — zapisz jako UTF-8").arg(encoding));
                return false;
            }
        }
    }
    QSaveFile f(path);
    if (!f.open(QIODevice::WriteOnly) || f.write(data) != data.size() || !f.commit()) {
        Q_EMIT message(QStringLiteral("Nie udało się zapisać „%1”").arg(QFileInfo(path).fileName()));
        return false;
    }
    refreshGit();
    return true;
}

QString Project::createFile(const QString &dir, const QString &name)
{
    // Nazwa może zawierać podfoldery („src/nowy.cpp”) — jak w VS Code
    const QString clean = name.trimmed();
    if (clean.isEmpty() || clean.startsWith(QLatin1Char('/')) || clean.contains(QLatin1String("..")))
        return {};
    const QString path = QDir::cleanPath(dir + QLatin1Char('/') + clean);
    if (QFileInfo::exists(path)) {
        Q_EMIT message(QStringLiteral("„%1” już istnieje").arg(clean));
        return {};
    }
    QDir().mkpath(QFileInfo(path).absolutePath());
    QFile f(path);
    if (!f.open(QIODevice::WriteOnly)) {
        Q_EMIT message(QStringLiteral("Nie udało się utworzyć „%1”").arg(clean));
        return {};
    }
    f.close();
    m_tree->reveal(path);
    m_tree->refresh();
    refreshGit();
    refreshFiles();
    return path;
}

QString Project::createFolder(const QString &dir, const QString &name)
{
    const QString clean = name.trimmed();
    if (clean.isEmpty() || clean.startsWith(QLatin1Char('/')) || clean.contains(QLatin1String("..")))
        return {};
    const QString path = QDir::cleanPath(dir + QLatin1Char('/') + clean);
    if (QFileInfo::exists(path)) {
        Q_EMIT message(QStringLiteral("„%1” już istnieje").arg(clean));
        return {};
    }
    if (!QDir().mkpath(path)) {
        Q_EMIT message(QStringLiteral("Nie udało się utworzyć folderu „%1”").arg(clean));
        return {};
    }
    m_tree->reveal(path);
    m_tree->expandPath(path);
    return path;
}

QString Project::rename(const QString &path, const QString &newName)
{
    const QString clean = newName.trimmed();
    if (clean.isEmpty() || clean.contains(QLatin1Char('/')) || clean == QLatin1String(".") || clean == QLatin1String(".."))
        return {};
    const QString target = QFileInfo(path).absolutePath() + QLatin1Char('/') + clean;
    if (target == path)
        return path;
    // Sama zmiana wielkości liter też jest zmianą nazwy
    if (QFileInfo::exists(target) && target.compare(path, Qt::CaseInsensitive) != 0) {
        Q_EMIT message(QStringLiteral("„%1” już istnieje").arg(clean));
        return {};
    }
    if (!QFile::rename(path, target)) {
        Q_EMIT message(QStringLiteral("Nie udało się zmienić nazwy „%1”").arg(QFileInfo(path).fileName()));
        return {};
    }
    m_tree->refresh();
    refreshGit();
    refreshFiles();
    return target;
}

bool Project::trash(const QString &path)
{
    if (!QFile::moveToTrash(path)) {
        Q_EMIT message(QStringLiteral("Nie udało się przenieść „%1” do Kosza").arg(QFileInfo(path).fileName()));
        return false;
    }
    m_tree->refresh();
    refreshGit();
    refreshFiles();
    return true;
}

void Project::watch(const QStringList &paths)
{
    const QStringList old = m_watcher.files();
    for (const QString &p : old)
        if (!paths.contains(p))
            m_watcher.removePath(p);
    for (const QString &p : paths)
        if (!p.isEmpty() && !old.contains(p) && QFileInfo::exists(p))
            m_watcher.addPath(p);
}

void Project::showInFiles(const QString &path) const
{
    QDesktopServices::openUrl(QUrl::fromLocalFile(QFileInfo(path).isDir() ? path : QFileInfo(path).absolutePath()));
}

void Project::copyText(const QString &text) const
{
    QGuiApplication::clipboard()->setText(text);
}

QString Project::clipboardText() const
{
    return QGuiApplication::clipboard()->text();
}

// ——— Git ———

QString Project::gitRelative(const QString &path) const
{
    return QDir(m_gitTop).relativeFilePath(path);
}

void Project::refreshGit()
{
    if (m_gitTop.isEmpty())
        return;
    if (const bool merging = !m_gitDir.isEmpty() && QFileInfo::exists(m_gitDir + QStringLiteral("/MERGE_HEAD")); merging != m_merging) {
        m_merging = merging;
        Q_EMIT gitChanged();
    }
    if (m_status) {
        m_statusAgain = true;               // kolejne odświeżenie po bieżącym
        return;
    }
    auto *p = new QProcess(this);
    m_status = p;
    connect(p, &QProcess::finished, this, [this, p](int code, QProcess::ExitStatus st) {
        p->deleteLater();
        if (st == QProcess::NormalExit && code == 0)
            parseStatus(p->readAllStandardOutput());
        if (m_statusAgain) {
            m_statusAgain = false;
            QMetaObject::invokeMethod(this, &Project::refreshGit, Qt::QueuedConnection);
        }
    });
    connect(p, &QProcess::errorOccurred, p, [p](QProcess::ProcessError e) { if (e == QProcess::FailedToStart) p->deleteLater(); });
    // Bez blokady indeksu (git status w tle nie przeszkadza poleceniom w terminalu)
    QProcessEnvironment env = QProcessEnvironment::systemEnvironment();
    env.insert(QStringLiteral("GIT_OPTIONAL_LOCKS"), QStringLiteral("0"));
    p->setProcessEnvironment(env);
    p->start(QStringLiteral("git"), {QStringLiteral("-C"), m_gitTop, QStringLiteral("status"), QStringLiteral("--porcelain=v2"),
                                     QStringLiteral("--branch"), QStringLiteral("-z"), QStringLiteral("--untracked-files=normal"),
                                     QStringLiteral("--ignored=traditional")});
}

void Project::parseStatus(const QByteArray &out)
{
    const QList<QByteArray> parts = out.split('\0');
    QString branch, head, upstream;
    int ahead = 0, behind = 0;
    QHash<QString, QString> files, dirs;
    QSet<QString> ignored;
    QVariantList changes;
    // index / work — stan w indeksie (dodane do zatwierdzenia) i w katalogu roboczym: litera albo pusty
    const auto add = [&](const QString &rel, const QString &status, const QString &index, const QString &work) {
        QString r = rel;
        const bool isDir = r.endsWith(QLatin1Char('/'));
        if (isDir)
            r.chop(1);
        const QString abs = m_gitTop + QLatin1Char('/') + r;
        files.insert(abs, status);
        // Foldery nad zmienionym plikiem — kropka w drzewie
        QString d = QFileInfo(abs).absolutePath();
        while (d.size() >= m_root.size() && d.startsWith(m_root)) {
            QString &cur = dirs[d];
            if (cur.isEmpty() || (cur == QLatin1String("U") && status != QLatin1String("U")))
                cur = status == QLatin1String("U") ? QStringLiteral("U") : QStringLiteral("M");
            if (d == m_root)
                break;
            d = QFileInfo(d).absolutePath();
        }
        changes << QVariantMap{{QStringLiteral("path"), abs},
                               {QStringLiteral("rel"), relative(abs)},
                               {QStringLiteral("name"), QFileInfo(abs).fileName()},
                               {QStringLiteral("dir"), QFileInfo(abs).absolutePath() == m_root ? QString() : relative(QFileInfo(abs).absolutePath())},
                               {QStringLiteral("status"), status},
                               {QStringLiteral("staged"), !index.isEmpty()},
                               {QStringLiteral("index"), index},
                               {QStringLiteral("work"), work},
                               {QStringLiteral("isDir"), isDir}};
    };
    const auto one = [](char c) {
        switch (c) {
        case '.': return QString();
        case 'A': case 'C': return QStringLiteral("A");
        case 'D': return QStringLiteral("D");
        case 'R': return QStringLiteral("R");
        default: return QStringLiteral("M");
        }
    };
    const auto letter = [&](char x, char y) { return one(y != '.' ? y : x); };
    for (int i = 0; i < parts.size(); ++i) {
        const QByteArray &e = parts.at(i);
        if (e.isEmpty())
            continue;
        if (e.startsWith("# branch.oid ")) {
            head = QString::fromLatin1(e.mid(13));
        } else if (e.startsWith("# branch.head ")) {
            branch = QString::fromUtf8(e.mid(14));
        } else if (e.startsWith("# branch.upstream ")) {
            upstream = QString::fromUtf8(e.mid(18));
        } else if (e.startsWith("# branch.ab ")) {
            const QList<QByteArray> ab = e.mid(12).split(' ');
            if (ab.size() == 2) {
                ahead = ab[0].mid(1).toInt();
                behind = ab[1].mid(1).toInt();
            }
        } else if (e.startsWith("1 ") || e.startsWith("2 ") || e.startsWith("u ")) {
            // Pola rozdzielone spacjami; ścieżka to reszta po stałej liczbie pól
            const int fields = e.startsWith("1 ") ? 8 : e.startsWith("2 ") ? 9 : 10;
            int at = 0;
            for (int f = 0; f < fields && at >= 0; ++f)
                at = int(e.indexOf(' ', at + 1));
            if (at < 0)
                continue;
            const QString rel = QString::fromUtf8(e.mid(at + 1));
            const char x = e.at(2), y = e.at(3);
            if (e.startsWith("u "))
                add(rel, QStringLiteral("C"), QString(), QStringLiteral("C"));
            else
                add(rel, letter(x, y), one(x), one(y));
            if (e.startsWith("2 "))
                ++i;                         // następne pole to stara nazwa
        } else if (e.startsWith("? ")) {
            add(QString::fromUtf8(e.mid(2)), QStringLiteral("U"), QString(), QStringLiteral("U"));
        } else if (e.startsWith("! ")) {
            QString rel = QString::fromUtf8(e.mid(2));
            if (rel.endsWith(QLatin1Char('/')))
                rel.chop(1);
            ignored.insert(m_gitTop + QLatin1Char('/') + rel);
        }
    }
    if (branch == QLatin1String("(detached)"))
        branch = head.left(7);
    std::sort(changes.begin(), changes.end(), [](const QVariant &a, const QVariant &b) {
        return a.toMap().value(QStringLiteral("rel")).toString() < b.toMap().value(QStringLiteral("rel")).toString();
    });
    m_tree->setGit(files, dirs, ignored);
    if (head != m_head)
        loadCommits();
    if (branch != m_branch || head != m_head || ahead != m_ahead || behind != m_behind || changes != m_changes || upstream != m_upstream) {
        m_branch = branch;
        m_upstream = upstream;
        m_head = head;
        m_ahead = ahead;
        m_behind = behind;
        m_changes = changes;
        Q_EMIT gitChanged();
    }
}

void Project::requestBase(const QString &path)
{
    if (m_gitTop.isEmpty() || !path.startsWith(m_gitTop + QLatin1Char('/'))) {
        Q_EMIT baseReady(path, QString(), false);
        return;
    }
    auto *p = new QProcess(this);
    connect(p, &QProcess::finished, this, [this, p, path](int code, QProcess::ExitStatus st) {
        p->deleteLater();
        const bool ok = st == QProcess::NormalExit && code == 0;
        Q_EMIT baseReady(path, ok ? QString::fromUtf8(p->readAllStandardOutput()) : QString(), ok);
    });
    connect(p, &QProcess::errorOccurred, p, [p](QProcess::ProcessError e) { if (e == QProcess::FailedToStart) p->deleteLater(); });
    p->start(QStringLiteral("git"), {QStringLiteral("-C"), m_gitTop, QStringLiteral("show"), QStringLiteral("HEAD:") + gitRelative(path)});
}

// ——— Git: zatwierdzanie i synchronizacja ———

void Project::runGit(const QString &op, const QStringList &args, const QByteArray &input, std::function<void(bool, const QString &)> done)
{
    if (m_gitTop.isEmpty())
        return;
    auto *p = new QProcess(this);
    // Bez pytań o hasło w tle (zawisłby niewidoczny monit) — logowanie raz w terminalu
    QProcessEnvironment env = QProcessEnvironment::systemEnvironment();
    env.insert(QStringLiteral("GIT_TERMINAL_PROMPT"), QStringLiteral("0"));
    env.insert(QStringLiteral("GIT_SSH_COMMAND"), QStringLiteral("ssh -o BatchMode=yes"));
    env.insert(QStringLiteral("LC_ALL"), QStringLiteral("C"));
    p->setProcessEnvironment(env);
    p->setWorkingDirectory(m_gitTop);
    m_gitBusy = op;
    Q_EMIT gitBusyChanged();
    connect(p, &QProcess::finished, this, [this, p, op, done](int code, QProcess::ExitStatus st) {
        p->deleteLater();
        const bool ok = st == QProcess::NormalExit && code == 0;
        const QString err = QString::fromUtf8(p->readAllStandardError()).trimmed();
        const QString out = QString::fromUtf8(p->readAllStandardOutput()).trimmed();
        m_gitBusy.clear();
        Q_EMIT gitBusyChanged();
        if (done)
            done(ok, ok ? out : (err.isEmpty() ? out : err));
        refreshGit();
    });
    connect(p, &QProcess::errorOccurred, this, [this, p, op](QProcess::ProcessError e) {
        if (e != QProcess::FailedToStart)
            return;
        p->deleteLater();
        m_gitBusy.clear();
        Q_EMIT gitBusyChanged();
        Q_EMIT gitDone(op, false, QStringLiteral("Nie można uruchomić gita"));
    });
    p->start(QStringLiteral("git"), args);
    if (!input.isEmpty())
        p->write(input);
    p->closeWriteChannel();
}

QStringList Project::gitPaths(const QStringList &paths) const
{
    QStringList out;
    for (const QString &p : paths)
        out << gitRelative(p);
    return out;
}

void Project::stage(const QStringList &paths)
{
    runGit(QStringLiteral("stage"), QStringList{QStringLiteral("add"), QStringLiteral("-A"), QStringLiteral("--")} + gitPaths(paths), {},
           [this](bool ok, const QString &msg) { if (!ok) Q_EMIT gitDone(QStringLiteral("stage"), false, msg); });
}

void Project::unstage(const QStringList &paths)
{
    // Repozytorium bez pierwszego zatwierdzenia nie ma HEAD — wtedy „rm --cached”
    const QStringList args = m_head.isEmpty() || m_head == QLatin1String("(initial)")
        ? QStringList{QStringLiteral("rm"), QStringLiteral("--cached"), QStringLiteral("-r"), QStringLiteral("-q"), QStringLiteral("--")}
        : QStringList{QStringLiteral("restore"), QStringLiteral("--staged"), QStringLiteral("--")};
    runGit(QStringLiteral("unstage"), args + gitPaths(paths), {},
           [this](bool ok, const QString &msg) { if (!ok) Q_EMIT gitDone(QStringLiteral("unstage"), false, msg); });
}

void Project::discard(const QStringList &paths)
{
    // Nowe (nieśledzone) pliki idą do Kosza — da się je odzyskać; śledzone wracają do wersji z indeksu
    QStringList tracked;
    for (const QString &p : paths) {
        bool untracked = false;
        for (const QVariant &v : std::as_const(m_changes)) {
            const QVariantMap m = v.toMap();
            if (m.value(QStringLiteral("path")).toString() == p && m.value(QStringLiteral("work")).toString() == QLatin1String("U"))
                untracked = true;
        }
        if (untracked)
            QFile::moveToTrash(p);
        else
            tracked << p;
    }
    if (tracked.isEmpty()) {
        m_tree->refresh();
        refreshGit();
        return;
    }
    runGit(QStringLiteral("discard"), QStringList{QStringLiteral("restore"), QStringLiteral("--worktree"), QStringLiteral("--")} + gitPaths(tracked), {},
           [this](bool ok, const QString &msg) {
               m_tree->refresh();
               if (!ok) Q_EMIT gitDone(QStringLiteral("discard"), false, msg);
           });
}

void Project::commit(const QString &message, bool amend, bool all)
{
    if (message.trimmed().isEmpty() && !amend) {
        Q_EMIT gitDone(QStringLiteral("commit"), false, QStringLiteral("Wpisz opis zmian"));
        return;
    }
    const auto doCommit = [this, message, amend] {
        QStringList args{QStringLiteral("commit"), QStringLiteral("-q")};
        if (amend)
            args << QStringLiteral("--amend");
        if (message.trimmed().isEmpty())
            args << QStringLiteral("--no-edit");
        else
            args << QStringLiteral("-F") << QStringLiteral("-");
        runGit(QStringLiteral("commit"), args, message.trimmed().toUtf8(), [this](bool ok, const QString &msg) {
            QString text = msg;
            if (!ok && msg.contains(QLatin1String("user.email")))
                text = QStringLiteral("Git nie zna autora — w terminalu: git config --global user.name \"Imię Nazwisko\" i git config --global user.email adres@poczta");
            else if (!ok && msg.contains(QLatin1String("nothing to commit")))
                text = QStringLiteral("Nie ma nic do zatwierdzenia");
            Q_EMIT gitDone(QStringLiteral("commit"), ok, ok ? QStringLiteral("Zatwierdzono") : text.left(300));
        });
    };
    // Nic nie dodano — zatwierdzamy wszystkie zmiany (jak „smart commit” w VS Code)
    if (all)
        runGit(QStringLiteral("stage"), {QStringLiteral("add"), QStringLiteral("-A")}, {}, [doCommit](bool ok, const QString &) { if (ok) doCommit(); });
    else
        doCommit();
}

static QString syncError(const QString &msg)
{
    if (msg.contains(QLatin1String("terminal prompts disabled")) || msg.contains(QLatin1String("Authentication failed"))
        || msg.contains(QLatin1String("Permission denied")) || msg.contains(QLatin1String("could not read Username")))
        return QStringLiteral("Serwer wymaga logowania — wyślij raz z terminala (git push), potem zadziała tutaj");
    if (msg.contains(QLatin1String("Could not resolve host")) || msg.contains(QLatin1String("unable to access")))
        return QStringLiteral("Brak połączenia z serwerem repozytorium");
    if (msg.contains(QLatin1String("rejected")) || msg.contains(QLatin1String("non-fast-forward")))
        return QStringLiteral("Na serwerze są nowsze zmiany — najpierw pobierz");
    if (msg.contains(QLatin1String("Not possible to fast-forward")) || msg.contains(QLatin1String("diverged")))
        return QStringLiteral("Twoje i zdalne zmiany się rozeszły — połącz je w terminalu (git pull)");
    if (msg.contains(QLatin1String("No configured push destination")) || msg.contains(QLatin1String("does not appear to be a git repository")))
        return QStringLiteral("Repozytorium nie ma serwera (remote) — dodaj go: git remote add origin ADRES");
    return msg.section(QLatin1Char('\n'), -2).left(300);
}

void Project::push()
{
    QStringList args{QStringLiteral("push")};
    if (m_upstream.isEmpty()) {
        // Pierwsze wysłanie gałęzi: na pierwszy serwer (zwykle origin) z ustawieniem śledzenia
        QProcess r;
        r.setWorkingDirectory(m_gitTop);
        r.start(QStringLiteral("git"), {QStringLiteral("remote")});
        r.waitForFinished(2000);
        const QString remote = QString::fromUtf8(r.readAllStandardOutput()).section(QLatin1Char('\n'), 0, 0).trimmed();
        if (remote.isEmpty()) {
            Q_EMIT gitDone(QStringLiteral("push"), false, syncError(QStringLiteral("No configured push destination")));
            return;
        }
        args << QStringLiteral("-u") << remote << m_branch;
    }
    runGit(QStringLiteral("push"), args, {}, [this](bool ok, const QString &msg) {
        Q_EMIT gitDone(QStringLiteral("push"), ok, ok ? QStringLiteral("Wysłano") : syncError(msg));
    });
}

void Project::pull()
{
    runGit(QStringLiteral("pull"), {QStringLiteral("pull"), QStringLiteral("--ff-only")}, {}, [this](bool ok, const QString &msg) {
        Q_EMIT gitDone(QStringLiteral("pull"), ok, ok ? QStringLiteral("Pobrano zmiany") : syncError(msg));
        m_tree->refresh();
    });
}

void Project::fetch(bool quiet)
{
    if (quiet && !m_gitBusy.isEmpty())
        return;
    runGit(QStringLiteral("fetch"), {QStringLiteral("fetch"), QStringLiteral("--prune")}, {}, [this, quiet](bool ok, const QString &msg) {
        if (!quiet || ok)
            Q_EMIT gitDone(QStringLiteral("fetch"), ok, ok ? QString() : syncError(msg));
    });
}

QString Project::lastCommitMessage() const
{
    if (m_gitTop.isEmpty())
        return {};
    QProcess p;
    p.setWorkingDirectory(m_gitTop);
    p.start(QStringLiteral("git"), {QStringLiteral("log"), QStringLiteral("-1"), QStringLiteral("--format=%B")});
    p.waitForFinished(2000);
    return QString::fromUtf8(p.readAllStandardOutput()).trimmed();
}

void Project::loadCommits()
{
    if (m_gitTop.isEmpty())
        return;
    auto *p = new QProcess(this);
    p->setWorkingDirectory(m_gitTop);
    connect(p, &QProcess::finished, this, [this, p] {
        p->deleteLater();
        QVariantList list;
        for (const QString &l : QString::fromUtf8(p->readAllStandardOutput()).split(QLatin1Char('\n'), Qt::SkipEmptyParts)) {
            const QStringList f = l.split(QChar(0x1f));
            if (f.size() < 4)
                continue;
            list << QVariantMap{{QStringLiteral("hash"), f[0]}, {QStringLiteral("subject"), f[1]},
                                {QStringLiteral("author"), f[2]}, {QStringLiteral("time"), f[3].toLongLong()}};
        }
        m_commits = list;
        Q_EMIT gitChanged();
    });
    connect(p, &QProcess::errorOccurred, p, [p](QProcess::ProcessError e) { if (e == QProcess::FailedToStart) p->deleteLater(); });
    p->start(QStringLiteral("git"), {QStringLiteral("log"), QStringLiteral("-8"), QStringLiteral("--format=%h%x1f%s%x1f%an%x1f%ct")});
}

QString Project::rawDiff(const QString &path, bool staged) const
{
    QProcess p;
    p.setWorkingDirectory(m_gitTop);
    bool untracked = false;
    for (const QVariant &v : std::as_const(m_changes))
        if (v.toMap().value(QStringLiteral("path")).toString() == path && v.toMap().value(QStringLiteral("work")).toString() == QLatin1String("U"))
            untracked = true;
    if (untracked && !staged)
        p.start(QStringLiteral("git"), {QStringLiteral("diff"), QStringLiteral("--no-color"), QStringLiteral("--no-index"), QStringLiteral("--"),
                                        QStringLiteral("/dev/null"), gitRelative(path)});
    else
        p.start(QStringLiteral("git"), QStringList{QStringLiteral("diff"), QStringLiteral("--no-color"), QStringLiteral("-U3")}
                                           + (staged ? QStringList{QStringLiteral("--cached")} : QStringList())
                                           + QStringList{QStringLiteral("--"), gitRelative(path)});
    p.waitForFinished(5000);
    return QString::fromUtf8(p.readAllStandardOutput());
}

QVariantList Project::diff(const QString &path, bool staged) const
{
    // Różnice jednego pliku jako wiersze: { kind: " " | "+" | "-" | "@", text, old, new, hunk }
    if (m_gitTop.isEmpty())
        return {};
    return parseDiff(rawDiff(path, staged));
}

// Wyjście git diff / git show jednego pliku jako wiersze: { kind: " " | "+" | "-" | "@", text, old, new, hunk }
QVariantList Project::parseDiff(const QString &raw)
{
    QVariantList out;
    int oldNo = 0, newNo = 0, hunkNo = -1;
    bool body = false;
    static const QRegularExpression hunk(QStringLiteral("^@@ -(\\d+)(?:,\\d+)? \\+(\\d+)(?:,\\d+)? @@(.*)$"));
    for (const QString &l : raw.split(QLatin1Char('\n'))) {
        if (const auto m = hunk.match(l); m.hasMatch()) {
            oldNo = m.captured(1).toInt();
            newNo = m.captured(2).toInt();
            body = true;
            ++hunkNo;
            out << QVariantMap{{QStringLiteral("kind"), QStringLiteral("@")}, {QStringLiteral("text"), m.captured(3).trimmed()},
                               {QStringLiteral("hunk"), hunkNo}};
            continue;
        }
        if (!body || l.startsWith(QLatin1String("\\")))
            continue;
        const QChar k = l.isEmpty() ? QLatin1Char(' ') : l.at(0);
        QVariantMap row{{QStringLiteral("kind"), QString(k)}, {QStringLiteral("text"), l.mid(1)}, {QStringLiteral("hunk"), hunkNo}};
        if (k == QLatin1Char('+')) {
            row.insert(QStringLiteral("new"), newNo++);
        } else if (k == QLatin1Char('-')) {
            row.insert(QStringLiteral("old"), oldNo++);
        } else {
            row.insert(QStringLiteral("old"), oldNo++);
            row.insert(QStringLiteral("new"), newNo++);
        }
        out << row;
        if (out.size() > 20000)
            break;
    }
    while (!out.isEmpty() && out.last().toMap().value(QStringLiteral("text")).toString().isEmpty()
           && out.last().toMap().value(QStringLiteral("kind")).toString() == QLatin1String(" "))
        out.removeLast();
    return out;
}

void Project::applyHunk(const QString &path, bool staged, int index, const QString &action)
{
    // Łatka z jednym fragmentem: nagłówek pliku (do pierwszego @@) i ten fragment, potem git apply.
    // stage — do indeksu; unstage — z indeksu (odwrotnie); discard — z katalogu roboczego (odwrotnie).
    const QStringList lines = rawDiff(path, staged).split(QLatin1Char('\n'));
    QStringList header, chunk;
    int n = -1;
    for (const QString &l : lines) {
        if (l.startsWith(QLatin1String("@@")))
            ++n;
        if (n < 0)
            header << l;
        else if (n == index)
            chunk << l;
    }
    while (!chunk.isEmpty() && chunk.last().isEmpty())
        chunk.removeLast();
    if (chunk.isEmpty() || header.isEmpty()) {
        Q_EMIT gitDone(QStringLiteral("hunk"), false, QStringLiteral("Ten fragment już się zmienił — odśwież podgląd"));
        return;
    }
    // Nowy plik (diff --no-index) — fragmentu nie da się dodać osobno; dodajemy cały plik
    if (header.join(QLatin1Char('\n')).contains(QLatin1String("/dev/null")) && action == QLatin1String("stage") && !staged) {
        stage({path});
        return;
    }
    const QByteArray patch = (header + chunk).join(QLatin1Char('\n')).toUtf8() + '\n';
    QStringList args{QStringLiteral("apply"), QStringLiteral("--whitespace=nowarn")};
    if (action != QLatin1String("discard"))
        args << QStringLiteral("--cached");
    if (action != QLatin1String("stage"))
        args << QStringLiteral("-R");
    args << QStringLiteral("-");
    runGit(QStringLiteral("hunk"), args, patch, [this, action](bool ok, const QString &msg) {
        if (action == QLatin1String("discard"))
            m_tree->refresh();
        Q_EMIT gitDone(QStringLiteral("hunk"), ok, ok ? QString() : QStringLiteral("Nie udało się: ") + msg.section(QLatin1Char('\n'), 0, 0).left(200));
    });
}

// ——— Łączenie z konfliktami i autor wiersza ———

QString Project::mergeMessage() const
{
    QFile f(m_gitDir + QStringLiteral("/MERGE_MSG"));
    if (!f.open(QIODevice::ReadOnly))
        return {};
    // Bez linii komentarzy (#), które git dopisuje przy konfliktach
    QStringList out;
    for (const QString &l : QString::fromUtf8(f.readAll()).split(QLatin1Char('\n')))
        if (!l.startsWith(QLatin1Char('#')))
            out << l;
    return out.join(QLatin1Char('\n')).trimmed();
}

void Project::mergeAbort()
{
    runGit(QStringLiteral("merge"), {QStringLiteral("merge"), QStringLiteral("--abort")}, {}, [this](bool ok, const QString &msg) {
        m_tree->refresh();
        Q_EMIT gitDone(QStringLiteral("merge"), ok, ok ? QStringLiteral("Przerwano łączenie — pliki wróciły do stanu sprzed niego") : msg.left(200));
    });
}

void Project::blame(const QString &path, const QString &text)
{
    if (m_gitTop.isEmpty() || !path.startsWith(m_gitTop + QLatin1Char('/')))
        return;
    // --contents - : treść z edytora (także niezapisana), więc wiersze się zgadzają
    auto *p = new QProcess(this);
    p->setWorkingDirectory(m_gitTop);
    connect(p, &QProcess::finished, this, [this, p, path](int code, QProcess::ExitStatus) {
        p->deleteLater();
        if (code != 0) {
            Q_EMIT blameReady(path, {}, {});
            return;
        }
        // Format porcelain: „hash wiersz_oryg wiersz [liczba]”, nagłówki zatwierdzenia przy pierwszym wystąpieniu, „\ttreść”
        QHash<QString, int> index;
        QVariantList commits, lines;
        QVariantMap cur;
        QString hash;
        for (const QString &l : QString::fromUtf8(p->readAllStandardOutput()).split(QLatin1Char('\n'))) {
            if (l.startsWith(QLatin1Char('\t'))) {
                if (!index.contains(hash)) {
                    index.insert(hash, int(commits.size()));
                    const bool uncommitted = hash.startsWith(QLatin1String("0000000"));
                    cur.insert(QStringLiteral("hash"), hash.left(8));
                    cur.insert(QStringLiteral("uncommitted"), uncommitted);
                    commits << cur;
                }
                lines << index.value(hash);
                cur.clear();
                continue;
            }
            static const QRegularExpression header(QStringLiteral("^[0-9a-f]{40} \\d+ \\d+"));
            if (header.match(l).hasMatch()) {
                hash = l.left(40);
                continue;
            }
            if (l.startsWith(QLatin1String("author ")))
                cur.insert(QStringLiteral("author"), l.mid(7));
            else if (l.startsWith(QLatin1String("author-time ")))
                cur.insert(QStringLiteral("time"), l.mid(12).toLongLong());
            else if (l.startsWith(QLatin1String("summary ")))
                cur.insert(QStringLiteral("summary"), l.mid(8));
        }
        Q_EMIT blameReady(path, commits, lines);
    });
    connect(p, &QProcess::errorOccurred, p, [p](QProcess::ProcessError e) { if (e == QProcess::FailedToStart) p->deleteLater(); });
    p->start(QStringLiteral("git"), {QStringLiteral("blame"), QStringLiteral("--porcelain"), QStringLiteral("--contents"), QStringLiteral("-"),
                                     QStringLiteral("--"), gitRelative(path)});
    p->write(text.toUtf8());
    p->closeWriteChannel();
}

// ——— Historia pliku i zatwierdzenia ———

void Project::requestHistory(const QString &path)
{
    if (m_gitTop.isEmpty() || !path.startsWith(m_gitTop + QLatin1Char('/'))) {
        Q_EMIT historyReady(path, {});
        return;
    }
    auto *p = new QProcess(this);
    p->setWorkingDirectory(m_gitTop);
    connect(p, &QProcess::finished, this, [this, p, path] {
        p->deleteLater();
        // Wpis: nagłówek z %x1e na początku, potem wiersze numstat „dodane usunięte ścieżka”
        QVariantList list;
        for (const QString &entry : QString::fromUtf8(p->readAllStandardOutput()).split(QChar(0x1e), Qt::SkipEmptyParts)) {
            const QStringList lines = entry.split(QLatin1Char('\n'));
            const QStringList f = lines.value(0).split(QChar(0x1f));
            if (f.size() < 6)
                continue;
            int added = 0, removed = 0;
            QString rel = gitRelative(path);
            for (int i = 1; i < lines.size(); ++i) {
                const QStringList n = lines.at(i).split(QLatin1Char('\t'));
                if (n.size() < 3)
                    continue;
                added += n[0].toInt();
                removed += n[1].toInt();
                rel = n[2].contains(QLatin1String(" => ")) ? n[2].section(QLatin1String(" => "), -1).remove(QLatin1Char('}')) : n[2];
            }
            list << QVariantMap{{QStringLiteral("hash"), f[0]}, {QStringLiteral("short"), f[1]}, {QStringLiteral("subject"), f[2]},
                                {QStringLiteral("author"), f[3]}, {QStringLiteral("time"), f[4].toLongLong()}, {QStringLiteral("body"), f[5].trimmed()},
                                {QStringLiteral("added"), added}, {QStringLiteral("removed"), removed}, {QStringLiteral("rel"), rel}};
        }
        Q_EMIT historyReady(path, list);
    });
    connect(p, &QProcess::errorOccurred, p, [p](QProcess::ProcessError e) { if (e == QProcess::FailedToStart) p->deleteLater(); });
    p->start(QStringLiteral("git"), {QStringLiteral("log"), QStringLiteral("--follow"), QStringLiteral("-n"), QStringLiteral("300"), QStringLiteral("--numstat"),
                                     QStringLiteral("--format=%x1e%H%x1f%h%x1f%s%x1f%an%x1f%ct%x1f%b"), QStringLiteral("--"), gitRelative(path)});
}

QVariantMap Project::commitInfo(const QString &hash) const
{
    if (m_gitTop.isEmpty())
        return {};
    QProcess p;
    p.setWorkingDirectory(m_gitTop);
    p.start(QStringLiteral("git"), {QStringLiteral("show"), QStringLiteral("--no-color"), QStringLiteral("--numstat"), QStringLiteral("--find-renames"),
                                    QStringLiteral("--format=%H%x1f%h%x1f%s%x1f%an%x1f%ct%x1f%b%x1e"), hash});
    p.waitForFinished(5000);
    const QString out = QString::fromUtf8(p.readAllStandardOutput());
    const QStringList f = out.section(QChar(0x1e), 0, 0).split(QChar(0x1f));
    if (f.size() < 6)
        return {};
    QVariantList files;
    for (const QString &l : out.section(QChar(0x1e), 1).split(QLatin1Char('\n'), Qt::SkipEmptyParts)) {
        const QStringList n = l.split(QLatin1Char('\t'));
        if (n.size() < 3)
            continue;
        QString rel = n[2];
        // Zmiana nazwy: „stara => nowa” albo „folder/{a => b}/plik”
        if (rel.contains(QLatin1String(" => "))) {
            static const QRegularExpression brace(QStringLiteral("\\{[^}]* => ([^}]*)\\}"));
            rel = rel.contains(QLatin1Char('{')) ? QString(rel).replace(brace, QStringLiteral("\\1")).replace(QLatin1String("//"), QLatin1String("/"))
                                                 : rel.section(QLatin1String(" => "), -1);
        }
        const QString abs = m_gitTop + QLatin1Char('/') + rel;
        files << QVariantMap{{QStringLiteral("path"), abs}, {QStringLiteral("rel"), rel}, {QStringLiteral("name"), QFileInfo(rel).fileName()},
                             {QStringLiteral("dir"), QFileInfo(rel).path() == QLatin1String(".") ? QString() : QFileInfo(rel).path()},
                             {QStringLiteral("added"), n[0] == QLatin1String("-") ? -1 : n[0].toInt()},
                             {QStringLiteral("removed"), n[1] == QLatin1String("-") ? -1 : n[1].toInt()},
                             {QStringLiteral("exists"), QFileInfo::exists(abs)}};
    }
    return {{QStringLiteral("hash"), f[0]}, {QStringLiteral("short"), f[1]}, {QStringLiteral("subject"), f[2]}, {QStringLiteral("author"), f[3]},
            {QStringLiteral("time"), f[4].toLongLong()}, {QStringLiteral("body"), f[5].trimmed()}, {QStringLiteral("files"), files}};
}

QVariantList Project::commitDiff(const QString &hash, const QString &rel) const
{
    if (m_gitTop.isEmpty())
        return {};
    QProcess p;
    p.setWorkingDirectory(m_gitTop);
    // Pierwsze zatwierdzenie nie ma rodzica — git show radzi sobie z tym sam
    p.start(QStringLiteral("git"), {QStringLiteral("show"), QStringLiteral("--no-color"), QStringLiteral("-U3"), QStringLiteral("--format="),
                                    QStringLiteral("--find-renames"), hash, QStringLiteral("--"), rel});
    p.waitForFinished(5000);
    return parseDiff(QString::fromUtf8(p.readAllStandardOutput()));
}

QVariantMap Project::fileAt(const QString &hash, const QString &rel) const
{
    if (m_gitTop.isEmpty())
        return {{QStringLiteral("ok"), false}};
    QProcess p;
    p.setWorkingDirectory(m_gitTop);
    p.start(QStringLiteral("git"), {QStringLiteral("show"), hash + QLatin1Char(':') + rel});
    p.waitForFinished(5000);
    const bool ok = p.exitStatus() == QProcess::NormalExit && p.exitCode() == 0;
    return {{QStringLiteral("ok"), ok}, {QStringLiteral("text"), ok ? QString::fromUtf8(p.readAllStandardOutput()) : QString()}};
}

// ——— Gałęzie i odkładanie zmian ———

QVariantList Project::branches() const
{
    if (m_gitTop.isEmpty())
        return {};
    QProcess p;
    p.setWorkingDirectory(m_gitTop);
    p.start(QStringLiteral("git"), {QStringLiteral("for-each-ref"), QStringLiteral("--sort=-committerdate"),
                                    QStringLiteral("--format=%(refname)%1f%(refname:short)%1f%(upstream:short)%1f%(committerdate:unix)%1f%(subject)"),
                                    QStringLiteral("refs/heads"), QStringLiteral("refs/remotes")});
    p.waitForFinished(3000);
    QVariantList local, remote;
    QSet<QString> localNames;
    for (const QString &l : QString::fromUtf8(p.readAllStandardOutput()).split(QLatin1Char('\n'), Qt::SkipEmptyParts)) {
        const QStringList f = l.split(QChar(0x1f));
        if (f.size() < 5 || f[0].endsWith(QLatin1String("/HEAD")))
            continue;
        const bool isRemote = f[0].startsWith(QLatin1String("refs/remotes/"));
        QVariantMap m{{QStringLiteral("name"), f[1]}, {QStringLiteral("remote"), isRemote}, {QStringLiteral("upstream"), f[2]},
                      {QStringLiteral("time"), f[3].toLongLong()}, {QStringLiteral("subject"), f[4]},
                      {QStringLiteral("current"), !isRemote && f[1] == m_branch}};
        if (isRemote) {
            remote << m;
        } else {
            localNames.insert(f[1]);
            local << m;
        }
    }
    // Zdalna gałąź, która ma już lokalną kopię, nie powtarza się
    for (const QVariant &v : std::as_const(remote))
        if (!localNames.contains(v.toMap().value(QStringLiteral("name")).toString().section(QLatin1Char('/'), 1)))
            local << v;
    return local;
}

static QString branchError(const QString &msg)
{
    if (msg.contains(QLatin1String("would be overwritten")))
        return QStringLiteral("Masz niezatwierdzone zmiany, które by przepadły — zatwierdź je albo odłóż (Git: odłóż zmiany)");
    if (msg.contains(QLatin1String("already exists")))
        return QStringLiteral("Gałąź o tej nazwie już istnieje");
    if (msg.contains(QLatin1String("is not a valid branch name")) || msg.contains(QLatin1String("not a valid branch")))
        return QStringLiteral("Niepoprawna nazwa gałęzi (bez spacji i znaków ~^:?*[\\)");
    if (msg.contains(QLatin1String("not fully merged")))
        return QStringLiteral("Gałąź ma zmiany niepołączone z bieżącą — najpierw ją połącz");
    if (msg.contains(QLatin1String("CONFLICT")) || msg.contains(QLatin1String("Automatic merge failed")))
        return QStringLiteral("Konflikty przy łączeniu — popraw pliki oznaczone „C” i zatwierdź");
    if (msg.contains(QLatin1String("No local changes to save")))
        return QStringLiteral("Nie ma zmian do odłożenia");
    if (msg.contains(QLatin1String("No stash entries")))
        return QStringLiteral("Nie ma odłożonych zmian");
    return msg.section(QLatin1Char('\n'), 0, 1).left(300);
}

void Project::checkout(const QString &name, bool remote)
{
    // Zdalna „origin/funkcja” — lokalna „funkcja” śledząca zdalną (git switch zgaduje)
    const QString local = remote ? name.section(QLatin1Char('/'), 1) : name;
    runGit(QStringLiteral("checkout"), {QStringLiteral("switch"), local}, {}, [this, local](bool ok, const QString &msg) {
        m_tree->refresh();
        refreshFiles();
        Q_EMIT gitDone(QStringLiteral("checkout"), ok, ok ? QStringLiteral("Gałąź: ") + local : branchError(msg));
    });
}

void Project::createBranch(const QString &name)
{
    const QString clean = name.trimmed().replace(QLatin1Char(' '), QLatin1Char('-'));
    runGit(QStringLiteral("branch"), {QStringLiteral("switch"), QStringLiteral("-c"), clean}, {}, [this, clean](bool ok, const QString &msg) {
        Q_EMIT gitDone(QStringLiteral("branch"), ok, ok ? QStringLiteral("Nowa gałąź: ") + clean : branchError(msg));
    });
}

void Project::mergeBranch(const QString &name)
{
    runGit(QStringLiteral("merge"), {QStringLiteral("merge"), QStringLiteral("--no-edit"), name}, {}, [this, name](bool ok, const QString &msg) {
        m_tree->refresh();
        Q_EMIT gitDone(QStringLiteral("merge"), ok, ok ? (msg.contains(QLatin1String("Already up to date")) ? QStringLiteral("Nic do połączenia — gałąź jest aktualna")
                                                                                                          : QStringLiteral("Połączono „") + name + QStringLiteral("”"))
                                                   : branchError(msg));
    });
}

void Project::deleteBranch(const QString &name)
{
    runGit(QStringLiteral("deleteBranch"), {QStringLiteral("branch"), QStringLiteral("-d"), name}, {}, [this, name](bool ok, const QString &msg) {
        Q_EMIT gitDone(QStringLiteral("deleteBranch"), ok, ok ? QStringLiteral("Usunięto gałąź „") + name + QStringLiteral("”") : branchError(msg));
    });
}

void Project::stash(bool pop)
{
    const QStringList args = pop ? QStringList{QStringLiteral("stash"), QStringLiteral("pop")}
                                 : QStringList{QStringLiteral("stash"), QStringLiteral("push"), QStringLiteral("-u"), QStringLiteral("-m"), QStringLiteral("Aster Code")};
    runGit(QStringLiteral("stash"), args, {}, [this, pop](bool ok, const QString &msg) {
        m_tree->refresh();
        QString text = ok ? (pop ? QStringLiteral("Przywrócono odłożone zmiany") : QStringLiteral("Odłożono zmiany")) : branchError(msg);
        // „stash push” bez zmian kończy się sukcesem z komunikatem na wyjściu
        if (ok && msg.contains(QLatin1String("No local changes to save")))
            text = branchError(msg);
        Q_EMIT gitDone(QStringLiteral("stash"), ok, text);
    });
}

int Project::replaceInFile(const QString &path, const QString &query, bool matchCase, bool wholeWord, bool regex, const QString &replacement)
{
    // Plik spoza kart: zamiana na dysku z zachowaniem kodowania i końców wierszy
    const QVariantMap f = load(path);
    if (!f.value(QStringLiteral("ok")).toBool())
        return 0;
    QString text = f.value(QStringLiteral("text")).toString();
    const int n = replaceInText(text, searchRegex(query, matchCase, wholeWord, regex), replacement, regex);
    if (n && !save(path, text, f.value(QStringLiteral("encoding")).toString(), f.value(QStringLiteral("eol")).toString()))
        return 0;
    return n;
}

// ——— Lista plików, szybkie otwieranie, szukanie ———

QStringList Project::listFiles(const QString &root, bool git)
{
    QStringList out;
    if (git) {
        // Pliki śledzone i nowe, bez pomijanych przez .gitignore
        QProcess p;
        p.start(QStringLiteral("git"), {QStringLiteral("-C"), root, QStringLiteral("ls-files"), QStringLiteral("-co"),
                                        QStringLiteral("--exclude-standard"), QStringLiteral("-z")});
        if (p.waitForFinished(15000) && p.exitCode() == 0) {
            for (const QByteArray &f : p.readAllStandardOutput().split('\0'))
                if (!f.isEmpty())
                    out << QString::fromUtf8(f);
            out.removeDuplicates();
            // Usunięte z dysku, a jeszcze w indeksie
            out.erase(std::remove_if(out.begin(), out.end(), [&](const QString &f) { return !QFileInfo(root + QLatin1Char('/') + f).isFile(); }), out.end());
            return out;
        }
    }
    static const QSet<QString> skip{QStringLiteral(".git"), QStringLiteral("node_modules"), QStringLiteral("build"), QStringLiteral(".cache"),
                                    QStringLiteral("__pycache__"), QStringLiteral(".venv"), QStringLiteral("venv"), QStringLiteral("target"),
                                    QStringLiteral("dist"), QStringLiteral(".idea"), QStringLiteral(".vscode-test")};
    QStringList stack{QString()};
    while (!stack.isEmpty() && out.size() < 50000) {
        const QString rel = stack.takeLast();
        const QFileInfoList list = QDir(rel.isEmpty() ? root : root + QLatin1Char('/') + rel)
                                       .entryInfoList(QDir::AllEntries | QDir::NoDotAndDotDot | QDir::Hidden, QDir::Name);
        for (const QFileInfo &fi : list) {
            const QString r = rel.isEmpty() ? fi.fileName() : rel + QLatin1Char('/') + fi.fileName();
            if (fi.isDir()) {
                if (!skip.contains(fi.fileName()) && !fi.isSymLink())
                    stack << r;
            } else {
                out << r;
            }
        }
    }
    std::sort(out.begin(), out.end());
    return out;
}

void Project::refreshFiles()
{
    if (m_root.isEmpty() || m_filesThread)
        return;
    const QString root = m_root;
    const bool git = isGit();
    QThread *t = QThread::create([this, root, git] {
        QStringList files = listFiles(root, git);
        QMetaObject::invokeMethod(this, [this, root, files] {
            if (root != m_root)
                return;
            m_files = files;
            Q_EMIT filesReady();
        }, Qt::QueuedConnection);
    });
    m_filesThread = t;
    connect(t, &QThread::finished, t, &QObject::deleteLater);
    t->start();
}

QVariantList Project::quickOpen(const QString &query, int limit) const
{
    const QString q = query.trimmed().toLower();
    struct Hit { int score; int index; QList<int> pos; int nameFrom; };
    QVector<Hit> hits;
    QList<int> pos;
    for (int i = 0; i < m_files.size(); ++i) {
        const QString &f = m_files.at(i);
        const int nameFrom = int(f.lastIndexOf(QLatin1Char('/'))) + 1;
        if (q.isEmpty()) {
            if (hits.size() < limit)
                hits.append({0, i, {}, nameFrom});
            continue;
        }
        // Najpierw sama nazwa pliku (premia), potem cała ścieżka
        int s = fuzzy(f, nameFrom, q, &pos);
        if (s >= 0) {
            s += 40 - std::min(40, int(f.size() - nameFrom - q.size()));
            if (f.mid(nameFrom).startsWith(q, Qt::CaseInsensitive))
                s += 30;
        } else {
            s = fuzzy(f, 0, q, &pos);
        }
        if (s >= 0)
            hits.append({s * 100 - int(f.size()), i, pos, nameFrom});
    }
    std::stable_sort(hits.begin(), hits.end(), [](const Hit &a, const Hit &b) { return a.score > b.score; });
    QVariantList out;
    for (int k = 0; k < hits.size() && k < limit; ++k) {
        const Hit &h = hits.at(k);
        const QString &f = m_files.at(h.index);
        // Nazwa z wyróżnionymi literami (<b>); folder — osobno
        QString html;
        const QString name = f.mid(h.nameFrom);
        for (int c = 0; c < name.size(); ++c) {
            const QString ch = escapeHtml(QStringView(name).mid(c, 1));
            html += h.pos.contains(h.nameFrom + c) ? QStringLiteral("<b>") + ch + QStringLiteral("</b>") : ch;
        }
        out << QVariantMap{{QStringLiteral("path"), m_root + QLatin1Char('/') + f},
                           {QStringLiteral("rel"), f},
                           {QStringLiteral("name"), name},
                           {QStringLiteral("dir"), h.nameFrom > 0 ? f.left(h.nameFrom - 1) : QString()},
                           {QStringLiteral("html"), html}};
    }
    return out;
}

void Project::search(const QString &query, bool matchCase, bool wholeWord, bool regex, const QVariantMap &buffers)
{
    const int gen = m_searchGen->fetch_add(1) + 1;
    m_searchError.clear();
    if (query.isEmpty() || m_root.isEmpty()) {
        m_results.clear();
        m_resultCount = 0;
        m_truncated = false;
        m_searching = false;
        Q_EMIT resultsChanged();
        Q_EMIT searchingChanged();
        return;
    }
    const QRegularExpression re = searchRegex(query, matchCase, wholeWord, regex);
    if (!re.isValid()) {
        m_searchError = QStringLiteral("Błędne wyrażenie: ") + re.errorString();
        m_results.clear();
        m_resultCount = 0;
        Q_EMIT resultsChanged();
        return;
    }
    m_searching = true;
    Q_EMIT searchingChanged();
    const QString root = m_root;
    const bool git = isGit();
    auto token = m_searchGen;
    QHash<QString, QString> open;
    for (auto it = buffers.cbegin(); it != buffers.cend(); ++it)
        open.insert(it.key(), it.value().toString());
    QThread *t = QThread::create([this, root, git, re, gen, token, open] {
        const QStringList files = listFiles(root, git);
        QVariantList results;
        int total = 0;
        bool truncated = false;
        for (const QString &rel : files) {
            if (token->load() != gen)
                return;
            const QString full = root + QLatin1Char('/') + rel;
            QString text;
            if (open.contains(full)) {
                text = open.value(full);
            } else {
                QFile f(full);
                if (f.size() > SearchFileLimit || !f.open(QIODevice::ReadOnly))
                    continue;
                const QByteArray data = f.readAll();
                if (data.left(8192).contains('\0'))
                    continue;
                text = QString::fromUtf8(data);
            }
            QVariantList matches;
            int lineNo = 0;
            for (QStringView line : QStringView(text).split(QLatin1Char('\n'))) {
                if (line.endsWith(QLatin1Char('\r')))
                    line.chop(1);
                auto it = re.globalMatchView(line);
                while (it.hasNext()) {
                    const QRegularExpressionMatch m = it.next();
                    if (m.capturedLength() == 0)
                        continue;
                    const int col = int(m.capturedStart()), len = int(m.capturedLength());
                    // Fragment wiersza wokół trafienia: przed (najwyżej 40 znaków), trafienie, po
                    QStringView before = line.left(col);
                    int lead = 0;
                    while (lead < before.size() && before.at(lead).isSpace())
                        ++lead;
                    before = before.mid(lead);
                    QString b = before.size() > 40 ? QStringLiteral("…") + before.right(40).toString() : before.toString();
                    matches << QVariantMap{{QStringLiteral("line"), lineNo},
                                           {QStringLiteral("col"), col},
                                           {QStringLiteral("length"), len},
                                           {QStringLiteral("before"), b},
                                           {QStringLiteral("match"), line.mid(col, len).left(200).toString()},
                                           {QStringLiteral("after"), line.mid(col + len, 160).toString()}};
                    if (++total >= MatchLimit) {
                        truncated = true;
                        break;
                    }
                }
                if (truncated)
                    break;
                ++lineNo;
            }
            if (!matches.isEmpty()) {
                const int slash = int(rel.lastIndexOf(QLatin1Char('/')));
                results << QVariantMap{{QStringLiteral("path"), root + QLatin1Char('/') + rel},
                                       {QStringLiteral("rel"), rel},
                                       {QStringLiteral("name"), rel.mid(slash + 1)},
                                       {QStringLiteral("dir"), slash > 0 ? rel.left(slash) : QString()},
                                       {QStringLiteral("matches"), matches}};
            }
            if (truncated)
                break;
        }
        QMetaObject::invokeMethod(this, [this, results, total, truncated, gen, token] {
            if (token->load() != gen)
                return;
            m_results = results;
            m_resultCount = total;
            m_truncated = truncated;
            m_searching = false;
            Q_EMIT resultsChanged();
            Q_EMIT searchingChanged();
        }, Qt::QueuedConnection);
    });
    // Poprzednie szukanie kończy się samo (inny numer); czekamy tylko przy zamykaniu programu
    m_searchThread = t;
    connect(t, &QThread::finished, t, &QObject::deleteLater);
    t->start();
}

void Project::cancelSearch()
{
    m_searchGen->fetch_add(1);
    if (m_searching) {
        m_searching = false;
        Q_EMIT searchingChanged();
    }
}
