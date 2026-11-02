#include "editor.h"

#include <QDesktopServices>
#include <QDir>
#include <QFile>
#include <QFileInfo>
#include <QJsonArray>
#include <QJsonDocument>
#include <QJsonObject>
#include <QLocale>
#include <QQuickTextDocument>
#include <QRegularExpression>
#include <QTextBlock>
#include <QTextDocument>
#include <QSaveFile>
#include <QStandardPaths>
#include <QStringDecoder>
#include <QStringEncoder>
#include <QUrl>

namespace {

QString sessionDir()
{
    return QStandardPaths::writableLocation(QStandardPaths::GenericDataLocation) + QStringLiteral("/aster/editor");
}

} // namespace

Editor::Editor(QObject *parent)
    : QObject(parent)
{
    connect(&m_watcher, &QFileSystemWatcher::fileChanged, this, [this](const QString &path) {
        // Zapis przez podmianę pliku (wiele programów tak robi) zdejmuje obserwację — dodaj ponownie
        if (QFileInfo::exists(path) && !m_watcher.files().contains(path))
            m_watcher.addPath(path);
        Q_EMIT fileChanged(path);
    });
}

QString Editor::toPath(const QString &pathOrUrl) const
{
    const QUrl url(pathOrUrl);
    return QFileInfo(url.isLocalFile() ? url.toLocalFile() : pathOrUrl).absoluteFilePath();
}

QString Editor::fileName(const QString &path) const
{
    return QFileInfo(path).fileName();
}

QString Editor::folder(const QString &path) const
{
    return QFileInfo(path).absolutePath();
}

bool Editor::exists(const QString &path) const
{
    return QFileInfo::exists(path);
}

QString Editor::documentsDir() const
{
    return QStandardPaths::writableLocation(QStandardPaths::DocumentsLocation);
}

QString Editor::number(int n) const
{
    return QLocale(QLocale::Polish).toString(n);
}

QPoint Editor::lineColumn(QQuickTextDocument *doc, int position) const
{
    if (!doc || !doc->textDocument())
        return {};
    const QTextBlock b = doc->textDocument()->findBlock(position);
    return {position - b.position(), b.blockNumber()};
}

int Editor::positionOfLine(QQuickTextDocument *doc, int line) const
{
    if (!doc || !doc->textDocument())
        return 0;
    QTextDocument *d = doc->textDocument();
    const QTextBlock b = d->findBlockByNumber(std::clamp(line, 0, d->blockCount() - 1));
    return b.isValid() ? b.position() : 0;
}

QString Editor::suggestedName(const QString &text) const
{
    // Jak w Notatniku: pierwsza linia tekstu jako nazwa pliku (bez znaków, których nie lubią systemy plików)
    QString first = text.section(QLatin1Char('\n'), 0, 0).trimmed().left(40);
    first.remove(QRegularExpression(QStringLiteral("[/\\\\:*?\"<>|]")));
    first = first.trimmed();
    return (first.isEmpty() ? QStringLiteral("Bez tytułu") : first) + QStringLiteral(".txt");
}

QVariantMap Editor::load(const QString &pathOrUrl) const
{
    const QString path = toPath(pathOrUrl);
    QFile f(path);
    const QFileInfo fi(path);
    if (fi.size() > 64LL * 1024 * 1024)
        return {{QStringLiteral("ok"), false}, {QStringLiteral("error"), QStringLiteral("Plik jest za duży dla Edytora tekstu (ponad 64 MB)")}};
    if (!f.open(QIODevice::ReadOnly))
        return {{QStringLiteral("ok"), false}, {QStringLiteral("error"), QStringLiteral("Nie można otworzyć „%1”").arg(fi.fileName())}};
    const QByteArray data = f.readAll();
    if (data.left(8192).contains('\0') && !data.startsWith("\xFF\xFE") && !data.startsWith("\xFE\xFF"))
        return {{QStringLiteral("ok"), false}, {QStringLiteral("error"), QStringLiteral("„%1” nie jest plikiem tekstowym").arg(fi.fileName())}};

    // Kodowanie: znacznik BOM, potem UTF-8; pliki z polskiego Windows (Notatnik sprzed lat) to zwykle Windows-1250
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

bool Editor::save(const QString &path, const QString &text, const QString &encoding, const QString &eol)
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
    // Zapis atomowy: przy błędzie (pełny dysk) stary plik zostaje nienaruszony
    QSaveFile f(path);
    if (!f.open(QIODevice::WriteOnly) || f.write(data) != data.size() || !f.commit()) {
        Q_EMIT message(QStringLiteral("Nie udało się zapisać „%1”").arg(QFileInfo(path).fileName()));
        return false;
    }
    return true;
}

void Editor::watch(const QStringList &paths)
{
    const QStringList old = m_watcher.files();
    for (const QString &p : old)
        if (!paths.contains(p))
            m_watcher.removePath(p);
    for (const QString &p : paths)
        if (!p.isEmpty() && !old.contains(p) && QFileInfo::exists(p))
            m_watcher.addPath(p);
}

void Editor::showInFolder(const QString &path) const
{
    QDesktopServices::openUrl(QUrl::fromLocalFile(QFileInfo(path).absolutePath()));
}

void Editor::openFiles(const QStringList &files)
{
    Q_EMIT openRequested(files);
}

void Editor::saveSession(const QVariantList &tabs, int current)
{
    // Treść niezapisanych kart trafia do osobnych plików; w session.json — lista kart
    const QString dir = sessionDir();
    QDir().mkpath(dir);
    QJsonArray list;
    QStringList keep;
    int n = 0;
    for (const QVariant &v : tabs) {
        QVariantMap t = v.toMap();
        QJsonObject o;
        o.insert(QStringLiteral("path"), t.value(QStringLiteral("path")).toString());
        o.insert(QStringLiteral("cursor"), t.value(QStringLiteral("cursor")).toInt());
        o.insert(QStringLiteral("encoding"), t.value(QStringLiteral("encoding")).toString());
        o.insert(QStringLiteral("eol"), t.value(QStringLiteral("eol")).toString());
        o.insert(QStringLiteral("title"), t.value(QStringLiteral("title")).toString());
        if (t.value(QStringLiteral("modified")).toBool()) {
            const QString file = QStringLiteral("tab-%1.txt").arg(n++);
            QSaveFile f(dir + QLatin1Char('/') + file);
            if (f.open(QIODevice::WriteOnly)) {
                f.write(t.value(QStringLiteral("text")).toString().toUtf8());
                f.commit();
            }
            o.insert(QStringLiteral("draft"), file);
            keep << file;
        }
        list.append(o);
    }
    for (const QString &f : QDir(dir).entryList({QStringLiteral("tab-*.txt")}, QDir::Files))
        if (!keep.contains(f))
            QFile::remove(dir + QLatin1Char('/') + f);
    QJsonObject root{{QStringLiteral("tabs"), list}, {QStringLiteral("current"), current}};
    QSaveFile f(dir + QStringLiteral("/session.json"));
    if (f.open(QIODevice::WriteOnly)) {
        f.write(QJsonDocument(root).toJson());
        f.commit();
    }
}

QVariantMap Editor::loadSession() const
{
    const QString dir = sessionDir();
    QFile f(dir + QStringLiteral("/session.json"));
    if (!f.open(QIODevice::ReadOnly))
        return {};
    const QJsonObject root = QJsonDocument::fromJson(f.readAll()).object();
    QVariantList tabs;
    for (const QJsonValue &v : root.value(QStringLiteral("tabs")).toArray()) {
        QVariantMap t = v.toObject().toVariantMap();
        const QString draft = t.value(QStringLiteral("draft")).toString();
        if (!draft.isEmpty()) {
            QFile d(dir + QLatin1Char('/') + draft);
            if (d.open(QIODevice::ReadOnly))
                t.insert(QStringLiteral("text"), QString::fromUtf8(d.readAll()));
            t.insert(QStringLiteral("modified"), true);
        } else if (!t.value(QStringLiteral("path")).toString().isEmpty()) {
            const QVariantMap loaded = load(t.value(QStringLiteral("path")).toString());
            if (!loaded.value(QStringLiteral("ok")).toBool())
                continue;                       // plik zniknął — karta też
            t.insert(QStringLiteral("text"), loaded.value(QStringLiteral("text")));
            t.insert(QStringLiteral("encoding"), loaded.value(QStringLiteral("encoding")));
            t.insert(QStringLiteral("eol"), loaded.value(QStringLiteral("eol")));
            t.insert(QStringLiteral("modified"), false);
        } else {
            continue;                           // pusta karta bez treści
        }
        tabs << t;
    }
    return {{QStringLiteral("tabs"), tabs}, {QStringLiteral("current"), root.value(QStringLiteral("current")).toInt()}};
}
