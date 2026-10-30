#!/bin/sh
# Jednorazowe przygotowanie maszyny wirtualnej Fedora KDE do pracy nad Aster.
set -e
if [ -d /run/initramfs/live ] || [ "$(id -un)" = "liveuser" ]; then
    echo "!! To jest wersja Live z płyty — najpierw zainstaluj Fedorę (ikona „Install to Hard Drive”),"
    echo "   zrestartuj, zaloguj się na swoje konto i uruchom ten skrypt ponownie."
    exit 1
fi
echo "==> Aktualizuję system (poprosi o hasło)…"
# Pakiety -devel wymagają najnowszych bibliotek KDE, więc najpierw pełna aktualizacja.
# --allowerasing pozwala dnf zamieniać przemianowane pakiety (np. kmime → kf6-kmime).
sudo dnf upgrade -y --refresh --allowerasing

echo "==> Instaluję narzędzia do budowania…"
sudo dnf install -y --skip-unavailable --allowerasing \
    git cmake ninja-build gcc-c++ extra-cmake-modules \
    qt6-qtbase-devel qt6-qtdeclarative-devel \
    layer-shell-qt-devel kf6-kwindowsystem-devel kf6-kservice-devel kf6-kio-devel qt6-qtwebengine-devel plasma-workspace-devel \
    rsms-inter-fonts google-roboto-fonts open-vm-tools-desktop

# Folder udostępniony z Maca montowany przy każdym starcie
# (VMware: Ustawienia maszyny → Sharing → folder „Aster”)
sudo mkdir -p /mnt/hgfs
if ! grep -q "/mnt/hgfs" /etc/fstab; then
    echo ".host:/ /mnt/hgfs fuse.vmhgfs-fuse defaults,allow_other,nofail 0 0" | sudo tee -a /etc/fstab >/dev/null
    sudo systemctl daemon-reload
fi

for tool in cmake ninja g++; do
    command -v "$tool" >/dev/null || { echo "!! Brakuje: $tool — przewiń w górę i sprawdź błąd dnf."; exit 1; }
done
echo "==> Gotowe. Teraz uruchom: sh /mnt/hgfs/Aster/tools/dev-run.sh"
