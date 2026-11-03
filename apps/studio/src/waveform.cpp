#include "waveform.h"
#include "studio.h"

#include <QPainter>
#include <cmath>

Waveform::Waveform(QQuickItem *parent) : QQuickPaintedItem(parent)
{
    setAntialiasing(true);
    connect(this, &Waveform::changed, this, [this] { update(); });
}

void Waveform::paint(QPainter *p)
{
    Studio *st = Studio::instance();
    if (!st || width() < 1 || height() < 2)
        return;
    std::vector<float> livePeaks;
    const float *peaks = nullptr;
    long long blocks = 0;
    SourcePtr src;
    if (m_live) {
        livePeaks = st->livePeaks();
        peaks = livePeaks.data();
        blocks = (long long)livePeaks.size() / 2;
    } else {
        src = st->source(m_file);
        if (!src)
            return;
        peaks = src->peaks.data();
        blocks = (long long)src->peaks.size() / 2;
    }
    if (blocks == 0)
        return;

    const double rate = Engine::Rate;
    const double perBlock = AudioSource::PeakStep / rate;           // sekundy na blok szczytów
    const double secPerPx = 1.0 / std::max(1e-6, m_pxPerSec);
    const double from = m_from / perBlock;
    const double mid = height() / 2.0, amp = height() / 2.0 - 1;
    const long long srcStart = llround(m_srcStart * rate / AudioSource::PeakStep);
    const long long srcLen = std::max(1LL, llround(m_srcLength * rate / AudioSource::PeakStep));
    const long long offset = llround(m_offset * rate / AudioSource::PeakStep);

    const int w = int(std::ceil(width()));
    QPolygonF upper, lower;
    upper.reserve(w + 1);
    lower.reserve(w + 1);
    for (int x = 0; x <= w; ++x) {
        // Bloki szczytów pod tym pikselem (w pętli — z zawinięciem)
        const long long b0 = (long long)std::floor(from + x * secPerPx / perBlock);
        const long long b1 = std::max(b0 + 1, (long long)std::floor(from + (x + 1) * secPerPx / perBlock));
        float lo = 0.f, hi = 0.f;
        for (long long b = b0; b < b1; ++b) {
            long long i;
            if (m_live)
                i = b;
            else if (m_loop)
                i = srcStart + (b + offset) % srcLen;
            else
                i = srcStart + b;
            if (i < 0 || i >= blocks)
                continue;
            lo = std::min(lo, peaks[i * 2]);
            hi = std::max(hi, peaks[i * 2 + 1]);
        }
        upper << QPointF(x, mid - std::min(1.f, hi) * amp);
        lower << QPointF(x, mid - std::max(-1.f, lo) * amp);
    }
    QPolygonF shape = upper;
    for (int i = int(lower.size()) - 1; i >= 0; --i)
        shape << lower[i];
    p->setPen(Qt::NoPen);
    p->setBrush(m_color);
    p->drawPolygon(shape);
}
