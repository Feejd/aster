#!/bin/sh
# Grafika z Astra na dowolnym Linuksie (Fedora, Ubuntu, Mint, Debian, Arch, openSUSE…) — jedną komendą:
#
#   curl -fsSL https://raw.githubusercontent.com/Feejd/aster/main/tools/install-grafika.sh | sh
#
# Instaluje Flatpak (jeśli go nie ma), a potem Grafikę dla bieżącego użytkownika. Ponowne uruchomienie
# aktualizuje ją do najnowszej wersji. Odinstalowanie: flatpak uninstall --user org.aster.grafika
set -eu

REPO="Feejd/aster"
APP="org.aster.grafika"

say() { printf '\033[1m%s\033[0m\n' "$*"; }
fail() { printf '\033[31m%s\033[0m\n' "$*" >&2; exit 1; }

case "$(uname -m)" in
    x86_64 | amd64) ARCH=x86_64 ;;
    aarch64 | arm64) ARCH=aarch64 ;;
    *) fail "Grafika działa na komputerach x86_64 i ARM (aarch64), a ten ma procesor $(uname -m)." ;;
esac

as_root() {
    if [ "$(id -u)" -eq 0 ]; then "$@"
    elif command -v sudo > /dev/null; then sudo "$@"
    else fail "Do zainstalowania Flatpaka potrzebne są uprawnienia administratora (sudo)."; fi
}

if ! command -v flatpak > /dev/null; then
    say "Instaluję Flatpak (poprosi o hasło administratora)…"
    if command -v apt-get > /dev/null; then as_root apt-get update -q && as_root apt-get install -y flatpak
    elif command -v dnf > /dev/null; then as_root dnf install -y flatpak
    elif command -v zypper > /dev/null; then as_root zypper --non-interactive install flatpak
    elif command -v pacman > /dev/null; then as_root pacman -S --noconfirm --needed flatpak
    elif command -v eopkg > /dev/null; then as_root eopkg install -y flatpak
    else fail "Nie umiem zainstalować Flatpaka w tym systemie — zainstaluj go ręcznie (https://flatpak.org/setup) i uruchom tę komendę jeszcze raz."
    fi
fi

command -v curl > /dev/null || fail "Brakuje programu curl."

say "Dodaję Flathub (stamtąd przyjdą biblioteki KDE, z których korzysta Grafika)…"
flatpak remote-add --user --if-not-exists flathub https://dl.flathub.org/repo/flathub.flatpakrepo

TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT
say "Pobieram Grafikę ($ARCH)…"
URL="${GRAFIKA_URL:-https://github.com/$REPO/releases/download/aplikacje/grafika-$ARCH.flatpak}"     # GRAFIKA_URL — do testów
curl -fL --progress-bar -o "$TMP/grafika.flatpak" "$URL" \
    || fail "Nie udało się pobrać Grafiki. Sprawdź połączenie z internetem."

say "Instaluję (za pierwszym razem pobiera też biblioteki KDE, ok. 400 MB)…"
flatpak install --user --reinstall -y --noninteractive "$TMP/grafika.flatpak"

say "Gotowe! Grafika jest w menu programów. Z terminala: flatpak run $APP"
