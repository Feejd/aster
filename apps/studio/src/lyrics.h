#pragma once

#include <QList>
#include <QString>
#include <QStringList>

// Tekst piosenki: rodzaj wiersza (wers, nagłówek części, pusty) i rymy na końcach wersów.
// Rymy liczone po polsku: od przedostatniej sylaby (akcent na przedostatnią), „ó” = „u”, „rz” = „ż”, „ch” = „h”,
// ubezdźwięcznienie na końcu („bóg” — „buk”). Rap żyje też z asonansów — wersy z tymi samymi samogłoskami
// w końcówce i tym samym ostatnim dźwiękiem („kasa” — „maska”) też się liczą. Para musi być blisko: do 3 wersów odstępu.
namespace Lyrics {

enum class Kind { Line, Head, Blank };

struct Line
{
    Kind kind = Kind::Blank;
    int rhyme = -1;         // numer grupy rymów (−1 — bez pary)
    int rhymeAt = -1;       // od którego znaku tekstu zaczyna się rymująca końcówka
    bool exact = false;     // rym dokładny (a nie tylko asonans)
};

QList<Line> analyze(const QStringList &lines);

}
