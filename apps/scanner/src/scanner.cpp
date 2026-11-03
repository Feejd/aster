#include "scanner.h"

#include <QDateTime>
#include <QDBusConnection>
#include <QDBusMessage>
#include <QDBusPendingCall>
#include <QDesktopServices>
#include <QDir>
#include <QFileInfo>
#include <QPageSize>
#include <QPainter>
#include <QPdfWriter>
#include <QStandardPaths>
#include <QTransform>
#include <QUrl>


#include <sane/sane.h>
#include <sane/saneopts.h>
#include <cstring>

Scanner *Scanner::s_instance = nullptr;

namespace {

SANE_Handle H(void *h) { return static_cast<SANE_Handle>(h); }

int optionIndex(SANE_Handle h, const char *name)
{
    SANE_Int count = 0;
    if (sane_control_option(h, 0, SANE_ACTION_GET_VALUE, &count, nullptr) != SANE_STATUS_GOOD)
        return -1;
    for (SANE_Int i = 1; i < count; ++i) {
        const SANE_Option_Descriptor *d = sane_get_option_descriptor(h, i);
        if (d && d->name && std::strcmp(d->name, name) == 0)
            return SANE_OPTION_IS_ACTIVE(d->cap) ? i : -1;
    }
    return -1;
}

QStringList stringOptions(SANE_Handle h, const char *name)
{
    QStringList out;
    const int i = optionIndex(h, name);
    if (i < 0)
        return out;
    const SANE_Option_Descriptor *d = sane_get_option_descriptor(h, i);
    if (d->type == SANE_TYPE_STRING && d->constraint_type == SANE_CONSTRAINT_STRING_LIST)
        for (const SANE_String_Const *s = d->constraint.string_list; *s; ++s)
            out << QString::fromUtf8(*s);
    return out;
}

bool setString(SANE_Handle h, const char *name, const QString &value)
{
    const int i = optionIndex(h, name);
    if (i < 0 || value.isEmpty())
        return false;
    const SANE_Option_Descriptor *d = sane_get_option_descriptor(h, i);
    if (d->type != SANE_TYPE_STRING || !SANE_OPTION_IS_SETTABLE(d->cap))
        return false;
    QByteArray buf = value.toUtf8();
    buf.resize(qMax<qsizetype>(d->size, buf.size() + 1), '\0');
    return sane_control_option(h, i, SANE_ACTION_SET_VALUE, buf.data(), nullptr) == SANE_STATUS_GOOD;
}

bool setNumber(SANE_Handle h, const char *name, double value)
{
    const int i = optionIndex(h, name);
    if (i < 0)
        return false;
    const SANE_Option_Descriptor *d = sane_get_option_descriptor(h, i);
    if (!SANE_OPTION_IS_SETTABLE(d->cap) || d->size != sizeof(SANE_Word))
        return false;
    SANE_Word w = d->type == SANE_TYPE_FIXED ? SANE_FIX(value) : SANE_Word(qRound(value));
    return sane_control_option(h, i, SANE_ACTION_SET_VALUE, &w, nullptr) == SANE_STATUS_GOOD;
}

double toDouble(const SANE_Option_Descriptor *d, SANE_Word w)
{
    return d->type == SANE_TYPE_FIXED ? SANE_UNFIX(w) : double(w);
}

// Zakres liczbowej opcji (min, max) — z przedziału albo listy wartości
bool range(SANE_Handle h, const char *name, double *min, double *max)
{
    const int i = optionIndex(h, name);
    if (i < 0)
        return false;
    const SANE_Option_Descriptor *d = sane_get_option_descriptor(h, i);
    if (d->constraint_type == SANE_CONSTRAINT_RANGE) {
        *min = toDouble(d, d->constraint.range->min);
        *max = toDouble(d, d->constraint.range->max);
        return true;
    }
    if (d->constraint_type == SANE_CONSTRAINT_WORD_LIST && d->constraint.word_list[0] > 0) {
        *min = *max = toDouble(d, d->constraint.word_list[1]);
        for (int k = 1; k <= d->constraint.word_list[0]; ++k) {
            *min = qMin(*min, toDouble(d, d->constraint.word_list[k]));
            *max = qMax(*max, toDouble(d, d->constraint.word_list[k]));
        }
        return true;
    }
    return false;
}

// Rozdzielczości do wyboru: zwykłe wartości (75–1200 dpi), które skaner obsługuje
QVariantList resolutionChoices(SANE_Handle h)
{
    static const int common[] = {75, 100, 150, 200, 300, 600, 1200};
    QVariantList out;
    const int i = optionIndex(h, SANE_NAME_SCAN_RESOLUTION);
    if (i < 0)
        return out;
    const SANE_Option_Descriptor *d = sane_get_option_descriptor(h, i);
    if (d->constraint_type == SANE_CONSTRAINT_WORD_LIST) {
        for (int k = 1; k <= d->constraint.word_list[0]; ++k) {
            const int v = qRound(toDouble(d, d->constraint.word_list[k]));
            if (v >= 75 && v <= 1200 && !out.contains(v))
                out << v;
        }
    } else if (d->constraint_type == SANE_CONSTRAINT_RANGE) {
        const double min = toDouble(d, d->constraint.range->min), max = toDouble(d, d->constraint.range->max);
        for (int v : common)
            if (v >= min && v <= max)
                out << v;
    }
    std::sort(out.begin(), out.end(), [](const QVariant &a, const QVariant &b) { return a.toInt() < b.toInt(); });
    return out;
}

QString modeLabel(const QString &m)
{
    const QString l = m.toLower();
    if (l == QLatin1String("color") || l == QLatin1String("colour") || l == QLatin1String("24bit color"))
        return QStringLiteral("Kolor");
    if (l == QLatin1String("gray") || l == QLatin1String("grey") || l == QLatin1String("grayscale"))
        return QStringLiteral("Szarości");
    if (l == QLatin1String("lineart") || l == QLatin1String("binary") || l == QLatin1String("black & white"))
        return QStringLiteral("Czarno-biały");
    return m;
}

bool isFeeder(const QString &s)
{
    const QString l = s.toLower();
    return l.contains(QLatin1String("adf")) || l.contains(QLatin1String("feeder")) || l.contains(QLatin1String("duplex"));
}

QString sourceLabel(const QString &s)
{
    const QString l = s.toLower();
    if (l.contains(QLatin1String("duplex")))
        return QStringLiteral("Podajnik, dwustronnie");
    if (isFeeder(s))
        return QStringLiteral("Podajnik");
    if (l.contains(QLatin1String("flatbed")) || l.contains(QLatin1String("platen")) || l == QLatin1String("normal"))
        return QStringLiteral("Szyba");
    return s;
}

QString statusText(SANE_Status st)
{
    switch (st) {
    case SANE_STATUS_NO_DOCS: return QStringLiteral("W podajniku nie ma kartek.");
    case SANE_STATUS_JAMMED: return QStringLiteral("Kartka zacięła się w podajniku.");
    case SANE_STATUS_COVER_OPEN: return QStringLiteral("Pokrywa skanera jest otwarta.");
    case SANE_STATUS_DEVICE_BUSY: return QStringLiteral("Skaner jest zajęty — może używa go inny program.");
    case SANE_STATUS_ACCESS_DENIED: return QStringLiteral("Brak dostępu do skanera.");
    case SANE_STATUS_IO_ERROR: return QStringLiteral("Utracono połączenie ze skanerem.");
    default: return QString::fromUtf8(sane_strstatus(st));
    }
}

// Jedna strona: sane_start → odczyt → QImage (szarości 1/8/16 bit, RGB 8/16 bit)
SANE_Status readPage(SANE_Handle h, const QAtomicInt &cancel, const std::function<void(qreal)> &progress, QImage *out)
{
    SANE_Status st = sane_start(h);
    if (st != SANE_STATUS_GOOD)
        return st;
    SANE_Parameters p;
    st = sane_get_parameters(h, &p);
    if (st != SANE_STATUS_GOOD)
        return st;
    if ((p.format != SANE_FRAME_GRAY && p.format != SANE_FRAME_RGB) || !p.last_frame)
        return SANE_STATUS_UNSUPPORTED;

    QByteArray data;
    const qint64 expected = p.lines > 0 ? qint64(p.bytes_per_line) * p.lines : 0;
    if (expected > 0)
        data.reserve(expected);
    QByteArray buf(256 * 1024, Qt::Uninitialized);
    for (;;) {
        if (cancel.loadRelaxed())
            return SANE_STATUS_CANCELLED;
        SANE_Int len = 0;
        st = sane_read(h, reinterpret_cast<SANE_Byte *>(buf.data()), buf.size(), &len);
        if (st == SANE_STATUS_EOF)
            break;
        if (st != SANE_STATUS_GOOD)
            return st;
        data.append(buf.constData(), len);
        if (expected > 0)
            progress(qMin<qreal>(1, qreal(data.size()) / expected));
    }

    const int bpl = p.bytes_per_line;
    const int lines = bpl > 0 ? int(data.size() / bpl) : 0;
    const int w = p.pixels_per_line;
    if (lines <= 0 || w <= 0)
        return SANE_STATUS_IO_ERROR;
    const bool rgb = p.format == SANE_FRAME_RGB;
    QImage img(w, lines, rgb ? QImage::Format_RGB888 : QImage::Format_Grayscale8);
    for (int y = 0; y < lines; ++y) {
        const auto *src = reinterpret_cast<const uchar *>(data.constData()) + qint64(y) * bpl;
        uchar *dst = img.scanLine(y);
        if (p.depth == 1) {                       // 1 = czarny, najstarszy bit pierwszy
            for (int x = 0; x < w; ++x)
                dst[x] = (src[x >> 3] & (0x80 >> (x & 7))) ? 0 : 255;
        } else if (p.depth == 16) {               // kolejność bajtów maszyny — bierzemy starszy bajt
            const auto *s16 = reinterpret_cast<const quint16 *>(src);
            for (int x = 0; x < w * (rgb ? 3 : 1); ++x)
                dst[x] = uchar(s16[x] >> 8);
        } else {
            std::memcpy(dst, src, size_t(w) * (rgb ? 3 : 1));
        }
    }
    *out = img;
    return SANE_STATUS_GOOD;
}

} // namespace

Scanner::Scanner(QObject *parent)
    : QObject(parent)
{
    s_instance = this;
    m_pool.setMaxThreadCount(1);
    m_pool.setExpiryTimeout(-1);
    m_pool.start([] {
        SANE_Int version = 0;
        sane_init(&version, nullptr);
    });
    refresh();
}

Scanner::~Scanner()
{
    m_cancel.storeRelaxed(1);
    m_pool.start([this] {
        if (m_handle)
            sane_close(H(m_handle));
        sane_exit();
    });
    m_pool.waitForDone();
    s_instance = nullptr;
}

QVariantList Scanner::pages() const
{
    QVariantList out;
    for (const Page &p : m_pages)
        out << QVariantMap{{QStringLiteral("url"), QStringLiteral("image://scan/page/%1").arg(p.id)},
                           {QStringLiteral("width"), p.image.width()},
                           {QStringLiteral("height"), p.image.height()}};
    return out;
}

void Scanner::run(const QString &task, std::function<void()> job)
{
    m_task = task;
    m_cancel.storeRelaxed(0);
    setProgress(0);
    Q_EMIT stateChanged();
    m_pool.start(std::move(job));
}

void Scanner::finish()
{
    m_task.clear();
    Q_EMIT stateChanged();
}

void Scanner::setProgress(qreal p)
{
    if (qFuzzyCompare(p + 1, m_progress + 1))
        return;
    m_progress = p;
    Q_EMIT progressChanged();
}

// Szukanie skanerów (sieciowe potrafią odpowiadać kilka sekund)
void Scanner::refresh()
{
    if (m_searching)
        return;
    m_searching = true;
    Q_EMIT devicesChanged();
    m_pool.start([this] {
        const SANE_Device **list = nullptr;
        QVariantList found;
        if (sane_get_devices(&list, SANE_FALSE) == SANE_STATUS_GOOD && list) {
            for (int i = 0; list[i]; ++i) {
                const QString name = QString::fromUtf8(list[i]->name);
                // Wirtualne urządzenia do testów SANE tylko w trybie podglądu
                if (name.startsWith(QLatin1String("test:")) && !qEnvironmentVariableIsSet("ASTER_PREVIEW"))
                    continue;
                const QString vendor = QString::fromUtf8(list[i]->vendor).trimmed();
                const QString model = QString::fromUtf8(list[i]->model).trimmed();
                QString label = model.startsWith(vendor, Qt::CaseInsensitive) || vendor == QLatin1String("Noname") ? model : vendor + QLatin1Char(' ') + model;
                if (name.startsWith(QLatin1String("airscan:")) || name.contains(QLatin1String("net:")))
                    label += QStringLiteral(" (sieć)");
                found << QVariantMap{{QStringLiteral("name"), name}, {QStringLiteral("label"), label}};
            }
        }
        QMetaObject::invokeMethod(this, [this, found] {
            m_searching = false;
            m_devices = found;
            Q_EMIT devicesChanged();
            bool still = false;
            for (const QVariant &d : found)
                still |= d.toMap().value(QStringLiteral("name")).toString() == m_device;
            if (!found.isEmpty() && !still)
                select(found.constFirst().toMap().value(QStringLiteral("name")).toString());
        });
    });
}

void Scanner::select(const QString &name)
{
    if (busy())
        return;
    run(QStringLiteral("Łączenie ze skanerem…"), [this, name] {
        if (m_handle) {
            sane_close(H(m_handle));
            m_handle = nullptr;
        }
        SANE_Handle h = nullptr;
        const SANE_Status st = sane_open(name.toUtf8().constData(), &h);
        QVariantList sources, modes, resolutions;
        QSizeF area;
        if (st == SANE_STATUS_GOOD) {
            m_handle = h;
            for (const QString &s : stringOptions(h, SANE_NAME_SCAN_SOURCE))
                sources << QVariantMap{{QStringLiteral("value"), s}, {QStringLiteral("label"), sourceLabel(s)}, {QStringLiteral("feeder"), isFeeder(s)}};
            for (const QString &m : stringOptions(h, SANE_NAME_SCAN_MODE))
                modes << QVariantMap{{QStringLiteral("value"), m}, {QStringLiteral("label"), modeLabel(m)}};
            resolutions = resolutionChoices(h);
            double min = 0, maxX = 0, maxY = 0;
            if (range(h, SANE_NAME_SCAN_BR_X, &min, &maxX) && range(h, SANE_NAME_SCAN_BR_Y, &min, &maxY))
                area = QSizeF(maxX, maxY);
        }
        QMetaObject::invokeMethod(this, [=, this] {
            m_device = st == SANE_STATUS_GOOD ? name : QString();
            m_sources = sources;
            m_modes = modes;
            m_resolutions = resolutions;
            m_area = area.isValid() && !area.isEmpty() ? area : QSizeF(215.9, 297);
            m_previewImage = QImage();
            m_previewUrl.clear();
            Q_EMIT previewChanged();
            Q_EMIT optionsChanged();
            finish();
            if (st != SANE_STATUS_GOOD)
                Q_EMIT error(QStringLiteral("Nie udało się połączyć ze skanerem: ") + statusText(st));
        });
    });
}

void Scanner::previewScan(const QString &source, const QString &mode)
{
    if (busy() || m_device.isEmpty())
        return;
    run(QStringLiteral("Podgląd…"), [this, source, mode] {
        SANE_Handle h = H(m_handle);
        setString(h, SANE_NAME_SCAN_SOURCE, source);
        setString(h, SANE_NAME_SCAN_MODE, mode);
        setNumber(h, SANE_NAME_BIT_DEPTH, 8);
        double min = 0, max = 0;
        const QVariantList res = resolutionChoices(h);
        setNumber(h, SANE_NAME_SCAN_RESOLUTION, res.isEmpty() ? 75 : res.constFirst().toInt());
        if (range(h, SANE_NAME_SCAN_TL_X, &min, &max)) setNumber(h, SANE_NAME_SCAN_TL_X, min);
        if (range(h, SANE_NAME_SCAN_TL_Y, &min, &max)) setNumber(h, SANE_NAME_SCAN_TL_Y, min);
        if (range(h, SANE_NAME_SCAN_BR_X, &min, &max)) setNumber(h, SANE_NAME_SCAN_BR_X, max);
        if (range(h, SANE_NAME_SCAN_BR_Y, &min, &max)) setNumber(h, SANE_NAME_SCAN_BR_Y, max);
        QImage img;
        const SANE_Status st = readPage(h, m_cancel, [this](qreal p) {
            QMetaObject::invokeMethod(this, [this, p] { setProgress(p); });
        }, &img);
        sane_cancel(h);
        QMetaObject::invokeMethod(this, [this, st, img] {
            finish();
            if (st == SANE_STATUS_GOOD) {
                {
                    QMutexLocker lock(&m_imagesLock);
                    m_previewImage = img;
                }
                m_previewUrl = QStringLiteral("image://scan/preview/%1").arg(++m_previewCount);
                Q_EMIT previewChanged();
            } else if (st != SANE_STATUS_CANCELLED) {
                Q_EMIT error(QStringLiteral("Podgląd się nie udał: ") + statusText(st));
            }
        });
    });
}

void Scanner::scan(const QString &source, const QString &mode, int dpi, const QRectF &crop)
{
    if (busy() || m_device.isEmpty())
        return;
    const bool feeder = isFeeder(source);
    run(feeder ? QStringLiteral("Skanowanie strony 1…") : QStringLiteral("Skanowanie…"), [this, source, mode, dpi, crop, feeder] {
        SANE_Handle h = H(m_handle);
        setString(h, SANE_NAME_SCAN_SOURCE, source);
        setString(h, SANE_NAME_SCAN_MODE, mode);
        setNumber(h, SANE_NAME_BIT_DEPTH, 8);
        setNumber(h, SANE_NAME_SCAN_RESOLUTION, dpi);
        // Obszar: kadr z podglądu przeliczony na jednostki skanera (zwykle mm)
        double x0 = 0, x1 = 0, y0 = 0, y1 = 0, dummy = 0;
        if (range(h, SANE_NAME_SCAN_BR_X, &x0, &x1) && range(h, SANE_NAME_SCAN_BR_Y, &y0, &y1)) {
            range(h, SANE_NAME_SCAN_TL_X, &x0, &dummy);
            range(h, SANE_NAME_SCAN_TL_Y, &y0, &dummy);
            const QRectF r = crop.isValid() && !crop.isEmpty() && !feeder ? crop.intersected(QRectF(0, 0, 1, 1)) : QRectF(0, 0, 1, 1);
            // Kolejność: najpierw prawy dolny róg (niektóre sterowniki pilnują tl < br)
            setNumber(h, SANE_NAME_SCAN_BR_X, x0 + (x1 - x0) * r.right());
            setNumber(h, SANE_NAME_SCAN_BR_Y, y0 + (y1 - y0) * r.bottom());
            setNumber(h, SANE_NAME_SCAN_TL_X, x0 + (x1 - x0) * r.left());
            setNumber(h, SANE_NAME_SCAN_TL_Y, y0 + (y1 - y0) * r.top());
        }
        int count = 0;
        SANE_Status st = SANE_STATUS_GOOD;
        for (;;) {
            QImage img;
            st = readPage(h, m_cancel, [this](qreal p) {
                QMetaObject::invokeMethod(this, [this, p] { setProgress(p); });
            }, &img);
            if (st != SANE_STATUS_GOOD)
                break;
            ++count;
            QMetaObject::invokeMethod(this, [this, img, dpi, count, feeder] {
                {
                    QMutexLocker lock(&m_imagesLock);
                    m_pages.append({m_nextId++, img, dpi});
                }
                Q_EMIT pagesChanged();
                if (feeder) {
                    m_task = QStringLiteral("Skanowanie strony %1…").arg(count + 1);
                    setProgress(0);
                    Q_EMIT stateChanged();
                }
            });
            if (!feeder)
                break;
        }
        sane_cancel(h);
        // Pusty podajnik po co najmniej jednej stronie to zwykły koniec
        if (st == SANE_STATUS_NO_DOCS && count > 0)
            st = SANE_STATUS_GOOD;
        QMetaObject::invokeMethod(this, [this, st] {
            finish();
            if (st != SANE_STATUS_GOOD && st != SANE_STATUS_CANCELLED)
                Q_EMIT error(statusText(st));
        });
    });
}

void Scanner::cancel()
{
    m_cancel.storeRelaxed(1);
    if (m_handle)
        sane_cancel(H(m_handle));    // SANE pozwala przerwać z innego wątku
}

void Scanner::removePage(int index)
{
    if (index < 0 || index >= m_pages.size())
        return;
    {
        QMutexLocker lock(&m_imagesLock);
        m_pages.removeAt(index);
    }
    Q_EMIT pagesChanged();
}

void Scanner::movePage(int from, int to)
{
    if (from < 0 || from >= m_pages.size() || to < 0 || to >= m_pages.size() || from == to)
        return;
    {
        QMutexLocker lock(&m_imagesLock);
        m_pages.move(from, to);
    }
    Q_EMIT pagesChanged();
}

void Scanner::rotatePage(int index)
{
    if (index < 0 || index >= m_pages.size())
        return;
    {
        QMutexLocker lock(&m_imagesLock);
        Page &p = m_pages[index];
        p.image = p.image.transformed(QTransform().rotate(90));
        p.id = m_nextId++;           // nowy adres — obrazek wczyta się na nowo
    }
    Q_EMIT pagesChanged();
}

void Scanner::clear()
{
    {
        QMutexLocker lock(&m_imagesLock);
        m_pages.clear();
    }
    Q_EMIT pagesChanged();
}

QString Scanner::folder(bool documents) const
{
    const QString base = QStandardPaths::writableLocation(documents ? QStandardPaths::DocumentsLocation : QStandardPaths::PicturesLocation);
    const QString dir = base + QStringLiteral("/Skany");
    QDir().mkpath(dir);
    return dir;
}

// PDF: jeden plik ze wszystkimi stronami (rozmiar strony z rozdzielczości skanu); JPG/PNG: plik na stronę
void Scanner::save(const QString &format)
{
    if (busy() || m_pages.isEmpty())
        return;
    const QList<Page> pages = m_pages;
    const bool pdf = format == QLatin1String("pdf");
    const QString dir = folder(pdf);
    const QString stamp = QDateTime::currentDateTime().toString(QStringLiteral("yyyy-MM-dd HH.mm.ss"));
    run(QStringLiteral("Zapisywanie…"), [this, pages, pdf, format, dir, stamp] {
        auto unique = [](const QString &base, const QString &ext) {
            QString path = base + QLatin1Char('.') + ext;
            for (int n = 2; QFileInfo::exists(path); ++n)
                path = QStringLiteral("%1 (%2).%3").arg(base).arg(n).arg(ext);
            return path;
        };
        QStringList written;
        bool ok = true;
        if (pdf) {
            const QString path = unique(dir + QStringLiteral("/Skan ") + stamp, QStringLiteral("pdf"));
            QPdfWriter writer(path);
            writer.setCreator(QStringLiteral("Skaner Aster"));
            writer.setTitle(QFileInfo(path).completeBaseName());
            QPainter painter;
            for (int i = 0; i < pages.size(); ++i) {
                const Page &p = pages.at(i);
                const QSizeF mm(p.image.width() * 25.4 / p.dpi, p.image.height() * 25.4 / p.dpi);
                writer.setPageSize(QPageSize(mm, QPageSize::Millimeter, QString(), QPageSize::ExactMatch));
                writer.setPageMargins(QMarginsF(0, 0, 0, 0));
                writer.setResolution(p.dpi);
                if (i == 0) {
                    if (!painter.begin(&writer)) { ok = false; break; }
                } else {
                    writer.newPage();
                }
                painter.drawImage(QRect(QPoint(0, 0), p.image.size()), p.image);
                QMetaObject::invokeMethod(this, [this, i, n = pages.size()] { setProgress(qreal(i + 1) / n); });
            }
            if (painter.isActive())
                painter.end();
            if (ok)
                written << path;
        } else {
            for (int i = 0; i < pages.size() && ok; ++i) {
                const QString base = dir + QStringLiteral("/Skan ") + stamp + (pages.size() > 1 ? QStringLiteral(" (strona %1)").arg(i + 1) : QString());
                const QString path = unique(base, format);
                QImage img = pages.at(i).image;
                img.setDotsPerMeterX(qRound(pages.at(i).dpi / 0.0254));
                img.setDotsPerMeterY(qRound(pages.at(i).dpi / 0.0254));
                ok = img.save(path, nullptr, format == QLatin1String("jpg") ? 90 : -1);
                if (ok)
                    written << path;
                QMetaObject::invokeMethod(this, [this, i, n = pages.size()] { setProgress(qreal(i + 1) / n); });
            }
        }
        QMetaObject::invokeMethod(this, [this, ok, written] {
            finish();
            if (ok && !written.isEmpty()) {
                clear();
                Q_EMIT saved(written.constFirst(), written.size());
            } else {
                Q_EMIT error(QStringLiteral("Nie udało się zapisać skanu."));
            }
        });
    });
}

void Scanner::showInFolder(const QString &path) const
{
    QDBusMessage msg = QDBusMessage::createMethodCall(QStringLiteral("org.freedesktop.FileManager1"),
                                                      QStringLiteral("/org/freedesktop/FileManager1"),
                                                      QStringLiteral("org.freedesktop.FileManager1"),
                                                      QStringLiteral("ShowItems"));
    msg << QStringList{QUrl::fromLocalFile(path).toString()} << QString();
    QDBusConnection::sessionBus().asyncCall(msg);
}

void Scanner::open(const QString &path) const
{
    QDesktopServices::openUrl(QUrl::fromLocalFile(path));
}

QImage Scanner::image(const QString &id) const
{
    QMutexLocker lock(&m_imagesLock);
    if (id.startsWith(QLatin1String("preview/")))
        return m_previewImage;
    if (id.startsWith(QLatin1String("page/"))) {
        const int pid = id.mid(5).toInt();
        for (const Page &p : m_pages)
            if (p.id == pid)
                return p.image;
    }
    return {};
}

QImage ScanImageProvider::requestImage(const QString &id, QSize *size, const QSize &requestedSize)
{
    QImage img = Scanner::s_instance ? Scanner::s_instance->image(id) : QImage();
    if (size)
        *size = img.size();
    if (!img.isNull() && requestedSize.isValid() && (requestedSize.width() < img.width() || requestedSize.height() < img.height()))
        img = img.scaled(requestedSize.width() > 0 ? requestedSize.width() : img.width(),
                         requestedSize.height() > 0 ? requestedSize.height() : img.height(),
                         Qt::KeepAspectRatio, Qt::SmoothTransformation);
    return img;
}
