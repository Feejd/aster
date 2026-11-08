#pragma once

#include <QFont>
#include <QGuiApplication>

// Typografia Aster: Inter jako czcionka domyślna. Lekki hinting tylko w pionie (jak „hintslight”):
// linie bazowe i wysokość liter trafiają w piksele, więc tekst jest ostry na zwykłych ekranach,
// a kształt i szerokość liter zostają prawdziwe.
// Wywołać zaraz po utworzeniu aplikacji, przed załadowaniem QML.
inline void asterTypography()
{
    QFont f(QStringLiteral("Inter"));
    f.setPixelSize(13);
    f.setHintingPreference(QFont::PreferVerticalHinting);
    f.setStyleStrategy(QFont::PreferAntialias);
    f.setKerning(true);
    QGuiApplication::setFont(f);
}
