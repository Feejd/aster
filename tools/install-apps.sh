#!/bin/sh
# Aplikacje Aster na dowolnym Linuksie (Fedora, Ubuntu, Mint, Debian, Arch, openSUSE, Aster…) — jedną komendą:
#
#   curl -fsSL https://raw.githubusercontent.com/Feejd/aster/main/tools/install-apps.sh | sh
#
# Wszystkie albo wybrane: … | sh -s -- montaz studio
# Instaluje Flatpak (jeśli go nie ma), a potem aplikacje dla bieżącego użytkownika. Ponowne uruchomienie
# aktualizuje je do najnowszych wersji. Odinstalowanie: flatpak uninstall --user org.aster.<nazwa>
set -eu

REPO="Feejd/aster"
ALL="grafika montaz studio code editor calculator photos music video pdf camera vault"

say() { printf '\033[1m%s\033[0m\n' "$*"; }
fail() { printf '\033[31m%s\033[0m\n' "$*" >&2; exit 1; }

case "$(uname -m)" in
    x86_64 | amd64) ARCH=x86_64 ;;
    aarch64 | arm64) ARCH=aarch64 ;;
    *) fail "Aplikacje Aster działają na komputerach x86_64 i ARM (aarch64), a ten ma procesor $(uname -m)." ;;
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
    else fail "Nie umiem zainstalować Flatpaka w tym systemie — zainstaluj go ręcznie (https://flatpak.org/setup) i uruchom tę komendę jeszcze raz."
    fi
fi
command -v curl > /dev/null || fail "Brakuje programu curl."

say "Dodaję Flathub (stamtąd przyjdą biblioteki KDE, z których korzystają aplikacje)…"
flatpak remote-add --user --if-not-exists flathub https://dl.flathub.org/repo/flathub.flatpakrepo

TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT
apps="${*:-$ALL}"
ok="" missing=""
for app in $apps; do
    say "Pobieram: $app ($ARCH)…"
    if curl -fsL -o "$TMP/$app.flatpak" "https://github.com/$REPO/releases/download/aplikacje/$app-$ARCH.flatpak"; then
        say "Instaluję: $app (za pierwszym razem pobiera też biblioteki KDE, ok. 400 MB)…"
        if flatpak install --user --reinstall -y --noninteractive "$TMP/$app.flatpak"; then ok="$ok $app"; else missing="$missing $app"; fi
    else
        missing="$missing $app"
    fi
done

[ -n "$ok" ] && say "Gotowe:$ok — są w menu programów."
[ -n "$missing" ] && printf '\033[33mNie udało się (jeszcze nie ma paczki albo błąd):%s\033[0m\n' "$missing"
[ -n "$ok" ]
