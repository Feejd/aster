import QtQuick

// Strona ustawień: przewijana kolumna sekcji
Flickable {
    id: page
    default property alias content: col.data
    // Przejście do innego działu (np. Klawiatura → Skróty klawiszowe) — obsługuje okno
    signal navigate(string id)
    contentHeight: col.y + col.height + 40
    boundsBehavior: Flickable.StopAtBounds
    clip: true
    Column {
        id: col
        x: 32; y: 6
        width: page.width - 64
        spacing: 24
    }
}
