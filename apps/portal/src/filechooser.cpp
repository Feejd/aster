#include "filechooser.h"

#include <QDBusArgument>
#include <QDBusConnection>
#include <QDir>
#include <QFileInfo>
#include <QLocale>
#include <QMimeDatabase>
#include <QQmlComponent>
#include <QQuickWindow>
#include <QSettings>
#include <QStandardPaths>
#include <QTimer>
#include <QUrl>

namespace {

// Filtry z portalu: a(sa(us)) — nazwa i lista [typ (0 — wzorzec, 1 — typ MIME), wartość].
// Dla QML zamieniamy wszystko na wzorce nazw plików („*.png”).
QStringList globsFor(uint type, const QString &value)
{
    if (type == 0)
        return {value};
    static const QMimeDatabase db;
    QStringList out;
    if (value.endsWith(QLatin1String("/*"))) {
        const QString prefix = value.chopped(1);
        for (const QMimeType &m : db.allMimeTypes())
            if (m.name().startsWith(prefix))
                out << m.globPatterns();
    } else {
        out << db.mimeTypeForName(value).globPatterns();
    }
    return out;
}

QVariantMap readFilter(const QDBusArgument &arg)
{
    QString name;
    QStringList globs;
    arg.beginStructure();
    arg >> name;
    arg.beginArray();
    while (!arg.atEnd()) {
        uint type = 0;
        QString value;
        arg.beginStructure();
        arg >> type >> value;
        arg.endStructure();
        globs << globsFor(type, value);
    }
    arg.endArray();
    arg.endStructure();
    globs.removeDuplicates();
    return {{QStringLiteral("name"), name}, {QStringLiteral("globs"), globs}};
}

QVariantList readFilters(const QVariant &v)
{
    QVariantList out;
    if (!v.canConvert<QDBusArgument>())
        return out;
    const QDBusArgument arg = v.value<QDBusArgument>();
    arg.beginArray();
    while (!arg.atEnd())
        out << readFilter(arg);
    arg.endArray();
    return out;
}

// Ścieżki w portalu to bajty zakończone zerem (ay)
QString pathFromBytes(const QVariant &v)
{
    QByteArray b;
    if (v.metaType() == QMetaType::fromType<QDBusArgument>())
        v.value<QDBusArgument>() >> b;          // ay w a{sv} przychodzi jako surowy argument D-Bus
    else
        b = v.toByteArray();
    // Do pierwszego zera (portal dokłada je na końcu)
    const qsizetype end = b.indexOf('\0');
    return QString::fromUtf8(b.constData(), end < 0 ? b.size() : end);
}

} // namespace

FileChooser::FileChooser(QQmlEngine *engine, QObject *parent)
    : QObject(parent)
    , m_engine(engine)
{
}

QQuickWindow *FileChooser::openDialog(const QVariantMap &props)
{
    QQmlComponent component(m_engine, QStringLiteral("Aster.Portal"), QStringLiteral("FileDialog"));
    QObject *obj = component.createWithInitialProperties(props);
    auto *window = qobject_cast<QQuickWindow *>(obj);
    if (!window) {
        qWarning("%s", qPrintable(component.errorString()));
        delete obj;
        return nullptr;
    }
    return window;
}

QQuickWindow *FileChooser::showDemo(const QString &mode)
{
    QVariantMap props{{QStringLiteral("mode"), mode == QLatin1String("folder") ? QStringLiteral("open") : mode},
                      {QStringLiteral("directory"), mode == QLatin1String("folder")},
                      {QStringLiteral("multiple"), mode == QLatin1String("open")},
                      {QStringLiteral("dialogTitle"), mode == QLatin1String("save") ? QStringLiteral("Zapisz obraz") : QString()},
                      {QStringLiteral("currentName"), mode == QLatin1String("save") ? QStringLiteral("Zdjęcie z wakacji.png") : QString()},
                      {QStringLiteral("filters"), QVariantList{
                           QVariantMap{{QStringLiteral("name"), QStringLiteral("Obrazy")}, {QStringLiteral("globs"), QStringList{QStringLiteral("*.png"), QStringLiteral("*.jpg"), QStringLiteral("*.jpeg"), QStringLiteral("*.webp")}}},
                           QVariantMap{{QStringLiteral("name"), QStringLiteral("Wszystkie pliki")}, {QStringLiteral("globs"), QStringList{QStringLiteral("*")}}}}}};
    const QString folder = qEnvironmentVariable("ASTER_PORTAL_FOLDER");
    if (!folder.isEmpty())
        props.insert(QStringLiteral("folder"), folder);
    return openDialog(props);
}

void FileChooser::request(const QDBusObjectPath &handle, const QString &mode, const QString &title, const QVariantMap &options)
{
    setDelayedReply(true);
    const QDBusMessage call = message();

    QVariantMap props{{QStringLiteral("mode"), mode == QLatin1String("savefiles") ? QStringLiteral("open") : mode},
                      {QStringLiteral("dialogTitle"), title},
                      {QStringLiteral("acceptLabel"), options.value(QStringLiteral("accept_label")).toString().remove(QLatin1Char('_'))},
                      {QStringLiteral("multiple"), options.value(QStringLiteral("multiple")).toBool()},
                      {QStringLiteral("directory"), options.value(QStringLiteral("directory")).toBool() || mode == QLatin1String("savefiles")},
                      {QStringLiteral("filters"), readFilters(options.value(QStringLiteral("filters")))},
                      {QStringLiteral("currentName"), options.value(QStringLiteral("current_name")).toString()}};
    if (options.contains(QStringLiteral("current_filter")) && options.value(QStringLiteral("current_filter")).canConvert<QDBusArgument>())
        props.insert(QStringLiteral("currentFilterName"), readFilter(options.value(QStringLiteral("current_filter")).value<QDBusArgument>()).value(QStringLiteral("name")));
    QString folder = pathFromBytes(options.value(QStringLiteral("current_folder")));
    const QString file = pathFromBytes(options.value(QStringLiteral("current_file")));
    if (!file.isEmpty()) {
        folder = QFileInfo(file).absolutePath();
        props.insert(QStringLiteral("currentName"), QFileInfo(file).fileName());
    }
    if (!folder.isEmpty())
        props.insert(QStringLiteral("folder"), folder);
    // Zapis kilku plików: wybieramy folder, nazwy daje program
    QStringList names;
    if (mode == QLatin1String("savefiles") && options.value(QStringLiteral("files")).canConvert<QDBusArgument>()) {
        const QDBusArgument arg = options.value(QStringLiteral("files")).value<QDBusArgument>();
        arg.beginArray();
        while (!arg.atEnd()) {
            QByteArray b;
            arg >> b;
            names << pathFromBytes(b);
        }
        arg.endArray();
        props.insert(QStringLiteral("acceptLabel"), QStringLiteral("Zapisz tutaj"));
    }

    QQuickWindow *window = openDialog(props);
    if (!window) {
        QDBusConnection::sessionBus().send(call.createReply({uint(2), QVariantMap()}));
        return;
    }
    ++m_open;
    emit busyChanged(true);
    if (qEnvironmentVariableIsSet("ASTER_PORTAL_AUTOPICK"))
        QTimer::singleShot(1500, window, [window] { QMetaObject::invokeMethod(window, "testPick"); });

    // Prośbę można anulować z programu
    auto *req = new PortalRequest(window);
    QDBusConnection::sessionBus().registerObject(handle.path(), req, QDBusConnection::ExportAllSlots);
    const QString handlePath = handle.path();

    auto done = std::make_shared<bool>(false);
    auto reply = [this, call, window, done, handlePath](uint response, const QVariantMap &results) {
        if (*done)
            return;
        *done = true;
        QDBusConnection::sessionBus().unregisterObject(handlePath);
        QDBusConnection::sessionBus().send(call.createReply({response, results}));
        window->deleteLater();
        if (--m_open == 0)
            emit busyChanged(false);
    };
    connect(req, &PortalRequest::closeRequested, window, [reply] { reply(2, {}); });
    connect(window, SIGNAL(rejected()), req, SIGNAL(closeRequested()));
    QObject::connect(window, &QWindow::visibleChanged, window, [window, req] {
        if (!window->isVisible())
            emit req->closeRequested();
    });
    // QML: sygnał accepted(), wybrane ścieżki we właściwości „result”
    connect(window, SIGNAL(accepted()), req, SLOT(accept()));
    connect(req, &PortalRequest::acceptRequested, window, [window, reply, names, mode] {
        QStringList uris;
        const QStringList paths = window->property("result").toStringList();
        if (mode == QLatin1String("savefiles")) {
            const QString dir = paths.value(0);
            for (const QString &n : names)
                uris << QUrl::fromLocalFile(QDir(dir).filePath(n)).toString();
        } else {
            for (const QString &p : paths)
                uris << QUrl::fromLocalFile(p).toString();
        }
        PortalHelper().rememberFolder(mode == QLatin1String("savefiles") || QFileInfo(paths.value(0)).isDir() ? paths.value(0) : QFileInfo(paths.value(0)).absolutePath());
        QVariantMap results{{QStringLiteral("uris"), uris}};
        if (mode != QLatin1String("open"))
            results.insert(QStringLiteral("writable"), true);
        reply(0, results);
    });
}

uint FileChooser::OpenFile(const QDBusObjectPath &handle, const QString &, const QString &, const QString &title,
                           const QVariantMap &options, QVariantMap &)
{
    request(handle, QStringLiteral("open"), title, options);
    return 0;
}

uint FileChooser::SaveFile(const QDBusObjectPath &handle, const QString &, const QString &, const QString &title,
                           const QVariantMap &options, QVariantMap &)
{
    request(handle, QStringLiteral("save"), title, options);
    return 0;
}

uint FileChooser::SaveFiles(const QDBusObjectPath &handle, const QString &, const QString &, const QString &title,
                            const QVariantMap &options, QVariantMap &)
{
    request(handle, QStringLiteral("savefiles"), title, options);
    return 0;
}

// ——— Pomocnicze dla QML ———

QString PortalHelper::home() const
{
    return QDir::homePath();
}

QVariantList PortalHelper::places() const
{
    struct Place {
        QStandardPaths::StandardLocation loc;
        const char *name;
        const char *icon;
    };
    const Place list[] = {
        {QStandardPaths::DesktopLocation, "Pulpit", "desktop"},
        {QStandardPaths::DocumentsLocation, "Dokumenty", "doc"},
        {QStandardPaths::DownloadLocation, "Pobrane", "download"},
        {QStandardPaths::PicturesLocation, "Obrazy", "image"},
        {QStandardPaths::MusicLocation, "Muzyka", "music"},
        {QStandardPaths::MoviesLocation, "Wideo", "video"},
    };
    QVariantList out;
    out << QVariantMap{{QStringLiteral("name"), QStringLiteral("Folder domowy")}, {QStringLiteral("icon"), QStringLiteral("home")},
                       {QStringLiteral("path"), QDir::homePath()}};
    for (const Place &p : list) {
        const QString path = QStandardPaths::writableLocation(p.loc);
        if (path.isEmpty() || path == QDir::homePath() || !QFileInfo(path).isDir())
            continue;
        out << QVariantMap{{QStringLiteral("name"), QString::fromUtf8(p.name)}, {QStringLiteral("icon"), QString::fromLatin1(p.icon)},
                           {QStringLiteral("path"), path}};
    }
    out << QVariantMap{{QStringLiteral("name"), QStringLiteral("Cały dysk")}, {QStringLiteral("icon"), QStringLiteral("drive")},
                       {QStringLiteral("path"), QStringLiteral("/")}};
    return out;
}

// „Folder domowy › Dokumenty › Projekty” — każdy element z własną ścieżką
QVariantList PortalHelper::crumbs(const QString &path) const
{
    QVariantList out;
    const QString home = QDir::homePath();
    QString base, rest;
    if (path == home || path.startsWith(home + QLatin1Char('/'))) {
        base = home;
        rest = path.mid(home.size());
        out << QVariantMap{{QStringLiteral("name"), QStringLiteral("Folder domowy")}, {QStringLiteral("path"), home}};
    } else {
        base = QString();
        rest = path;
        out << QVariantMap{{QStringLiteral("name"), QStringLiteral("Cały dysk")}, {QStringLiteral("path"), QStringLiteral("/")}};
    }
    QString cur = base;
    for (const QString &part : rest.split(QLatin1Char('/'), Qt::SkipEmptyParts)) {
        cur += QLatin1Char('/') + part;
        out << QVariantMap{{QStringLiteral("name"), part}, {QStringLiteral("path"), cur}};
    }
    return out;
}

QString PortalHelper::parentPath(const QString &path) const
{
    if (path == QLatin1String("/"))
        return {};
    return QFileInfo(path).absolutePath();
}

bool PortalHelper::exists(const QString &path) const
{
    return QFileInfo::exists(path);
}

bool PortalHelper::isDir(const QString &path) const
{
    return QFileInfo(path).isDir();
}

QString PortalHelper::makeFolder(const QString &dir, const QString &name) const
{
    QString n = name.trimmed();
    if (n.isEmpty() || n.contains(QLatin1Char('/')))
        return {};
    QDir d(dir);
    QString candidate = n;
    for (int i = 2; d.exists(candidate); ++i)
        candidate = QStringLiteral("%1 (%2)").arg(n).arg(i);
    return d.mkdir(candidate) ? d.filePath(candidate) : QString();
}

QString PortalHelper::lastFolder() const
{
    const QString f = QSettings(QStringLiteral("Aster"), QStringLiteral("aster-portal")).value(QStringLiteral("lastFolder")).toString();
    return QFileInfo(f).isDir() ? f : QString();
}

void PortalHelper::rememberFolder(const QString &path) const
{
    if (QFileInfo(path).isDir())
        QSettings(QStringLiteral("Aster"), QStringLiteral("aster-portal")).setValue(QStringLiteral("lastFolder"), path);
}

QString PortalHelper::sizeText(qint64 bytes) const
{
    return QLocale(QStringLiteral("pl_PL")).formattedDataSize(bytes, 1, QLocale::DataSizeTraditionalFormat);
}
