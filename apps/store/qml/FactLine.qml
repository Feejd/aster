import QtQuick
import Aster.Ui
import Aster.Store

// Wiersz karty programu: kropka z oceną, co sprawdzamy, co wyszło
Item {
    id: f
    property string tone: "info"
    property string title
    property string text
    implicitHeight: col.implicitHeight + 16
    width: parent ? parent.width : 280

    Rectangle {
        x: 0; y: 13
        width: 8; height: 8; radius: 4
        color: f.tone === "unknown" ? "transparent" : Ui.tone(f.tone)
        border.width: f.tone === "unknown" ? 1.5 : 0
        border.color: Ui.tone("unknown")
    }
    Column {
        id: col
        x: 20; y: 8
        width: parent.width - 20
        spacing: 1
        Txt { text: f.title; color: Theme.text2; font.pixelSize: 11; font.weight: Font.DemiBold }
        Txt { width: parent.width; text: f.text; wrapMode: Text.Wrap; font.pixelSize: 13; lineHeight: 1.15 }
    }
}
