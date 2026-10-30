#!/bin/sh
# Jednorazowe przygotowanie maszyny wirtualnej Fedora KDE do pracy nad Aster.
set -e
sudo dnf install -y \
    git cmake ninja-build gcc-c++ extra-cmake-modules \
    qt6-qtbase-devel qt6-qtdeclarative-devel \
    layer-shell-qt-devel kf6-kwindowsystem-devel \
    rsms-inter-fonts open-vm-tools-desktop

# Folder udostępniony z Maca (VMware: Ustawienia maszyny → Sharing → folder „Aster”)
sudo mkdir -p /mnt/hgfs
if ! grep -q hgfs /etc/fstab; then
    echo "vmhgfs-fuse /mnt/hgfs fuse defaults,allow_other,_netdev 0 0" | sudo tee -a /etc/fstab
fi
sudo systemctl daemon-reload
sudo mount /mnt/hgfs || true
echo "Gotowe. Kod jest w /mnt/hgfs/Aster — uruchom: sh /mnt/hgfs/Aster/tools/dev-run.sh"
