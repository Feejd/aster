#pragma once

#include <QFont>
#include <QGuiApplication>

// Typografia Aster: Outfit jako czcionka domyślna, wygładzana bez hintingu —
// litery mają swój prawdziwy kształt i grubość (jak w macOS), zamiast być dociągane do pikseli.
// Wywołać zaraz po utworzeniu aplikacji, przed załadowaniem QML.
inline void asterTypography()
{
    QFont f(QStringLiteral("Outfit"));
    f.setPixelSize(13);
    f.setHintingPreference(QFont::PreferNoHinting);
    f.setStyleStrategy(QFont::PreferAntialias);
    f.setKerning(true);
    QGuiApplication::setFont(f);
}
