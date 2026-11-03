#!/bin/bash
# Buduje plik ISO z instalatorem Aster (pendrive: start → instalator na cały ekran → instalacja → pulpit).
#   sudo tools/build-iso.sh [UPDATE_REF]
# UPDATE_REF — skąd zainstalowany system weźmie aktualizacje (np. ghcr.io/twoje-konto/aster:latest).
# ASTER_IMAGE — gotowy obraz systemu zamiast budowania; ASTER_PREBUILT=1 — użyj już zbudowanego localhost/aster:latest
# (GitHub Actions: .github/workflows/aster.yml).
# Wymaga Linuksa z podman, skopeo, squashfs-tools, xorriso, dosfstools, mtools (jako root) i ok. 30 GB miejsca.
# Wynik: build/iso/aster-install-<arch>.iso — UEFI (x86_64 albo aarch64), na pendrive przez `dd` albo Fedora Media Writer.
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
UPDATE_REF="${1:-localhost/aster:latest}"
WORK="${WORK:-$ROOT/build/iso}"
LABEL=ASTER_INSTALL
ARCH=$(uname -m)
case "$ARCH" in
    x86_64) EFI_NAME=BOOTX64.EFI; GRUB_EFI=grubx64.efi; SHIM=shimx64.efi ;;
    aarch64) EFI_NAME=BOOTAA64.EFI; GRUB_EFI=grubaa64.efi; SHIM=shimaa64.efi ;;
    *) echo "Nieobsługiwana architektura: $ARCH" >&2; exit 1 ;;
esac
[ "$(id -u)" = 0 ] || { echo "Uruchom jako root (sudo)." >&2; exit 1; }
for tool in podman skopeo mksquashfs xorriso mkfs.vfat mcopy; do
    command -v "$tool" >/dev/null || { echo "Brakuje: $tool" >&2; exit 1; }
done

# ASTER_IMAGE=rejestr/aster:tag — gotowy obraz (np. z GitHub Actions) zamiast budowania od zera
if [ "${ASTER_PREBUILT:-0}" = 1 ]; then
    echo "==> Obraz systemu Aster: już zbudowany (localhost/aster:latest)"
elif [ -n "${ASTER_IMAGE:-}" ]; then
    echo "==> Obraz systemu Aster: $ASTER_IMAGE"
    podman pull "$ASTER_IMAGE"
    podman tag "$ASTER_IMAGE" localhost/aster:latest
else
    echo "==> Obraz systemu Aster"
    podman build -f "$ROOT/image/Containerfile" -t localhost/aster:latest "$ROOT"
fi

echo "==> Obraz nośnika (instalator zamiast pulpitu)"
podman build -f "$ROOT/image/installer/Containerfile" --build-arg UPDATE_REF="$UPDATE_REF" \
    -t localhost/aster-installer:latest "$ROOT"

rm -rf "${WORK:?}/rootfs" "${WORK:?}/iso" "${WORK:?}/run"
mkdir -p "$WORK/rootfs" "$WORK/iso/LiveOS" "$WORK/iso/boot" "$WORK/iso/EFI/BOOT" "$WORK/run"

echo "==> System plików nośnika"
ctr=$(podman create localhost/aster-installer:latest)
podman export "$ctr" | tar -xf - -C "$WORK/rootfs"
podman rm "$ctr" >/dev/null

echo "==> Obraz Aster do instalacji (bez internetu) w magazynie kontenerów nośnika"
skopeo copy containers-storage:localhost/aster:latest \
    "containers-storage:[overlay@$WORK/rootfs/var/lib/containers/storage+$WORK/run]localhost/aster:latest"
# Sterownik overlay podłącza swój katalog sam na siebie i zostawia go podłączonego — odłączamy wszystko
# w katalogu nośnika (inaczej nie da się go potem usunąć)
findmnt -rno TARGET | grep -E "^($WORK/rootfs|$WORK/run)(/|$)" | sort -r | while read -r m; do umount -l "$m" || true; done

echo "==> Jądro i initramfs startujące z nośnika (dmsquash-live)"
kver=$(ls "$WORK/rootfs/usr/lib/modules" | head -n1)
cp "$WORK/rootfs/usr/lib/modules/$kver/vmlinuz" "$WORK/iso/boot/vmlinuz"
# /root w obrazie atomowym to dowiązanie do /var/roothome — w kontenerze trzeba go założyć, inaczej dracut się sypie
podman run --rm -v "$WORK/iso/boot:/out" localhost/aster-installer:latest sh -c "mkdir -p /var/roothome && \
    dracut --no-hostonly --reproducible --add 'dmsquash-live dmsquash-live-autooverlay' \
           --omit plymouth --force /out/initramfs.img $kver"
[ -s "$WORK/iso/boot/initramfs.img" ] || { echo "Nie powstał initramfs" >&2; exit 1; }
chmod 644 "$WORK/iso/boot/initramfs.img"

echo "==> Rozruch UEFI (shim + GRUB z obrazu, bez menu)"
# Fedora 41+ trzyma je w /usr/lib/efi/<pakiet>/<wersja>/EFI/fedora, starsze obrazy w /usr/lib/bootupd albo /boot/efi
find_efi() {
    local d
    for d in "$WORK/rootfs/usr/lib/efi" "$WORK/rootfs/usr/lib/bootupd" "$WORK/rootfs/boot/efi"; do
        if [ -d "$d" ]; then find "$d" -name "$1" -path '*EFI*'; fi
    done | sort -V | tail -n1
}
shim=$(find_efi "$SHIM"); grub=$(find_efi "$GRUB_EFI")
[ -n "$shim" ] && [ -n "$grub" ] || { echo "Nie znaleziono $SHIM / $GRUB_EFI w obrazie" >&2; exit 1; }
cp "$shim" "$WORK/iso/EFI/BOOT/$EFI_NAME"
cp "$grub" "$WORK/iso/EFI/BOOT/$GRUB_EFI"

echo "==> squashfs"
mksquashfs "$WORK/rootfs" "$WORK/iso/LiveOS/squashfs.img" -comp zstd -Xcompression-level 15 -noappend -quiet
# System plików nośnika jest już w squashfs — miejsce na dysku wraca od razu (runner GitHuba ma go mało)
rm -rf "${WORK:?}/rootfs" "${WORK:?}/run"
cat > "$WORK/iso/EFI/BOOT/grub.cfg" <<EOF
set default=0
set timeout=0
set timeout_style=hidden
search --no-floppy --set=root --label $LABEL
menuentry 'Zainstaluj Aster' {
    linux /boot/vmlinuz root=live:CDLABEL=$LABEL rd.live.image rd.live.overlay.overlayfs=1 selinux=0 quiet splash loglevel=3 rd.udev.log_level=3 systemd.show_status=false vt.global_cursor_default=0
    initrd /boot/initramfs.img
}
EOF
cp "$WORK/iso/EFI/BOOT/grub.cfg" "$WORK/iso/EFI/BOOT/grub-fedora.cfg"
mkdir -p "$WORK/iso/EFI/fedora" && cp "$WORK/iso/EFI/BOOT/grub.cfg" "$WORK/iso/EFI/fedora/grub.cfg"

# Partycja EFI wewnątrz ISO (dla rozruchu z pendrive’a i płyty)
efiimg="$WORK/iso/boot/efiboot.img"
rm -f "$efiimg"
mkfs.vfat -C "$efiimg" 8192 >/dev/null
mmd -i "$efiimg" ::/EFI ::/EFI/BOOT ::/EFI/fedora
mcopy -i "$efiimg" "$WORK/iso/EFI/BOOT/$EFI_NAME" "$WORK/iso/EFI/BOOT/$GRUB_EFI" "$WORK/iso/EFI/BOOT/grub.cfg" ::/EFI/BOOT/
mcopy -i "$efiimg" "$WORK/iso/EFI/BOOT/grub.cfg" ::/EFI/fedora/

echo "==> ISO"
out="$WORK/aster-install-$ARCH.iso"
xorriso -as mkisofs -R -J -joliet-long -V "$LABEL" \
    -e boot/efiboot.img -no-emul-boot -append_partition 2 0xef "$efiimg" -appended_part_as_gpt \
    -o "$out" "$WORK/iso"
rm -rf "${WORK:?}/rootfs" "${WORK:?}/run"
echo "Gotowe: $out"
