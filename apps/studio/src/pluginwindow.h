#pragma once

#include <QString>
#include <functional>
#include <memory>

class QSocketNotifier;

// Okno wtyczki: osobne okno X11 (przez XWayland), bo VST3 i CLAP na Linuksie osadzają się tylko w X11.
class PluginWindow
{
public:
    PluginWindow(const QString &title, int width, int height, std::function<void()> closed);
    ~PluginWindow();
    bool ok() const;
    unsigned long id() const;
    void resize(int width, int height);
    void raise();

private:
    void pump();
    void *m_dpy = nullptr;
    unsigned long m_win = 0, m_delete = 0;
    std::function<void()> m_closed;
    std::unique_ptr<QSocketNotifier> m_notifier;
};
