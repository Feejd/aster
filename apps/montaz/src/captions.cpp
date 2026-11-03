#include "captions.h"
#include "project.h"

#include <QDir>
#include <QFile>
#include <QFileInfo>
#include <QNetworkAccessManager>
#include <QNetworkReply>
#include <QRegularExpression>
#include <QStandardPaths>
#include <QThread>

#include <mlt++/Mlt.h>

#ifdef HAVE_WHISPER
#include <whisper.h>
#endif

namespace {

struct ModelInfo { const char *id, *name, *detail; };
const ModelInfo modelTable[] = {
    {"base", "Szybki", "ok. 150 MB — dobry do wyraźnej mowy"},
    {"small", "Dokładny", "ok. 490 MB — lepiej rozumie polski, wolniejszy"},
};

// Zdania, które Whisper „słyszy” w ciszy i szumie (wyuczone z napisów filmowych)
bool hallucination(const QString &text)
{
    static const QRegularExpression re(QStringLiteral("amara\\.org|napisy (stworzone|wykonane|przygotowane)|dziękuję za (uwagę|obejrzenie)|"
                                                      "subskrybuj|thanks for watching|subtitles by"),
                                       QRegularExpression::CaseInsensitiveOption);
    return re.match(text).hasMatch();
}

} // namespace

Captions::Captions(QObject *parent)
    : QObject(parent)
{
}

Captions::~Captions()
{
    m_abort = 1;
    if (m_reply)
        m_reply->abort();
}

bool Captions::available() const
{
#ifdef HAVE_WHISPER
    return true;
#else
    return false;
#endif
}

QString Captions::modelsDir() const
{
    const QString dir = QStandardPaths::writableLocation(QStandardPaths::AppDataLocation) + QStringLiteral("/models");
    QDir().mkpath(dir);
    return dir;
}

QString Captions::modelPath(const QString &model) const
{
    return modelsDir() + QStringLiteral("/ggml-%1.bin").arg(model);
}

QVariantList Captions::models() const
{
    QVariantList l;
    for (const ModelInfo &m : modelTable)
        l << QVariantMap{{QStringLiteral("id"), QString::fromLatin1(m.id)}, {QStringLiteral("name"), QString::fromUtf8(m.name)},
                         {QStringLiteral("detail"), QString::fromUtf8(m.detail)},
                         {QStringLiteral("ready"), QFileInfo::exists(modelPath(QString::fromLatin1(m.id)))}};
    return l;
}

void Captions::setState(const QString &state, const QString &error)
{
    m_state = state;
    m_error = error;
    Q_EMIT stateChanged();
}

void Captions::reset()
{
    if (m_state == QLatin1String("downloading") || m_state == QLatin1String("listening"))
        return;
    m_progress = 0;
    m_added = 0;
    setState(QString());
    Q_EMIT progressChanged();
}

void Captions::start(const QString &model, const QString &language, const QString &style, const QString &anim)
{
    m_anim = anim;
    if (!available() || m_state == QLatin1String("downloading") || m_state == QLatin1String("listening"))
        return;
    m_model = model;
    m_language = language;
    m_style = style;
    m_abort = 0;
    m_added = 0;
    if (QFileInfo::exists(modelPath(model)))
        transcribe();
    else
        download(model);
}

void Captions::cancel()
{
    m_abort = 1;
    if (m_reply)
        m_reply->abort();
}

// ——— Pobieranie modelu ———

void Captions::download(const QString &model)
{
    if (!m_net)
        m_net = new QNetworkAccessManager(this);
    const QString path = modelPath(model);
    m_file = new QFile(path + QStringLiteral(".part"), this);
    if (!m_file->open(QIODevice::WriteOnly)) {
        setState(QString(), QStringLiteral("Nie można zapisać modelu w %1").arg(modelsDir()));
        return;
    }
    QNetworkRequest req(QUrl(QStringLiteral("https://huggingface.co/ggerganov/whisper.cpp/resolve/main/ggml-%1.bin").arg(model)));
    req.setAttribute(QNetworkRequest::RedirectPolicyAttribute, QNetworkRequest::NoLessSafeRedirectPolicy);
    m_reply = m_net->get(req);
    m_progress = 0;
    setState(QStringLiteral("downloading"));
    Q_EMIT progressChanged();
    connect(m_reply, &QNetworkReply::readyRead, this, [this] { m_file->write(m_reply->readAll()); });
    connect(m_reply, &QNetworkReply::downloadProgress, this, [this](qint64 got, qint64 total) {
        m_progress = total > 0 ? double(got) / total : 0;
        Q_EMIT progressChanged();
    });
    connect(m_reply, &QNetworkReply::finished, this, [this, path] {
        if (m_reply->isOpen())
            m_file->write(m_reply->readAll());
        m_file->close();
        const bool ok = m_reply->error() == QNetworkReply::NoError && m_file->size() > 1000000;
        const QString err = m_reply->error() == QNetworkReply::OperationCanceledError ? QString()
                          : QStringLiteral("Nie udało się pobrać modelu. Sprawdź połączenie z internetem i spróbuj ponownie.");
        m_reply->deleteLater();
        if (ok) {
            QFile::remove(path);
            m_file->rename(path);
        } else {
            m_file->remove();
        }
        m_file->deleteLater();
        m_file = nullptr;
        Q_EMIT modelsChanged();
        if (ok && !m_abort)
            transcribe();
        else
            setState(QString(), ok ? QString() : err);
    });
}

// ——— Rozpoznawanie mowy ———

void Captions::transcribe()
{
#ifdef HAVE_WHISPER
    struct Piece { QString path; int in, length, start; double speed; };
    QList<Piece> pieces;
    for (const QVariant &v : Project::instance()->clips()) {
        const QVariantMap c = v.toMap();
        if (c.value(QStringLiteral("kind")).toString() != QLatin1String("video") || c.value(QStringLiteral("volume")).toDouble() <= 0.01)
            continue;
        pieces << Piece{c.value(QStringLiteral("path")).toString(), c.value(QStringLiteral("in")).toInt(), c.value(QStringLiteral("length")).toInt(),
                        c.value(QStringLiteral("start")).toInt(), c.value(QStringLiteral("speed")).toDouble()};
    }
    if (pieces.isEmpty()) {
        setState(QString(), QStringLiteral("Na osi czasu nie ma filmów z dźwiękiem."));
        return;
    }
    m_progress = 0;
    setState(QStringLiteral("listening"));
    Q_EMIT progressChanged();

    const QString model = modelPath(m_model), language = m_language;
    QThread *t = QThread::create([this, pieces, model, language] {
        QVariantList found;
        QString error;
        whisper_context_params cparams = whisper_context_default_params();
        cparams.use_gpu = false;
        whisper_context *ctx = whisper_init_from_file_with_params(model.toUtf8().constData(), cparams);
        if (!ctx) {
            QFile::remove(model);          // uszkodzony plik — przy następnej próbie pobierze się od nowa
            error = QStringLiteral("Nie udało się wczytać modelu mowy.");
        }
        for (int i = 0; ctx && i < pieces.size() && !m_abort; ++i) {
            const Piece &p = pieces.at(i);
            // Dźwięk klipu: 16 kHz, mono, z uwzględnieniem prędkości (czasy od razu w czasie osi)
            std::vector<float> pcm;
            {
                Mlt::Profile profile;
                profile.set_width(64);
                profile.set_height(36);
                profile.set_frame_rate(Project::Fps, 1);
                profile.set_explicit(1);
                const bool warp = !qFuzzyCompare(p.speed, 1.0);
                const QByteArray res = warp ? (QByteArray::number(p.speed, 'g', 8) + ':' + p.path.toUtf8()) : p.path.toUtf8();
                Mlt::Producer prod(profile, warp ? "timewarp" : nullptr, res.constData());
                if (!prod.is_valid())
                    continue;
                prod.set("video_index", -1);
                prod.seek(qRound(p.in / (warp ? p.speed : 1.0)));
                float peak = 0;
                for (int f = 0; f < p.length && !m_abort; ++f) {
                    std::unique_ptr<Mlt::Frame> frame(prod.get_frame());
                    if (!frame)
                        break;
                    mlt_audio_format fmt = mlt_audio_f32le;
                    int freq = 16000, channels = 1;
                    int samples = mlt_audio_calculate_frame_samples(Project::Fps, freq, f);
                    const auto *data = static_cast<const float *>(frame->get_audio(fmt, freq, channels, samples));
                    for (int k = 0; data && k < samples * channels; k += channels) {
                        pcm.push_back(data[k]);
                        peak = qMax(peak, qAbs(data[k]));
                    }
                    if (f % 30 == 0)
                        QMetaObject::invokeMethod(this, [this, i, f, n = pieces.size(), len = p.length] {
                            m_progress = (i + 0.15 * f / qMax(1, len)) / n;
                            Q_EMIT progressChanged();
                        }, Qt::QueuedConnection);
                }
                if (peak < 0.02)            // cisza — nie ma czego słuchać (i Whisper by coś „usłyszał”)
                    continue;
            }
            whisper_full_params wp = whisper_full_default_params(WHISPER_SAMPLING_GREEDY);
            wp.n_threads = qBound(1, QThread::idealThreadCount(), 8);
            wp.language = language == QLatin1String("auto") ? "auto" : (language == QLatin1String("en") ? "en" : "pl");
            wp.translate = false;
            wp.print_progress = false;
            wp.print_realtime = false;
            wp.print_timestamps = false;
            wp.token_timestamps = true;
            wp.max_len = 34;                // krótkie napisy, jak na TikToku
            wp.split_on_word = true;
            wp.suppress_blank = true;
            wp.no_context = true;
            struct Ctx { Captions *self; int i, n; };
            Ctx cbData{this, i, int(pieces.size())};
            wp.progress_callback = [](whisper_context *, whisper_state *, int progress, void *data) {
                auto *c = static_cast<Ctx *>(data);
                QMetaObject::invokeMethod(c->self, [self = c->self, i = c->i, n = c->n, progress] {
                    self->m_progress = (i + 0.15 + 0.85 * progress / 100.0) / n;
                    Q_EMIT self->progressChanged();
                }, Qt::QueuedConnection);
            };
            wp.progress_callback_user_data = &cbData;
            wp.abort_callback = [](void *data) { return bool(static_cast<Captions *>(data)->m_abort.loadRelaxed()); };
            wp.abort_callback_user_data = this;
            if (whisper_full(ctx, wp, pcm.data(), int(pcm.size())) != 0)
                continue;
            const int n = whisper_full_n_segments(ctx);
            for (int s = 0; s < n; ++s) {
                const QString text = QString::fromUtf8(whisper_full_get_segment_text(ctx, s)).trimmed();
                if (text.isEmpty() || hallucination(text) || text.startsWith(QLatin1Char('[')) || text.startsWith(QLatin1Char('(')))
                    continue;
                // Czas w setnych sekundy → klatki osi
                const int a = p.start + qRound(whisper_full_get_segment_t0(ctx, s) * Project::Fps / 100.0);
                const int b = p.start + qRound(whisper_full_get_segment_t1(ctx, s) * Project::Fps / 100.0);
                // Słowa z czasami (do napisów karaoke): tokeny sklejane w słowa, nowe słowo zaczyna się od spacji.
                // Bajty UTF-8 skleja się przed dekodowaniem — polska litera bywa rozdzielona między tokeny.
                QVariantList words;
                QByteArray cur;
                int ws = -1, we = -1;
                auto push = [&] {
                    const QString w = QString::fromUtf8(cur).trimmed();
                    if (!w.isEmpty())
                        words << QVariantMap{{QStringLiteral("text"), w},
                                             {QStringLiteral("start"), p.start + qRound(ws * Project::Fps / 100.0)},
                                             {QStringLiteral("end"), p.start + qRound(we * Project::Fps / 100.0)}};
                    cur.clear();
                    ws = -1;
                };
                const int nt = whisper_full_n_tokens(ctx, s);
                for (int k = 0; k < nt; ++k) {
                    const whisper_token_data d = whisper_full_get_token_data(ctx, s, k);
                    if (d.id >= whisper_token_eot(ctx))
                        continue;           // znaczniki specjalne ([_BEG_], czasy itp.)
                    const QByteArray piece(whisper_full_get_token_text(ctx, s, k));
                    if (piece.startsWith(' ') && !cur.trimmed().isEmpty())
                        push();
                    if (ws < 0)
                        ws = int(d.t0);
                    we = int(d.t1);
                    cur += piece;
                }
                push();
                found << QVariantMap{{QStringLiteral("start"), qMax(p.start, a)}, {QStringLiteral("end"), qMin(p.start + p.length, qMax(b, a + 1))},
                                     {QStringLiteral("text"), text}, {QStringLiteral("words"), words}};
            }
        }
        if (ctx)
            whisper_free(ctx);
        const bool aborted = m_abort;
        QMetaObject::invokeMethod(this, [this, found, error, aborted] {
            if (aborted) {
                setState(QString());
                return;
            }
            if (!error.isEmpty()) {
                setState(QString(), error);
                return;
            }
            m_added = Project::instance()->setCaptions(found, m_style, m_anim);
            m_progress = 1;
            Q_EMIT progressChanged();
            setState(QStringLiteral("done"), m_added == 0 ? QStringLiteral("Nie usłyszałem mowy w filmach na osi czasu.") : QString());
        }, Qt::QueuedConnection);
    });
    connect(t, &QThread::finished, t, &QObject::deleteLater);
    t->start(QThread::LowPriority);
#else
    setState(QString(), QStringLiteral("Ta wersja programu nie ma rozpoznawania mowy."));
#endif
}
