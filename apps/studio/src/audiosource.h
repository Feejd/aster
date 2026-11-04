#pragma once

#include <QString>
#include <memory>
#include <vector>

// Dźwięk jednego pliku w pamięci: próbki float z przeplotem (1 albo 2 kanały) w częstotliwości projektu,
// do tego szczyty (min/maks co PeakStep ramek) do rysowania kształtu fali.
// Po wczytaniu niezmienny — wątek audio czyta go bez blokad.
struct AudioSource
{
    static constexpr int PeakStep = 256;

    QString file;                 // nazwa pliku w folderze audio/ projektu
    int channels = 1;
    long long frames = 0;
    std::vector<float> data;      // frames * channels
    std::vector<float> peaks;     // pary (min, maks) mono, co PeakStep ramek

    float at(long long frame, int ch) const { return data[size_t(frame * channels + (channels > 1 ? ch : 0))]; }
    void computePeaks();
};
using SourcePtr = std::shared_ptr<const AudioSource>;

// Wczytuje WAV/FLAC/OGG/Opus/MP3 (libsndfile) i przepróbkowuje do `rate` (libsamplerate). Pusty wskaźnik i `error` przy błędzie.
std::shared_ptr<AudioSource> loadAudio(const QString &path, int rate, QString *error = nullptr);
