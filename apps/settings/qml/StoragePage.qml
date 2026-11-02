pragma ComponentBehavior: Bound
import QtQuick
import Aster.Ui
import Aster.Settings

// Pamięć (jak „Magazyn” w Windows): pasek zajętego miejsca podzielony na kategorie, lista kategorii
// (klik otwiera folder), porządkowanie (pliki tymczasowe, kosz), największe foldery i podłączone dyski.
Page {
    id: sp
    Component.onCompleted: Storage.scan()

    readonly property var cats: Storage.categories
    readonly property real maxCat: cats.length ? Math.max(1, ...cats.map(c => c.size)) : 1
    function cat(id) { return cats.find(c => c.id === id) || { size: 0, sizeText: "0 B" }; }

    Section {
        title: "Dysk systemowy"
        Item {
            width: parent.width; height: 96
            Text {
                x: 16; y: 16
                text: Storage.summary || "Liczę…"
                color: Theme.text; font.family: Theme.font; font.pixelSize: 15; font.weight: Font.DemiBold
            }
            Text {
                anchors.right: parent.right; anchors.rightMargin: 16; y: 18
                visible: Storage.scanning
                text: "Sprawdzam, co zajmuje miejsce…"
                color: Theme.text2; font.family: Theme.font; font.pixelSize: 12
            }
            // Pasek: kategorie jedna po drugiej, reszta — wolne miejsce
            Rectangle {
                id: bar
                x: 16; y: 48
                width: parent.width - 32; height: 16; radius: 8
                color: Theme.fill
                Row {
                    Repeater {
                        model: Storage.total > 0 ? sp.cats : []
                        delegate: Rectangle {
                            required property var modelData
                            required property int index
                            width: bar.width * modelData.size / Storage.total
                            height: bar.height
                            topLeftRadius: index === 0 ? bar.radius : 0
                            bottomLeftRadius: index === 0 ? bar.radius : 0
                            color: modelData.color
                        }
                    }
                }
            }
            Text {
                x: 16; y: 72
                text: Storage.total > 0 ? Storage.size(Storage.total - Storage.used) + " wolne" : ""
                color: Theme.text2; font.family: Theme.font; font.pixelSize: 12
            }
        }
    }

    Section {
        title: "Co zajmuje miejsce"
        Repeater {
            model: sp.cats
            delegate: SettingRow {
                id: catRow
                required property var modelData
                title: modelData.name
                icon: modelData.icon
                colors: [Qt.lighter(modelData.color, 1.35), modelData.color]
                clickable: modelData.id !== "system"
                onClicked: Storage.open(modelData.path)
                Item {
                    width: 120; height: 6
                    anchors.verticalCenter: parent ? parent.verticalCenter : undefined
                    Rectangle {
                        width: parent.width; height: 6; radius: 3; color: Theme.fill
                        Rectangle { width: Math.max(3, parent.width * catRow.modelData.size / sp.maxCat); height: 6; radius: 3; color: catRow.modelData.color }
                    }
                }
                Text {
                    width: 70; horizontalAlignment: Text.AlignRight
                    anchors.verticalCenter: parent ? parent.verticalCenter : undefined
                    text: catRow.modelData.sizeText
                    color: Theme.text2; font.family: Theme.font; font.pixelSize: 13; font.features: { "tnum": 1 }
                }
            }
        }
    }

    Section {
        title: "Porządkowanie"
        footer: "Pliki tymczasowe to pamięć podręczna programów (miniatury, pobrane strony) — programy odtworzą ją same, gdy będzie potrzebna."
        SettingRow {
            title: "Pliki tymczasowe"
            subtitle: sp.cat("temp").sizeText
            icon: "clock"; colors: ["#FDE68A", "#CA8A04"]
            TextButton { text: "Wyczyść"; enabled: sp.cat("temp").size > 0 && !Storage.scanning; onClicked: Storage.cleanTemp() }
        }
        SettingRow {
            title: "Kosz"
            subtitle: sp.cat("trash").sizeText
            icon: "trash"; colors: ["#CBD5E1", "#64748B"]
            TextButton { text: "Opróżnij"; enabled: sp.cat("trash").size > 0 && !Storage.scanning; onClicked: trashSheet.open() }
        }
        SettingRow {
            title: "Pobrane"
            subtitle: sp.cat("downloads").sizeText + " — przejrzyj i usuń niepotrzebne instalatory i archiwa"
            icon: "download"; colors: ["#5EEAD4", "#0D9488"]
            chevron: true
            onClicked: Storage.open(sp.cat("downloads").path)
        }
    }

    Section {
        title: "Największe foldery"
        visible: Storage.largest.length > 0
        Repeater {
            model: Storage.largest
            delegate: SettingRow {
                required property var modelData
                title: modelData.name
                icon: "folder"
                value: modelData.sizeText
                chevron: true
                onClicked: Storage.open(modelData.path)
            }
        }
    }

    Section {
        title: "Dyski"
        Repeater {
            model: Storage.drives
            delegate: SettingRow {
                id: driveRow
                required property var modelData
                title: modelData.name
                subtitle: modelData.freeText
                icon: "drive"
                chevron: true
                onClicked: Storage.open(modelData.path)
                Rectangle {
                    anchors.verticalCenter: parent ? parent.verticalCenter : undefined
                    width: 120; height: 6; radius: 3; color: Theme.fill
                    Rectangle { width: parent.width * driveRow.modelData.usedRatio; height: 6; radius: 3; color: driveRow.modelData.usedRatio > 0.9 ? Theme.danger : Theme.accent }
                }
            }
        }
    }

    Sheet {
        id: trashSheet
        title: "Opróżnić kosz?"
        subtitle: "Usuniesz na zawsze " + sp.cat("trash").sizeText + " plików. Tego nie można cofnąć."
        acceptText: "Opróżnij kosz"
        danger: true
        onAccepted: Storage.emptyTrash()
    }
}
