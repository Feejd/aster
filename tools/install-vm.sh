#!/bin/sh
# Aster w maszynie wirtualnej jak w gotowym systemie: po restarcie ekran startowy Aster (bez tekstu),
# ukryte menu wyboru systemu i od razu sesja Aster — bez Plasmy i bez ręcznego uruchamiania dev-run.sh.
#   sh tools/install-vm.sh          instaluje (do /usr) i ustawia start
#   sh tools/install-vm.sh --undo   przywraca zwykły start Fedory (pliki Aster zostają)
set -e
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
BUILD="${BUILD:-$HOME/aster-build-system}"      # osobno od dev-run.sh (inne ustawienia budowania)
KARGS="rhgb quiet splash loglevel=3 rd.udev.log_level=3 systemd.show_status=false rd.systemd.show_status=false vt.global_cursor_default=0"
AUTOLOGIN=/etc/sddm.conf.d/zz-aster-autologin.conf

if [ "$1" = "--undo" ]; then
    sudo grubby --update-kernel=ALL --remove-args="splash loglevel=3 rd.udev.log_level=3 systemd.show_status=false rd.systemd.show_status=false vt.global_cursor_default=0"
    sudo grub2-editenv - unset menu_auto_hide
    sudo rm -f "$AUTOLOGIN"
    sudo plymouth-set-default-theme -R bgrt
    echo "Przywrócono zwykły start Fedory. Po restarcie: ekran logowania KDE z wyborem sesji."
    exit 0
fi

# Budowanie (te same pakiety i katalog co dev-run.sh)
rpm -q cmake kf6-kio-devel kf6-kservice-devel kf6-kconfig-devel libxcrypt-devel libvterm-devel jetbrains-mono-fonts-all layer-shell-qt-devel qt6-qtwebengine-devel plasma-workspace-devel >/dev/null 2>&1 || sh "$ROOT/tools/setup-vm.sh"
cmake -S "$ROOT" -B "$BUILD" -G Ninja -DCMAKE_BUILD_TYPE=Release -DCMAKE_INSTALL_PREFIX=/usr >/dev/null
cmake --build "$BUILD"

echo "==> Instaluję Aster w systemie…"
sudo cmake --install "$BUILD" >/dev/null
# Wersje z dev-run.sh w katalogu domowym przesłaniałyby zainstalowane
rm -f "$HOME/.local/bin/aster-terminal"
for app in files browser webapps store settings terminal; do rm -f "$HOME/.local/share/applications/org.aster.$app.desktop"; done
sudo systemctl --global enable aster-shell.service
fc-cache -f >/dev/null 2>&1 || true

echo "==> Ekran startowy Aster (przebudowa initramfs — chwilę potrwa)…"
rpm -q plymouth-plugin-script >/dev/null 2>&1 || sudo dnf install -y plymouth-plugin-script
sudo plymouth-set-default-theme -R aster
sudo grubby --update-kernel=ALL --args="$KARGS"
sudo grub2-editenv - set menu_auto_hide=1

echo "==> Logowanie od razu do sesji Aster…"
if systemctl is-enabled sddm >/dev/null 2>&1; then
    sudo mkdir -p /etc/sddm.conf.d
    printf '[Autologin]\nUser=%s\nSession=aster.desktop\nRelogin=false\n' "$USER" | sudo tee "$AUTOLOGIN" >/dev/null
else
    echo "   Ekran logowania to nie SDDM — wybierz sesję „Aster” przy logowaniu (zapamięta się)."
fi

echo
echo "Gotowe. Uruchom maszynę ponownie: sudo reboot"
echo "Powrót do zwykłego startu: sh $ROOT/tools/install-vm.sh --undo"
