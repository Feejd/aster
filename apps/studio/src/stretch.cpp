#include "stretch.h"

#include <rubberband/RubberBandStretcher.h>
#include <algorithm>

using RubberBand::RubberBandStretcher;

std::shared_ptr<AudioSource> stretchAudio(const AudioSource &src, double ratio, int rate)
{
    RubberBandStretcher rb(size_t(rate), size_t(src.channels),
                           RubberBandStretcher::OptionProcessOffline | RubberBandStretcher::OptionEngineFiner, ratio);
    std::vector<std::vector<float>> in(size_t(src.channels), std::vector<float>(size_t(src.frames)));
    std::vector<const float *> ptr;
    for (int c = 0; c < src.channels; ++c) {
        for (long long i = 0; i < src.frames; ++i)
            in[size_t(c)][size_t(i)] = src.at(i, c);
        ptr.push_back(in[size_t(c)].data());
    }
    rb.setExpectedInputDuration(size_t(src.frames));
    rb.study(ptr.data(), size_t(src.frames), true);
    const size_t chunk = 4096;
    std::vector<std::vector<float>> out(size_t(src.channels));
    std::vector<std::vector<float>> tmp(size_t(src.channels), std::vector<float>(chunk));
    std::vector<float *> tp;
    for (auto &t : tmp)
        tp.push_back(t.data());
    auto drain = [&] {
        while (rb.available() > 0) {
            const size_t got = rb.retrieve(tp.data(), std::min<size_t>(chunk, size_t(rb.available())));
            for (int c = 0; c < src.channels; ++c)
                out[size_t(c)].insert(out[size_t(c)].end(), tmp[size_t(c)].begin(), tmp[size_t(c)].begin() + long(got));
        }
    };
    for (size_t at = 0; at < size_t(src.frames); at += chunk) {
        const size_t n = std::min(chunk, size_t(src.frames) - at);
        std::vector<const float *> p;
        for (auto &v : in)
            p.push_back(v.data() + at);
        rb.process(p.data(), n, at + n >= size_t(src.frames));
        drain();
    }
    drain();
    auto res = std::make_shared<AudioSource>();
    res->channels = src.channels;
    res->frames = out.empty() ? 0 : (long long)out[0].size();
    res->data.resize(size_t(res->frames * src.channels));
    for (long long i = 0; i < res->frames; ++i)
        for (int c = 0; c < src.channels; ++c)
            res->data[size_t(i * src.channels + c)] = out[size_t(c)][size_t(i)];
    res->computePeaks();
    return res;
}
