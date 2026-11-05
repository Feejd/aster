#pragma once

#include "audiosource.h"

// Zmiana długości bez zmiany wysokości (Rubber Band, GPL). ratio 1,1 — o 10% dłużej.
std::shared_ptr<AudioSource> stretchAudio(const AudioSource &src, double ratio, int rate);
