#!/bin/bash
# aster-install USTAWIENIA.env — instaluje Aster na wybrany dysk (uruchamia go instalator jako root).
# 1. bootc install to-disk z obrazu Aster zapisanego na nośniku instalacyjnym (bez internetu),
# 2. ustawienia nowego systemu prosto do jego /etc: nazwa komputera, język, klawiatura, strefa czasowa, Wi‑Fi,
# 3. konto użytkownika i wygląd czekają w /etc/aster/firstboot.env na aster-firstboot (pierwszy start).
# Dla instalatora wypisuje: „@stage tekst”, „@progress teraz [maksimum do czasu następnego kroku]”, „@error tekst”.
set -u -o pipefail

[ "$(id -u)" = 0 ] || { echo "@error Instalacja wymaga uprawnień administratora."; exit 1; }
SETTINGS="${1:?plik z ustawieniami}"
# shellcheck disable=SC1090
. "$SETTINGS"

IMAGE="${ASTER_IMAGE:-localhost/aster:latest}"                                  # obraz w magazynie nośnika
UPDATE_REF="$(cat /usr/share/aster/update-ref 2>/dev/null || echo "$IMAGE")"   # skąd system weźmie aktualizacje
TARGET=/run/aster-target

stage() { echo "@stage $1"; }
progress() { echo "@progress $*"; }
fail() { echo "@error $1"; exit 1; }

[ -b "${DISK:-}" ] || fail "Nie znaleziono wybranego dysku."

# ——— 1. Dysk ———
stage "Przygotowanie dysku…"
progress 0.02 0.05
# Partycje zamontowane automatycznie albo swap na tym dysku blokowałyby wymazanie
for part in $(lsblk -nrpo PATH "$DISK" | tail -n +2); do
    swapoff "$part" 2>/dev/null || true
    umount -R "$part" 2>/dev/null || true
done

# ——— 2. System ———
stage "Kopiowanie systemu…"
progress 0.06 0.55
# bootc działa z wnętrza kontenera z obrazem Aster (tak wymaga „bootc install”); obraz leży w magazynie
# kontenerów na nośniku (tools/build-iso.sh), więc nic nie jest pobierane z internetu
podman run --rm --privileged --pid=host --security-opt label=type:unconfined_t \
    -v /dev:/dev -v /var/lib/containers:/var/lib/containers \
    "$IMAGE" \
    bootc install to-disk --wipe --filesystem btrfs \
        --source-imgref "containers-storage:$IMAGE" --target-imgref "$UPDATE_REF" "$DISK" 2>&1 |
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
udevadm settle 2>/dev/null || true
root=$(lsblk -nrpo PATH,LABEL "$DISK" | awk '$2 == "root" { print $1 }' | head -n1)
[ -n "$root" ] || fail "Nie znaleziono nowego systemu na dysku."
mkdir -p "$TARGET"
mount "$root" "$TARGET" || fail "Nie udało się otworzyć nowego systemu."
trap 'umount -R "$TARGET" 2>/dev/null' EXIT
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

# Konto i wygląd — przy pierwszym starcie (aster-firstboot.service); plik tylko dla roota, jest w nim skrót hasła
mkdir -p "$etc/aster"
grep -v '^DISK=' "$SETTINGS" > "$etc/aster/firstboot.env"
chmod 600 "$etc/aster/firstboot.env"

# Etykiety SELinux nowych plików według reguł nowego systemu
contexts="$etc/selinux/targeted/contexts/files/file_contexts"
if command -v setfiles >/dev/null && [ -f "$contexts" ]; then
    setfiles -r "$deploy" "$contexts" "$etc/hostname" "$etc/locale.conf" "$etc/vconsole.conf" "$etc/X11" \
        "$etc/localtime" "$etc/aster" "$etc/NetworkManager/system-connections" 2>/dev/null || true
fi

sync
umount -R "$TARGET"
trap - EXIT
progress 1 1
stage "Gotowe"
