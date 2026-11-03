#!/bin/sh
# Programy KDE, które Aster zastępuje własnymi, znikają z systemu; okna KDE, które muszą zostać (Ustawienia KDE
# dla zaawansowanych, edytor menu), znikają tylko ze Startu.
#   sh image/debloat.sh             obraz systemu (image/Containerfile, jako root): usuń pakiety i ukryj okna
#   sh image/debloat.sh --hide      tylko ukryj okna w Starcie bieżącego użytkownika (~/.local/share/applications)
#   sh image/debloat.sh --dry-run   pokaż, co dnf by usunął, niczego nie zmieniając
set -e

# Zastąpione przez programy Aster: Pliki, Terminal, Edytor, PDF, Zdjęcia, Muzyka, Wideo, Kamera, Skaner,
# Kalkulator, Pakowanie w Plikach, Pamięć/Dyski, panel emoji i znaków, Sklep, Menedżer zadań, Ustawienia → Ogólne
REPLACED="dolphin dolphin-plugins konsole kate kate-plugins kwrite okular gwenview elisa-player dragon haruna
kamoso skanlite kcalc ark filelight kde-partitionmanager kcharselect
plasma-discover plasma-discover-* plasma-systemmonitor kinfocenter ksystemlog kjournald kwalletmanager5 kfind
kmail kontact akregator korganizer kaddressbook kdepim kdepim-* khelpcenter plasma-welcome plasma-welcome-fedora
plasma-drkonqi kmahjongg kmines kpat ksudoku kolourpaint krdc krfb kmousetool kmag kmouth
pim-sieve-editor pim-data-exporter akonadi-import-wizard akonadiconsole kmail-account-wizard grantlee-editor
kleopatra kgpg neochat qrca skanpage kdebugsettings mediawriter gnome-abrt abrt-gui abrt-desktop setroubleshoot
libreoffice libreoffice-*"
# LibreOffice też: biuro to w Asterze aplikacje webowe (Dokumenty, Arkusze) albo Flatpak ze Sklepu

# Infrastruktura bez własnych okien (albo potrzebna Asterowi) — po usuwaniu musi zostać
KEEP="kwin plasma-workspace kdeconnectd kio-extras kf6-kio-core kf6-kio-widgets sddm plasma-nm powerdevil
pipewire NetworkManager bluez kde-cli-tools xdg-desktop-portal-kde polkit-kde systemsettings spectacle
layer-shell-qt kf6-solid kf6-kwallet kde-connect flatpak fuse-sshfs fwupd cups-client ModemManager"
# kde-connect zostaje mimo programu Telefon: usługa kdeconnectd wymaga tego pakietu (jego okna są tylko ukryte)

# Zostają w systemie, ale nie w Starcie (Ustawienia KDE otwiera się z Ustawień Aster → Ogólne)
HIDE="systemsettings kdesystemsettings org.kde.kmenuedit org.kde.keditbookmarks org.kde.kwalletd org.kde.plasma.emojier org.kde.kdeconnect.daemon
org.kde.kdeconnect.app org.kde.kdeconnect.sms org.kde.kdeconnect-settings org.kde.kdeconnect.nonplasma
org.kde.drkonqi.coredump.gui org.kde.kwalletd6 org.kde.klipper org.kde.kscreen org.kde.plasma-welcome
org.kde.discover org.kde.discover.notifier org.kde.dolphin org.kde.konsole org.kde.kwrite org.kde.kate
org.kde.okular org.kde.gwenview org.kde.ark org.kde.kcalc org.kde.kinfocenter org.kde.plasma-systemmonitor
org.kde.spectacle org.kde.skanpage org.kde.kdebugsettings org.kde.kleopatra org.kde.kwatchgnupg org.kde.neochat
org.kde.qrca org.kde.sieveeditor org.kde.pimdataexporter org.kde.akonadiimportwizard org.kde.contactthemeeditor
org.kde.contactprintthemeeditor org.kde.headerthemeeditor org.fedoraproject.MediaWriter org.freedesktop.GnomeAbrt
org.freedesktop.problems.applet setroubleshoot im-chooser firewall-config qt6-designer qt6-linguist qt6-assistant
kwalletmanager5-kwalletd org.kde.kwalletmanager libreoffice-startcenter libreoffice-writer libreoffice-calc
libreoffice-impress libreoffice-draw libreoffice-math libreoffice-base libreoffice-xsltfilter"
# Zrzuty ekranu (Spectacle) działają dalej pod Print Screen i z centrum sterowania — tylko bez ikony w Starcie.
# Qt Designer/Linguist przychodzą z pakietami do budowania (maszyna wirtualna), zapora i metody wprowadzania z Fedory.

hide_system() {
    for id in $HIDE; do
        f="/usr/share/applications/$id.desktop"
        [ -f "$f" ] && ! grep -q '^NoDisplay=true' "$f" && sed -i '/^\[Desktop Entry\]/a NoDisplay=true' "$f"
    done
    return 0
}

# Kopia w ~/.local/share/applications z NoDisplay=true przesłania systemową (pakiet zostaje nietknięty)
hide_user() {
    dir="$HOME/.local/share/applications"
    mkdir -p "$dir"
    for id in $HIDE; do
        f="/usr/share/applications/$id.desktop"
        [ -f "$f" ] || continue
        sed '/^NoDisplay=/d; /^\[Desktop Entry\]/a NoDisplay=true' "$f" > "$dir/$id.desktop"
    done
    return 0
}

if [ "$1" = "--hide" ]; then
    hide_user
    exit 0
fi

# Tylko zainstalowane (wzorce z gwiazdką rozwija rpm)
remove=""
for p in $REPLACED; do
    remove="$remove $(rpm -qa --qf '%{NAME}\n' "$p" 2>/dev/null)"
done
keep=""
for p in $KEEP; do
    rpm -q "$p" >/dev/null 2>&1 && keep="$keep $p"
done

if [ "$1" = "--dry-run" ]; then
    echo "Do usunięcia:$remove"
    [ -n "$(echo $remove)" ] && dnf remove --assumeno --setopt=clean_requirements_on_remove=False $remove || true
    exit 0
fi

# Bez sprzątania „niepotrzebnych” zależności: w obrazie z rpm-ostree dnf uważa za takie np. flatpak i fwupd
[ -n "$(echo $remove)" ] && dnf remove -y --setopt=clean_requirements_on_remove=False $remove

missing=""
for p in $keep; do
    rpm -q "$p" >/dev/null 2>&1 || missing="$missing $p"
done
if [ -n "$missing" ]; then
    echo "debloat: usuwanie zabrało potrzebne pakiety:$missing" >&2
    exit 1
fi

hide_system
