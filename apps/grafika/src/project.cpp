#include "project.h"

#include <QBuffer>
#include <QClipboard>
#include <QCryptographicHash>
#include <QDateTime>
#include <QDir>
#include <QFile>
#include <QFileInfo>
#include <QGuiApplication>
#include <QImageReader>
#include <QJsonDocument>
#include <QMimeData>
#include <QPainter>
#include <QPdfWriter>
#include <QRandomGenerator>
#include <QSaveFile>
#include <QFontDatabase>
#include <QStandardPaths>
#include <QSvgRenderer>
#include "online.h"
#include <QUrl>
#include <private/qzipreader_p.h>
#include <private/qzipwriter_p.h>

static const char *ClipboardMime = "application/x-aster-grafika";
static void regroup(QVariantMap &el, QHash<QString, QString> &groups);

static QString projectsDir()
{
    return QStandardPaths::writableLocation(QStandardPaths::DocumentsLocation) + QStringLiteral("/Grafiki");
}

static qreal num(const QVariantMap &m, const char *key, qreal fallback = 0)
{
    const QVariant v = m.value(QLatin1String(key));
    return v.isValid() && !v.isNull() ? v.toDouble() : fallback;
}

Project::Project(QObject *parent)
    : QAbstractListModel(parent)
{
    create(1080, 1080, QStringLiteral("Bez tytułu"));
}

int Project::rowCount(const QModelIndex &parent) const
{
    return parent.isValid() ? 0 : m_elements.size();
}

QVariant Project::data(const QModelIndex &index, int role) const
{
    if (!index.isValid() || index.row() >= m_elements.size())
        return {};
    const QVariantMap el = m_elements.at(index.row()).toMap();
    if (role == ElementRole)
        return el;
    if (role == IdRole)
        return el.value(QStringLiteral("id"));
    return {};
}

QHash<int, QByteArray> Project::roleNames() const
{
    return {{ElementRole, "element"}, {IdRole, "uid"}};
}

// ——— Stan i historia ———

QVariantMap Project::document() const
{
    QVariantMap doc;
    doc[QStringLiteral("format")] = QStringLiteral("aster-grafika");
    doc[QStringLiteral("version")] = 1;
    doc[QStringLiteral("name")] = m_name;
    doc[QStringLiteral("width")] = m_width;
    doc[QStringLiteral("height")] = m_height;
    if (!m_print.isEmpty())
        doc[QStringLiteral("print")] = m_print;
    doc[QStringLiteral("background")] = m_background;
    doc[QStringLiteral("elements")] = m_elements;
    doc[QStringLiteral("pages")] = pages();
    doc[QStringLiteral("page")] = m_page;
    if (!m_guides.value(QStringLiteral("x")).toList().isEmpty() || !m_guides.value(QStringLiteral("y")).toList().isEmpty())
        doc[QStringLiteral("guides")] = m_guides;
    return doc;
}

QVariantList Project::pages() const
{
    QVariantList out = m_pages;
    if (m_page >= 0 && m_page < out.size())
        out[m_page] = QVariantMap{{QStringLiteral("background"), m_background}, {QStringLiteral("elements"), m_elements}};
    return out;
}

void Project::storePage()
{
    if (m_page >= 0 && m_page < m_pages.size())
        m_pages[m_page] = QVariantMap{{QStringLiteral("background"), m_background}, {QStringLiteral("elements"), m_elements}};
}

void Project::showPage(int page)
{
    m_page = qBound(0, page, int(m_pages.size()) - 1);
    const QVariantMap p = m_pages.value(m_page).toMap();
    beginResetModel();
    m_background = p.value(QStringLiteral("background")).toMap();
    if (m_background.isEmpty())
        m_background = {{QStringLiteral("type"), QStringLiteral("color")}, {QStringLiteral("color"), QStringLiteral("#ffffff")}};
    m_elements = p.value(QStringLiteral("elements")).toList();
    endResetModel();
    Q_EMIT backgroundChanged();
    Q_EMIT countChanged();
    Q_EMIT colorsChanged();
    Q_EMIT pagesChanged();
    Q_EMIT reset();
}

QVariantMap Project::pageDocument(int page) const
{
    const QVariantMap p = page == m_page ? QVariantMap{{QStringLiteral("background"), m_background}, {QStringLiteral("elements"), m_elements}}
                                         : m_pages.value(page).toMap();
    return {{QStringLiteral("width"), m_width}, {QStringLiteral("height"), m_height},
            {QStringLiteral("background"), p.value(QStringLiteral("background"))}, {QStringLiteral("elements"), p.value(QStringLiteral("elements"))}};
}

// Przejście na inną stronę nie jest krokiem cofania — cofnięcie wraca na stronę, na której była zmiana
void Project::setGuides(const QVariantMap &guides, bool commitNow)
{
    if (guides == m_guides)
        return;
    m_guides = guides;
    Q_EMIT guidesChanged();
    if (commitNow)
        commit();
}

void Project::goToPage(int page)
{
    if (page == m_page || page < 0 || page >= m_pages.size())
        return;
    commit();
    storePage();
    showPage(page);
    m_last = snapshot();
}

void Project::addPage()
{
    commit();
    storePage();
    m_pages.insert(m_page + 1, QVariantMap{{QStringLiteral("background"), m_background}, {QStringLiteral("elements"), QVariantList()}});
    showPage(m_page + 1);
    commit();
}

void Project::duplicatePage(int page)
{
    commit();
    storePage();
    QVariantMap p = m_pages.value(page).toMap();
    QVariantList elements;
    QHash<QString, QString> groups;
    for (const QVariant &v : p.value(QStringLiteral("elements")).toList()) {
        QVariantMap el = v.toMap();
        regroup(el, groups);
        el[QStringLiteral("id")] = newId();
        elements.append(el);
    }
    p[QStringLiteral("elements")] = elements;
    m_pages.insert(page + 1, p);
    showPage(page + 1);
    commit();
}

void Project::removePage(int page)
{
    if (m_pages.size() < 2 || page < 0 || page >= m_pages.size())
        return;
    commit();
    storePage();
    m_pages.removeAt(page);
    showPage(qMin(page, int(m_pages.size()) - 1));
    commit();
}

void Project::movePage(int from, int to)
{
    to = qBound(0, to, int(m_pages.size()) - 1);
    if (from == to || from < 0 || from >= m_pages.size())
        return;
    commit();
    storePage();
    m_pages.move(from, to);
    // Bieżąca strona idzie razem z przesuwaną albo przesuwa się o jedno miejsce
    if (m_page == from)
        m_page = to;
    else if (from < m_page && to >= m_page)
        --m_page;
    else if (from > m_page && to <= m_page)
        ++m_page;
    Q_EMIT pagesChanged();
    commit();
}

QByteArray Project::snapshot() const
{
    QVariantMap doc = document();
    doc.remove(QStringLiteral("name"));
    return QJsonDocument::fromVariant(doc).toJson(QJsonDocument::Compact);
}

QString Project::newId()
{
    return QStringLiteral("e%1").arg(m_nextId++);
}

// Uzupełnia brakujące pola i liczy wysokość tekstu
QVariantMap Project::prepared(QVariantMap el) const
{
    const QString type = el.value(QStringLiteral("type")).toString();
    for (const char *k : {"x", "y"})
        if (!el.contains(QLatin1String(k)))
            el[QLatin1String(k)] = 0.0;
    if (!el.contains(QStringLiteral("w")))
        el[QStringLiteral("w")] = 200.0;
    if (!el.contains(QStringLiteral("h")))
        el[QStringLiteral("h")] = 200.0;
    if (type == QLatin1String("text"))
        el[QStringLiteral("h")] = std::ceil(Art::textHeight(el));
    return el;
}

void Project::load(const QVariantMap &doc)
{
    beginResetModel();
    m_width = qMax(16.0, num(doc, "width", 1080));
    m_height = qMax(16.0, num(doc, "height", 1080));
    m_print = doc.value(QStringLiteral("print")).toMap();
    const QVariantMap guides = doc.value(QStringLiteral("guides")).toMap();
    if (guides != m_guides) {
        m_guides = guides;
        Q_EMIT guidesChanged();
    }
    // Stary zapis (jedna strona) — background i elements na wierzchu
    m_pages = doc.value(QStringLiteral("pages")).toList();
    if (m_pages.isEmpty())
        m_pages = {QVariantMap{{QStringLiteral("background"), doc.value(QStringLiteral("background"))}, {QStringLiteral("elements"), doc.value(QStringLiteral("elements"))}}};
    for (const QVariant &pv : std::as_const(m_pages))
        for (const QVariant &v : pv.toMap().value(QStringLiteral("elements")).toList()) {
            const QString id = v.toMap().value(QStringLiteral("id")).toString();
            if (id.startsWith(QLatin1Char('e')))
                m_nextId = qMax(m_nextId, id.mid(1).toInt() + 1);
        }
    for (QVariant &pv : m_pages) {
        QVariantMap p = pv.toMap();
        QVariantList elements = p.value(QStringLiteral("elements")).toList();
        for (QVariant &v : elements) {
            QVariantMap el = v.toMap();
            if (el.value(QStringLiteral("id")).toString().isEmpty())
                el[QStringLiteral("id")] = newId();
            v = prepared(el);
        }
        p[QStringLiteral("elements")] = elements;
        pv = p;
    }
    endResetModel();
    Q_EMIT pageChanged();
    showPage(doc.value(QStringLiteral("page")).toInt());
}

void Project::restore(const QByteArray &json)
{
    load(QJsonDocument::fromJson(json).toVariant().toMap());
    m_last = snapshot();
}

void Project::commit()
{
    const QByteArray now = snapshot();
    if (now == m_last)
        return;
    m_undo.append(m_last);
    if (m_undo.size() > 200)
        m_undo.removeFirst();
    m_redo.clear();
    m_last = now;
    setModified(true);
    Q_EMIT historyChanged();
    Q_EMIT colorsChanged();
    Q_EMIT changed();
}

void Project::undo()
{
    commit();
    if (m_undo.isEmpty())
        return;
    m_redo.append(m_last);
    restore(m_undo.takeLast());
    setModified(true);
    Q_EMIT historyChanged();
    Q_EMIT changed();
}

void Project::redo()
{
    commit();
    if (m_redo.isEmpty())
        return;
    m_undo.append(m_last);
    restore(m_redo.takeLast());
    setModified(true);
    Q_EMIT historyChanged();
    Q_EMIT changed();
}

void Project::setModified(bool on)
{
    if (m_modified == on)
        return;
    m_modified = on;
    Q_EMIT modifiedChanged();
}

void Project::setPath(const QString &path)
{
    if (m_path == path)
        return;
    m_path = path;
    Q_EMIT pathChanged();
}

void Project::setName(const QString &name)
{
    const QString n = name.trimmed().isEmpty() ? QStringLiteral("Bez tytułu") : name.trimmed();
    if (n == m_name)
        return;
    m_name = n;
    // Plik w folderze Grafiki nazywa się jak projekt
    if (!m_path.isEmpty() && QFileInfo(m_path).absolutePath() == projectsDir()) {
        const QString target = uniquePath(projectsDir(), n, QStringLiteral("grafika"));
        if (QFile::rename(m_path, target))
            setPath(target);
    }
    Q_EMIT nameChanged();
    if (!m_path.isEmpty()) {
        setModified(true);
        Q_EMIT changed();
    }
}

// ——— Projekt ———

void Project::create(qreal width, qreal height, const QString &name, const QVariantMap &print)
{
    m_assets.clear();
    m_undo.clear();
    m_redo.clear();
    // print — rozmiar do druku w mm (A4, plakat), dla PDF
    QVariantMap doc{{QStringLiteral("width"), width}, {QStringLiteral("height"), height}, {QStringLiteral("print"), print}};
    load(doc);
    m_last = snapshot();
    m_name = name;
    setPath(QString());
    setModified(false);
    Q_EMIT nameChanged();
    Q_EMIT historyChanged();
    Q_EMIT imagesChanged();
}

static QVariantMap readJson(const QString &file)
{
    QFile f(file);
    if (!f.open(QIODevice::ReadOnly))
        return {};
    return QJsonDocument::fromJson(f.readAll()).toVariant().toMap();
}

bool Project::openTemplate(const QString &file)
{
    const QVariantMap doc = readJson(file);
    if (doc.isEmpty())
        return false;
    create(num(doc, "width", 1080), num(doc, "height", 1080), doc.value(QStringLiteral("name")).toString());
    load(doc);
    m_last = snapshot();
    return true;
}

bool Project::applyTemplate(const QString &file)
{
    const QVariantMap doc = readJson(file);
    if (doc.isEmpty())
        return false;
    // Szablon zastępuje tylko bieżącą stronę (i ustawia rozmiar stron) — pozostałe strony zostają
    commit();
    storePage();
    QVariantList elements;
    for (const QVariant &v : doc.value(QStringLiteral("elements")).toList()) {
        QVariantMap el = v.toMap();
        el[QStringLiteral("id")] = newId();
        elements.append(prepared(el));
    }
    QVariantMap bg = doc.value(QStringLiteral("background")).toMap();
    m_pages[m_page] = QVariantMap{{QStringLiteral("background"), bg}, {QStringLiteral("elements"), elements}};
    // Szablon wielostronicowy (karuzela, wizytówka): pozostałe jego strony wchodzą za bieżącą
    const QVariantList more = doc.value(QStringLiteral("pages")).toList();
    for (int i = 1; i < more.size(); ++i) {
        QVariantMap p = more.at(i).toMap();
        QVariantList els;
        for (const QVariant &v : p.value(QStringLiteral("elements")).toList()) {
            QVariantMap el = v.toMap();
            el[QStringLiteral("id")] = newId();
            els.append(prepared(el));
        }
        p[QStringLiteral("elements")] = els;
        m_pages.insert(m_page + i, p);
    }
    m_width = qMax(16.0, num(doc, "width", m_width));
    m_height = qMax(16.0, num(doc, "height", m_height));
    m_print = doc.value(QStringLiteral("print")).toMap();
    Q_EMIT pageChanged();
    showPage(m_page);
    commit();
    return true;
}

bool Project::open(const QString &fileOrUrl)
{
    const QString path = fileOrUrl.startsWith(QLatin1String("file:")) ? QUrl(fileOrUrl).toLocalFile() : fileOrUrl;
    QZipReader zip(path);
    if (!zip.isReadable()) {
        Q_EMIT error(QStringLiteral("Nie udało się otworzyć projektu."));
        return false;
    }
    const QVariantMap doc = QJsonDocument::fromJson(zip.fileData(QStringLiteral("project.json"))).toVariant().toMap();
    if (doc.isEmpty()) {
        Q_EMIT error(QStringLiteral("To nie jest projekt graficzny albo plik jest uszkodzony."));
        return false;
    }
    create(1080, 1080, QString());
    for (const QZipReader::FileInfo &fi : zip.fileInfoList()) {
        if (!fi.isFile || !fi.filePath.startsWith(QLatin1String("images/")))
            continue;
        const QString file = fi.filePath.mid(7);
        Asset a;
        a.data = zip.fileData(fi.filePath);
        a.ext = QFileInfo(file).suffix();
        if (decode(a))
            m_assets.insert(file, a);
    }
    // Czcionki pobrane na innym komputerze, których tu nie ma
    for (const QZipReader::FileInfo &fi : zip.fileInfoList()) {
        if (!fi.isFile || !fi.filePath.startsWith(QLatin1String("fonts/")))
            continue;
        const QString file = QFileInfo(fi.filePath).fileName();
        const QString family = QFileInfo(fi.filePath).path().section(QLatin1Char('/'), 1);
        if (m_fonts.contains(file) || !Online::fontFiles(family).isEmpty())
            continue;
        const int id = QFontDatabase::addApplicationFontFromData(zip.fileData(fi.filePath));
        if (id >= 0)
            m_fonts.insert(file, id);
    }
    load(doc);
    m_last = snapshot();
    m_name = doc.value(QStringLiteral("name")).toString();
    if (m_name.isEmpty())
        m_name = QFileInfo(path).completeBaseName();
    setPath(QFileInfo(path).absoluteFilePath());
    Q_EMIT nameChanged();
    Q_EMIT imagesChanged();
    return true;
}

QString Project::uniquePath(const QString &dir, const QString &base, const QString &ext) const
{
    QString clean = base;
    for (const QChar c : QStringLiteral("/\\:*?\"<>|"))
        clean.replace(c, QLatin1Char('-'));
    clean = clean.trimmed();
    if (clean.isEmpty())
        clean = QStringLiteral("Bez tytułu");
    QString path = dir + QLatin1Char('/') + clean + QLatin1Char('.') + ext;
    for (int i = 2; QFileInfo::exists(path) && path != m_path; ++i)
        path = dir + QLatin1Char('/') + clean + QStringLiteral(" (%1).").arg(i) + ext;
    return path;
}

bool Project::save()
{
    commit();
    if (m_path.isEmpty()) {
        QDir().mkpath(projectsDir());
        setPath(uniquePath(projectsDir(), m_name, QStringLiteral("grafika")));
    }
    // ZIP najpierw w pamięci (QZipWriter zamyka urządzenie, a QSaveFile na to nie pozwala), potem zapis „na raz”
    const QVariantMap doc = document();
    QByteArray bytes;
    {
        QBuffer out(&bytes);
        out.open(QIODevice::WriteOnly);
        QZipWriter zip(&out);
        zip.setCompressionPolicy(QZipWriter::AutoCompress);
        zip.addFile(QStringLiteral("project.json"), QJsonDocument::fromVariant(doc).toJson(QJsonDocument::Indented));
        // Tylko zdjęcia, które są jeszcze na stronie
        const QByteArray json = m_last;
        for (auto it = m_assets.cbegin(); it != m_assets.cend(); ++it)
            if (json.contains(it.key().toUtf8()))
                zip.addFile(QStringLiteral("images/") + it.key(), it->data);
        // Pobrane czcionki jadą razem z projektem — na innym komputerze tekst wygląda tak samo
        QSet<QString> families;
        for (const QVariant &pv : pages())
            for (const QVariant &v : pv.toMap().value(QStringLiteral("elements")).toList())
                families.insert(v.toMap().value(QStringLiteral("font")).toString());
        for (const QString &family : std::as_const(families)) {
            for (const QString &path : Online::fontFiles(family)) {
                QFile f(path);
                if (f.open(QIODevice::ReadOnly))
                    zip.addFile(QStringLiteral("fonts/%1/%2").arg(family, QFileInfo(path).fileName()), f.readAll());
            }
        }
        const qreal k = 512 / qMax(m_width, m_height);
        QByteArray thumb;
        QBuffer buf(&thumb);
        buf.open(QIODevice::WriteOnly);
        Art::renderPage(pageDocument(0), QSize(qMax(1, qRound(m_width * k)), qMax(1, qRound(m_height * k))), this).save(&buf, "PNG");
        zip.addFile(QStringLiteral("thumbnail.png"), thumb);
        zip.close();
    }
    QSaveFile file(m_path);
    if (!file.open(QIODevice::WriteOnly) || file.write(bytes) != bytes.size()) {
        Q_EMIT error(QStringLiteral("Nie udało się zapisać projektu."));
        return false;
    }
    if (!file.commit()) {
        Q_EMIT error(QStringLiteral("Nie udało się zapisać projektu."));
        return false;
    }
    setModified(false);
    return true;
}

QVariantMap Project::scaled(const QVariantMap &el, qreal k, qreal ox, qreal oy) const
{
    QVariantMap out = el;
    out[QStringLiteral("x")] = std::round((ox + (num(el, "x") - ox) * k) * 10) / 10;
    out[QStringLiteral("y")] = std::round((oy + (num(el, "y") - oy) * k) * 10) / 10;
    for (const char *key : {"w", "h", "size", "strokeWidth", "radius", "shadowBlur", "shadowDist"})
        if (el.contains(QLatin1String(key)))
            out[QLatin1String(key)] = std::round(num(el, key) * k * 10) / 10;
    return out;
}

void Project::setPageSize(qreal width, qreal height, bool fit)
{
    commit();
    width = qMax(16.0, width);
    height = qMax(16.0, height);
    // Prowadnice zostają w tym samym miejscu względem strony
    if (!m_guides.isEmpty()) {
        QVariantMap g;
        for (const auto &[axis, k] : {std::pair{QStringLiteral("x"), width / m_width}, std::pair{QStringLiteral("y"), height / m_height}}) {
            QVariantList list;
            for (const QVariant &v : m_guides.value(axis).toList())
                list.append(std::round(v.toDouble() * k * 10) / 10);
            g[axis] = list;
        }
        m_guides = g;
        Q_EMIT guidesChanged();
    }
    // Dopasowanie: treść skalowana do mniejszego z boków i wyśrodkowana; tło wypełnia nową stronę samo
    if (fit) {
        const qreal k = qMin(width / m_width, height / m_height);
        const qreal dx = (width - m_width * k) / 2, dy = (height - m_height * k) / 2;
        storePage();
        for (QVariant &pv : m_pages) {
            QVariantMap p = pv.toMap();
            QVariantList elements = p.value(QStringLiteral("elements")).toList();
            for (QVariant &v : elements) {
                QVariantMap el = scaled(v.toMap(), k, 0, 0);
                el[QStringLiteral("x")] = std::round((num(el, "x") + dx) * 10) / 10;
                el[QStringLiteral("y")] = std::round((num(el, "y") + dy) * 10) / 10;
                v = prepared(el);
            }
            p[QStringLiteral("elements")] = elements;
            pv = p;
        }
        m_width = width;
        m_height = height;
        showPage(m_page);
    }
    m_width = width;
    m_height = height;
    m_print.clear();
    Q_EMIT pageChanged();
    commit();
}

// ——— Elementy ———

int Project::indexOf(const QString &id) const
{
    for (int i = 0; i < m_elements.size(); ++i)
        if (m_elements.at(i).toMap().value(QStringLiteral("id")).toString() == id)
            return i;
    return -1;
}

QString Project::idAt(int index) const
{
    return index >= 0 && index < m_elements.size() ? m_elements.at(index).toMap().value(QStringLiteral("id")).toString() : QString();
}

QVariantMap Project::get(const QString &id) const
{
    const int i = indexOf(id);
    return i < 0 ? QVariantMap() : m_elements.at(i).toMap();
}

QString Project::add(const QVariantMap &element)
{
    const QString id = insert(element);
    commit();
    return id;
}

QString Project::insert(const QVariantMap &element)
{
    QVariantMap el = prepared(element);
    el[QStringLiteral("id")] = newId();
    if (!element.contains(QStringLiteral("x")))
        el[QStringLiteral("x")] = std::round((m_width - num(el, "w")) / 2);
    if (!element.contains(QStringLiteral("y")))
        el[QStringLiteral("y")] = std::round((m_height - num(el, "h")) / 2);
    beginInsertRows({}, m_elements.size(), m_elements.size());
    m_elements.append(el);
    endInsertRows();
    Q_EMIT countChanged();
    return el.value(QStringLiteral("id")).toString();
}

void Project::change(const QString &id, const QVariantMap &patch, bool commitNow)
{
    const int i = indexOf(id);
    if (i < 0)
        return;
    QVariantMap el = m_elements.at(i).toMap();
    const QVariantMap before = el;
    for (auto it = patch.cbegin(); it != patch.cend(); ++it) {
        if (it.value().isNull())
            el.remove(it.key());
        else
            el.insert(it.key(), it.value());
    }
    el = prepared(el);
    if (el != before) {
        m_elements[i] = el;
        Q_EMIT dataChanged(index(i), index(i));
    }
    if (commitNow)
        commit();
}

void Project::remove(const QString &id)
{
    const int i = indexOf(id);
    if (i < 0)
        return;
    beginRemoveRows({}, i, i);
    m_elements.removeAt(i);
    endRemoveRows();
    Q_EMIT countChanged();
    commit();
}

// Kopie zgrupowanych elementów tworzą nową grupę, a nie dołączają do starej
static void regroup(QVariantMap &el, QHash<QString, QString> &groups)
{
    const QString g = el.value(QStringLiteral("group")).toString();
    if (g.isEmpty())
        return;
    if (!groups.contains(g))
        groups.insert(g, QStringLiteral("g%1").arg(QRandomGenerator::global()->generate() % 100000000));
    el[QStringLiteral("group")] = groups.value(g);
}

QStringList Project::duplicateAll(const QStringList &ids)
{
    QStringList out;
    QHash<QString, QString> groups;
    const QVariantList all = m_elements;
    for (const QVariant &v : all) {       // w kolejności warstw, nie zaznaczania
        QVariantMap el = v.toMap();
        if (!ids.contains(el.value(QStringLiteral("id")).toString()))
            continue;
        regroup(el, groups);
        el[QStringLiteral("x")] = num(el, "x") + 24;
        el[QStringLiteral("y")] = num(el, "y") + 24;
        el.remove(QStringLiteral("id"));
        out.append(insert(el));
    }
    commit();
    return out;
}

void Project::removeAll(const QStringList &ids)
{
    for (const QString &id : ids) {
        const int i = indexOf(id);
        if (i < 0)
            continue;
        beginRemoveRows({}, i, i);
        m_elements.removeAt(i);
        endRemoveRows();
    }
    Q_EMIT countChanged();
    commit();
}

void Project::moveTo(const QString &id, int index)
{
    const int i = indexOf(id);
    const int to = qBound(0, index, int(m_elements.size()) - 1);
    if (i < 0 || to == i)
        return;
    beginMoveRows({}, i, i, {}, to > i ? to + 1 : to);
    m_elements.move(i, to);
    endMoveRows();
    commit();
}

QString Project::duplicate(const QString &id)
{
    QVariantMap el = get(id);
    if (el.isEmpty())
        return {};
    el[QStringLiteral("x")] = num(el, "x") + 24;
    el[QStringLiteral("y")] = num(el, "y") + 24;
    el.remove(QStringLiteral("id"));
    return add(el);
}

void Project::arrange(const QString &id, const QString &how)
{
    const int i = indexOf(id);
    if (i < 0)
        return;
    const int last = m_elements.size() - 1;
    int to = i;
    if (how == QLatin1String("up"))
        to = qMin(last, i + 1);
    else if (how == QLatin1String("down"))
        to = qMax(0, i - 1);
    else if (how == QLatin1String("front"))
        to = last;
    else if (how == QLatin1String("back"))
        to = 0;
    if (to == i)
        return;
    beginMoveRows({}, i, i, {}, to > i ? to + 1 : to);
    m_elements.move(i, to);
    endMoveRows();
    commit();
}

void Project::setBackground(const QVariantMap &background, bool commitNow)
{
    if (background != m_background) {
        m_background = background;
        Q_EMIT backgroundChanged();
    }
    if (commitNow)
        commit();
}

qreal Project::naturalWidth(const QVariantMap &textElement) const
{
    return Art::textNaturalWidth(textElement);
}

QStringList Project::colors() const
{
    QStringList out;
    auto take = [&out](const QVariant &v) {
        const QString s = v.toString().toLower();
        if (s.startsWith(QLatin1Char('#')) && !out.contains(s) && out.size() < 12)
            out.append(s);
    };
    take(m_background.value(QStringLiteral("color")));
    take(m_background.value(QStringLiteral("color2")));
    for (const QVariant &v : m_elements) {
        const QVariantMap el = v.toMap();
        for (const char *k : {"color", "fill", "fill2", "stroke", "outlineColor"})
            take(el.value(QLatin1String(k)));
    }
    return out;
}

static const char *const ColorKeys[] = {"color", "color2", "fill", "fill2", "stroke", "outlineColor", "bg", "shadowColor", "duo1", "duo2", "headerFill", "headerColor", "stripe"};

// Wywołuje fn dla każdego koloru w projekcie (tła stron, pola elementów, kolory słupków wykresów)
static void eachColor(QVariantList &pages, const std::function<void(QVariant &)> &fn)
{
    for (QVariant &pv : pages) {
        QVariantMap p = pv.toMap();
        QVariantMap bg = p.value(QStringLiteral("background")).toMap();
        for (const char *k : {"color", "color2"})
            if (bg.contains(QLatin1String(k)))
                fn(bg[QLatin1String(k)]);
        p[QStringLiteral("background")] = bg;
        QVariantList elements = p.value(QStringLiteral("elements")).toList();
        for (QVariant &v : elements) {
            QVariantMap el = v.toMap();
            for (const char *k : ColorKeys)
                if (el.contains(QLatin1String(k)))
                    fn(el[QLatin1String(k)]);
            if (el.contains(QStringLiteral("data")) && el.value(QStringLiteral("data")).typeId() == QMetaType::QVariantList) {
                QVariantList data = el.value(QStringLiteral("data")).toList();
                for (QVariant &d : data) {
                    QVariantMap row = d.toMap();
                    if (row.contains(QStringLiteral("color")))
                        fn(row[QStringLiteral("color")]);
                    d = row;
                }
                el[QStringLiteral("data")] = data;
            }
            v = el;
        }
        p[QStringLiteral("elements")] = elements;
        pv = p;
    }
}

QStringList Project::projectColors() const
{
    QVariantList all = pages();
    QStringList out;
    eachColor(all, [&out](QVariant &v) {
        const QString s = v.toString().toLower();
        if (s.startsWith(QLatin1Char('#')) && (s.size() == 7 || s.size() == 9) && !out.contains(s) && out.size() < 18)
            out.append(s);
    });
    return out;
}

void Project::replaceColor(const QString &from, const QString &to, bool commitNow)
{
    QVariantMap doc = QJsonDocument::fromJson(m_last).toVariant().toMap();
    QVariantList all = doc.value(QStringLiteral("pages")).toList();
    const QString f = from.toLower();
    eachColor(all, [&f, &to](QVariant &v) {
        if (v.toString().toLower() == f)
            v = to;
    });
    doc[QStringLiteral("pages")] = all;
    load(doc);
    setModified(true);
    Q_EMIT changed();
    if (commitNow)
        commit();
}

// ——— Moje elementy ———

static QString savedDir()
{
    return QStandardPaths::writableLocation(QStandardPaths::GenericDataLocation) + QStringLiteral("/aster-grafika/elements");
}

static QRectF clipBounds(const QVariantList &list)
{
    QRectF r;
    for (const QVariant &v : list) {
        const QVariantMap el = v.toMap();
        r = r.united(QRectF(num(el, "x"), num(el, "y"), qMax(1.0, num(el, "w")), qMax(1.0, num(el, "h"))));
    }
    return r;
}

bool Project::saveElements(const QStringList &ids)
{
    QVariantMap clip = clipData(ids);
    QVariantList list = clip.value(QStringLiteral("elements")).toList();
    if (list.isEmpty() || !QDir().mkpath(savedDir()))
        return false;
    const QRectF r = clipBounds(list);
    // Zapis od lewego górnego rogu; miniatura do 240 px na dłuższym boku
    for (QVariant &v : list) {
        QVariantMap el = v.toMap();
        el[QStringLiteral("x")] = num(el, "x") - r.x();
        el[QStringLiteral("y")] = num(el, "y") - r.y();
        v = el;
    }
    clip[QStringLiteral("elements")] = list;
    const QString base = savedDir() + QLatin1Char('/') + QString::number(QDateTime::currentMSecsSinceEpoch());
    QSaveFile f(base + QStringLiteral(".json"));
    if (!f.open(QIODevice::WriteOnly))
        return false;
    f.write(QJsonDocument::fromVariant(clip).toJson(QJsonDocument::Compact));
    if (!f.commit())
        return false;
    const qreal k = 240 / qMax(r.width(), r.height());
    const QVariantMap doc{{QStringLiteral("width"), r.width()}, {QStringLiteral("height"), r.height()},
                          {QStringLiteral("background"), QVariantMap{{QStringLiteral("type"), QStringLiteral("color")}, {QStringLiteral("color"), QStringLiteral("#00000000")}}},
                          {QStringLiteral("elements"), list}};
    Art::renderPage(doc, QSize(qMax(1, qRound(r.width() * k)), qMax(1, qRound(r.height() * k))), this).save(base + QStringLiteral(".png"));
    Q_EMIT savedElementsChanged();
    return true;
}

QVariantList Project::savedElements() const
{
    QVariantList out;
    const QDir dir(savedDir());
    const QStringList files = dir.entryList({QStringLiteral("*.json")}, QDir::Files, QDir::Name | QDir::Reversed);
    for (const QString &name : files) {
        const QString file = dir.filePath(name);
        QString thumb = file;
        thumb.replace(thumb.size() - 4, 4, QStringLiteral("png"));
        // Jasna treść (np. biały napis) — podgląd na ciemnym tle
        const QImage img(thumb);
        qreal sum = 0, weight = 0;
        for (int y = 0; y < img.height(); y += 2)
            for (int x = 0; x < img.width(); x += 2) {
                const QColor c = img.pixelColor(x, y);
                sum += c.lightnessF() * c.alphaF();
                weight += c.alphaF();
            }
        out.append(QVariantMap{{QStringLiteral("file"), file},
                               {QStringLiteral("thumb"), img.isNull() ? QString() : QUrl::fromLocalFile(thumb).toString()},
                               {QStringLiteral("light"), weight > 0 && sum / weight > 0.72}});
    }
    return out;
}

QStringList Project::insertSaved(const QString &file)
{
    QFile f(file);
    if (!f.open(QIODevice::ReadOnly))
        return {};
    const QVariantMap clip = QJsonDocument::fromJson(f.readAll()).toVariant().toMap();
    const QRectF r = clipBounds(clip.value(QStringLiteral("elements")).toList());
    if (r.isEmpty())
        return {};
    // Na środek strony; większe niż 80% strony — zmniejszone
    const qreal k = qMin(1.0, qMin(m_width * 0.8 / r.width(), m_height * 0.8 / r.height()));
    const qreal dx = (m_width - r.width() * k) / 2, dy = (m_height - r.height() * k) / 2;
    return insertClip(clip, [this, k, dx, dy, r](QVariantMap el) {
        if (k < 1)
            el = scaled(el, k, r.x(), r.y());
        el[QStringLiteral("x")] = std::round((num(el, "x") - r.x() + dx) * 10) / 10;
        el[QStringLiteral("y")] = std::round((num(el, "y") - r.y() + dy) * 10) / 10;
        return el;
    });
}

void Project::removeSaved(const QString &file)
{
    if (!file.startsWith(savedDir()))
        return;
    QFile::remove(file);
    QString thumb = file;
    QFile::remove(thumb.replace(thumb.size() - 4, 4, QStringLiteral("png")));
    Q_EMIT savedElementsChanged();
}

// ——— Zdjęcia ———

QString Project::addAsset(const QByteArray &data, const QString &ext)
{
    const QString key = QString::fromLatin1(QCryptographicHash::hash(data, QCryptographicHash::Sha1).toHex().left(20)) + QLatin1Char('.') + ext;
    if (m_assets.contains(key))
        return key;
    Asset a;
    a.data = data;
    a.ext = ext;
    if (!decode(a))
        return {};
    m_assets.insert(key, a);
    Q_EMIT imagesChanged();
    return key;
}

// Zdjęcie do pamięci (pełne i mniejsze na ekran); SVG — obraz 512 px tylko do proporcji i miniatur
bool Project::decode(Asset &a)
{
    if (a.ext == QLatin1String("svg")) {
        QSvgRenderer svg(a.data);
        if (!svg.isValid())
            return false;
        QSizeF s = svg.viewBoxF().size();
        if (s.isEmpty())
            s = svg.defaultSize();
        if (s.isEmpty())
            return false;
        s.scale(512, 512, Qt::KeepAspectRatio);
        a.full = QImage(s.toSize().expandedTo(QSize(1, 1)), QImage::Format_ARGB32_Premultiplied);
        a.full.fill(Qt::transparent);
        QPainter p(&a.full);
        svg.render(&p);
        p.end();
        a.preview = a.full;
        return true;
    }
    QBuffer buf(&a.data);
    QImageReader reader(&buf);
    reader.setAutoTransform(true);
    a.full = reader.read();
    if (a.full.isNull())
        return false;
    a.preview = qMax(a.full.width(), a.full.height()) > 1600 ? a.full.scaled(1600, 1600, Qt::KeepAspectRatio, Qt::SmoothTransformation) : a.full;
    return true;
}

QByteArray Project::vector(const QString &key) const
{
    const auto it = m_assets.constFind(key);
    return it != m_assets.cend() && it->ext == QLatin1String("svg") ? it->data : QByteArray();
}

bool Project::recolorable(const QString &key) const
{
    return vector(key).contains("currentColor");
}

QString Project::importImage(const QString &fileOrUrl)
{
    const QString path = fileOrUrl.startsWith(QLatin1String("file:")) ? QUrl(fileOrUrl).toLocalFile() : fileOrUrl;
    QFile f(path);
    if (!f.open(QIODevice::ReadOnly)) {
        Q_EMIT error(QStringLiteral("Nie udało się otworzyć zdjęcia."));
        return {};
    }
    const QByteArray data = f.readAll();
    QBuffer buf;
    buf.setData(data);
    buf.open(QIODevice::ReadOnly);
    QByteArray format = QImageReader::imageFormat(&buf);
    if (format.isEmpty() && (path.endsWith(QLatin1String(".svg"), Qt::CaseInsensitive) || data.trimmed().startsWith("<svg")))
        format = "svg";
    if (format == "svg" || format == "svgz") {
        const QString key = addAsset(data, QStringLiteral("svg"));
        if (key.isEmpty())
            Q_EMIT error(QStringLiteral("Nie udało się wczytać grafiki SVG."));
        return key;
    }
    if (format.isEmpty()) {
        Q_EMIT error(QStringLiteral("Ten plik nie jest zdjęciem, które umiem wczytać."));
        return {};
    }
    // Zdjęcia w formatach spoza zwykłego zestawu (HEIC, TIFF…) zapisujemy jako PNG/JPG — projekt otworzy się wszędzie
    if (format != "png" && format != "jpeg" && format != "webp" && format != "gif") {
        QImageReader reader(path);
        reader.setAutoTransform(true);
        const QImage img = reader.read();
        QByteArray out;
        QBuffer ob(&out);
        ob.open(QIODevice::WriteOnly);
        const bool alpha = img.hasAlphaChannel();
        img.save(&ob, alpha ? "PNG" : "JPG", alpha ? -1 : 92);
        return addAsset(out, alpha ? QStringLiteral("png") : QStringLiteral("jpg"));
    }
    const QString ext = format == "jpeg" ? QStringLiteral("jpg") : QString::fromLatin1(format);
    const QString key = addAsset(data, ext);
    if (key.isEmpty())
        Q_EMIT error(QStringLiteral("Nie udało się wczytać zdjęcia."));
    return key;
}

QImage Project::image(const QString &key, qreal pixels) const
{
    const auto it = m_assets.constFind(key);
    if (it == m_assets.cend())
        return {};
    const int pv = qMax(it->preview.width(), it->preview.height());
    return pixels <= pv * 1.05 ? it->preview : it->full;
}

QImage Project::fullImage(const QString &key) const
{
    const auto it = m_assets.constFind(key);
    return it == m_assets.cend() ? QImage() : it->full;
}

QString Project::addImage(const QImage &img)
{
    QByteArray data;
    QBuffer buf(&data);
    buf.open(QIODevice::WriteOnly);
    img.save(&buf, "PNG");
    const QString key = addAsset(data, QStringLiteral("png"));
    if (!key.isEmpty())
        Q_EMIT imagesChanged();
    return key;
}

QSize Project::imageSize(const QString &key) const
{
    const auto it = m_assets.constFind(key);
    return it == m_assets.cend() ? QSize() : it->full.size();
}

QStringList Project::images() const
{
    return m_assets.keys();
}

// ——— Schowek ———

QVariantMap Project::clipData(const QStringList &ids) const
{
    QVariantList list;
    QVariantMap images;
    for (const QVariant &v : m_elements) {
        const QVariantMap el = v.toMap();
        if (!ids.contains(el.value(QStringLiteral("id")).toString()))
            continue;
        list.append(el);
        const QString src = el.value(QStringLiteral("src")).toString();
        if (m_assets.contains(src) && !images.contains(src))
            images[src] = QString::fromLatin1(m_assets.value(src).data.toBase64());
    }
    return {{QStringLiteral("elements"), list}, {QStringLiteral("images"), images}};
}

QStringList Project::insertClip(const QVariantMap &clip, const std::function<QVariantMap(QVariantMap)> &place)
{
    const QVariantMap images = clip.value(QStringLiteral("images")).toMap();
    QHash<QString, QString> keys;
    for (auto it = images.cbegin(); it != images.cend(); ++it)
        keys[it.key()] = addAsset(QByteArray::fromBase64(it.value().toString().toLatin1()), QFileInfo(it.key()).suffix());
    if (!keys.isEmpty())
        Q_EMIT imagesChanged();
    QStringList out;
    QHash<QString, QString> groups;
    for (const QVariant &v : clip.value(QStringLiteral("elements")).toList()) {
        QVariantMap el = v.toMap();
        regroup(el, groups);
        const QString src = el.value(QStringLiteral("src")).toString();
        if (keys.contains(src))
            el[QStringLiteral("src")] = keys.value(src);
        el.remove(QStringLiteral("id"));
        out.append(insert(place(el)));
    }
    commit();
    return out;
}

void Project::copy(const QStringList &ids) const
{
    const QVariantMap clip = clipData(ids);
    const QVariantList list = clip.value(QStringLiteral("elements")).toList();
    if (list.isEmpty())
        return;
    auto *mime = new QMimeData;
    mime->setData(QLatin1String(ClipboardMime), QJsonDocument::fromVariant(clip).toJson(QJsonDocument::Compact));
    // Inne programy dostają tekst albo zdjęcie pojedynczego elementu
    const QVariantMap first = list.constFirst().toMap();
    const QString src = first.value(QStringLiteral("src")).toString();
    if (list.size() == 1 && first.value(QStringLiteral("type")).toString() == QLatin1String("text"))
        mime->setText(first.value(QStringLiteral("text")).toString());
    else if (list.size() == 1 && m_assets.contains(src))
        mime->setImageData(m_assets.value(src).full);
    QGuiApplication::clipboard()->setMimeData(mime);
}

QVariantMap Project::autoEnhance(const QString &key) const
{
    QImage img = fullImage(key);
    if (img.isNull())
        return {};
    img = img.scaled(256, 256, Qt::KeepAspectRatio, Qt::SmoothTransformation).convertToFormat(QImage::Format_ARGB32);
    int hist[256] = {};
    qint64 n = 0;
    qreal chroma = 0, sum = 0;
    for (int y = 0; y < img.height(); ++y) {
        const QRgb *row = reinterpret_cast<const QRgb *>(img.constScanLine(y));
        for (int x = 0; x < img.width(); ++x) {
            if (qAlpha(row[x]) < 128)
                continue;
            const int r = qRed(row[x]), g = qGreen(row[x]), b = qBlue(row[x]);
            const int l = (299 * r + 587 * g + 114 * b) / 1000;
            ++hist[l];
            sum += l;
            chroma += qMax(r, qMax(g, b)) - qMin(r, qMin(g, b));
            ++n;
        }
    }
    if (n == 0)
        return {};
    // Ciemne i jasne 1,5% pikseli — zakres, który rozciągamy do pełnej skali
    auto percentile = [&](qreal p) {
        qint64 acc = 0;
        for (int i = 0; i < 256; ++i)
            if ((acc += hist[i]) >= n * p)
                return i;
        return 255;
    };
    const int lo = percentile(0.015), hi = percentile(0.985);
    const qreal mean = sum / n;
    const qreal k = qBound(1.0, 225.0 / qMax(30, hi - lo), 1.45);
    const qreal mid = (mean - 128) * k + 128;
    const qreal brightness = qBound(-0.25, (128 - mid) / 110 * 0.55, 0.3);
    const qreal c = chroma / n;
    const qreal saturation = c < 35 ? 0.25 : c < 60 ? 0.15 : c < 90 ? 0.08 : 0;
    auto r2 = [](qreal v) { return std::round(v * 100) / 100; };
    return {{QStringLiteral("brightness"), r2(brightness)}, {QStringLiteral("contrast"), r2(k - 1)}, {QStringLiteral("saturation"), r2(saturation)}};
}

QString Project::clipboardText() const
{
    return QGuiApplication::clipboard()->text();
}

QStringList Project::paste()
{
    const QMimeData *mime = QGuiApplication::clipboard()->mimeData();
    if (!mime)
        return {};
    if (mime->hasFormat(QLatin1String(ClipboardMime))) {
        const QVariantMap clip = QJsonDocument::fromJson(mime->data(QLatin1String(ClipboardMime))).toVariant().toMap();
        return insertClip(clip, [](QVariantMap el) {
            el[QStringLiteral("x")] = num(el, "x") + 24;
            el[QStringLiteral("y")] = num(el, "y") + 24;
            return el;
        });
    }
    if (mime->hasImage()) {
        const QImage img = qvariant_cast<QImage>(mime->imageData());
        QByteArray data;
        QBuffer buf(&data);
        buf.open(QIODevice::WriteOnly);
        img.save(&buf, "PNG");
        const QString key = addAsset(data, QStringLiteral("png"));
        if (key.isEmpty())
            return {};
        const qreal k = qMin(1.0, qMin(m_width * 0.7 / img.width(), m_height * 0.7 / img.height()));
        return {add({{QStringLiteral("type"), QStringLiteral("image")}, {QStringLiteral("src"), key},
                     {QStringLiteral("w"), std::round(img.width() * k)}, {QStringLiteral("h"), std::round(img.height() * k)}})};
    }
    if (mime->hasText() && !mime->text().trimmed().isEmpty()) {
        QVariantMap el{{QStringLiteral("type"), QStringLiteral("text")}, {QStringLiteral("text"), mime->text().trimmed()},
                       {QStringLiteral("size"), std::round(m_width / 18)}, {QStringLiteral("color"), QStringLiteral("#16181d")}};
        el[QStringLiteral("w")] = qMin(m_width * 0.8, Art::textNaturalWidth(el));
        return {add(el)};
    }
    return {};
}

bool Project::copyImage()
{
    // Najwyżej 2400 px na dłuższym boku — komunikatory i tak zmniejszają większe obrazy
    const qreal k = qMin(1.0, 2400 / qMax(m_width, m_height));
    const QImage img = Art::renderPage(pageDocument(m_page), QSize(qMax(1, qRound(m_width * k)), qMax(1, qRound(m_height * k))), this, Qt::white);
    if (img.isNull())
        return false;
    QGuiApplication::clipboard()->setImage(img.convertToFormat(QImage::Format_RGB32));
    return true;
}

// ——— Eksport ———

QString Project::exportFile(const QString &format, qreal scale, const QString &target, bool allPages)
{
    commit();
    const QVariantMap doc = pageDocument(m_page);
    QString path = target.startsWith(QLatin1String("file:")) ? QUrl(target).toLocalFile() : target;
    // „pdf-print” — PDF dla drukarni: spad 3 mm i znaczniki cięcia
    const bool forPrint = format == QLatin1String("pdf-print");
    const bool pdfOut = format == QLatin1String("pdf") || forPrint;
    if (path.isEmpty()) {
        const QString dir = (pdfOut ? QStandardPaths::writableLocation(QStandardPaths::DocumentsLocation)
                                    : QStandardPaths::writableLocation(QStandardPaths::PicturesLocation))
                            + QStringLiteral("/Grafiki");
        QDir().mkpath(dir);
        path = uniquePath(dir, forPrint ? m_name + QStringLiteral(" (do druku)") : m_name, pdfOut ? QStringLiteral("pdf") : format);
    }

    if (pdfOut) {
        QPdfWriter pdf(path);
        pdf.setCreator(QStringLiteral("Aster Pixel"));
        pdf.setTitle(m_name);
        // Rozmiar do druku (A4, plakat) albo piksele jak na ekranie (96 na cal)
        const QSizeF mm = !m_print.isEmpty() ? QSizeF(num(m_print, "width"), num(m_print, "height"))
                                             : QSizeF(m_width / 96 * 25.4, m_height / 96 * 25.4);
        const qreal bleedMm = forPrint ? 3 : 0, edgeMm = forPrint ? 9 : 0;      // spad i pas na znaczniki
        pdf.setPageSize(QPageSize(mm + QSizeF(2 * edgeMm, 2 * edgeMm), QPageSize::Millimeter));
        pdf.setPageMargins(QMarginsF(0, 0, 0, 0));
        pdf.setResolution(300);
        QPainter p;
        if (!p.begin(&pdf)) {
            Q_EMIT error(QStringLiteral("Nie udało się zapisać PDF."));
            return {};
        }
        p.setRenderHints(QPainter::Antialiasing | QPainter::TextAntialiasing | QPainter::SmoothPixmapTransform);
        // Wszystkie strony, każda na osobnej stronie PDF
        const qreal perMm = pdf.width() / (mm.width() + 2 * edgeMm);              // punkty urządzenia na milimetr
        const qreal k = mm.width() * perMm / m_width;                             // na piksel projektu
        for (int i = 0; i < m_pages.size(); ++i) {
            if (i > 0)
                pdf.newPage();
            p.save();
            p.translate(edgeMm * perMm, edgeMm * perMm);
            p.scale(k, k);
            Art::paintPage(&p, pageDocument(i), this, bleedMm * perMm / k);
            p.restore();
            if (forPrint) {
                // Znaczniki cięcia w rogach, poza spadem
                p.setPen(QPen(Qt::black, 0.25 / 72 * 25.4 * perMm));
                const qreal x0 = edgeMm * perMm, y0 = edgeMm * perMm, x1 = x0 + mm.width() * perMm, y1 = y0 + mm.height() * perMm;
                const qreal gap = (bleedMm + 1) * perMm, len = (edgeMm - bleedMm - 2) * perMm;
                for (const qreal x : {x0, x1}) {
                    p.drawLine(QPointF(x, y0 - gap), QPointF(x, y0 - gap - len));
                    p.drawLine(QPointF(x, y1 + gap), QPointF(x, y1 + gap + len));
                }
                for (const qreal y : {y0, y1}) {
                    p.drawLine(QPointF(x0 - gap, y), QPointF(x0 - gap - len, y));
                    p.drawLine(QPointF(x1 + gap, y), QPointF(x1 + gap + len, y));
                }
            }
        }
        p.end();
        return path;
    }

    const QSize size(qMax(1, qRound(m_width * scale)), qMax(1, qRound(m_height * scale)));
    const bool jpg = format == QLatin1String("jpg");
    const bool many = allPages && m_pages.size() > 1;
    const QFileInfo fi(path);
    for (int i = many ? 0 : m_page; i < (many ? m_pages.size() : m_page + 1); ++i) {
        // Kilka stron: nazwa-1.png, nazwa-2.png… obok siebie (karuzela w mediach społecznościowych)
        const QString file = many ? fi.path() + QLatin1Char('/') + fi.completeBaseName() + QStringLiteral("-%1.").arg(i + 1) + fi.suffix() : path;
        QImage img = Art::renderPage(pageDocument(i), size, this, jpg ? QColor(Qt::white) : QColor(Qt::transparent));
        if (jpg)
            img = img.convertToFormat(QImage::Format_RGB32);
        if (!img.save(file, jpg ? "JPG" : "PNG", jpg ? 92 : -1)) {
            Q_EMIT error(QStringLiteral("Nie udało się zapisać pliku."));
            return {};
        }
        if (i == 0 && many)
            path = file;
    }
    return path;
}
