#pragma once

#include "audiosource.h"

// Odszumianie nagrania (szum mikrofonu, komputera, wentylatora, szum tła pokoju).
// Profil szumu Studio bierze samo z najcichszych fragmentów nagrania (pauzy między wersami), potem w każdym
// paśmie widma ścisza to, co nie wystaje ponad szum (bramka widmowa z wygładzaniem w czasie i częstotliwości —
// bez „bulgotania”). Głos zostaje, tło opada o 10–24 dB zależnie od siły.
namespace Denoise {

// level: 1 lekko, 2 średnio, 3 mocno. Pusty wskaźnik — za krótkie nagranie.
std::shared_ptr<AudioSource> process(const AudioSource &src, int level);
bool saveWav(const AudioSource &src, const QString &path);

}
