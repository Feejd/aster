#pragma once

#include <QObject>
#include <QPoint>
#include <QQmlEngine>
#include <QQuickTextDocument>
#include <QVariantMap>

// Operacje edytora kodu na dokumencie TextEdit: wcięcia, komentarze, przenoszenie i duplikowanie
// wierszy (każda jako jeden krok cofania), dopasowanie nawiasów, wykrywanie stylu wcięć.
class TextOps : public QObject
{
    Q_OBJECT
    QML_ELEMENT
    QML_SINGLETON

public:
    explicit TextOps(QObject *parent = nullptr);

    Q_INVOKABLE QPoint lineColumn(QQuickTextDocument *doc, int position) const;   // (kolumna, wiersz) od 0
    Q_INVOKABLE int positionOfLine(QQuickTextDocument *doc, int line) const;      // początek wiersza (od 0)
    Q_INVOKABLE int lineCount(QQuickTextDocument *doc) const;
    Q_INVOKABLE QString lineText(QQuickTextDocument *doc, int line) const;

    // op: indent | outdent | comment | moveUp | moveDown | duplicateUp | duplicateDown | deleteLine
    // unit — jednostka wcięcia („\t” albo spacje); line, blockStart, blockEnd — znaczniki komentarza.
    // Zwraca nowe zaznaczenie { start, end }.
    Q_INVOKABLE QVariantMap editLines(QQuickTextDocument *doc, int selStart, int selEnd, const QString &op,
                                      const QString &unit = QString(), const QVariantMap &comment = QVariantMap());
    // Para nawiasów przy kursorze: [pozycja, pozycja] albo pusta lista
    Q_INVOKABLE QVariantList matchBracket(QQuickTextDocument *doc, int position) const;
    // { tabs: bool, size: int } — ze wcięć w tekście, domyślnie 4 spacje
    Q_INVOKABLE QVariantMap detectIndent(const QString &text) const;
    // { line: "//", start: "/*", end: "*/" } — z definicji języka KSyntaxHighlighting
    Q_INVOKABLE QVariantMap commentMarkers(const QString &fileName, const QString &language) const;
    // Zmiany z serwera języka [{ sl, sc, el, ec, text }] jednym krokiem cofania; zwraca liczbę zmian
    Q_INVOKABLE int applyEdits(QQuickTextDocument *doc, const QVariantList &edits);
    // Słowo (nazwa) pod pozycją: { start, end, text }
    Q_INVOKABLE QVariantMap wordAt(QQuickTextDocument *doc, int position) const;
    // Bloki konfliktu (<<<<<<< / ||||||| / ======= / >>>>>>>): [{ start, end, startLine, sepLine, endLine, ours, theirs }]
    Q_INVOKABLE QVariantList conflicts(QQuickTextDocument *doc) const;
    // choice: ours | theirs | both — zamienia blok zaczynający się w wierszu startLine
    Q_INVOKABLE bool resolveConflict(QQuickTextDocument *doc, int startLine, const QString &choice);
    // Wiele kursorów: zakresy [{ a, b }] (a ≤ b) zamieniane na texts[i] jednym krokiem cofania;
    // zwraca nowe kursory [{ p, i }] (i — numer zakresu; p — początek wstawienia + caretOffset, −1 — za wstawionym tekstem)
    Q_INVOKABLE QVariantList multiEdit(QQuickTextDocument *doc, const QVariantList &ranges, const QStringList &texts, int caretOffset = -1);
    // Następne wystąpienie tekstu od pozycji (z zawinięciem do początku); −1 — brak
    Q_INVOKABLE int findNext(QQuickTextDocument *doc, const QString &needle, int from, bool wholeWord) const;
    Q_INVOKABLE QVariantList findAll(QQuickTextDocument *doc, const QString &needle, bool wholeWord) const;
};
