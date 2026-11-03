#include "project.h"

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
    m_branch.clear();
    m_head.clear();
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

// ——— Git ———

QString Project::gitRelative(const QString &path) const
{
    return QDir(m_gitTop).relativeFilePath(path);
}

void Project::refreshGit()
{
    if (m_gitTop.isEmpty())
        return;
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
    QString branch, head;
    int ahead = 0, behind = 0;
    QHash<QString, QString> files, dirs;
    QSet<QString> ignored;
    QVariantList changes;
    const auto add = [&](const QString &rel, const QString &status, bool staged) {
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
                               {QStringLiteral("staged"), staged},
                               {QStringLiteral("isDir"), isDir}};
    };
    const auto letter = [](char x, char y) {
        const char c = y != '.' ? y : x;
        switch (c) {
        case 'A': case 'C': return QStringLiteral("A");
        case 'D': return QStringLiteral("D");
        case 'R': return QStringLiteral("R");
        default: return QStringLiteral("M");
        }
    };
    for (int i = 0; i < parts.size(); ++i) {
        const QByteArray &e = parts.at(i);
        if (e.isEmpty())
            continue;
        if (e.startsWith("# branch.oid ")) {
            head = QString::fromLatin1(e.mid(13));
        } else if (e.startsWith("# branch.head ")) {
            branch = QString::fromUtf8(e.mid(14));
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
            add(rel, e.startsWith("u ") ? QStringLiteral("C") : letter(x, y), x != '.');
            if (e.startsWith("2 "))
                ++i;                         // następne pole to stara nazwa
        } else if (e.startsWith("? ")) {
            add(QString::fromUtf8(e.mid(2)), QStringLiteral("U"), false);
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
    if (branch != m_branch || head != m_head || ahead != m_ahead || behind != m_behind || changes != m_changes) {
        m_branch = branch;
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

void Project::search(const QString &query, bool matchCase, bool wholeWord, bool regex)
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
    QString pattern = regex ? query : QRegularExpression::escape(query);
    if (wholeWord)
        pattern = QStringLiteral("\\b(?:") + pattern + QStringLiteral(")\\b");
    QRegularExpression re(pattern, (matchCase ? QRegularExpression::NoPatternOption : QRegularExpression::CaseInsensitiveOption)
                                       | QRegularExpression::UseUnicodePropertiesOption);
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
    QThread *t = QThread::create([this, root, git, re, gen, token] {
        const QStringList files = listFiles(root, git);
        QVariantList results;
        int total = 0;
        bool truncated = false;
        for (const QString &rel : files) {
            if (token->load() != gen)
                return;
            QFile f(root + QLatin1Char('/') + rel);
            if (f.size() > SearchFileLimit || !f.open(QIODevice::ReadOnly))
                continue;
            const QByteArray data = f.readAll();
            if (data.left(8192).contains('\0'))
                continue;
            const QString text = QString::fromUtf8(data);
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
