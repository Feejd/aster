#include "project.h"

#include <QBuffer>
#include <QClipboard>
#include <QCryptographicHash>
#include <QDir>
#include <QFile>
#include <QFileInfo>
#include <QGuiApplication>
#include <QImageReader>
#include <QJsonDocument>
#include <QMimeData>
#include <QPainter>
#include <QPdfWriter>
#include <QSaveFile>
#include <QStandardPaths>
#include <QUrl>
#include <private/qzipreader_p.h>
#include <private/qzipwriter_p.h>

static const char *ClipboardMime = "application/x-aster-grafika";

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
    return doc;
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
    m_background = doc.value(QStringLiteral("background")).toMap();
    if (m_background.isEmpty())
        m_background = {{QStringLiteral("type"), QStringLiteral("color")}, {QStringLiteral("color"), QStringLiteral("#ffffff")}};
    m_elements.clear();
    for (const QVariant &v : doc.value(QStringLiteral("elements")).toList()) {
        QVariantMap el = v.toMap();
        const QString id = el.value(QStringLiteral("id")).toString();
        if (id.startsWith(QLatin1Char('e')))
            m_nextId = qMax(m_nextId, id.mid(1).toInt() + 1);
        m_elements.append(el);
    }
    for (QVariant &v : m_elements) {
        QVariantMap el = v.toMap();
        if (el.value(QStringLiteral("id")).toString().isEmpty())
            el[QStringLiteral("id")] = newId();
        v = prepared(el);
    }
    endResetModel();
    Q_EMIT pageChanged();
    Q_EMIT backgroundChanged();
    Q_EMIT countChanged();
    Q_EMIT colorsChanged();
    Q_EMIT reset();
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
    commit();
    load(doc);
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
        QBuffer buf(&a.data);
        QImageReader reader(&buf);
        reader.setAutoTransform(true);
        a.full = reader.read();
        if (a.full.isNull())
            continue;
        a.preview = qMax(a.full.width(), a.full.height()) > 1600 ? a.full.scaled(1600, 1600, Qt::KeepAspectRatio, Qt::SmoothTransformation) : a.full;
        m_assets.insert(file, a);
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
        const qreal k = 512 / qMax(m_width, m_height);
        QByteArray thumb;
        QBuffer buf(&thumb);
        buf.open(QIODevice::WriteOnly);
        Art::renderPage(doc, QSize(qMax(1, qRound(m_width * k)), qMax(1, qRound(m_height * k))), this).save(&buf, "PNG");
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

void Project::setPageSize(qreal width, qreal height)
{
    commit();
    m_width = qMax(16.0, width);
    m_height = qMax(16.0, height);
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

QStringList Project::duplicateAll(const QStringList &ids)
{
    QStringList out;
    for (const QVariant &v : std::as_const(m_elements)) {       // w kolejności warstw, nie zaznaczania
        QVariantMap el = v.toMap();
        if (!ids.contains(el.value(QStringLiteral("id")).toString()))
            continue;
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

// ——— Zdjęcia ———

QString Project::addAsset(const QByteArray &data, const QString &ext)
{
    const QString key = QString::fromLatin1(QCryptographicHash::hash(data, QCryptographicHash::Sha1).toHex().left(20)) + QLatin1Char('.') + ext;
    if (m_assets.contains(key))
        return key;
    Asset a;
    a.data = data;
    a.ext = ext;
    QBuffer buf(&a.data);
    QImageReader reader(&buf);
    reader.setAutoTransform(true);
    a.full = reader.read();
    if (a.full.isNull())
        return {};
    a.preview = qMax(a.full.width(), a.full.height()) > 1600 ? a.full.scaled(1600, 1600, Qt::KeepAspectRatio, Qt::SmoothTransformation) : a.full;
    m_assets.insert(key, a);
    Q_EMIT imagesChanged();
    return key;
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

void Project::copy(const QStringList &ids) const
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
    if (list.isEmpty())
        return;
    const QVariantMap clip{{QStringLiteral("elements"), list}, {QStringLiteral("images"), images}};
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

QStringList Project::paste()
{
    const QMimeData *mime = QGuiApplication::clipboard()->mimeData();
    if (!mime)
        return {};
    if (mime->hasFormat(QLatin1String(ClipboardMime))) {
        const QVariantMap clip = QJsonDocument::fromJson(mime->data(QLatin1String(ClipboardMime))).toVariant().toMap();
        const QVariantMap images = clip.value(QStringLiteral("images")).toMap();
        QHash<QString, QString> keys;
        for (auto it = images.cbegin(); it != images.cend(); ++it)
            keys[it.key()] = addAsset(QByteArray::fromBase64(it.value().toString().toLatin1()), QFileInfo(it.key()).suffix());
        QStringList out;
        for (const QVariant &v : clip.value(QStringLiteral("elements")).toList()) {
            QVariantMap el = v.toMap();
            const QString src = el.value(QStringLiteral("src")).toString();
            if (keys.contains(src))
                el[QStringLiteral("src")] = keys.value(src);
            el.remove(QStringLiteral("id"));
            el[QStringLiteral("x")] = num(el, "x") + 24;
            el[QStringLiteral("y")] = num(el, "y") + 24;
            out.append(insert(el));
        }
        commit();
        return out;
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
    const QImage img = Art::renderPage(document(), QSize(qMax(1, qRound(m_width * k)), qMax(1, qRound(m_height * k))), this, Qt::white);
    if (img.isNull())
        return false;
    QGuiApplication::clipboard()->setImage(img.convertToFormat(QImage::Format_RGB32));
    return true;
}

// ——— Eksport ———

QString Project::exportFile(const QString &format, qreal scale, const QString &target)
{
    commit();
    const QVariantMap doc = document();
    QString path = target.startsWith(QLatin1String("file:")) ? QUrl(target).toLocalFile() : target;
    if (path.isEmpty()) {
        const QString dir = (format == QLatin1String("pdf") ? QStandardPaths::writableLocation(QStandardPaths::DocumentsLocation)
                                                             : QStandardPaths::writableLocation(QStandardPaths::PicturesLocation))
                            + QStringLiteral("/Grafiki");
        QDir().mkpath(dir);
        path = uniquePath(dir, m_name, format);
    }

    if (format == QLatin1String("pdf")) {
        QPdfWriter pdf(path);
        pdf.setCreator(QStringLiteral("Aster Grafika"));
        pdf.setTitle(m_name);
        // Rozmiar do druku (A4, plakat) albo piksele jak na ekranie (96 na cal)
        const QSizeF mm = !m_print.isEmpty() ? QSizeF(num(m_print, "width"), num(m_print, "height"))
                                             : QSizeF(m_width / 96 * 25.4, m_height / 96 * 25.4);
        pdf.setPageSize(QPageSize(mm, QPageSize::Millimeter));
        pdf.setPageMargins(QMarginsF(0, 0, 0, 0));
        pdf.setResolution(300);
        QPainter p;
        if (!p.begin(&pdf)) {
            Q_EMIT error(QStringLiteral("Nie udało się zapisać PDF."));
            return {};
        }
        p.setRenderHints(QPainter::Antialiasing | QPainter::TextAntialiasing | QPainter::SmoothPixmapTransform);
        p.scale(pdf.width() / m_width, pdf.height() / m_height);
        Art::paintPage(&p, doc, this);
        p.end();
        return path;
    }

    const QSize size(qMax(1, qRound(m_width * scale)), qMax(1, qRound(m_height * scale)));
    const bool jpg = format == QLatin1String("jpg");
    QImage img = Art::renderPage(doc, size, this, jpg ? QColor(Qt::white) : QColor(Qt::transparent));
    if (jpg)
        img = img.convertToFormat(QImage::Format_RGB32);
    if (!img.save(path, jpg ? "JPG" : "PNG", jpg ? 92 : -1)) {
        Q_EMIT error(QStringLiteral("Nie udało się zapisać pliku."));
        return {};
    }
    return path;
}
