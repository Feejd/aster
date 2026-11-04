#pragma once

#include <QString>

// Hasła połączeń w portfelu systemu przez Secret Service (w Aster: KWallet / ksecretd, gdzie indziej
// gnome-keyring) — nigdy w plikach. Jeden wpis na połączenie: atrybuty application=aster-vault, connection=<id>.
namespace Secrets {
QString get(const QString &connectionId, QString *error = nullptr);
bool set(const QString &connectionId, const QString &label, const QString &password, QString *error = nullptr);
bool remove(const QString &connectionId, QString *error = nullptr);
}
