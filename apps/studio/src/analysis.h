#pragma once

#include "audiosource.h"

// Rozpoznawanie tempa i tonacji gotowego bitu (MP3/WAV z internetu), żeby siatka taktów i autotune
// od razu do niego pasowały. Wszystko lokalnie, bez sieci; kilka sekund pracy w tle dla 3-minutowego pliku.
//
// Tempo — strumień nastąpień (przyrost widma w skali log), autokorelacja z uwzględnieniem wielokrotności
// okresu i łagodną preferencją okolic 120 BPM (trap 140, a nie 70; boom bap 90, a nie 180).
// Faza — przesunięcie siatki uderzeń, przy którym nastąpienia wypadają najmocniej.
// Tonacja — chromagram (energia 12 klas wysokości) porównany z profilami Krumhansla dla 24 tonacji.
namespace Analysis {

struct Result
{
    double bpm = 0;               // 0 — nie rozpoznano
    double firstBeat = 0;         // sekundy: pierwsze uderzenie siatki (0 … jeden okres)
    double firstBar = 0;          // sekundy: pierwszy „raz” — początek taktu (0 … jeden takt, 4 uderzenia)
    double beatStrength = 0;      // 0…1 — jak wyraźny jest rytm
    int keyRoot = -1;             // 0 = C … 11 = H; -1 — nie rozpoznano
    bool minor = true;
    double keyConfidence = 0;     // 0…1 — przewaga najlepszej tonacji nad kolejną
    double leadIn = 0;            // sekundy ciszy na początku
};

Result analyze(const AudioSource &src, int rate);
// Początki uderzeń (ramki `rate`), najmocniejsze `maxCount`, rosnąco — do cięcia sampli
std::vector<double> onsetTimes(const AudioSource &src, int rate, int maxCount);

}
