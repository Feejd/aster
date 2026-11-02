#pragma once

#include <QtWaylandClient/QWaylandClientExtension>
#include "qwayland-fake-input.h"

// Wirtualna klawiatura KWin (org_kde_kwin_fake_input): po wybraniu emoji panel się chowa,
// a ta klasa „naciska” Ctrl+V w programie, który był aktywny. KWin pozwala na to tylko programom
// z X-KDE-Wayland-Interfaces=org_kde_kwin_fake_input w pliku .desktop.
class FakeInput : public QWaylandClientExtensionTemplate<FakeInput>, public QtWayland::org_kde_kwin_fake_input
{
public:
    FakeInput();
    // Ctrl+V (albo Ctrl+Shift+V) — false, gdy KWin nie udostępnił interfejsu
    bool paste(bool shift);
};
