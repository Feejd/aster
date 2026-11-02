#include "pdf.h"

#include <QDateTime>
#include <QDesktopServices>
#include <QDir>
#include <QFileInfo>
#include <QLocale>
#include <QPainter>
#include <QPdfDocument>
#include <QPrintDialog>
#include <QPrinter>
#include <QSettings>
#include <QUrl>

namespace {

QString sizeText(qint64 b)
{
    const QLocale pl(QLocale::Polish);
    if (b < 1024 * 1024)
        return pl.toString(std::max<qint64>(1, b / 1024)) + QStringLiteral(" KB");
    const double mb = b / (1024.0 * 1024.0);
    return pl.toString(mb, 'f', mb < 10 ? 1 : 0) + QStringLiteral(" MB");
}

} // namespace

Pdf::Pdf(QObject *parent)
    : QObject(parent)
{
}

QString Pdf::date(const QDateTime &dt) const
{
    if (!dt.isValid())
        return {};
    const QLocale pl(QLocale::Polish);
    const QDate d = dt.date(), today = QDate::currentDate();
    if (d == today)
        return QStringLiteral("dziś, ") + pl.toString(dt.time(), QStringLiteral("HH:mm"));
    if (d == today.addDays(-1))
        return QStringLiteral("wczoraj, ") + pl.toString(dt.time(), QStringLiteral("HH:mm"));
    return pl.toString(d, d.year() == today.year() ? QStringLiteral("d MMMM") : QStringLiteral("d MMMM yyyy"));
}

QVariantList Pdf::recent() const
{
    QVariantList out;
    QSettings s;
    const int n = s.beginReadArray(QStringLiteral("recent"));
    for (int i = 0; i < n; ++i) {
        s.setArrayIndex(i);
        const QString path = s.value(QStringLiteral("path")).toString();
        const QFileInfo fi(path);
        if (!fi.exists())
            continue;
        out << QVariantMap{{QStringLiteral("path"), path},
                           {QStringLiteral("name"), fi.completeBaseName()},
                           {QStringLiteral("folder"), fi.absolutePath()},
                           {QStringLiteral("page"), s.value(QStringLiteral("page")).toInt()},
                           {QStringLiteral("when"), date(s.value(QStringLiteral("opened")).toDateTime())}};
    }
    s.endArray();
    return out;
}

void Pdf::remember(const QString &path, int page)
{
    // Lista ostatnich (najnowszy na górze, najwyżej 20) razem ze stroną, na której skończono czytać
    QSettings s;
    QList<QVariantMap> list;
    const int n = s.beginReadArray(QStringLiteral("recent"));
    for (int i = 0; i < n; ++i) {
        s.setArrayIndex(i);
        if (s.value(QStringLiteral("path")).toString() != path)
            list << QVariantMap{{QStringLiteral("path"), s.value(QStringLiteral("path"))}, {QStringLiteral("page"), s.value(QStringLiteral("page"))},
                                {QStringLiteral("opened"), s.value(QStringLiteral("opened"))}};
    }
    s.endArray();
    list.prepend({{QStringLiteral("path"), path}, {QStringLiteral("page"), page}, {QStringLiteral("opened"), QDateTime::currentDateTime()}});
    while (list.size() > 20)
        list.removeLast();
    s.beginWriteArray(QStringLiteral("recent"), list.size());
    for (int i = 0; i < list.size(); ++i) {
        s.setArrayIndex(i);
        for (auto it = list.at(i).cbegin(); it != list.at(i).cend(); ++it)
            s.setValue(it.key(), it.value());
    }
    s.endArray();
    Q_EMIT recentChanged();
}

int Pdf::lastPage(const QString &path) const
{
    for (const QVariant &v : recent())
        if (v.toMap().value(QStringLiteral("path")).toString() == path)
            return v.toMap().value(QStringLiteral("page")).toInt();
    return 0;
}

void Pdf::forget(const QString &path)
{
    QSettings s;
    QList<QVariantMap> list;
    const int n = s.beginReadArray(QStringLiteral("recent"));
    for (int i = 0; i < n; ++i) {
        s.setArrayIndex(i);
        if (s.value(QStringLiteral("path")).toString() != path)
            list << QVariantMap{{QStringLiteral("path"), s.value(QStringLiteral("path"))}, {QStringLiteral("page"), s.value(QStringLiteral("page"))},
                                {QStringLiteral("opened"), s.value(QStringLiteral("opened"))}};
    }
    s.endArray();
    s.remove(QStringLiteral("recent"));
    s.beginWriteArray(QStringLiteral("recent"), list.size());
    for (int i = 0; i < list.size(); ++i) {
        s.setArrayIndex(i);
        for (auto it = list.at(i).cbegin(); it != list.at(i).cend(); ++it)
            s.setValue(it.key(), it.value());
    }
    s.endArray();
    Q_EMIT recentChanged();
}

QVariantMap Pdf::fileInfo(const QString &path) const
{
    const QFileInfo fi(path);
    return {{QStringLiteral("name"), fi.fileName()},
            {QStringLiteral("folder"), fi.absolutePath()},
            {QStringLiteral("size"), sizeText(fi.size())},
            {QStringLiteral("modified"), date(fi.lastModified())}};
}

QString Pdf::toPath(const QString &pathOrUrl) const
{
    const QUrl url(pathOrUrl);
    return url.isLocalFile() ? url.toLocalFile() : pathOrUrl;
}

void Pdf::showInFolder(const QString &path) const
{
    QDesktopServices::openUrl(QUrl::fromLocalFile(QFileInfo(path).absolutePath()));
}

bool Pdf::print(const QString &path, const QString &password)
{
    QPdfDocument doc;
    if (!password.isEmpty())
        doc.setPassword(password);
    if (doc.load(path) != QPdfDocument::Error::None || doc.pageCount() == 0) {
        Q_EMIT message(QStringLiteral("Nie udało się przygotować dokumentu do druku"));
        return false;
    }
    QPrinter printer(QPrinter::HighResolution);
    printer.setDocName(QFileInfo(path).completeBaseName());
    printer.setFromTo(1, doc.pageCount());
    QPrintDialog dialog(&printer);
    dialog.setWindowTitle(QStringLiteral("Drukuj „%1”").arg(QFileInfo(path).fileName()));
    dialog.setMinMax(1, doc.pageCount());
    if (dialog.exec() != QDialog::Accepted)
        return false;

    int from = printer.fromPage(), to = printer.toPage();
    if (from <= 0 || printer.printRange() == QPrinter::AllPages) {
        from = 1;
        to = doc.pageCount();
    }
    QPainter painter;
    if (!painter.begin(&printer)) {
        Q_EMIT message(QStringLiteral("Nie udało się połączyć z drukarką"));
        return false;
    }
    // Każda strona w rozdzielczości drukarki, dopasowana do kartki z zachowaniem proporcji
    const double dpi = printer.resolution();
    for (int p = from - 1; p < to; ++p) {
        if (p > from - 1)
            printer.newPage();
        const QSizeF pts = doc.pagePointSize(p);
        const QRect area = printer.pageLayout().paintRectPixels(int(dpi));
        const QSize target = (pts * dpi / 72.0).toSize().scaled(area.size(), Qt::KeepAspectRatio);
        const QImage img = doc.render(p, target);
        painter.drawImage(QRect(QPoint((area.width() - target.width()) / 2, (area.height() - target.height()) / 2), target), img);
    }
    painter.end();
    Q_EMIT message(QStringLiteral("Wysłano do drukarki"));
    return true;
}
