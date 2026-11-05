#include "pluginwindow.h"

#include <QSocketNotifier>
#include <algorithm>

#include <X11/Xatom.h>
#include <X11/Xlib.h>
#include <X11/Xutil.h>

#define DPY static_cast<Display *>(m_dpy)

PluginWindow::PluginWindow(const QString &title, int width, int height, std::function<void()> closed) : m_closed(std::move(closed))
{
    m_dpy = XOpenDisplay(nullptr);             // XWayland albo X11; bez niego okna wtyczki się nie otworzą
    if (!m_dpy)
        return;
    const int screen = DefaultScreen(DPY);
    m_win = XCreateSimpleWindow(DPY, RootWindow(DPY, screen), 0, 0, unsigned(std::max(width, 100)), unsigned(std::max(height, 60)), 0,
                                BlackPixel(DPY, screen), BlackPixel(DPY, screen));
    const QByteArray t = title.toUtf8();
    XChangeProperty(DPY, m_win, XInternAtom(DPY, "_NET_WM_NAME", False), XInternAtom(DPY, "UTF8_STRING", False), 8, PropModeReplace,
                    reinterpret_cast<const unsigned char *>(t.constData()), int(t.size()));
    Atom del = XInternAtom(DPY, "WM_DELETE_WINDOW", False);
    m_delete = del;
    XSetWMProtocols(DPY, m_win, &del, 1);
    // Okno wtyczki nad Studiem, jak pływające okna w innych programach
    Atom above = XInternAtom(DPY, "_NET_WM_STATE_ABOVE", False);
    XChangeProperty(DPY, m_win, XInternAtom(DPY, "_NET_WM_STATE", False), XA_ATOM, 32, PropModeReplace, reinterpret_cast<const unsigned char *>(&above), 1);
    XMapWindow(DPY, m_win);
    XFlush(DPY);
    m_notifier = std::make_unique<QSocketNotifier>(ConnectionNumber(DPY), QSocketNotifier::Read);
    QObject::connect(m_notifier.get(), &QSocketNotifier::activated, m_notifier.get(), [this] { pump(); });
}

PluginWindow::~PluginWindow()
{
    m_notifier.reset();
    if (m_dpy) {
        XDestroyWindow(DPY, m_win);
        XCloseDisplay(DPY);
    }
}

bool PluginWindow::ok() const { return m_dpy != nullptr; }
unsigned long PluginWindow::id() const { return m_win; }

void PluginWindow::resize(int width, int height)
{
    XResizeWindow(DPY, m_win, unsigned(width), unsigned(height));
    XFlush(DPY);
}

void PluginWindow::raise()
{
    XRaiseWindow(DPY, m_win);
    XFlush(DPY);
}

void PluginWindow::pump()
{
    while (m_dpy && XPending(DPY)) {
        XEvent e;
        XNextEvent(DPY, &e);
        if (e.type == ClientMessage && static_cast<unsigned long>(e.xclient.data.l[0]) == m_delete) {
            m_closed();
            return;
        }
    }
}
