#include "fakeinput.h"

#include <linux/input-event-codes.h>

FakeInput::FakeInput()
    : QWaylandClientExtensionTemplate<FakeInput>(4)
{
    initialize();
    connect(this, &QWaylandClientExtension::activeChanged, this, [this] {
        if (isActive())
            authenticate(QStringLiteral("Emoji"), QStringLiteral("Wstawianie emoji w aktywnym programie"));
    });
}

bool FakeInput::paste(bool shift)
{
    if (!isActive())
        return false;
    constexpr uint32_t pressed = 1, released = 0;
    keyboard_key(KEY_LEFTCTRL, pressed);
    if (shift)
        keyboard_key(KEY_LEFTSHIFT, pressed);
    keyboard_key(KEY_V, pressed);
    keyboard_key(KEY_V, released);
    if (shift)
        keyboard_key(KEY_LEFTSHIFT, released);
    keyboard_key(KEY_LEFTCTRL, released);
    return true;
}
