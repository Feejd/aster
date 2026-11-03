#pragma once

#include "audiosource.h"
#include "synthvoice.h"

#include <QJsonArray>
#include <QJsonObject>
#include <QString>
#include <QVariantList>
#include <memory>

// Beat Maker Studia: perkusja i bas 808 syntezowane w całości w programie (bez sampli — nic obcego,
// wszystko na licencji projektu). Wzór (JSON) to siatka szesnastek; z niego powstaje pętla audio,
// którą ścieżka gra jak każdy zapętlony klip — działa z mikserem, efektami i eksportem.
//
// Wzór perkusji: { kit, bars, swing, rows: { kick, snare, clap, hat, openhat, perc: [głośność 0…1 na krok] },
//                  rolls: [1…4 na krok — rolka hi-hatu] }
// Wzór 808:      { kit, bars, root (0 = C … 11 = H), notes: [stopień skali molowej 0…14 albo -1], glide }
namespace BeatSynth {

enum Kind { Drums, Bass, Keys, Melody };

QVariantList kits();                                       // [{ id, label, hint }]
QVariantList genres();                                     // [{ id, label, bpm, hint }]
QJsonObject genrePattern(const QString &genre, Kind kind); // gotowy wzór gatunku
QJsonObject emptyPattern(Kind kind, const QString &kit, int bars);
QStringList rowNames();                                    // kick, snare, clap, hat, openhat, perc
// Akordy: { instrument, rhythm, chords: [stopień 0…6 na takt], octave, seventh } — tonację (keyRoot, keyMinor) wstawia Studio
SynthVoice::Inst instrumentOf(const QString &id);           // „piano”, „pad”… → głos syntezatora
QVariantList instruments();                                // [{ id, label, hint }]
QVariantList rhythms();                                    // [{ id, label }]
QVariantList progressions();                               // [{ id, label, hint, chords }]
QString chordName(int root, bool minor, int degree, bool seventh);
// Melodia (piano roll): { instrument, bars, notes: [{ step, len, pitch (MIDI), vel, pan }] }
QJsonArray chordNotes(const QJsonObject &keysPattern);     // akordy → nuty (do piano rolla)   // „a-moll”, „F-dur⁷”
int noteMidi(const QJsonObject &bassPattern, int degree);  // stopień skali → MIDI

// Pętla audio (stereo, `rate`) z wzoru w danym tempie; ogony dźwięków zawijają się na początek (pętla bez szwu)
std::shared_ptr<AudioSource> render(const QJsonObject &pattern, Kind kind, double bpm, int rate);

}
