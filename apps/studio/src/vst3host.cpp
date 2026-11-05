#include "vst3host.h"

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

#include <X11/Xatom.h>
#include <X11/Xlib.h>
#include <X11/Xutil.h>
// Xlib definiuje makra, które gryzą się z Qt i SDK
#undef Bool
#undef None
#undef Status
#undef Success

using namespace Steinberg;
using namespace Steinberg::Vst;

namespace Vst3 {

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
    explicit Handler(Plugin::Impl *i) : impl(i) {}
    tresult PLUGIN_API beginEdit(ParamID) override { return kResultOk; }
    tresult PLUGIN_API performEdit(ParamID id, ParamValue value) override;
    tresult PLUGIN_API endEdit(ParamID) override { return kResultOk; }
    tresult PLUGIN_API restartComponent(int32 flags) override;
    Plugin::Impl *impl;
};

// Ramka okna wtyczki: zmiana rozmiaru i pętla zdarzeń, której wtyczki X11 potrzebują od gospodarza
class Frame : public U::Implements<U::Directly<IPlugFrame, Linux::IRunLoop>>
{
public:
    Frame(Display *d, ::Window w) : dpy(d), win(w) {}
    ~Frame() override
    {
        qDeleteAll(notifiers);
        qDeleteAll(timers);
    }
    tresult PLUGIN_API resizeView(IPlugView *view, ViewRect *r) override
    {
        XResizeWindow(dpy, win, unsigned(r->getWidth()), unsigned(r->getHeight()));
        XFlush(dpy);
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
    Display *dpy;
    ::Window win;
    QMultiHash<Linux::IEventHandler *, QSocketNotifier *> notifiers;
    QMultiHash<Linux::ITimerHandler *, QTimer *> timers;
};

struct Plugin::Impl
{
    Plugin *self = nullptr;
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
    int maxBlock = 2048;
    double rate = 48000;
    std::atomic_flag busy = ATOMIC_FLAG_INIT;      // wczytywanie stanu: wątek audio przepuszcza dźwięk bez wtyczki
    ParamMsg queue[QueueSize];
    std::atomic<unsigned> qw{0}, qr{0};
    // Okno
    IPtr<IPlugView> view;
    IPtr<Frame> frame;
    Display *dpy = nullptr;
    ::Window win = 0;
    Atom wmDelete = 0;
    std::unique_ptr<QSocketNotifier> xNotifier;

    void push(ParamID id, ParamValue v)
    {
        const unsigned w = qw.load(std::memory_order_relaxed);
        if (w - qr.load(std::memory_order_acquire) >= QueueSize)
            return;
        queue[w % QueueSize] = {id, v};
        qw.store(w + 1, std::memory_order_release);
    }
    void pumpX();
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

Plugin::Plugin() : d(std::make_unique<Impl>())
{
    d->self = this;
    d->latency = &m_latency;
}

Plugin::~Plugin()
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

QList<Info> scan()
{
    QStringList paths{QDir::homePath() + QStringLiteral("/.vst3"), QStringLiteral("/usr/lib64/vst3"),
                      QStringLiteral("/usr/lib/vst3"), QStringLiteral("/usr/local/lib/vst3")};
    paths = qEnvironmentVariable("VST3_PATH").split(QLatin1Char(':'), Qt::SkipEmptyParts) + paths;
    QList<Info> out;
    QStringList seen;
    std::function<void(const QString &, int)> walk = [&](const QString &dir, int depth) {
        for (const QFileInfo &fi : QDir(dir).entryInfoList(QDir::Dirs | QDir::Files | QDir::NoDotAndDotDot)) {
            if (fi.suffix() != QLatin1String("vst3")) {
                if (fi.isDir() && depth < 4)
                    walk(fi.filePath(), depth + 1);
                continue;
            }
            const QString path = fi.canonicalFilePath();
            if (seen.contains(path))
                continue;
            seen << path;
            QString err;
            const auto m = module(path, &err);
            if (!m)
                continue;
            for (const auto &c : m->getFactory().classInfos()) {
                if (c.category() != kVstAudioEffectClass)
                    continue;
                Info i;
                i.path = path;
                i.uid = QString::fromStdString(c.ID().toString());
                i.name = QString::fromStdString(c.name());
                i.vendor = QString::fromStdString(c.vendor());
                i.category = QString::fromStdString(c.subCategoriesString());
                i.instrument = i.category.contains(QLatin1String("Instrument"));
                out << i;
            }
        }
    };
    for (const QString &p : std::as_const(paths))
        walk(p, 0);
    std::sort(out.begin(), out.end(), [](const Info &a, const Info &b) { return a.name.compare(b.name, Qt::CaseInsensitive) < 0; });
    return out;
}

std::unique_ptr<Plugin> Plugin::load(const Info &info, double rate, int maxBlock, QString *error)
{
    auto fail = [error](const QString &e) {
        if (error)
            *error = e;
        return nullptr;
    };
    auto mod = module(info.path, error);
    if (!mod)
        return nullptr;
    const auto factory = mod->getFactory();
    for (const auto &c : factory.classInfos()) {
        if (QString::fromStdString(c.ID().toString()) != info.uid)
            continue;
        std::unique_ptr<Plugin> p(new Plugin);
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
        for (int i = 0; i < d->inBuses; ++i)
            d->component->activateBus(kAudio, kInput, i, i == 0);
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
        return p;
    }
    return fail(QStringLiteral("Nie ma już tej wtyczki: %1").arg(info.name));
}

void Plugin::process(float *l, float *r, int n, const Note *notes, int noteCount, const Transport &t)
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

QList<Param> Plugin::params() const
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

void Plugin::setParam(unsigned id, double value)
{
    value = std::clamp(value, 0.0, 1.0);
    if (d->controller)
        d->controller->setParamNormalized(id, value);
    d->push(id, value);
}

// Stan: długość + stan procesora, potem stan kontrolera
QByteArray Plugin::state() const
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

bool Plugin::setState(const QByteArray &data)
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

bool Plugin::hasEditor() const
{
    if (!d->controller)
        return false;
    IPtr<IPlugView> v = owned(d->controller->createView(ViewType::kEditor));
    return v && v->isPlatformTypeSupported(kPlatformTypeX11EmbedWindowID) == kResultTrue;
}

void Plugin::Impl::pumpX()
{
    while (dpy && XPending(dpy)) {
        XEvent e;
        XNextEvent(dpy, &e);
        if (e.type == ClientMessage && Atom(e.xclient.data.l[0]) == wmDelete) {
            self->closeEditor();
            return;
        }
    }
}

bool Plugin::openEditor()
{
    Impl *i = d.get();
    if (i->view) {
        XRaiseWindow(i->dpy, i->win);
        XFlush(i->dpy);
        return true;
    }
    if (!i->controller)
        return false;
    i->view = owned(i->controller->createView(ViewType::kEditor));
    if (!i->view || i->view->isPlatformTypeSupported(kPlatformTypeX11EmbedWindowID) != kResultTrue) {
        i->view = nullptr;
        return false;
    }
    i->dpy = XOpenDisplay(nullptr);            // XWayland albo X11; bez niego okna wtyczki się nie otworzą
    if (!i->dpy) {
        i->view = nullptr;
        return false;
    }
    ViewRect r{};
    i->view->getSize(&r);
    const int screen = DefaultScreen(i->dpy);
    i->win = XCreateSimpleWindow(i->dpy, RootWindow(i->dpy, screen), 0, 0, unsigned(std::max(r.getWidth(), 100)), unsigned(std::max(r.getHeight(), 60)), 0,
                                 BlackPixel(i->dpy, screen), BlackPixel(i->dpy, screen));
    const QByteArray title = m_info.name.toUtf8();
    XChangeProperty(i->dpy, i->win, XInternAtom(i->dpy, "_NET_WM_NAME", False), XInternAtom(i->dpy, "UTF8_STRING", False), 8, PropModeReplace,
                    reinterpret_cast<const unsigned char *>(title.constData()), int(title.size()));
    i->wmDelete = XInternAtom(i->dpy, "WM_DELETE_WINDOW", False);
    XSetWMProtocols(i->dpy, i->win, &i->wmDelete, 1);
    // Okno wtyczki nad Studiem, jak pływające okna w innych programach
    Atom above = XInternAtom(i->dpy, "_NET_WM_STATE_ABOVE", False);
    XChangeProperty(i->dpy, i->win, XInternAtom(i->dpy, "_NET_WM_STATE", False), XA_ATOM, 32, PropModeReplace, reinterpret_cast<const unsigned char *>(&above), 1);
    XMapWindow(i->dpy, i->win);
    XFlush(i->dpy);
    i->frame = owned(new Frame(i->dpy, i->win));
    i->view->setFrame(i->frame.get());
    if (i->view->attached(reinterpret_cast<void *>(i->win), kPlatformTypeX11EmbedWindowID) != kResultOk) {
        closeEditor();
        return false;
    }
    i->xNotifier = std::make_unique<QSocketNotifier>(ConnectionNumber(i->dpy), QSocketNotifier::Read);
    QObject::connect(i->xNotifier.get(), &QSocketNotifier::activated, i->xNotifier.get(), [i] { i->pumpX(); });
    return true;
}

void Plugin::closeEditor()
{
    Impl *i = d.get();
    i->xNotifier.reset();
    if (i->view) {
        i->view->setFrame(nullptr);
        i->view->removed();
        i->view = nullptr;
    }
    i->frame = nullptr;
    if (i->dpy) {
        XDestroyWindow(i->dpy, i->win);
        XCloseDisplay(i->dpy);
        i->dpy = nullptr;
        i->win = 0;
    }
}

}
