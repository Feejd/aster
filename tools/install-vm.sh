#!/bin/sh
# Aster w maszynie wirtualnej jak w gotowym systemie: po restarcie ekran startowy Aster (bez tekstu),
# ukryte menu wyboru systemu, ekran logowania Aster i od razu sesja Aster — bez Plasmy i bez dev-run.sh.
#   sh tools/install-vm.sh          instaluje (do /usr) i ustawia start
#   sh tools/install-vm.sh --autologin   to samo, ale bez ekranu logowania (od razu pulpit)
#   sh tools/install-vm.sh --undo   przywraca zwykły start Fedory (pliki Aster zostają)
set -e
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
BUILD="${BUILD:-$HOME/aster-build-system}"      # osobno od dev-run.sh (inne ustawienia budowania)
KARGS="rhgb quiet splash loglevel=3 rd.udev.log_level=3 systemd.show_status=false rd.systemd.show_status=false vt.global_cursor_default=0"
AUTOLOGIN=/etc/sddm.conf.d/zz-aster-autologin.conf

if [ "$1" = "--undo" ]; then
    sudo grubby --update-kernel=ALL --remove-args="splash loglevel=3 rd.udev.log_level=3 systemd.show_status=false rd.systemd.show_status=false vt.global_cursor_default=0"
    sudo grub2-editenv - unset menu_auto_hide
    sudo rm -f "$AUTOLOGIN" /etc/sddm.conf.d/10-aster.conf /etc/systemd/system/sddm.service.d/10-aster-plymouth.conf
    for s in /usr/share/wayland-sessions/plasma*.desktop; do [ -f "$s" ] && sudo sed -i '/^NoDisplay=true$/d; /^Hidden=true$/d' "$s"; done
    if [ -f /etc/aster-previous-dm ]; then sudo systemctl enable --force "$(cat /etc/aster-previous-dm)"; sudo rm -f /etc/aster-previous-dm; fi
    sudo plymouth-set-default-theme -R bgrt
    echo "Przywrócono zwykły start Fedory. Po restarcie: ekran logowania KDE z wyborem sesji."
    exit 0
fi

# Budowanie (te same pakiety i katalog co dev-run.sh)
rpm -q cmake kf6-kio-devel kf6-kservice-devel kf6-kconfig-devel libxcrypt-devel libvterm-devel polkit-qt6-1-devel jetbrains-mono-fonts-all layer-shell-qt-devel qt6-qtwebengine-devel plasma-workspace-devel exiv2-devel qt6-qtpdf-devel kf6-syntax-highlighting-devel qt6-qtmultimedia-devel taglib-devel libarchive-devel kf6-solid-devel plasma-wayland-protocols-devel kf6-kguiaddons-devel >/dev/null 2>&1 || sh "$ROOT/tools/setup-vm.sh"
cmake -S "$ROOT" -B "$BUILD" -G Ninja -DCMAKE_BUILD_TYPE=Release -DCMAKE_INSTALL_PREFIX=/usr >/dev/null
cmake --build "$BUILD"

echo "==> Instaluję Aster w systemie…"
sudo cmake --install "$BUILD" >/dev/null
# Wersje z dev-run.sh w katalogu domowym przesłaniałyby zainstalowane
rm -f "$HOME/.local/bin/aster-terminal"
for app in files browser webapps store settings terminal tasks photos pdf editor calculator video music emoji; do rm -f "$HOME/.local/share/applications/org.aster.$app.desktop"; done
rm -f "$HOME/.local/share/kglobalaccel/org.aster.tasks.desktop" "$HOME/.local/share/kglobalaccel/org.aster.emoji.desktop" \
      "$HOME/.local/share/kglobalaccel/org.kde.plasma.emojier.desktop" "$HOME/.local/share/applications/org.aster.emoji.desktop"
# Win+. — panel emoji Aster zamiast wybieraka KDE (zapamiętany skrót użytkownika też)
kwriteconfig6 --file kglobalaccelrc --group org.kde.plasma.emojier.desktop --key _launch "Meta+Ctrl+Alt+Shift+Space,Meta+Ctrl+Alt+Shift+Space,Emoji Selector" 2>/dev/null || true
sudo systemctl --global enable aster-shell.service
fc-cache -f >/dev/null 2>&1 || true

echo "==> Ekran startowy Aster (przebudowa initramfs — chwilę potrwa)…"
rpm -q plymouth-plugin-script >/dev/null 2>&1 || sudo dnf install -y plymouth-plugin-script
sudo plymouth-set-default-theme -R aster
sudo grubby --update-kernel=ALL --args="$KARGS"
sudo grub2-editenv - set menu_auto_hide=1
# Menu ukrywa się tylko po udanym poprzednim starcie (znacznik stawiany ~2 min po zalogowaniu) — stawiamy go od razu
sudo grub2-editenv - set boot_success=1

echo "==> Ekran logowania Aster (SDDM)…"
rpm -q sddm sddm-wayland-plasma >/dev/null 2>&1 || sudo dnf install -y sddm sddm-wayland-plasma
# Zapamiętaj poprzedni menedżer logowania (np. Plasma Login Manager), żeby --undo mógł go przywrócić
current=$(basename "$(readlink -f /etc/systemd/system/display-manager.service 2>/dev/null)" 2>/dev/null)
[ -n "$current" ] && [ "$current" != sddm.service ] && echo "$current" | sudo tee /etc/aster-previous-dm >/dev/null
sudo systemctl enable --force sddm.service
# Znak Aster zostaje do pojawienia się ekranu logowania (bez czarnej przerwy)
sudo mkdir -p /etc/systemd/system/sddm.service.d
sudo cp "$ROOT/image/boot/10-aster-plymouth.conf" /etc/systemd/system/sddm.service.d/10-aster-plymouth.conf
sudo systemctl daemon-reload
sudo mkdir -p /etc/sddm.conf.d
printf '[Theme]\nCurrent=aster\n' | sudo tee /etc/sddm.conf.d/10-aster.conf >/dev/null
# Ukryj sesję Plasmy na liście (zostaje w systemie; wraca po aktualizacji pakietu plasma-workspace)
for s in /usr/share/wayland-sessions/plasma*.desktop; do
    [ -f "$s" ] && ! grep -q "^Hidden=true" "$s" && sudo sed -i '/^\[Desktop Entry\]/a NoDisplay=true\nHidden=true' "$s"
done
# Ostatnia sesja = Aster (ekran logowania zaznaczy ją od razu)
printf '[Last]\nSession=/usr/share/wayland-sessions/aster.desktop\nUser=%s\n' "$USER" | sudo tee /var/lib/sddm/state.conf >/dev/null 2>&1 || true

if [ "$1" = "--autologin" ]; then
    printf '[Autologin]\nUser=%s\nSession=aster.desktop\nRelogin=false\n' "$USER" | sudo tee "$AUTOLOGIN" >/dev/null
    echo "   Automatyczne logowanie włączone (bez ekranu logowania)."
else
    sudo rm -f "$AUTOLOGIN"
fi

echo
echo "Gotowe. Uruchom maszynę ponownie: sudo reboot"
echo "Ekran logowania Aster: hasło jak dotąd. Bez logowania: sh $ROOT/tools/install-vm.sh --autologin"
echo "Powrót do zwykłego startu: sh $ROOT/tools/install-vm.sh --undo"
