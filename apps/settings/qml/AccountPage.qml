pragma ComponentBehavior: Bound
import QtQuick
import QtQuick.Dialogs
import Aster.Ui
import Aster.Settings

// Konto: zdjęcie, imię i hasło; inne osoby korzystające z komputera (dodawanie i usuwanie kont)
Page {
    id: acp
    property var removing: null

    component Avatar: Rectangle {
        id: av
        property string name
        property string url
        property real size: 44
        width: size; height: size; radius: size / 2
        clip: true
        gradient: Gradient {
            GradientStop { position: 0; color: "#7C9BFF" }
            GradientStop { position: 1; color: "#8B5CF6" }
        }
        Text { anchors.centerIn: parent; visible: img.status !== Image.Ready; text: av.name.charAt(0).toUpperCase(); color: "white"; font.family: Theme.font; font.pixelSize: av.size * 0.42; font.weight: Font.DemiBold }
        Image { id: img; anchors.fill: parent; source: av.url; fillMode: Image.PreserveAspectCrop; sourceSize: Qt.size(av.size * 2, av.size * 2); visible: status === Image.Ready }
    }

    Item {
        width: parent.width; height: 196
        Column {
            anchors.centerIn: parent
            spacing: 10
            Item {
                anchors.horizontalCenter: parent.horizontalCenter
                width: 96; height: 96
                Avatar { anchors.fill: parent; size: 96; name: Accounts.realName || Accounts.userName; url: Accounts.iconUrl }
                Rectangle {
                    anchors.fill: parent; radius: 48
                    color: Qt.rgba(0, 0, 0, 0.45)
                    opacity: picArea.containsMouse ? 1 : 0
                    Behavior on opacity { NumberAnimation { duration: 120 } }
                    Text { anchors.centerIn: parent; text: "Zmień"; color: "white"; font.family: Theme.font; font.pixelSize: 13; font.weight: Font.Medium }
                }
                MouseArea { id: picArea; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor; onClicked: picker.open() }
            }
            Text { anchors.horizontalCenter: parent.horizontalCenter; text: Accounts.realName || Accounts.userName; color: Theme.text; font.family: Theme.font; font.pixelSize: 22; font.weight: Font.Bold; font.letterSpacing: -0.4 }
            Text { anchors.horizontalCenter: parent.horizontalCenter; text: Accounts.userName + (Accounts.admin ? " · Administrator" : " · Zwykłe konto"); color: Theme.text2; font.family: Theme.font; font.pixelSize: 13 }
        }
    }

    Section {
        SettingRow {
            title: "Imię i nazwisko"
            value: Accounts.realName
            icon: "user"
            chevron: true
            onClicked: { nameField.text = Accounts.realName; nameSheet.open(); }
        }
        SettingRow {
            title: "Zmień hasło"
            icon: "lock"
            chevron: true
            onClicked: { pass1.text = ""; pass2.text = ""; passSheet.open(); }
        }
        SettingRow {
            title: "Zablokuj ekran teraz"
            icon: "moon"
            chevron: true
            onClicked: System.run("loginctl", ["lock-session"])
        }
    }

    Section {
        title: "Inne osoby"
        footer: "Każda osoba ma własne pliki, tapetę i ustawienia. Administrator może instalować programy i zmieniać ustawienia systemu."
        Repeater {
            model: Accounts.others
            delegate: SettingRow {
                id: other
                required property var modelData
                title: modelData.realName || modelData.userName
                subtitle: modelData.userName + (modelData.admin ? " · Administrator" : "")
                icon: "user"
                HoverButton {
                    visible: Accounts.admin
                    anchors.verticalCenter: parent.verticalCenter
                    width: 28; height: 28; radius: 14
                    onClicked: { acp.removing = other.modelData; removeSheet.open(); }
                    Icon { anchors.centerIn: parent; d: Icons.trash; size: 15; color: Theme.text2 }
                }
            }
        }
        SettingRow {
            visible: Accounts.others.length === 0
            title: "Z komputera korzysta tylko jedna osoba"
        }
        SettingRow {
            visible: Accounts.admin
            title: "Dodaj osobę"
            titleColor: Theme.accentText
            icon: "plus"
            clickable: true
            onClicked: { newName.text = ""; newLogin.text = ""; newPass.text = ""; newAdmin.checked = false; addSheet.open(); }
        }
    }

    FileDialog {
        id: picker
        title: "Wybierz zdjęcie"
        nameFilters: ["Zdjęcia (*.jpg *.jpeg *.png *.webp *.heic)"]
        currentFolder: "file://" + System.picturesDir
        onAccepted: Accounts.setIcon(selectedFile.toString())
    }

    Sheet {
        id: nameSheet
        title: "Imię i nazwisko"
        subtitle: "Widać je na ekranie logowania i w Starcie."
        acceptEnabled: nameField.text.trim().length > 0
        Field { id: nameField; placeholder: "Imię i nazwisko"; onSubmitted: { if (nameSheet.acceptEnabled) { Accounts.setRealName(text); nameSheet.close(); } } }
        onAccepted: Accounts.setRealName(nameField.text)
    }

    Sheet {
        id: passSheet
        title: "Zmień hasło"
        subtitle: "System zapyta jeszcze o obecne hasło."
        acceptEnabled: pass1.text.length >= 4 && pass1.text === pass2.text
        acceptText: "Zmień hasło"
        Field { id: pass1; password: true; placeholder: "Nowe hasło" }
        Field { id: pass2; password: true; placeholder: "Powtórz nowe hasło" }
        Text {
            visible: pass2.text.length > 0 && pass1.text !== pass2.text
            text: "Hasła się różnią"
            color: Theme.danger; font.family: Theme.font; font.pixelSize: 12
        }
        onAccepted: Accounts.setPassword(pass1.text)
    }

    Sheet {
        id: addSheet
        title: "Nowa osoba"
        acceptText: "Dodaj"
        acceptEnabled: newName.text.trim() && /^[a-z_][a-z0-9_-]*$/.test(newLogin.text) && newPass.text.length >= 4
        Field { id: newName; placeholder: "Imię i nazwisko"; onTextChanged: newLogin.text = Accounts.suggestUserName(text) }
        Field { id: newLogin; placeholder: "Nazwa konta (małe litery, bez spacji)" }
        Field { id: newPass; password: true; placeholder: "Hasło" }
        Row {
            spacing: 10
            Toggle { id: newAdmin; onToggled: on => checked = on }
            Text { anchors.verticalCenter: parent.verticalCenter; text: "Administrator"; color: Theme.text; font.family: Theme.font; font.pixelSize: 13 }
        }
        onAccepted: Accounts.createUser(newLogin.text, newName.text.trim(), newAdmin.checked, newPass.text)
    }

    Sheet {
        id: removeSheet
        title: acp.removing ? "Usunąć konto „" + (acp.removing.realName || acp.removing.userName) + "”?" : ""
        subtitle: "Pliki tej osoby (dokumenty, zdjęcia, pobrane) też zostaną usunięte."
        acceptText: "Usuń konto"
        danger: true
        onAccepted: Accounts.deleteUser(acp.removing.uid, true)
    }
}
