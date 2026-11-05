pragma ComponentBehavior: Bound
import QtQuick
import Aster.Ui
import Aster.Studio

// Przeglądarka z lewej: wszystko, z czego robi się muzykę. Kliknięcie dodaje kanał do racka;
// efekt VST3 idzie na insert zaznaczony w mikserze.
Item {
    id: br
    property string open: "kits"
    property string query: ""
    signal effectAdded()
    function match(t) { return query === "" || t.toLowerCase().includes(query.toLowerCase()); }
    readonly property var rows: [{ id: "kick", label: "Stopa" }, { id: "snare", label: "Werbel" }, { id: "clap", label: "Klaśnięcie" },
                                 { id: "hat", label: "Hi-hat" }, { id: "openhat", label: "Otwarty hat" }, { id: "perc", label: "Perkusjonalia" }]
    readonly property var sounds: Studio.open && Studio.sourcesVersion >= 0 ? Studio.projectSounds() : []
    property var libraryItems: []
    property var channelPresets: []
    property var insertPresets: []
    function reload() {
        libraryItems = Studio.library();
        channelPresets = Studio.presetList("channel");
        insertPresets = Studio.presetList("insert");
    }
    onOpenChanged: reload()
    Connections { target: Studio; function onPresetsChanged() { br.reload(); } }
    Component.onCompleted: { reload(); Qt.callLater(Studio.scanPlugins); }

    Rectangle { anchors.fill: parent; color: Theme.windowGlass }
    Rectangle { anchors.right: parent.right; width: 1; height: parent.height; color: Theme.line }
    Field {
        id: search
        x: 10; y: 10; width: parent.width - 20; height: 32
        placeholder: "Szukaj dźwięku…"
        input.onTextChanged: br.query = input.text
    }
    Flickable {
        x: 0; y: 50
        width: parent.width; height: parent.height - y
        contentHeight: list.height + 12
        clip: true
        boundsBehavior: Flickable.StopAtBounds
        Column {
            id: list
            width: parent.width
            Section { key: "kits"; label: "Perkusja" }
            Repeater {
                model: br.open === "kits" || br.query !== "" ? Studio.kits : []
                delegate: Column {
                    id: kit
                    required property var modelData
                    width: list.width
                    Text { x: 16; visible: br.match(kit.modelData.label) || br.query === ""; text: kit.modelData.label; color: Theme.text2; topPadding: 6; bottomPadding: 2; font.family: Theme.font; font.pixelSize: 11; font.weight: Font.DemiBold }
                    Repeater {
                        model: br.rows
                        delegate: Entry {
                            required property var modelData
                            label: modelData.label
                            visible: br.match(modelData.label + " " + kit.modelData.label)
                            onClicked: Studio.addChannel("drum", kit.modelData.id + ":" + modelData.id, modelData.label)
                        }
                    }
                    Entry { label: "808"; icon: "audioTrack"; visible: br.match("808 " + kit.modelData.label); onClicked: Studio.addChannel("bass", kit.modelData.id) }
                }
            }
            Section { key: "synth"; label: "Instrumenty Studia" }
            Repeater {
                model: br.open === "synth" || br.query !== "" ? Studio.instruments : []
                delegate: Entry {
                    required property var modelData
                    label: modelData.label
                    icon: "keyboard"
                    visible: br.match(modelData.label)
                    onClicked: Studio.addChannel("synth", modelData.id, modelData.label)
                }
            }
            Section { key: "vsti"; label: "Instrumenty VST3" }
            Repeater {
                model: br.open === "vsti" || br.query !== "" ? Studio.plugins.filter((p) => p.instrument) : []
                delegate: Entry {
                    required property var modelData
                    label: modelData.name
                    icon: "keyboard"
                    visible: br.match(modelData.name + " " + modelData.vendor)
                    onClicked: Studio.addChannel("vst", modelData.uid)
                }
            }
            Hint { visible: br.open === "vsti" && Studio.plugins.filter((p) => p.instrument).length === 0; text: "Nie ma instrumentów VST3. Instaluje się je do ~/.vst3." }
            Section { key: "vstfx"; label: "Efekty VST3" }
            Repeater {
                model: br.open === "vstfx" || br.query !== "" ? Studio.plugins.filter((p) => !p.instrument) : []
                delegate: Entry {
                    required property var modelData
                    label: modelData.name
                    icon: "sliders"
                    visible: br.match(modelData.name + " " + modelData.vendor)
                    onClicked: { Studio.addPlugin(Studio.selectedInsert, modelData.uid); br.effectAdded(); }
                }
            }
            Section { key: "lib"; label: "Biblioteka" }
            Repeater {
                model: br.open === "lib" || br.query !== "" ? br.libraryItems : []
                delegate: Entry {
                    id: libEntry
                    required property var modelData
                    label: modelData.name
                    icon: "audioTrack"
                    visible: br.match(modelData.name + " " + modelData.folder)
                    onClicked: Studio.addSample(modelData.path)
                    HoverButton {
                        anchors.right: parent.right; anchors.rightMargin: 8; anchors.verticalCenter: parent.verticalCenter
                        width: 22; height: 22; radius: 6
                        onClicked: Studio.previewFile(libEntry.modelData.path)
                        Icon { anchors.centerIn: parent; d: Icons.play; size: 11; stroke: 2; color: Theme.text2 }
                        Tip { shown: parent.hovered; text: "Posłuchaj" }
                    }
                }
            }
            Hint { visible: br.open === "lib" && br.libraryItems.length === 0; text: "Dodaj sample do folderu Biblioteka obok projektów. Pliki można też upuścić na rack." }
            Section { key: "presets"; label: "Zapisane ustawienia" }
            Repeater {
                model: br.open === "presets" ? br.channelPresets : []
                delegate: Entry {
                    required property var modelData
                    label: modelData.name
                    icon: "keyboard"
                    onClicked: Studio.loadPreset("channel", Studio.selectedChannel, modelData.path)
                }
            }
            Repeater {
                model: br.open === "presets" ? br.insertPresets : []
                delegate: Entry {
                    required property var modelData
                    label: modelData.name
                    icon: "sliders"
                    onClicked: Studio.loadPreset("insert", Studio.selectedInsert, modelData.path)
                }
            }
            Hint { visible: br.open === "presets" && br.channelPresets.length + br.insertPresets.length === 0; text: "Ustawienia kanału i insertu zapisuje się przyciskami w ich panelach." }
            Section { key: "files"; label: "Dźwięki projektu" }
            Repeater {
                model: br.open === "files" || br.query !== "" ? br.sounds : []
                delegate: Entry {
                    required property var modelData
                    label: modelData
                    icon: "audioTrack"
                    visible: br.match(modelData)
                    onClicked: Studio.addChannel("sampler", modelData)
                }
            }
            Hint { visible: br.open === "files" && br.sounds.length === 0; text: "Tu pojawią się nagrania i pliki dodane do projektu." }
        }
    }

    component Section: HoverButton {
        id: sec
        property string key
        property string label
        width: parent ? parent.width : 0; height: 34; radius: 0
        onClicked: br.open = br.open === key ? "" : key
        Icon { x: 10; anchors.verticalCenter: parent.verticalCenter; d: br.open === sec.key ? Icons.chevronDown : Icons.chevronRight; size: 13; stroke: 2; color: Theme.text2 }
        Text { x: 30; anchors.verticalCenter: parent.verticalCenter; text: sec.label; color: Theme.text; font.family: Theme.font; font.pixelSize: 13; font.weight: Font.DemiBold }
    }
    component Entry: HoverButton {
        id: en
        property string label
        property string icon: "music"
        width: parent ? parent.width : 0; height: visible ? 28 : 0; radius: 0
        Icon { x: 16; anchors.verticalCenter: parent.verticalCenter; d: Icons[en.icon] || ""; size: 13; stroke: 1.9; color: Theme.text2 }
        Text { x: 36; width: parent.width - 44; anchors.verticalCenter: parent.verticalCenter; text: en.label; elide: Text.ElideRight; color: Theme.text; font.family: Theme.font; font.pixelSize: 12 }
    }
    component Hint: Text {
        x: 16; width: br.width - 32
        wrapMode: Text.WordWrap
        color: Theme.text2; topPadding: 4; bottomPadding: 8
        font.family: Theme.font; font.pixelSize: 11
    }
}
