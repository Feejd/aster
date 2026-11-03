// aster-assistant — usługa Asystenta Aster w sesji użytkownika (D-Bus org.aster.Assistant).
// Uruchamiana na żądanie przez D-Bus; po kwadransie bezczynności sama się kończy.

#include "service.h"

#include <QCoreApplication>
#include <QDBusConnection>
#include <QDBusError>
#include <cstdio>

int main(int argc, char *argv[])
{
    QCoreApplication app(argc, argv);
    app.setApplicationName(QStringLiteral("aster-assistant"));
    app.setOrganizationName(QStringLiteral("Aster"));

    QDBusConnection bus = QDBusConnection::sessionBus();
    if (!bus.isConnected()) {
        std::fprintf(stderr, "aster-assistant: brak szyny sesji D-Bus\n");
        return 1;
    }
    Service service;
    if (!bus.registerObject(QStringLiteral("/org/aster/Assistant"), &service,
                            QDBusConnection::ExportScriptableSlots | QDBusConnection::ExportScriptableSignals)) {
        std::fprintf(stderr, "aster-assistant: nie można zarejestrować obiektu\n");
        return 1;
    }
    if (!bus.registerService(QStringLiteral("org.aster.Assistant"))) {
        std::fprintf(stderr, "aster-assistant: usługa już działa\n");
        return 0;
    }
    return app.exec();
}
