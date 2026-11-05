#include "plugin.h"
#include "pluginwindow.h"

#include "base/source/fstring.h"
#include "pluginterfaces/base/funknownimpl.h"
#include "pluginterfaces/base/ipluginbase.h"
#include "pluginterfaces/gui/iplugview.h"
#include "pluginterfaces/vst/ivstaudioprocessor.h"
#include "pluginterfaces/vst/ivstcomponent.h"
#include "pluginterfaces/vst/ivsteditcontroller.h"
#include "pluginterfaces/vst/ivstevents.h"
#include "pluginterfaces/vst/ivstprocesscontext.h"
#include "pluginterfaces/vst/vsttypes.h"
#include "public.sdk/source/common/memorystream.h"
#include "public.sdk/source/vst/hosting/eventlist.h"
#include "public.sdk/source/vst/hosting/hostclasses.h"
#include "public.sdk/source/vst/hosting/module.h"
#include "public.sdk/source/vst/hosting/parameterchanges.h"
#include "public.sdk/source/vst/hosting/plugprovider.h"
#include "public.sdk/source/vst/hosting/processdata.h"
#include "public.sdk/source/vst/utility/stringconvert.h"

#include <QDir>
#include <QFileInfo>
#include <QHash>
#include <QSocketNotifier>
#include <QTimer>
#include <algorithm>
#include <cstring>

using namespace Steinberg;
using namespace Steinberg::Vst;

namespace Vst3 {

using namespace Plug;

class Instance;

namespace {

// Moduły zostają załadowane do końca programu: fabryki i kod wtyczek muszą przeżyć każdą instancję
QHash<QString, VST3::Hosting::Module::Ptr> &modules()
{
    static auto *m = new QHash<QString, VST3::Hosting::Module::Ptr>;       // bez destruktora przy wyjściu
    return *m;
}

HostApplication *hostApp()
{
    static HostApplication *app = [] {
        auto *a = new HostApplication;
        PluginContextFactory::instance().setPluginContext(a);
        return a;
    }();
    return app;
}

VST3::Hosting::Module::Ptr module(const QString &path, QString *error)
{
    auto &all = modules();
    if (const auto it = all.find(path); it != all.end())
        return it.value();
    hostApp();
    std::string err;
    auto m = VST3::Hosting::Module::create(path.toStdString(), err);
    if (!m) {
        if (error)
            *error = QString::fromStdString(err);
        return nullptr;
    }
    all.insert(path, m);
    return m;
}

QString str(const TChar *s)
{
    return QString::fromUtf16(reinterpret_cast<const char16_t *>(s));
}

// Parametr z interfejsu do wątku audio (kolejka jeden-pisze-jeden-czyta)
struct ParamMsg
{
    ParamID id;
    ParamValue value;
};
constexpr unsigned QueueSize = 1024;

}

// Rączka wtyczki: zmiany z jej okna (performEdit) idą do procesora, restartComponent — nowe opóźnienie
class Handler : public U::Implements<U::Directly<IComponentHandler>>
{
public:
    explicit Handler(struct Impl *i) : impl(i) {}
    tresult PLUGIN_API beginEdit(ParamID) override { return kResultOk; }
    tresult PLUGIN_API performEdit(ParamID id, ParamValue value) override;
    tresult PLUGIN_API endEdit(ParamID) override { return kResultOk; }
    tresult PLUGIN_API restartComponent(int32 flags) override;
    Impl *impl;
};

// Ramka okna wtyczki: zmiana rozmiaru i pętla zdarzeń, której wtyczki X11 potrzebują od gospodarza
class Frame : public U::Implements<U::Directly<IPlugFrame, Linux::IRunLoop>>
{
public:
    explicit Frame(PluginWindow *w) : window(w) {}
    ~Frame() override
    {
        qDeleteAll(notifiers);
        qDeleteAll(timers);
    }
    tresult PLUGIN_API resizeView(IPlugView *view, ViewRect *r) override
    {
        window->resize(r->getWidth(), r->getHeight());
        view->onSize(r);
        return kResultOk;
    }
    tresult PLUGIN_API registerEventHandler(Linux::IEventHandler *h, Linux::FileDescriptor fd) override
    {
        auto *n = new QSocketNotifier(fd, QSocketNotifier::Read);
        QObject::connect(n, &QSocketNotifier::activated, n, [h, fd] { h->onFDIsSet(fd); });
        notifiers.insert(h, n);
        return kResultOk;
    }
    tresult PLUGIN_API unregisterEventHandler(Linux::IEventHandler *h) override
    {
        for (auto *n : notifiers.values(h))
            delete n;
        notifiers.remove(h);
        return kResultOk;
    }
    tresult PLUGIN_API registerTimer(Linux::ITimerHandler *h, Linux::TimerInterval ms) override
    {
        auto *t = new QTimer;
        t->setInterval(int(std::max<Linux::TimerInterval>(ms, 10)));
        QObject::connect(t, &QTimer::timeout, t, [h] { h->onTimer(); });
        t->start();
        timers.insert(h, t);
        return kResultOk;
    }
    tresult PLUGIN_API unregisterTimer(Linux::ITimerHandler *h) override
    {
        for (auto *t : timers.values(h))
            delete t;
        timers.remove(h);
        return kResultOk;
    }
    PluginWindow *window;
    QMultiHash<Linux::IEventHandler *, QSocketNotifier *> notifiers;
    QMultiHash<Linux::ITimerHandler *, QTimer *> timers;
};

struct Impl
{
    std::atomic<int> *latency = nullptr;
    VST3::Hosting::Module::Ptr mod;
    IPtr<PlugProvider> provider;
    IPtr<IComponent> component;
    IPtr<IEditController> controller;
    IPtr<IAudioProcessor> processor;
    IPtr<Handler> handler;
    HostProcessData data;
    EventList events;
    ParameterChanges inChanges{256}, outChanges{256};
    ProcessContext ctx{};
    int inBuses = 0, outBuses = 0;
    int auxBus = -1;                               // pierwsza szyna boczna (sidechain)
    int maxBlock = 2048;
    double rate = 48000;
    ParamMsg rtParams[64];                         // automatyka z wątku audio
    int rtCount = 0;
    std::atomic_flag busy = ATOMIC_FLAG_INIT;      // wczytywanie stanu: wątek audio przepuszcza dźwięk bez wtyczki
    ParamMsg queue[QueueSize];
    std::atomic<unsigned> qw{0}, qr{0};
    // Okno
    IPtr<IPlugView> view;
    IPtr<Frame> frame;
    std::unique_ptr<PluginWindow> window;

    void push(ParamID id, ParamValue v)
    {
        const unsigned w = qw.load(std::memory_order_relaxed);
        if (w - qr.load(std::memory_order_acquire) >= QueueSize)
            return;
        queue[w % QueueSize] = {id, v};
        qw.store(w + 1, std::memory_order_release);
    }
};

class Instance : public Plugin
{
public:
    static std::unique_ptr<Plugin> load(const Info &info, double rate, int maxBlock, QString *error);
    Instance();
    ~Instance() override;
    void process(float *l, float *r, int n, const Note *notes, int noteCount, const Transport &t, const float *sideL, const float *sideR) override;
    void automate(unsigned id, double value) override;
    bool hasSidechain() const override;
    QList<Param> params() const override;
    void setParam(unsigned id, double value) override;
    QByteArray state() const override;
    bool setState(const QByteArray &data) override;
    bool hasEditor() const override;
    bool openEditor() override;
    void closeEditor() override;

private:
    std::unique_ptr<Impl> d;
};

tresult PLUGIN_API Handler::performEdit(ParamID id, ParamValue value)
{
    impl->push(id, value);
    return kResultOk;
}

tresult PLUGIN_API Handler::restartComponent(int32 flags)
{
    if (flags & kLatencyChanged)
        impl->latency->store(int(impl->processor->getLatencySamples()));
    return kResultOk;
}

Instance::Instance() : d(std::make_unique<Impl>())
{
    d->latency = &m_latency;
}

Instance::~Instance()
{
    closeEditor();
    if (d->processor) {
        d->processor->setProcessing(false);
        d->component->setActive(false);
    }
    if (d->controller)
        d->controller->setComponentHandler(nullptr);
    d->data.unprepare();
}

QList<Info> scanFile(const QString &file)
{
    QList<Info> out;
    QString err;
    const QString path = QFileInfo(file).canonicalFilePath();
    const auto m = module(path, &err);
    if (!m)
        return out;
    for (const auto &c : m->getFactory().classInfos()) {
        if (c.category() != kVstAudioEffectClass)
            continue;
        Info i;
        i.format = QStringLiteral("vst3");
        i.path = path;
        i.uid = QString::fromStdString(c.ID().toString());
        i.name = QString::fromStdString(c.name());
        i.vendor = QString::fromStdString(c.vendor());
        i.category = QString::fromStdString(c.subCategoriesString());
        i.instrument = i.category.contains(QLatin1String("Instrument"));
        out << i;
    }
    return out;
}

std::unique_ptr<Plugin> Instance::load(const Info &info, double rate, int maxBlock, QString *error)
{
    auto fail = [error](const QString &e) {
        if (error)
            *error = e;
        return std::unique_ptr<Plugin>();
    };
    auto mod = module(info.path, error);
    if (!mod)
        return {};
    const auto factory = mod->getFactory();
    for (const auto &c : factory.classInfos()) {
        if (QString::fromStdString(c.ID().toString()) != info.uid)
            continue;
        std::unique_ptr<Instance> p(new Instance);
        Impl *d = p->d.get();
        p->m_info = info;
        d->mod = mod;
        d->rate = rate;
        d->maxBlock = maxBlock;
        d->provider = owned(new PlugProvider(factory, c, true));
        if (!d->provider->initialize())
            return fail(QStringLiteral("Wtyczka nie chce się uruchomić: %1").arg(info.name));
        d->component = d->provider->getComponentPtr();
        d->controller = d->provider->getControllerPtr();
        d->processor = FUnknownPtr<IAudioProcessor>(d->component);
        if (!d->processor)
            return fail(QStringLiteral("To nie jest wtyczka dźwiękowa: %1").arg(info.name));

        // Stereo na głównych szynach, jeśli wtyczka się zgodzi (mono — zostaje jej układ)
        d->inBuses = d->component->getBusCount(kAudio, kInput);
        d->outBuses = d->component->getBusCount(kAudio, kOutput);
        std::vector<SpeakerArrangement> ins(size_t(d->inBuses), SpeakerArr::kStereo), outs(size_t(d->outBuses), SpeakerArr::kStereo);
        d->processor->setBusArrangements(ins.data(), d->inBuses, outs.data(), d->outBuses);
        ProcessSetup setup{kRealtime, kSample32, maxBlock, rate};
        if (d->processor->setupProcessing(setup) != kResultOk)
            return fail(QStringLiteral("Wtyczka nie obsługuje dźwięku 32-bitowego: %1").arg(info.name));
        for (int i = 0; i < d->inBuses; ++i) {
            BusInfo bi{};
            if (i > 0 && d->auxBus < 0 && d->component->getBusInfo(kAudio, kInput, i, bi) == kResultOk && bi.busType == kAux)
                d->auxBus = i;
            d->component->activateBus(kAudio, kInput, i, i == 0 || i == d->auxBus);
        }
        for (int i = 0; i < d->outBuses; ++i)
            d->component->activateBus(kAudio, kOutput, i, i == 0);
        for (int i = 0, n = d->component->getBusCount(kEvent, kInput); i < n; ++i)
            d->component->activateBus(kEvent, kInput, i, i == 0);

        d->data.prepare(*d->component, maxBlock, kSample32);
        d->data.processMode = kRealtime;
        d->data.symbolicSampleSize = kSample32;
        d->data.inputParameterChanges = &d->inChanges;
        d->data.outputParameterChanges = &d->outChanges;
        d->data.inputEvents = &d->events;
        d->data.processContext = &d->ctx;
        d->handler = owned(new Handler(d));
        if (d->controller)
            d->controller->setComponentHandler(d->handler.get());
        d->component->setActive(true);
        d->processor->setProcessing(true);
        p->m_latency.store(int(d->processor->getLatencySamples()));
        return std::unique_ptr<Plugin>(p.release());
    }
    return fail(QStringLiteral("Nie ma już tej wtyczki: %1").arg(info.name));
}

bool Instance::hasSidechain() const { return d->auxBus >= 0; }

void Instance::process(float *l, float *r, int n, const Note *notes, int noteCount, const Transport &t, const float *sideL, const float *sideR)
{
    Impl *i = d.get();
    if (i->busy.test_and_set(std::memory_order_acquire))
        return;
    n = std::min(n, i->maxBlock);
    // Parametry z interfejsu i okna wtyczki
    i->inChanges.clearQueue();
    unsigned rd = i->qr.load(std::memory_order_relaxed);
    const unsigned wr = i->qw.load(std::memory_order_acquire);
    for (; rd != wr; ++rd) {
        const ParamMsg &m = i->queue[rd % QueueSize];
        int32 idx = 0, pt = 0;
        if (IParamValueQueue *q = i->inChanges.addParameterData(m.id, idx))
            q->addPoint(0, m.value, pt);
    }
    i->qr.store(rd, std::memory_order_release);
    for (int k = 0; k < i->rtCount; ++k) {
        int32 idx = 0, pt = 0;
        if (IParamValueQueue *q = i->inChanges.addParameterData(i->rtParams[k].id, idx))
            q->addPoint(0, i->rtParams[k].value, pt);
    }
    i->rtCount = 0;
    i->outChanges.clearQueue();
    // Nuty
    i->events.clear();
    for (int k = 0; k < noteCount; ++k) {
        Event e{};
        e.busIndex = 0;
        e.sampleOffset = notes[k].offset;
        if (notes[k].on) {
            e.type = Event::kNoteOnEvent;
            e.noteOn.channel = 0;
            e.noteOn.pitch = int16(notes[k].pitch);
            e.noteOn.velocity = notes[k].velocity;
            e.noteOn.noteId = -1;
        } else {
            e.type = Event::kNoteOffEvent;
            e.noteOff.channel = 0;
            e.noteOff.pitch = int16(notes[k].pitch);
            e.noteOff.velocity = 0;
            e.noteOff.noteId = -1;
        }
        i->events.addEvent(e);
    }
    // Czas: wtyczki synchronizują LFO i echa z tempem
    ProcessContext &c = i->ctx;
    c.state = ProcessContext::kTempoValid | ProcessContext::kProjectTimeMusicValid | ProcessContext::kTimeSigValid | (t.playing ? ProcessContext::kPlaying : 0);
    c.tempo = t.bpm;
    c.sampleRate = i->rate;
    c.projectTimeSamples = t.samples;
    c.projectTimeMusic = double(t.samples) / i->rate * t.bpm / 60.0;
    c.timeSigNumerator = t.beatsPerBar;
    c.timeSigDenominator = 4;

    ProcessData &pd = i->data;
    pd.numSamples = n;
    auto copyIn = [&](AudioBusBuffers &b) {
        if (b.numChannels > 0)
            std::memcpy(b.channelBuffers32[0], l, size_t(n) * sizeof(float));
        if (b.numChannels > 1)
            std::memcpy(b.channelBuffers32[1], r, size_t(n) * sizeof(float));
    };
    if (pd.numInputs > 0)
        copyIn(pd.inputs[0]);
    if (i->auxBus >= 0 && i->auxBus < pd.numInputs) {
        AudioBusBuffers &b = pd.inputs[i->auxBus];
        for (int c = 0; c < b.numChannels; ++c) {
            const float *from = c == 0 ? sideL : sideR;
            if (from)
                std::memcpy(b.channelBuffers32[c], from, size_t(n) * sizeof(float));
            else
                std::memset(b.channelBuffers32[c], 0, size_t(n) * sizeof(float));
        }
    }
    i->processor->process(pd);
    if (pd.numOutputs > 0) {
        const AudioBusBuffers &o = pd.outputs[0];
        if (o.numChannels > 0)
            std::memcpy(l, o.channelBuffers32[0], size_t(n) * sizeof(float));
        if (o.numChannels > 1)
            std::memcpy(r, o.channelBuffers32[1], size_t(n) * sizeof(float));
        else if (o.numChannels == 1)
            std::memcpy(r, l, size_t(n) * sizeof(float));
    }
    i->busy.clear(std::memory_order_release);
}

void Instance::automate(unsigned id, double value)
{
    if (d->rtCount < 64)
        d->rtParams[d->rtCount++] = {id, std::clamp(value, 0.0, 1.0)};
}

QList<Param> Instance::params() const
{
    QList<Param> out;
    if (!d->controller)
        return out;
    for (int i = 0, n = d->controller->getParameterCount(); i < n; ++i) {
        ParameterInfo pi{};
        if (d->controller->getParameterInfo(i, pi) != kResultOk || (pi.flags & ParameterInfo::kIsHidden))
            continue;
        out << Param{pi.id, str(pi.title), str(pi.units), d->controller->getParamNormalized(pi.id), bool(pi.flags & ParameterInfo::kCanAutomate)};
    }
    return out;
}

void Instance::setParam(unsigned id, double value)
{
    value = std::clamp(value, 0.0, 1.0);
    if (d->controller)
        d->controller->setParamNormalized(id, value);
    d->push(id, value);
}

// Stan: długość + stan procesora, potem stan kontrolera
QByteArray Instance::state() const
{
    auto grab = [](auto *obj) {
        QByteArray b;
        if (!obj)
            return b;
        auto s = owned(new MemoryStream);
        if (obj->getState(s) == kResultOk)
            b = QByteArray(s->getData(), qsizetype(s->getSize()));
        return b;
    };
    const QByteArray a = grab(d->component.get()), c = grab(d->controller.get());
    QByteArray out;
    const qint64 la = a.size();
    out.append(reinterpret_cast<const char *>(&la), sizeof la);
    out.append(a);
    out.append(c);
    return out;
}

bool Instance::setState(const QByteArray &data)
{
    qint64 la = 0;
    if (data.size() < qsizetype(sizeof la))
        return false;
    std::memcpy(&la, data.constData(), sizeof la);
    if (la < 0 || sizeof la + size_t(la) > size_t(data.size()))
        return false;
    QByteArray a = data.mid(sizeof la, la), c = data.mid(qsizetype(sizeof la) + la);
    auto as = owned(new MemoryStream(a.data(), a.size()));
    // Stan ładuje się bez dźwięku: procesor nie może grać w tym samym czasie
    while (d->busy.test_and_set(std::memory_order_acquire)) {}
    d->processor->setProcessing(false);
    d->component->setActive(false);
    const bool ok = d->component->setState(as) == kResultOk;
    d->component->setActive(true);
    d->processor->setProcessing(true);
    d->busy.clear(std::memory_order_release);
    if (d->controller) {
        as->seek(0, IBStream::kIBSeekSet, nullptr);
        d->controller->setComponentState(as);
        if (!c.isEmpty()) {
            auto cs = owned(new MemoryStream(c.data(), c.size()));
            d->controller->setState(cs);
        }
    }
    return ok;
}

bool Instance::hasEditor() const
{
    if (!d->controller)
        return false;
    IPtr<IPlugView> v = owned(d->controller->createView(ViewType::kEditor));
    return v && v->isPlatformTypeSupported(kPlatformTypeX11EmbedWindowID) == kResultTrue;
}

bool Instance::openEditor()
{
    Impl *i = d.get();
    if (i->view) {
        i->window->raise();
        return true;
    }
    if (!i->controller)
        return false;
    i->view = owned(i->controller->createView(ViewType::kEditor));
    if (!i->view || i->view->isPlatformTypeSupported(kPlatformTypeX11EmbedWindowID) != kResultTrue) {
        i->view = nullptr;
        return false;
    }
    ViewRect r{};
    i->view->getSize(&r);
    i->window = std::make_unique<PluginWindow>(m_info.name, r.getWidth(), r.getHeight(), [this] { closeEditor(); });
    if (!i->window->ok()) {
        i->window.reset();
        i->view = nullptr;
        return false;
    }
    i->frame = owned(new Frame(i->window.get()));
    i->view->setFrame(i->frame.get());
    if (i->view->attached(reinterpret_cast<void *>(i->window->id()), kPlatformTypeX11EmbedWindowID) != kResultOk) {
        closeEditor();
        return false;
    }
    return true;
}

void Instance::closeEditor()
{
    Impl *i = d.get();
    if (i->view) {
        i->view->setFrame(nullptr);
        i->view->removed();
        i->view = nullptr;
    }
    i->frame = nullptr;
    i->window.reset();
}

std::unique_ptr<Plugin> load(const Info &info, double rate, int maxBlock, QString *error)
{
    return Instance::load(info, rate, maxBlock, error);
}

}
