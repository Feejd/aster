#include "magic.h"
#include "project.h"

#include <QCoreApplication>
#include <algorithm>
#include <QDir>
#include <QFileInfo>
#include <QMutex>
#include <QNetworkAccessManager>
#include <QNetworkReply>
#include <QPainter>
#include <QPainterPath>
#include <QSaveFile>
#include <QStandardPaths>
#include <QThread>
#include <QThreadPool>
#include <QUrl>
#include <cmath>

#ifdef GRAFIKA_ONNX
#include <onnxruntime_cxx_api.h>
#endif

namespace {

struct ModelInfo {
    const char *id;
    const char *file;
    const char *url;
    qint64 size;
};

const ModelInfo Models[] = {
    {"isnet", "isnet-general-use.onnx", "https://github.com/danielgatis/rembg/releases/download/v0.0.0/isnet-general-use.onnx", 178648008},
    {"sam-encoder", "mobile-sam-encoder.onnx", "https://huggingface.co/Acly/MobileSAM/resolve/main/mobile_sam_image_encoder.onnx", 28157093},
    {"sam-decoder", "mobile-sam-decoder.onnx", "https://huggingface.co/Acly/MobileSAM/resolve/main/sam_mask_decoder_single.onnx", 16501323},
    {"migan", "migan-pipeline-v2.onnx", "https://huggingface.co/andraniksargsyan/migan/resolve/main/migan_pipeline_v2.onnx", 28079181},
};

const ModelInfo *modelInfo(const QString &id)
{
    for (const ModelInfo &m : Models)
        if (id == QLatin1String(m.id))
            return &m;
    return nullptr;
}

QString modelsDir()
{
    return QStandardPaths::writableLocation(QStandardPaths::GenericDataLocation) + QStringLiteral("/aster-grafika/models");
}

QString modelPath(const QString &id)
{
    const ModelInfo *m = modelInfo(id);
    return m ? modelsDir() + QLatin1Char('/') + QLatin1String(m->file) : QString();
}

bool haveModel(const QString &id)
{
    const ModelInfo *m = modelInfo(id);
    return m && QFileInfo(modelPath(id)).size() == m->size;
}

QStringList featureModels(const QString &feature)
{
    if (feature == QLatin1String("background"))
        return {QStringLiteral("isnet")};
    if (feature == QLatin1String("object"))
        return {QStringLiteral("sam-encoder"), QStringLiteral("sam-decoder")};
    if (feature == QLatin1String("erase") || feature == QLatin1String("move"))
        return {QStringLiteral("migan")};
    return {};
}

qreal num(const QVariantMap &m, const char *key, qreal fallback = 0)
{
    const QVariant v = m.value(QLatin1String(key));
    return v.isValid() ? v.toDouble() : fallback;
}

// ——— Maski (Alpha8, 255 — zaznaczone) ———

QRect maskBounds(const QImage &mask, int threshold = 127)
{
    int x0 = mask.width(), y0 = mask.height(), x1 = -1, y1 = -1;
    for (int y = 0; y < mask.height(); ++y) {
        const uchar *row = mask.constScanLine(y);
        for (int x = 0; x < mask.width(); ++x)
            if (row[x] > threshold) {
                x0 = qMin(x0, x);
                x1 = qMax(x1, x);
                y0 = qMin(y0, y);
                y1 = qMax(y1, y);
            }
    }
    return x1 < 0 ? QRect() : QRect(QPoint(x0, y0), QPoint(x1, y1));
}

// Rozdzielne maksimum (poszerzenie zaznaczenia) albo średnia (zmiękczenie krawędzi) w promieniu r
QImage filtered(const QImage &src, int r, bool maximum)
{
    if (r <= 0)
        return src;
    QImage tmp(src.size(), QImage::Format_Alpha8), out(src.size(), QImage::Format_Alpha8);
    const int w = src.width(), h = src.height();
    for (int y = 0; y < h; ++y) {
        const uchar *in = src.constScanLine(y);
        uchar *o = tmp.scanLine(y);
        for (int x = 0; x < w; ++x) {
            int v = 0, sum = 0, n = 0;
            for (int k = qMax(0, x - r); k <= qMin(w - 1, x + r); ++k) {
                v = qMax(v, int(in[k]));
                sum += in[k];
                ++n;
            }
            o[x] = uchar(maximum ? v : sum / n);
        }
    }
    for (int x = 0; x < w; ++x)
        for (int y = 0; y < h; ++y) {
            int v = 0, sum = 0, n = 0;
            for (int k = qMax(0, y - r); k <= qMin(h - 1, y + r); ++k) {
                const int c = tmp.constScanLine(k)[x];
                v = qMax(v, c);
                sum += c;
                ++n;
            }
            out.scanLine(y)[x] = uchar(maximum ? v : sum / n);
        }
    return out;
}

QImage alpha8(const QImage &gray)
{
    QImage out(gray.size(), QImage::Format_Alpha8);
    const QImage g = gray.convertToFormat(QImage::Format_Grayscale8);
    for (int y = 0; y < g.height(); ++y)
        memcpy(out.scanLine(y), g.constScanLine(y), size_t(g.width()));
    return out;
}

// Przezroczystość zdjęcia ograniczona maską (wycięcie)
QImage withAlpha(const QImage &img, const QImage &mask)
{
    QImage out = img.convertToFormat(QImage::Format_ARGB32);
    for (int y = 0; y < out.height(); ++y) {
        QRgb *row = reinterpret_cast<QRgb *>(out.scanLine(y));
        const uchar *m = mask.constScanLine(y);
        for (int x = 0; x < out.width(); ++x)
            row[x] = qRgba(qRed(row[x]), qGreen(row[x]), qBlue(row[x]), qAlpha(row[x]) * m[x] / 255);
    }
    return out;
}

// Ramka elementu ↔ piksele zdjęcia (tak jak rysuje Art: „cover”, kadr focusX/focusY, powiększenie, odbicie)
QTransform frameTransform(const QVariantMap &el, const QSize &img)
{
    const qreal w = num(el, "w", 100), h = num(el, "h", 100);
    const qreal s = qMax(w / img.width(), h / img.height()) * qMax(1.0, num(el, "zoom", 1));
    const qreal ox = -(img.width() * s - w) * num(el, "focusX", 0.5), oy = -(img.height() * s - h) * num(el, "focusY", 0.5);
    QTransform t = QTransform::fromScale(s, s) * QTransform::fromTranslate(ox, oy);
    if (el.value(QStringLiteral("flipX")).toBool())
        t = t * QTransform(-1, 0, 0, 1, w, 0);
    return t;
}

// Wycięty fragment zdjęcia (tylko część widoczna w kadrze) i jego miejsce na stronie — nowa ramka z tym samym obrotem
struct Piece {
    QImage image;
    QVariantMap geometry;           // x, y, w, h
};

Piece piece(const QImage &img, const QImage &mask, const QVariantMap &el, int threshold = 127)
{
    const QTransform toFrame = frameTransform(el, img.size());
    const qreal w = num(el, "w"), h = num(el, "h");
    const QRectF visible = toFrame.inverted().mapRect(QRectF(0, 0, w, h));
    const QRect bb = maskBounds(mask, threshold) & visible.toAlignedRect() & img.rect();
    if (bb.isEmpty())
        return {};
    const QRectF r = toFrame.mapRect(QRectF(bb));
    const qreal rot = num(el, "rotation") * M_PI / 180;
    const QPointF d = r.center() - QPointF(w / 2, h / 2);
    const QPointF c(num(el, "x") + w / 2 + d.x() * std::cos(rot) - d.y() * std::sin(rot),
                    num(el, "y") + h / 2 + d.x() * std::sin(rot) + d.y() * std::cos(rot));
    return {withAlpha(img.copy(bb), filtered(mask.copy(bb), 1, false)),
            {{QStringLiteral("x"), std::round((c.x() - r.width() / 2) * 10) / 10},
             {QStringLiteral("y"), std::round((c.y() - r.height() / 2) * 10) / 10},
             {QStringLiteral("w"), std::round(r.width() * 10) / 10},
             {QStringLiteral("h"), std::round(r.height() * 10) / 10}}};
}

} // namespace

// ——— Modele ———

struct MagicModels {
#ifdef GRAFIKA_ONNX
    Ort::Env env{ORT_LOGGING_LEVEL_WARNING, "aster-grafika"};
    QMutex lock;                                     // jedno zadanie naraz
    std::unique_ptr<Ort::Session> isnet, encoder, decoder, migan;
    qint64 embKey = 0;                               // zdjęcie, dla którego jest gotowe osadzenie SAM
    std::vector<float> emb;

    Ort::Session &session(std::unique_ptr<Ort::Session> &s, const char *id)
    {
        if (!s) {
            Ort::SessionOptions o;
            o.SetIntraOpNumThreads(qMax(1, QThread::idealThreadCount()));
            o.SetGraphOptimizationLevel(GraphOptimizationLevel::ORT_ENABLE_ALL);
            s = std::make_unique<Ort::Session>(env, QFile::encodeName(modelPath(QLatin1String(id))).constData(), o);
        }
        return *s;
    }

    static Ort::MemoryInfo memory() { return Ort::MemoryInfo::CreateCpu(OrtArenaAllocator, OrtMemTypeDefault); }

    // Maska pierwszego planu (ISNet: 1024×1024, wartości −0,5…0,5)
    QImage foreground(const QImage &img)
    {
        const int N = 1024;
        const QImage rgb = img.convertToFormat(QImage::Format_RGB888).scaled(N, N, Qt::IgnoreAspectRatio, Qt::SmoothTransformation);
        std::vector<float> in(size_t(3) * N * N);
        for (int y = 0; y < N; ++y) {
            const uchar *p = rgb.constScanLine(y);
            for (int x = 0; x < N; ++x)
                for (int c = 0; c < 3; ++c)
                    in[size_t(c) * N * N + size_t(y) * N + x] = p[x * 3 + c] / 255.f - 0.5f;
        }
        const int64_t shape[] = {1, 3, N, N};
        Ort::Value t = Ort::Value::CreateTensor<float>(memory(), in.data(), in.size(), shape, 4);
        Ort::Session &s = session(isnet, "isnet");
        Ort::AllocatorWithDefaultOptions alloc;
        const auto inName = s.GetInputNameAllocated(0, alloc), outName = s.GetOutputNameAllocated(0, alloc);
        const char *ins[] = {inName.get()}, *outs[] = {outName.get()};
        auto out = s.Run(Ort::RunOptions{nullptr}, ins, &t, 1, outs, 1);
        const float *o = out[0].GetTensorData<float>();
        const auto [lo, hi] = std::minmax_element(o, o + size_t(N) * N);
        const float range = qMax(1e-6f, *hi - *lo);
        QImage m(N, N, QImage::Format_Grayscale8);
        for (int y = 0; y < N; ++y) {
            uchar *row = m.scanLine(y);
            for (int x = 0; x < N; ++x)
                row[x] = uchar(qBound(0.f, (o[size_t(y) * N + x] - *lo) / range, 1.f) * 255);
        }
        return alpha8(m.scaled(img.size(), Qt::IgnoreAspectRatio, Qt::SmoothTransformation));
    }

    // Obiekt wskazany punktami (MobileSAM); punkty w pikselach zdjęcia, etykieta 1 — obiekt, 0 — tło
    QImage object(const QImage &img, const QList<QPointF> &points, const QList<float> &labels)
    {
        const qreal k = 1024.0 / qMax(img.width(), img.height());
        if (embKey != img.cacheKey() || emb.empty()) {
            const QImage r = img.convertToFormat(QImage::Format_RGB888)
                                 .scaled(qRound(img.width() * k), qRound(img.height() * k), Qt::IgnoreAspectRatio, Qt::SmoothTransformation);
            std::vector<float> in(size_t(r.width()) * r.height() * 3);
            for (int y = 0; y < r.height(); ++y) {
                const uchar *p = r.constScanLine(y);
                for (int x = 0; x < r.width() * 3; ++x)
                    in[size_t(y) * r.width() * 3 + x] = p[x];
            }
            const int64_t shape[] = {r.height(), r.width(), 3};
            Ort::Value t = Ort::Value::CreateTensor<float>(memory(), in.data(), in.size(), shape, 3);
            const char *ins[] = {"input_image"}, *outs[] = {"image_embeddings"};
            auto out = session(encoder, "sam-encoder").Run(Ort::RunOptions{nullptr}, ins, &t, 1, outs, 1);
            const float *e = out[0].GetTensorData<float>();
            emb.assign(e, e + 256 * 64 * 64);
            embKey = img.cacheKey();
        }
        std::vector<float> coords, lab;
        for (int i = 0; i < points.size(); ++i) {
            coords.push_back(float(points[i].x() * k));
            coords.push_back(float(points[i].y() * k));
            lab.push_back(labels[i]);
        }
        coords.push_back(0);
        coords.push_back(0);
        lab.push_back(-1);
        std::vector<float> maskIn(256 * 256, 0.f), hasMask{0.f}, size{float(img.height()), float(img.width())};
        const int64_t n = int64_t(lab.size());
        const int64_t eShape[] = {1, 256, 64, 64}, cShape[] = {1, n, 2}, lShape[] = {1, n}, mShape[] = {1, 1, 256, 256}, one[] = {1}, two[] = {2};
        std::vector<Ort::Value> ins;
        ins.push_back(Ort::Value::CreateTensor<float>(memory(), emb.data(), emb.size(), eShape, 4));
        ins.push_back(Ort::Value::CreateTensor<float>(memory(), coords.data(), coords.size(), cShape, 3));
        ins.push_back(Ort::Value::CreateTensor<float>(memory(), lab.data(), lab.size(), lShape, 2));
        ins.push_back(Ort::Value::CreateTensor<float>(memory(), maskIn.data(), maskIn.size(), mShape, 4));
        ins.push_back(Ort::Value::CreateTensor<float>(memory(), hasMask.data(), 1, one, 1));
        ins.push_back(Ort::Value::CreateTensor<float>(memory(), size.data(), 2, two, 1));
        const char *names[] = {"image_embeddings", "point_coords", "point_labels", "mask_input", "has_mask_input", "orig_im_size"};
        const char *outs[] = {"masks"};
        auto out = session(decoder, "sam-decoder").Run(Ort::RunOptions{nullptr}, names, ins.data(), ins.size(), outs, 1);
        const float *m = out[0].GetTensorData<float>();
        QImage mask(img.size(), QImage::Format_Alpha8);
        for (int y = 0; y < img.height(); ++y) {
            uchar *row = mask.scanLine(y);
            for (int x = 0; x < img.width(); ++x)
                row[x] = m[size_t(y) * img.width() + x] > 0 ? 255 : 0;
        }
        return mask;
    }

    // Usunięcie zaznaczonego i uzupełnienie tła (MI-GAN) — tylko w okolicy zaznaczenia, najwyżej 1024 px
    QImage erase(const QImage &img, const QImage &mask)
    {
        const QRect bb = maskBounds(mask);
        if (bb.isEmpty())
            return img;
        const int margin = qMax(32, qMax(bb.width(), bb.height()) / 2);
        const QRect crop = bb.adjusted(-margin, -margin, margin, margin) & img.rect();
        const QImage grown = filtered(mask.copy(crop), qMax(3, qMax(crop.width(), crop.height()) / 160), true);
        const qreal f = qMin(1.0, 1024.0 / qMax(crop.width(), crop.height()));
        const QSize work(qMax(8, qRound(crop.width() * f)), qMax(8, qRound(crop.height() * f)));
        const QImage part = img.copy(crop).convertToFormat(QImage::Format_RGB888).scaled(work, Qt::IgnoreAspectRatio, Qt::SmoothTransformation);
        const QImage pm = grown.scaled(work, Qt::IgnoreAspectRatio, Qt::SmoothTransformation);
        const int W = work.width(), H = work.height();
        std::vector<uint8_t> in(size_t(3) * W * H), keep(size_t(W) * H);
        for (int y = 0; y < H; ++y) {
            const uchar *p = part.constScanLine(y), *m = pm.constScanLine(y);
            for (int x = 0; x < W; ++x) {
                for (int c = 0; c < 3; ++c)
                    in[size_t(c) * W * H + size_t(y) * W + x] = p[x * 3 + c];
                keep[size_t(y) * W + x] = m[x] > 20 ? 0 : 255;
            }
        }
        const int64_t iShape[] = {1, 3, H, W}, mShape[] = {1, 1, H, W};
        std::vector<Ort::Value> ins;
        ins.push_back(Ort::Value::CreateTensor<uint8_t>(memory(), in.data(), in.size(), iShape, 4));
        ins.push_back(Ort::Value::CreateTensor<uint8_t>(memory(), keep.data(), keep.size(), mShape, 4));
        const char *names[] = {"image", "mask"}, *outs[] = {"result"};
        auto out = session(migan, "migan").Run(Ort::RunOptions{nullptr}, names, ins.data(), 2, outs, 1);
        const uint8_t *o = out[0].GetTensorData<uint8_t>();
        QImage filled(W, H, QImage::Format_RGB888);
        for (int y = 0; y < H; ++y) {
            uchar *row = filled.scanLine(y);
            for (int x = 0; x < W; ++x)
                for (int c = 0; c < 3; ++c)
                    row[x * 3 + c] = o[size_t(c) * W * H + size_t(y) * W + x];
        }
        const QImage back = filled.scaled(crop.size(), Qt::IgnoreAspectRatio, Qt::SmoothTransformation).convertToFormat(QImage::Format_ARGB32);
        const QImage soft = filtered(grown, 2, false);
        QImage result = img.convertToFormat(QImage::Format_ARGB32);
        for (int y = 0; y < crop.height(); ++y) {
            QRgb *dst = reinterpret_cast<QRgb *>(result.scanLine(crop.y() + y)) + crop.x();
            const QRgb *src = reinterpret_cast<const QRgb *>(back.constScanLine(y));
            const uchar *a = soft.constScanLine(y);
            for (int x = 0; x < crop.width(); ++x) {
                const int k = a[x];
                if (k == 0)
                    continue;
                const QRgb d = dst[x], s = src[x];
                dst[x] = qRgba((qRed(s) * k + qRed(d) * (255 - k)) / 255, (qGreen(s) * k + qGreen(d) * (255 - k)) / 255,
                               (qBlue(s) * k + qBlue(d) * (255 - k)) / 255, qAlpha(d));
            }
        }
        return result;
    }
#endif
};

// ——— Magic ———

Magic::Magic(QObject *parent)
    : QObject(parent)
    , m_net(new QNetworkAccessManager(this))
    , m_models(std::make_shared<MagicModels>())
{
}

Magic::~Magic() = default;

bool Magic::available() const
{
#ifdef GRAFIKA_ONNX
    return true;
#else
    return false;
#endif
}

int Magic::downloadMB(const QString &feature) const
{
    qint64 bytes = 0;
    for (const QString &id : featureModels(feature))
        if (!haveModel(id))
            bytes += modelInfo(id)->size;
    return int((bytes + 999999) / 1000000);
}

void Magic::setStatus(const QString &status)
{
    if (status == m_status)
        return;
    m_status = status;
    Q_EMIT busyChanged();
}

void Magic::ensureModels(const QStringList &models, std::function<void()> then)
{
    QStringList missing;
    for (const QString &id : models)
        if (!haveModel(id))
            missing.append(id);
    if (missing.isEmpty()) {
        then();
        return;
    }
    const ModelInfo *m = modelInfo(missing.constFirst());
    QDir().mkpath(modelsDir());
    setStatus(QStringLiteral("Pobieram model AI (%1 MB, tylko za pierwszym razem)…").arg((m->size + 999999) / 1000000));
    m_progress = 0;
    Q_EMIT progressChanged();
    QNetworkRequest req{QUrl(QLatin1String(m->url))};
    req.setHeader(QNetworkRequest::UserAgentHeader, QStringLiteral("AsterGrafika/1.0"));
    req.setAttribute(QNetworkRequest::RedirectPolicyAttribute, QNetworkRequest::NoLessSafeRedirectPolicy);
    QNetworkReply *reply = m_net->get(req);
    auto file = std::make_shared<QSaveFile>(modelPath(QLatin1String(m->id)));
    file->open(QIODevice::WriteOnly);
    connect(reply, &QNetworkReply::readyRead, this, [reply, file] { file->write(reply->readAll()); });
    connect(reply, &QNetworkReply::downloadProgress, this, [this, m](qint64 got, qint64) {
        m_progress = qreal(got) / m->size;
        Q_EMIT progressChanged();
    });
    connect(reply, &QNetworkReply::finished, this, [this, reply, file, m, models, then] {
        reply->deleteLater();
        file->write(reply->readAll());
        const bool ok = reply->error() == QNetworkReply::NoError && file->size() == m->size && file->commit();
        if (!ok)
            file->cancelWriting();
        m_progress = -1;
        Q_EMIT progressChanged();
        setStatus(QString());
        if (!ok) {
            Q_EMIT failed(QStringLiteral("Nie udało się pobrać modelu AI. Sprawdź połączenie z internetem i spróbuj jeszcze raz."));
            return;
        }
        ensureModels(models, then);
    });
}

void Magic::run(const QString &status, const QStringList &models, std::function<std::function<void()>()> work)
{
    if (busy())
        return;
    if (!available()) {
        Q_EMIT failed(QStringLiteral("Ta wersja Grafiki nie ma narzędzi AI."));
        return;
    }
    ensureModels(models, [this, status, work] {
        setStatus(status);
        auto models = m_models;
        QThreadPool::globalInstance()->start([this, models, work] {
            std::function<void()> done;
            QString error;
            try {
#ifdef GRAFIKA_ONNX
                QMutexLocker lock(&models->lock);
#endif
                done = work();
            } catch (const std::exception &e) {
                error = QString::fromLocal8Bit(e.what());
            }
            QMetaObject::invokeMethod(this, [this, done, error] {
                setStatus(QString());
                if (!error.isEmpty()) {
                    qWarning("Grafika AI: %s", qPrintable(error));
                    Q_EMIT failed(QStringLiteral("Nie udało się — za mało pamięci albo uszkodzony model. Spróbuj jeszcze raz."));
                } else if (done) {
                    done();
                }
            }, Qt::QueuedConnection);
        });
    });
}

void Magic::removeBackground(Project *project, const QString &id)
{
#ifdef GRAFIKA_ONNX
    if (!project)
        return;
    const QVariantMap el = project->get(id);
    const QImage img = project->fullImage(el.value(QStringLiteral("src")).toString());
    if (img.isNull())
        return;
    QPointer<Project> pr(project);
    auto models = m_models;
    run(QStringLiteral("Usuwam tło…"), featureModels(QStringLiteral("background")), [this, models, img, el, pr, id]() -> std::function<void()> {
        // Ramka przycięta do obiektu — bez pustych pasów dookoła
        QImage mask = models->foreground(img);
        const Piece cut = piece(img, mask, el, 12);
        return [this, cut, pr, id] {
            if (!pr || pr->indexOf(id) < 0 || cut.image.isNull())
                return;
            QVariantMap patch = cut.geometry;
            patch[QStringLiteral("src")] = pr->addImage(cut.image);
            for (const char *k : {"removeBg", "bgTolerance", "focusX", "focusY", "zoom"})
                patch[QLatin1String(k)] = QVariant();
            pr->change(id, patch);
            Q_EMIT finished(QStringLiteral("Tło usunięte. Ctrl+Z przywraca zdjęcie z tłem."), {id});
        };
    });
#else
    Q_UNUSED(project);
    Q_UNUSED(id);
    Q_EMIT failed(QStringLiteral("Ta wersja Grafiki nie ma narzędzi AI."));
#endif
}

// ——— Tryb narzędzi AI: zaznaczanie i działania ———

bool Magic::loadElement()
{
    if (!m_project)
        return false;
    m_el = m_project->get(m_id);
    m_src = m_el.value(QStringLiteral("src")).toString();
    m_img = m_project->fullImage(m_src);
    if (m_img.isNull())
        return false;
    m_toFrame = frameTransform(m_el, m_img.size());
    return true;
}

void Magic::begin(Project *project, const QString &id)
{
    m_project = project;
    m_id = id;
    m_history.clear();
    if (!loadElement()) {
        m_id.clear();
        Q_EMIT maskChanged();
        return;
    }
    m_mask = QImage(m_img.size(), QImage::Format_Alpha8);
    m_mask.fill(0);
    setMask(m_mask, false);
}

void Magic::end()
{
    m_id.clear();
    m_img = QImage();
    m_mask = QImage();
    m_history.clear();
    m_hasMask = false;
    if (!m_maskUrl.isEmpty())
        QFile::remove(QUrl(m_maskUrl).toLocalFile());
    m_maskUrl.clear();
    Q_EMIT maskChanged();
}

void Magic::setMask(const QImage &mask, bool remember)
{
    if (remember && !m_mask.isNull()) {
        m_history.append(m_mask);
        if (m_history.size() > 20)
            m_history.removeFirst();
    }
    m_mask = mask;
    publishMask();
}

// Podgląd zaznaczenia w ramce elementu (półprzezroczysty kolor), do 900 px
void Magic::publishMask()
{
    const qreal w = num(m_el, "w", 100), h = num(m_el, "h", 100);
    const qreal k = qMin(1.0, 900 / qMax(w, h));
    QImage ov(qMax(1, qCeil(w * k)), qMax(1, qCeil(h * k)), QImage::Format_ARGB32_Premultiplied);
    ov.fill(Qt::transparent);
    {
        QPainter p(&ov);
        p.setRenderHint(QPainter::SmoothPixmapTransform);
        p.setTransform(m_toFrame * QTransform::fromScale(k, k));
        p.drawImage(0, 0, m_mask);
        p.resetTransform();
        p.setCompositionMode(QPainter::CompositionMode_SourceIn);
        p.fillRect(ov.rect(), QColor(255, 61, 154, 120));
    }
    m_hasMask = !maskBounds(m_mask).isEmpty();
    const QString dir = QStandardPaths::writableLocation(QStandardPaths::CacheLocation);
    QDir().mkpath(dir);
    if (!m_maskUrl.isEmpty())
        QFile::remove(QUrl(m_maskUrl).toLocalFile());
    const QString file = dir + QStringLiteral("/zaznaczenie-%1.png").arg(++m_maskSerial);
    ov.save(file);
    m_maskUrl = QUrl::fromLocalFile(file).toString();
    Q_EMIT maskChanged();
}

void Magic::addStroke(const QVariantList &points, qreal width, bool lasso, bool subtract)
{
    if (m_id.isEmpty() || points.isEmpty())
        return;
    QPainterPath path;
    for (int i = 0; i < points.size(); ++i) {
        const QVariantList pt = points[i].toList();
        const QPointF q(pt.value(0).toDouble(), pt.value(1).toDouble());
        if (i == 0)
            path.moveTo(q);
        else
            path.lineTo(q);
    }
    QImage mask = m_mask.copy();
    {
        QPainter p(&mask);
        p.setRenderHint(QPainter::Antialiasing);
        p.setTransform(m_toFrame.inverted());
        if (subtract)
            p.setCompositionMode(QPainter::CompositionMode_DestinationOut);
        if (lasso) {
            path.closeSubpath();
            p.setPen(Qt::NoPen);
            p.setBrush(Qt::white);
            p.drawPath(path);
        } else {
            QPen pen(Qt::white, width, Qt::SolidLine, Qt::RoundCap, Qt::RoundJoin);
            p.setPen(pen);
            p.setBrush(Qt::NoBrush);
            if (points.size() == 1)
                p.drawPoint(path.elementAt(0));
            else
                p.drawPath(path);
        }
    }
    setMask(mask);
}

void Magic::addObject(qreal x, qreal y, bool subtract)
{
#ifdef GRAFIKA_ONNX
    if (m_id.isEmpty())
        return;
    const QPointF at = m_toFrame.inverted().map(QPointF(x, y));
    if (!m_img.rect().contains(at.toPoint()))
        return;
    const QImage img = m_img;
    auto models = m_models;
    run(QStringLiteral("Szukam obiektu…"), featureModels(QStringLiteral("object")), [this, models, img, at, subtract]() -> std::function<void()> {
        const QImage obj = models->object(img, {at}, {1.f});
        return [this, obj, subtract, key = img.cacheKey()] {
            if (m_img.cacheKey() != key)
                return;
            QImage mask = m_mask.copy();
            QPainter p(&mask);
            p.setCompositionMode(subtract ? QPainter::CompositionMode_DestinationOut : QPainter::CompositionMode_SourceOver);
            p.drawImage(0, 0, obj);
            p.end();
            setMask(mask);
        };
    });
#else
    Q_UNUSED(x);
    Q_UNUSED(y);
    Q_UNUSED(subtract);
#endif
}

void Magic::clearMask()
{
    if (m_mask.isNull())
        return;
    QImage mask(m_mask.size(), QImage::Format_Alpha8);
    mask.fill(0);
    setMask(mask);
}

void Magic::undoMask()
{
    if (m_history.isEmpty())
        return;
    m_mask = m_history.takeLast();
    publishMask();
}

void Magic::apply(const QString &action)
{
#ifdef GRAFIKA_ONNX
    if (m_id.isEmpty() || !m_project || !m_hasMask)
        return;
    const QImage img = m_img, mask = m_mask;
    const QVariantMap el = m_el;
    QPointer<Project> pr(m_project);
    const QString id = m_id;
    const bool cut = action != QLatin1String("erase"), erase = action != QLatin1String("extract");
    auto models = m_models;
    const QString status = action == QLatin1String("erase") ? QStringLiteral("Usuwam zaznaczone…")
                         : action == QLatin1String("move") ? QStringLiteral("Wyodrębniam i uzupełniam tło…") : QStringLiteral("Wyodrębniam…");
    run(status, erase ? featureModels(QStringLiteral("erase")) : QStringList(), [=, this]() -> std::function<void()> {
        // Wycięty obiekt: tylko część widoczna w kadrze, krawędź lekko zmiękczona
        const Piece part = cut ? piece(img, mask, el) : Piece();
        const QImage filled = erase ? models->erase(img, mask) : QImage();
        return [=, this] {
            if (!pr || pr->indexOf(id) < 0)
                return;
            QStringList ids;
            if (erase) {
                pr->change(id, {{QStringLiteral("src"), pr->addImage(filled)}}, false);
                ids.append(id);
            }
            if (!part.image.isNull()) {
                // Nowy element dokładnie w miejscu obiektu
                QVariantMap n = part.geometry;
                n[QStringLiteral("type")] = QStringLiteral("image");
                n[QStringLiteral("src")] = pr->addImage(part.image);
                for (const char *k : {"rotation", "flipX", "opacity", "filter", "brightness", "contrast", "saturation", "duo1", "duo2"})
                    if (el.contains(QLatin1String(k)))
                        n[QLatin1String(k)] = el.value(QLatin1String(k));
                ids = QStringList{pr->add(n)};
            } else {
                pr->commit();
            }
            if (cut) {
                end();
                Q_EMIT finished(part.image.isNull() ? QStringLiteral("Zaznaczenie jest poza widocznym kadrem zdjęcia.")
                                               : QStringLiteral("Wyodrębniony obiekt jest nowym elementem — możesz go przesuwać."), ids);
            } else {
                // Gumka: zostajemy w trybie, można usuwać dalej
                loadElement();
                m_history.clear();
                m_mask = QImage(m_img.size(), QImage::Format_Alpha8);
                m_mask.fill(0);
                publishMask();
                Q_EMIT finished(QString(), ids);
            }
        };
    });
#else
    Q_UNUSED(action);
#endif
}
