#!/bin/bash
# aster-install USTAWIENIA.env — instaluje Aster na wybrany dysk (uruchamia go instalator jako root).
# 1. partycje (EFI + btrfs) i bootc install to-filesystem z obrazu Aster zapisanego na nośniku (bez internetu),
# 2. ustawienia nowego systemu prosto do jego /etc: nazwa komputera, język, klawiatura, strefa czasowa, Wi‑Fi,
# 3. konto użytkownika i wygląd czekają w /etc/aster/firstboot.env na aster-firstboot (pierwszy start).
# Dla instalatora wypisuje: „@stage tekst”, „@progress teraz [maksimum do czasu następnego kroku]”, „@error tekst”.
set -u -o pipefail

[ "$(id -u)" = 0 ] || { echo "@error Instalacja wymaga uprawnień administratora."; exit 1; }
SETTINGS="${1:?plik z ustawieniami}"
# shellcheck disable=SC1090
. "$SETTINGS"

IMAGE="${ASTER_IMAGE:-localhost/aster:latest}"                                  # obraz w magazynie nośnika
STORE_IMG=/run/initramfs/live/LiveOS/aster-image.img                           # magazyn obrazu na nośniku (squashfs)
STORE=/run/aster-store
UPDATE_REF="$(cat /usr/share/aster/update-ref 2>/dev/null || echo "$IMAGE")"   # skąd system weźmie aktualizacje
TARGET=/run/aster-target

stage() { echo "@stage $1"; }
progress() { echo "@progress $*"; }
fail() { echo "@error $1"; exit 1; }

[ -b "${DISK:-}" ] || fail "Nie znaleziono wybranego dysku."

TMPDIR_HOST=/run/aster-tmp
TMP_MIB=6144

# /dev/sda → /dev/sda2, /dev/nvme0n1 → /dev/nvme0n1p2
part() { case "$DISK" in *[0-9]) echo "${DISK}p$1" ;; *) echo "$DISK$1" ;; esac; }

# ——— 1. Dysk ———
stage "Przygotowanie dysku…"
progress 0.02 0.05
# Partycje zamontowane automatycznie albo swap na tym dysku blokowałyby wymazanie
for p in $(lsblk -nrpo PATH "$DISK" | tail -n +2); do
    swapoff "$p" 2>/dev/null || true
    umount -R "$p" 2>/dev/null || true
    wipefs -aq "$p" 2>/dev/null || true
done
# Partycje: EFI, system (btrfs) i na końcu tymczasowa na pliki bootc. bootc rozpakowuje warstwy obrazu
# w /var/tmp, a na nośniku to RAM (~20% pamięci) — za mało przy 4 GB. Po instalacji tymczasowa znika,
# a system dostaje jej miejsce.
case "$(uname -m)" in
    x86_64)  root_type=4F68BCE3-E8CD-4DB1-96E7-FBCAF984B709 ;;
    aarch64) root_type=B921B045-1DF0-41C3-AF44-4C6F280D3FAE ;;
    *)       root_type=0FC63DAF-8483-4772-8E79-3D69D8477DE4 ;;
esac
disk_mib=$(( $(blockdev --getsize64 "$DISK") / 1048576 ))
root_mib=$(( disk_mib - 600 - TMP_MIB - 4 ))
[ "$root_mib" -ge 12000 ] || fail "Dysk jest za mały."
sfdisk -q --wipe always --wipe-partitions always "$DISK" <<EOF || fail "Nie udało się podzielić dysku."
label: gpt
size=600MiB, type=C12A7328-F81F-11D2-BA4B-00A0C93EC93B, name="EFI-SYSTEM"
size=${root_mib}MiB, type=$root_type, name="root"
type=0FC63DAF-8483-4772-8E79-3D69D8477DE4, name="aster-tmp"
EOF
udevadm settle 2>/dev/null || true
mkfs.vfat -F 32 -n EFI-SYSTEM "$(part 1)" >/dev/null || fail "Nie udało się przygotować partycji EFI."
mkfs.btrfs -q -f -L root "$(part 2)" || fail "Nie udało się przygotować partycji systemu."
mkfs.ext4 -q -F -L aster-tmp "$(part 3)" || fail "Nie udało się przygotować dysku."
mkdir -p "$TARGET" "$TMPDIR_HOST"
mount "$(part 2)" "$TARGET" && mkdir -p "$TARGET/boot/efi" && mount "$(part 1)" "$TARGET/boot/efi" &&
    mount "$(part 3)" "$TMPDIR_HOST" || fail "Nie udało się otworzyć dysku."
trap 'umount -R "$TARGET" "$TMPDIR_HOST" 2>/dev/null' EXIT

# ——— 2. System ———
stage "Kopiowanie systemu…"
progress 0.06 0.55
# Magazyn z obrazem Aster z nośnika — tylko do odczytu, jako dodatkowy (nowe dane podmana idą do pamięci)
if ! mountpoint -q "$STORE"; then
    mkdir -p "$STORE"
    mount -o loop,ro "$STORE_IMG" "$STORE" || fail "Nie znaleziono obrazu systemu na nośniku instalacyjnym."
fi
conf=/run/aster-storage.conf
printf '[storage]\ndriver = "overlay"\nrunroot = "/run/containers/storage"\ngraphroot = "/var/lib/containers/storage"\n[storage.options]\nadditionalimagestores = ["%s"]\n' "$STORE" > "$conf"
export CONTAINERS_STORAGE_CONF="$conf"
# bootc działa z wnętrza kontenera z obrazem Aster (tak wymaga „bootc install”); obraz leży w magazynie
# kontenerów na nośniku (tools/build-iso.sh), więc nic nie jest pobierane z internetu
podman run --rm --privileged --pid=host --security-opt label=type:unconfined_t \
    -v /dev:/dev -v /var/lib/containers:/var/lib/containers -v "$STORE:$STORE:ro" \
    -v "$conf:/etc/containers/storage.conf:ro" \
    -v "$TARGET:/target" -v "$TMPDIR_HOST:/var/tmp" \
    "$IMAGE" \
    bootc install to-filesystem --skip-finalize \
        --source-imgref "containers-storage:$IMAGE" --target-imgref "$UPDATE_REF" /target 2>&1 |
while IFS= read -r line; do
    echo "$line"
    case "$line" in
        *"Initializing ostree"*)      progress 0.12 0.55 ;;
        *Deploying*)                  progress 0.62 0.72 ;;
        *bootloader*|*bootupd*)       stage "Instalowanie programu rozruchowego…"; progress 0.74 0.82 ;;
        *Trimming*|*Finaliz*)         progress 0.84 0.88 ;;
        *"Installation complete"*)    progress 0.88 0.9 ;;
    esac
done || fail "Nie udało się skopiować systemu na dysk."

# ——— 3. Ustawienia ———
stage "Zapisywanie Twoich ustawień…"
progress 0.9 0.97
# Partycja tymczasowa już niepotrzebna — system rośnie do końca dysku (btrfs powiększa się w locie)
umount "$TMPDIR_HOST" 2>/dev/null
sfdisk -q --delete "$DISK" 3 2>/dev/null && partx -d --nr 3 "$DISK" 2>/dev/null
echo ", +" | sfdisk -q -N 2 --no-reread --force "$DISK" 2>/dev/null && partx -u --nr 2 "$DISK" 2>/dev/null &&
    btrfs filesystem resize max "$TARGET" >/dev/null 2>&1 || echo "Nie udało się powiększyć partycji systemu."
udevadm settle 2>/dev/null || true
deploy=$(ls -d "$TARGET"/ostree/deploy/*/deploy/*.0 "$TARGET"/*/ostree/deploy/*/deploy/*.0 2>/dev/null | head -n1)
[ -n "$deploy" ] || fail "Nie znaleziono nowego systemu na dysku."
etc="$deploy/etc"

echo "$HOSTNAME" > "$etc/hostname"
printf 'LANG=%s\n' "$LOCALE" > "$etc/locale.conf"
printf 'KEYMAP=%s\n' "$KEYMAP" > "$etc/vconsole.conf"
mkdir -p "$etc/X11/xorg.conf.d"
printf 'Section "InputClass"\n    Identifier "system-keyboard"\n    MatchIsKeyboard "on"\n    Option "XkbLayout" "%s"\n    Option "XkbVariant" "%s"\nEndSection\n' \
    "$XKB_LAYOUT" "$XKB_VARIANT" > "$etc/X11/xorg.conf.d/00-keyboard.conf"
[ -e "$deploy/usr/share/zoneinfo/$TIMEZONE" ] && ln -sfn "../usr/share/zoneinfo/$TIMEZONE" "$etc/localtime"

# Sieci Wi‑Fi połączone w instalatorze — nowy system połączy się sam
if ls /etc/NetworkManager/system-connections/*.nmconnection >/dev/null 2>&1; then
    mkdir -p "$etc/NetworkManager/system-connections"
    cp /etc/NetworkManager/system-connections/*.nmconnection "$etc/NetworkManager/system-connections/"
    chmod 600 "$etc"/NetworkManager/system-connections/*.nmconnection
fi

# Kreator pierwszego uruchomienia KDE (plasma-setup) — konto zakłada już Aster, więc oznaczamy go jako wykonany
touch "$etc/plasma-setup-done"

# Konto i wygląd — przy pierwszym starcie (aster-firstboot.service); plik tylko dla roota, jest w nim skrót hasła
mkdir -p "$etc/aster"
grep -v '^DISK=' "$SETTINGS" > "$etc/aster/firstboot.env"
chmod 600 "$etc/aster/firstboot.env"

# Etykiety SELinux nowych plików według reguł nowego systemu
contexts="$etc/selinux/targeted/contexts/files/file_contexts"
if command -v setfiles >/dev/null && [ -f "$contexts" ]; then
    setfiles -r "$deploy" "$contexts" "$etc/hostname" "$etc/locale.conf" "$etc/vconsole.conf" "$etc/X11" \
        "$etc/localtime" "$etc/aster" "$etc/plasma-setup-done" "$etc/NetworkManager/system-connections" 2>/dev/null || true
fi

sync
fstrim "$TARGET" 2>/dev/null || true
umount -R "$TARGET"
trap - EXIT
progress 1 1
stage "Gotowe"
