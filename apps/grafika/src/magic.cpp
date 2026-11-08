#include "magic.h"
#include "art.h"
#include "project.h"
#include "selection.h"

#include <QCoreApplication>
#include <algorithm>
#include <QDir>
#include <QFileInfo>
#include <QMutex>
#include <QNetworkAccessManager>
#include <QNetworkReply>
#include <QPainter>
#include <QPainterPath>
#include <QProcess>
#include <QRandomGenerator>
#include <QRegularExpression>
#include <QTemporaryDir>
#include <QSaveFile>
#include <QStandardPaths>
#include <QThread>
#include <QThreadPool>
#include <QUrl>
#include <cmath>

#ifdef GRAFIKA_ONNX
#include <onnxruntime_cxx_api.h>
#endif

using namespace Qt::StringLiterals;

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
    // Wypełnianie z opisu: DreamShaper 8 Inpainting w jednym pliku GGUF (CreativeML OpenRAIL-M)
    {"sd-inpaint", "sd-inpaint.gguf", "https://github.com/Feejd/aster/releases/download/modele/sd-inpaint.gguf", 1881276000},
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
    if (feature == QLatin1String("generate"))
        return {QStringLiteral("sd-inpaint")};
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

// Ramka elementu ↔ piksele zdjęcia
QTransform frameTransform(const QVariantMap &el, const QSize &img)
{
    return Art::frameTransform(el, img);
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

// Rozmycie pudełkowe (trzy przebiegi ≈ Gauss) obrazu z premultiplikowaną alfą, sumy kroczące — czas nie zależy od promienia
void boxBlurPremul(QImage &img, int r)
{
    if (r < 1)
        return;
    const int w = img.width(), h = img.height();
    QList<QRgb> buf(qMax(w, h));
    auto pass = [&](QRgb *data, int n, int stride) {
        for (int i = 0; i < n; ++i)
            buf[i] = data[i * stride];
        int s[4] = {0, 0, 0, 0};
        auto add = [&](QRgb c, int k) { s[0] += k * qRed(c); s[1] += k * qGreen(c); s[2] += k * qBlue(c); s[3] += k * qAlpha(c); };
        const int win = 2 * r + 1;
        for (int k = -r; k <= r; ++k)
            add(buf[qBound(0, k, n - 1)], 1);
        for (int i = 0; i < n; ++i) {
            data[i * stride] = qRgba(s[0] / win, s[1] / win, s[2] / win, s[3] / win);
            add(buf[qMin(n - 1, i + r + 1)], 1);
            add(buf[qMax(0, i - r)], -1);
        }
    };
    for (int round = 0; round < 3; ++round) {
        for (int y = 0; y < h; ++y)
            pass(reinterpret_cast<QRgb *>(img.scanLine(y)), w, 1);
        QRgb *base = reinterpret_cast<QRgb *>(img.bits());
        const int stride = int(img.bytesPerLine() / 4);
        for (int x = 0; x < w; ++x)
            pass(base + x, h, stride);
    }
}

// Tło rozmyte bez „aureoli”: rozmywa się tylko tło (pierwszy plan ma wagę 0), potem ostry pierwszy plan na wierzch
QImage portraitBlur(const QImage &src, const QImage &mask, int radius)
{
    const QImage img = src.convertToFormat(QImage::Format_ARGB32);
    const QImage soft = filtered(mask, 2, false);
    const QImage grown = filtered(mask, qMax(1, radius / 6), true);      // tło nie bierze kolorów z brzegu postaci
    QImage bg(img.size(), QImage::Format_ARGB32_Premultiplied);
    for (int y = 0; y < img.height(); ++y) {
        const QRgb *in = reinterpret_cast<const QRgb *>(img.constScanLine(y));
        const uchar *g = grown.constScanLine(y);
        QRgb *o = reinterpret_cast<QRgb *>(bg.scanLine(y));
        for (int x = 0; x < img.width(); ++x) {
            const int a = 255 - g[x];
            o[x] = qRgba(qRed(in[x]) * a / 255, qGreen(in[x]) * a / 255, qBlue(in[x]) * a / 255, a);
        }
    }
    boxBlurPremul(bg, radius);
    QImage out(img.size(), QImage::Format_ARGB32);
    for (int y = 0; y < img.height(); ++y) {
        const QRgb *in = reinterpret_cast<const QRgb *>(img.constScanLine(y));
        const QRgb *b = reinterpret_cast<const QRgb *>(bg.constScanLine(y));
        const uchar *m = soft.constScanLine(y);
        QRgb *o = reinterpret_cast<QRgb *>(out.scanLine(y));
        for (int x = 0; x < img.width(); ++x) {
            const int a = qAlpha(b[x]);
            // Pod samym środkiem postaci tło nie ma danych — wtedy zostaje zdjęcie
            const int br = a > 0 ? qMin(255, qRed(b[x]) * 255 / a) : qRed(in[x]);
            const int bgc = a > 0 ? qMin(255, qGreen(b[x]) * 255 / a) : qGreen(in[x]);
            const int bb = a > 0 ? qMin(255, qBlue(b[x]) * 255 / a) : qBlue(in[x]);
            const int k = m[x];
            o[x] = qRgba((qRed(in[x]) * k + br * (255 - k)) / 255, (qGreen(in[x]) * k + bgc * (255 - k)) / 255,
                         (qBlue(in[x]) * k + bb * (255 - k)) / 255, qAlpha(in[x]));
        }
    }
    return out;
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
    req.setHeader(QNetworkRequest::UserAgentHeader, QStringLiteral("AsterPixel/1.0"));
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
        Q_EMIT failed(QStringLiteral("Ta wersja Aster Pixel nie ma narzędzi AI."));
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
                    qWarning("Aster Pixel AI: %s", qPrintable(error));
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
    Q_EMIT failed(QStringLiteral("Ta wersja Aster Pixel nie ma narzędzi AI."));
#endif
}

void Magic::blurBackground(Project *project, const QString &id, qreal strength)
{
#ifdef GRAFIKA_ONNX
    if (!project)
        return;
    const QVariantMap el = project->get(id);
    // Zmiana siły liczy od oryginału, o ile zdjęcie nie zmieniło się od poprzedniego rozmycia
    const QString src = el.value(QStringLiteral("src")).toString();
    const bool again = !el.value(QStringLiteral("bgBlurSrc")).toString().isEmpty() && el.value(QStringLiteral("bgBlurOut")).toString() == src;
    const QString orig = again ? el.value(QStringLiteral("bgBlurSrc")).toString() : src;
    if (strength <= 0) {
        if (again)
            project->change(id, {{QStringLiteral("src"), orig}, {QStringLiteral("bgBlur"), QVariant()},
                                 {QStringLiteral("bgBlurSrc"), QVariant()}, {QStringLiteral("bgBlurOut"), QVariant()}});
        return;
    }
    const QImage img = project->fullImage(orig);
    if (img.isNull())
        return;
    QPointer<Project> pr(project);
    auto models = m_models;
    const QImage cached = m_fgKey == orig ? m_fgMask : QImage();
    run(QStringLiteral("Rozmywam tło…"), featureModels(QStringLiteral("background")), [=, this]() -> std::function<void()> {
        const QImage mask = cached.isNull() ? models->foreground(img) : cached;
        const int radius = qMax(2, qRound(qMax(img.width(), img.height()) * 0.025 * strength));
        const QImage out = portraitBlur(img, mask, radius);
        return [=, this] {
            m_fgKey = orig;
            m_fgMask = mask;
            if (!pr || pr->indexOf(id) < 0)
                return;
            const QString key = pr->addImage(out);
            pr->change(id, {{QStringLiteral("src"), key}, {QStringLiteral("bgBlur"), strength},
                            {QStringLiteral("bgBlurSrc"), orig}, {QStringLiteral("bgBlurOut"), key}});
            Q_EMIT finished(QStringLiteral("Tło rozmyte. Ctrl+Z przywraca ostre zdjęcie."), {id});
        };
    });
#else
    Q_UNUSED(project);
    Q_UNUSED(id);
    Q_UNUSED(strength);
    Q_EMIT failed(QStringLiteral("Ta wersja Aster Pixel nie ma narzędzi AI."));
#endif
}

void Magic::selectSubject(Project *project, const QString &id, const QString &mode)
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
    run(QStringLiteral("Szukam głównego obiektu…"), featureModels(QStringLiteral("background")), [=]() -> std::function<void()> {
        const QImage mask = models->foreground(img);
        return [=] {
            if (pr)
                Selection::instance()->fromLayer(pr, el, mask, mode);
        };
    });
#else
    Q_UNUSED(project);
    Q_UNUSED(id);
    Q_UNUSED(mode);
#endif
}

void Magic::selectObject(Project *project, const QString &id, qreal x, qreal y, const QString &mode)
{
#ifdef GRAFIKA_ONNX
    if (!project)
        return;
    const QVariantMap el = project->get(id);
    const QImage img = project->fullImage(el.value(QStringLiteral("src")).toString());
    if (img.isNull())
        return;
    const QTransform toImage = Art::pageToFrame(el) * Art::frameTransform(el, img.size()).inverted();
    const QPointF at = toImage.map(QPointF(x, y));
    if (!img.rect().contains(at.toPoint()))
        return;
    QPointer<Project> pr(project);
    auto models = m_models;
    run(QStringLiteral("Szukam obiektu…"), featureModels(QStringLiteral("object")), [=]() -> std::function<void()> {
        const QImage mask = models->object(img, {at}, {1.f});
        return [=] {
            if (pr)
                Selection::instance()->fromLayer(pr, el, mask, mode);
        };
    });
#else
    Q_UNUSED(project);
    Q_UNUSED(id);
    Q_UNUSED(x);
    Q_UNUSED(y);
    Q_UNUSED(mode);
#endif
}

void Magic::fillSelection(Project *project, const QString &id)
{
#ifdef GRAFIKA_ONNX
    Selection *sel = Selection::instance();
    if (!project || !sel->active())
        return;
    const QVariantMap el = project->get(id);
    const QImage img = project->fullImage(el.value(QStringLiteral("src")).toString());
    if (img.isNull())
        return;
    const QTransform toImage = Art::pageToFrame(el) * Art::frameTransform(el, img.size()).inverted();
    const QImage mask = sel->mapped(toImage, img.size());
    QPointer<Project> pr(project);
    auto models = m_models;
    run(QStringLiteral("Wypełniam zaznaczenie…"), featureModels(QStringLiteral("erase")), [=, this]() -> std::function<void()> {
        const QImage filled = models->erase(img, mask);
        return [=, this] {
            if (pr && pr->indexOf(id) >= 0)
                pr->change(id, {{QStringLiteral("src"), pr->addImage(filled)}});
            Selection::instance()->clear();
            Q_EMIT finished(QString(), {id});
        };
    });
#else
    Q_UNUSED(project);
    Q_UNUSED(id);
    Q_EMIT failed(QStringLiteral("Ta wersja Aster Pixel nie ma narzędzi AI."));
#endif
}

// ——— Wypełnianie z opisu ———

// Model rozumie opisy po angielsku. Słownik tematów najczęstszych w grafice: rdzeń polskiego słowa → angielskie.
// Reszta zostaje bez zmian, więc można pisać po angielsku albo mieszać.
static QString englishPrompt(const QString &text)
{
    static const QList<std::pair<QString, QString>> stems = {
        {u"czerwon"_s, u"red"_s}, {u"niebiesk"_s, u"blue"_s}, {u"zielon"_s, u"green"_s}, {u"żółt"_s, u"yellow"_s}, {u"czarn"_s, u"black"_s},
        {u"biał"_s, u"white"_s}, {u"różow"_s, u"pink"_s}, {u"fiolet"_s, u"purple"_s}, {u"pomarańcz"_s, u"orange"_s}, {u"złot"_s, u"golden"_s},
        {u"srebrn"_s, u"silver"_s}, {u"brązow"_s, u"brown"_s}, {u"szar"_s, u"gray"_s}, {u"mał"_s, u"small"_s}, {u"duż"_s, u"big"_s},
        {u"star"_s, u"old"_s}, {u"drewnian"_s, u"wooden"_s}, {u"kamienn"_s, u"stone"_s},
        {u"pies"_s, u"dog"_s}, {u"psa"_s, u"dog"_s}, {u"kot"_s, u"cat"_s}, {u"koń"_s, u"horse"_s}, {u"konia"_s, u"horse"_s}, {u"ptak"_s, u"bird"_s},
        {u"motyl"_s, u"butterfly"_s}, {u"ryb"_s, u"fish"_s}, {u"drzew"_s, u"tree"_s}, {u"kwiat"_s, u"flowers"_s}, {u"krzew"_s, u"bush"_s},
        {u"krzak"_s, u"bush"_s}, {u"traw"_s, u"grass"_s}, {u"lasu"_s, u"forest"_s}, {u"las"_s, u"forest"_s}, {u"nieb"_s, u"sky"_s}, {u"chmur"_s, u"clouds"_s},
        {u"słońc"_s, u"sun"_s}, {u"księżyc"_s, u"moon"_s}, {u"gwiazd"_s, u"stars"_s}, {u"tęcz"_s, u"rainbow"_s}, {u"śnieg"_s, u"snow"_s},
        {u"deszcz"_s, u"rain"_s}, {u"mgł"_s, u"fog"_s}, {u"gór"_s, u"mountains"_s}, {u"morz"_s, u"sea"_s}, {u"jezior"_s, u"lake"_s},
        {u"rzek"_s, u"river"_s}, {u"plaż"_s, u"beach"_s}, {u"zamek"_s, u"castle"_s}, {u"zamk"_s, u"castle"_s}, {u"dom"_s, u"house"_s}, {u"most"_s, u"bridge"_s},
        {u"wież"_s, u"tower"_s}, {u"kości"_s, u"church"_s}, {u"ulic"_s, u"street"_s}, {u"drog"_s, u"road"_s},
        {u"samoch"_s, u"car"_s}, {u"rower"_s, u"bicycle"_s}, {u"motocykl"_s, u"motorcycle"_s},
        {u"samolot"_s, u"airplane"_s}, {u"statek"_s, u"ship"_s}, {u"łód"_s, u"boat"_s}, {u"balon"_s, u"balloon"_s}, {u"ławk"_s, u"bench"_s},
        {u"krzesł"_s, u"chair"_s}, {u"stół"_s, u"table"_s}, {u"stoł"_s, u"table"_s}, {u"kobiet"_s, u"woman"_s}, {u"mężczyzn"_s, u"man"_s}, {u"dziec"_s, u"child"_s},
        {u"osob"_s, u"person"_s}, {u"człowiek"_s, u"person"_s}, {u"ludzi"_s, u"people"_s}, {u"okular"_s, u"glasses"_s}, {u"kapelusz"_s, u"hat"_s},
        {u"czapk"_s, u"cap"_s}, {u"kurtk"_s, u"jacket"_s}, {u"sukienk"_s, u"dress"_s}, {u"ognisk"_s, u"campfire"_s}, {u"ogień"_s, u"fire"_s},
    };
    static const QHash<QString, QString> words = {
        {u"na"_s, u"on"_s}, {u"w"_s, u"in"_s}, {u"z"_s, u"with"_s}, {u"ze"_s, u"with"_s}, {u"pod"_s, u"under"_s}, {u"nad"_s, u"above"_s}, {u"i"_s, u"and"_s}, {u"obok"_s, u"next to"_s},
    };
    QStringList out;
    const QStringList parts = text.simplified().split(QLatin1Char(' '), Qt::SkipEmptyParts);
    for (const QString &raw : parts) {
        const QString w = raw.toLower();
        if (words.contains(w)) {
            out.append(words.value(w));
            continue;
        }
        QString hit;
        for (const auto &[stem, en] : stems)
            if (hit.isEmpty() && w.startsWith(stem))
                hit = en;
        out.append(hit.isEmpty() ? raw : hit);
    }
    return out.join(QLatin1Char(' '));
}

static QString generatorPath()
{
    return QStandardPaths::findExecutable(QStringLiteral("aster-pixel-gen"));
}

bool Magic::canGenerate() const
{
    return !generatorPath().isEmpty();
}

// Karta (Vulkan), jeśli jest prawdziwa; programowy Vulkan w maszynie wirtualnej byłby wolniejszy od procesora
static bool realGpu(const QString &engine)
{
    QProcess p;
    p.start(engine, {QStringLiteral("--list-devices")});
    if (!p.waitForFinished(15000))
        return false;
    const QString text = QString::fromUtf8(p.readAllStandardOutput() + p.readAllStandardError()).toLower();
    return text.contains(QLatin1String("vulkan")) && !text.contains(QLatin1String("llvmpipe")) && !text.contains(QLatin1String("lavapipe"));
}

// Biały, czarny albo jednolity obraz to objaw przepełnienia obliczeń na karcie
static bool looksBroken(const QImage &img)
{
    if (img.isNull())
        return true;
    const QImage s = img.scaled(32, 32).convertToFormat(QImage::Format_RGB32);
    const QRgb first = s.pixel(0, 0);
    for (int y = 0; y < 32; ++y)
        for (int x = 0; x < 32; ++x) {
            const QRgb c = s.pixel(x, y);
            if (std::abs(qRed(c) - qRed(first)) + std::abs(qGreen(c) - qGreen(first)) + std::abs(qBlue(c) - qBlue(first)) > 12)
                return false;
        }
    return true;
}

void Magic::generate(Project *project, const QString &prompt)
{
    Selection *sel = Selection::instance();
    if (!project || !sel->active())
        return;
    // Ramka wokół zaznaczenia z zapasem: model musi widzieć otoczenie, żeby dopasować światło i styl
    const QImage &m = sel->mask();
    int x0 = m.width(), y0 = m.height(), x1 = -1, y1 = -1;
    for (int y = 0; y < m.height(); ++y) {
        const uchar *row = m.constScanLine(y);
        for (int x = 0; x < m.width(); ++x)
            if (row[x] > 8) {
                x0 = qMin(x0, x);
                x1 = qMax(x1, x);
                y0 = qMin(y0, y);
                y1 = qMax(y1, y);
            }
    }
    if (x1 < 0)
        return;
    const qreal k = sel->scale();
    const QRectF box(x0 / k, y0 / k, (x1 - x0 + 1) / k, (y1 - y0 + 1) / k);
    const qreal pad = prompt.trimmed().isEmpty() ? qMax(qMax(box.width(), box.height()) * 0.35, 24.0) : 0;
    const QRectF page(0, 0, project->pageWidth(), project->pageHeight());
    startGenerate(project, box.adjusted(-pad, -pad, pad, pad) & page, QImage(), prompt, QString());
}

void Magic::regenerate(Project *project, const QString &id, const QString &prompt)
{
    if (!project)
        return;
    const QVariantMap el = project->get(id);
    const QRectF area(num(el, "x"), num(el, "y"), num(el, "w"), num(el, "h"));
    const QImage mask = Art::maskSource(el.value(QStringLiteral("layerMask")).toString(), project);
    if (!mask.isNull())
        startGenerate(project, area, mask, prompt, id);
}

void Magic::startGenerate(Project *project, const QRectF &area, const QImage &oldMask, const QString &prompt, const QString &replace)
{
    if (generatorPath().isEmpty()) {
        Q_EMIT failed(QStringLiteral("Tej wersji Aster Pixel brakuje silnika wypełniania."));
        return;
    }
    // Trzy przepisy, sprawdzone na zdjęciach. Model trzyma się opisu tylko wtedy, gdy tworzy cały kadr od zera, więc:
    // - obiekt: powstaje na czystym tle, wycina go ISNet, a warstwa ląduje w zaznaczeniu z miękkim cieniem,
    // - duży obszar (nowe tło, niebo): cały kadr z opisu, wtopiony miękką maską,
    // - bez opisu: uzupełnienie z otoczenia, z maską i niską skalą prowadzenia.
    const bool fill = prompt.trimmed().isEmpty();
    const bool scene = !fill && (replace.isEmpty() ? area.width() * area.height() > project->pageWidth() * project->pageHeight() * 0.35
                                                   : !project->get(replace).value(QStringLiteral("cutout")).toBool());
    const bool object = !fill && !scene;

    // Rozmiar pracy: dłuższy bok 512 px, wielokrotności 64 — tak model działa najlepiej
    const qreal scale = 512 / qMax(area.width(), area.height());
    auto snap = [](qreal v) { return qMax(256, int(std::round(v / 64)) * 64); };
    const QSize work(snap(area.width() * scale), snap(area.height() * scale));
    const QTransform toWork = QTransform::fromTranslate(-area.x(), -area.y()) * QTransform::fromScale(work.width() / area.width(), work.height() / area.height());

    // Obraz wejściowy: wszystko, co widać na stronie w tym miejscu, bez warstwy, którą zastępujemy
    QVariantMap doc = project->pageDocument(project->currentPage());
    if (!replace.isEmpty()) {
        QVariantList kept;
        for (const QVariant &v : doc.value(QStringLiteral("elements")).toList())
            if (v.toMap().value(QStringLiteral("id")).toString() != replace)
                kept.append(v);
        doc[QStringLiteral("elements")] = kept;
    }
    QImage input(work, QImage::Format_RGB32);
    input.fill(Qt::white);
    {
        QPainter p(&input);
        p.setRenderHints(QPainter::Antialiasing | QPainter::TextAntialiasing | QPainter::SmoothPixmapTransform);
        p.setTransform(toWork);
        Art::paintPage(&p, doc, project);
    }
    // Maska: białe powstaje od nowa. Osobno miękka maska warstwy, żeby wynik wtopił się w zdjęcie.
    const QImage alpha = oldMask.isNull() ? Selection::instance()->mapped(toWork, work)
                                          : oldMask.convertToFormat(QImage::Format_Grayscale8).scaled(work);
    QImage engineMask(work, QImage::Format_Grayscale8);
    for (int y = 0; y < work.height(); ++y) {
        const uchar *a = alpha.constScanLine(y);
        uchar *o = engineMask.scanLine(y);
        for (int x = 0; x < work.width(); ++x)
            o[x] = !fill || a[x] > 8 ? 255 : 0;
    }
    QImage gray(work, QImage::Format_Grayscale8);
    for (int y = 0; y < work.height(); ++y)
        memcpy(gray.scanLine(y), alpha.constScanLine(y), size_t(work.width()));
    if (oldMask.isNull()) {
        // Lekkie zmiękczenie krawędzi
        QImage soft = gray.convertToFormat(QImage::Format_ARGB32_Premultiplied);
        Art::blur(soft, 3);
        gray = soft.convertToFormat(QImage::Format_Grayscale8);
    }

    const QString english = englishPrompt(prompt);
    const QString full = fill ? QStringLiteral("background, seamless, photo, high detail")
                       : object ? english + QStringLiteral(", full view, centered, product photo, plain white background, high detail")
                                : english + QStringLiteral(", realistic photo, natural light, high detail");
    QPointer<Project> pr(project);
    auto cancel = std::make_shared<std::atomic_bool>(false);
    m_cancel = cancel;
    const QString models = modelsDir();
    const bool forceCpu = m_genCpu;
    auto engineModels = m_models;
    QStringList need = featureModels(QStringLiteral("generate"));
    if (object)
        need += featureModels(QStringLiteral("background"));
    run(QStringLiteral("Generuję…"), need, [=, this]() -> std::function<void()> {
        QMetaObject::invokeMethod(this, [this] {
            m_generating = true;
            m_progress = 0;
            Q_EMIT busyChanged();
            Q_EMIT progressChanged();
        }, Qt::QueuedConnection);
        QTemporaryDir tmp;
        input.save(tmp.filePath(QStringLiteral("in.png")));
        engineMask.save(tmp.filePath(QStringLiteral("mask.png")));
        const QString out = tmp.filePath(QStringLiteral("out.png"));
        const qint64 seed = QRandomGenerator::global()->bounded(1 << 30);
        auto attempt = [&](bool cpu) {
            QFile::remove(out);
            QStringList args{QStringLiteral("-m"), models + QStringLiteral("/sd-inpaint.gguf"),
                             QStringLiteral("-i"), tmp.filePath(QStringLiteral("in.png")), QStringLiteral("--mask"), tmp.filePath(QStringLiteral("mask.png")),
                             QStringLiteral("-p"), full, QStringLiteral("-n"), QStringLiteral("blurry, lowres, deformed, cartoon, text, watermark, cropped"),
                             QStringLiteral("--strength"), QStringLiteral("1"), QStringLiteral("--steps"), QStringLiteral("20"),
                             QStringLiteral("--cfg-scale"), fill ? QStringLiteral("2") : QStringLiteral("7.5"),
                             QStringLiteral("--sampling-method"), fill ? QStringLiteral("euler") : QStringLiteral("euler_a"),
                             QStringLiteral("-W"), QString::number(work.width()), QStringLiteral("-H"), QString::number(work.height()),
                             QStringLiteral("--seed"), QString::number(seed), QStringLiteral("-o"), out};
            if (cpu)
                args << QStringLiteral("--backend") << QStringLiteral("cpu");
            QProcess p;
            p.setProcessChannelMode(QProcess::MergedChannels);
            p.start(generatorPath(), args);
            static const QRegularExpression step(QStringLiteral("(\\d+)/(\\d+)"));
            while (p.state() != QProcess::NotRunning) {
                if (cancel->load()) {
                    p.kill();
                    p.waitForFinished(3000);
                    return QImage();
                }
                p.waitForReadyRead(300);
                const QString text = QString::fromUtf8(p.readAll());
                auto it = step.globalMatch(text);
                int done = -1, total = 0;
                while (it.hasNext()) {
                    const auto hit = it.next();
                    done = hit.captured(1).toInt();
                    total = hit.captured(2).toInt();
                }
                if (done >= 0 && total == 20)
                    QMetaObject::invokeMethod(this, [this, done, total] {
                        m_progress = qreal(done) / total;
                        setStatus(QStringLiteral("Generuję… %1 z %2").arg(done).arg(total));
                        Q_EMIT progressChanged();
                    }, Qt::QueuedConnection);
            }
            return QImage(out).convertToFormat(QImage::Format_ARGB32);
        };
        const bool cpu = forceCpu || !realGpu(generatorPath());
        QImage result = attempt(cpu);
        bool fellBack = false;
        if (!cancel->load() && !cpu && looksBroken(result)) {
            result = attempt(true);
            fellBack = true;
        }
        const bool stopped = cancel->load();
        // Obiekt: tło wycina ISNet; gdyby nic nie znalazł, zostaje maska zaznaczenia
        QImage finalMask = gray;
        bool cut = false;
#ifdef GRAFIKA_ONNX
        if (object && !stopped && !looksBroken(result)) {
            const QImage fg = engineModels->foreground(result).convertToFormat(QImage::Format_ARGB32_Premultiplied).scaled(work, Qt::IgnoreAspectRatio, Qt::SmoothTransformation);
            QImage cutMask(work, QImage::Format_Grayscale8);
            qint64 sum = 0;
            for (int y = 0; y < work.height(); ++y) {
                const QRgb *row = reinterpret_cast<const QRgb *>(fg.constScanLine(y));
                uchar *o = cutMask.scanLine(y);
                for (int x = 0; x < work.width(); ++x) {
                    o[x] = uchar(qAlpha(row[x]));
                    sum += o[x];
                }
            }
            cut = sum > qint64(work.width()) * work.height() * 255 / 50;
            if (cut)
                finalMask = cutMask;
        }
#endif
        return [=, this] {
            m_generating = false;
            m_progress = -1;
            Q_EMIT busyChanged();
            Q_EMIT progressChanged();
            if (fellBack)
                m_genCpu = true;
            if (stopped || !pr)
                return;
            if (looksBroken(result)) {
                Q_EMIT failed(QStringLiteral("Nie udało się wygenerować obrazu. Spróbuj jeszcze raz albo zmień opis."));
                return;
            }
            const QString key = pr->addImage(result);
            QString id = replace;
            if (id.isEmpty()) {
                QVariantMap n{{QStringLiteral("type"), QStringLiteral("image")}, {QStringLiteral("src"), key}, {QStringLiteral("x"), area.x()},
                              {QStringLiteral("y"), area.y()}, {QStringLiteral("w"), area.width()}, {QStringLiteral("h"), area.height()},
                              {QStringLiteral("prompt"), prompt}, {QStringLiteral("generated"), true}};
                if (cut) {
                    // Miękki cień osadza obiekt na zdjęciu
                    const qreal side = qMin(area.width(), area.height());
                    n[QStringLiteral("cutout")] = true;
                    n[QStringLiteral("shadow")] = true;
                    n[QStringLiteral("shadowBlur")] = std::round(side * 0.05);
                    n[QStringLiteral("shadowDist")] = std::round(side * 0.03);
                    n[QStringLiteral("shadowAngle")] = 180.0;
                    n[QStringLiteral("shadowOpacity")] = 0.35;
                }
                id = pr->add(n);
                Selection::instance()->clear();
            } else {
                pr->change(id, {{QStringLiteral("src"), key}, {QStringLiteral("prompt"), prompt}}, false);
            }
            pr->setMaskImage(id, finalMask);
            Q_EMIT finished(QStringLiteral("Gotowe — wynik jest osobną warstwą z maską, a „Nowa wersja” da inny wariant."), {id});
        };
    });
}

void Magic::cancelGenerate()
{
    if (m_cancel)
        m_cancel->store(true);
}

void Magic::heal(Project *project, const QString &id, const QVariantList &points, qreal width)
{
#ifdef GRAFIKA_ONNX
    if (!project || points.isEmpty())
        return;
    const QVariantMap el = project->get(id);
    const QImage img = project->fullImage(el.value(QStringLiteral("src")).toString());
    if (img.isNull())
        return;
    // Punkty strony → piksele zdjęcia
    const QTransform toImage = Art::pageToFrame(el) * Art::frameTransform(el, img.size()).inverted();
    const qreal px = qMax(3.0, width * std::sqrt(std::abs(toImage.determinant())));
    QPainterPath path;
    for (int i = 0; i < points.size(); ++i) {
        const QVariantList pt = points[i].toList();
        const QPointF q = toImage.map(QPointF(pt.value(0).toDouble(), pt.value(1).toDouble()));
        if (i == 0)
            path.moveTo(q);
        else
            path.lineTo(q);
    }
    if (points.size() == 1)
        path.lineTo(path.currentPosition() + QPointF(0.01, 0));
    QImage mask(img.size(), QImage::Format_Alpha8);
    mask.fill(0);
    {
        QPainter p(&mask);
        p.setRenderHint(QPainter::Antialiasing);
        p.setPen(QPen(Qt::white, px, Qt::SolidLine, Qt::RoundCap, Qt::RoundJoin));
        p.drawPath(path);
    }
    QPointer<Project> pr(project);
    auto models = m_models;
    run(QStringLiteral("Naprawiam…"), featureModels(QStringLiteral("erase")), [=, this]() -> std::function<void()> {
        const QImage filled = models->erase(img, mask);
        return [=, this] {
            if (pr && pr->indexOf(id) >= 0)
                pr->change(id, {{QStringLiteral("src"), pr->addImage(filled)}});
            Q_EMIT finished(QString(), {id});
        };
    });
#else
    Q_UNUSED(project);
    Q_UNUSED(id);
    Q_UNUSED(points);
    Q_UNUSED(width);
    Q_EMIT failed(QStringLiteral("Ta wersja Aster Pixel nie ma narzędzi AI."));
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
    if (action == QLatin1String("mask")) {
        // Zaznaczenie jako maska warstwy: zostaje tylko ono, a zdjęcie jest nietknięte — pędzlem można to poprawić
        const QSizeF frame(num(m_el, "w", 100), num(m_el, "h", 100));
        const qreal k = 1024 / qMax(frame.width(), frame.height());
        QImage layer(qMax(8, qRound(frame.width() * k)), qMax(8, qRound(frame.height() * k)), QImage::Format_ARGB32_Premultiplied);
        layer.fill(Qt::black);
        {
            QImage white(m_mask.size(), QImage::Format_ARGB32_Premultiplied);
            for (int y = 0; y < white.height(); ++y) {
                const uchar *in = m_mask.constScanLine(y);
                QRgb *o = reinterpret_cast<QRgb *>(white.scanLine(y));
                for (int x = 0; x < white.width(); ++x)
                    o[x] = qPremultiply(qRgba(255, 255, 255, in[x]));
            }
            QPainter q(&layer);
            q.setRenderHints(QPainter::Antialiasing | QPainter::SmoothPixmapTransform);
            q.scale(k, k);
            q.setTransform(m_toFrame, true);
            q.drawImage(0, 0, white);
        }
        const QString id = m_id;
        QPointer<Project> pr(m_project);
        end();
        pr->setMaskImage(id, layer.convertToFormat(QImage::Format_Grayscale8));
        Q_EMIT finished(QStringLiteral("Zaznaczenie jest maską warstwy — zdjęcie zostało nietknięte."), {id});
        return;
    }
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
