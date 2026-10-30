#!/bin/sh
# Uruchamia świeżo zbudowany aster-shell w zwykłej sesji Plasmy (w maszynie wirtualnej).
# Na czas działania zatrzymuje plasmashell; po Ctrl+C przywraca zwykły pulpit.
set -e
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
BUILD="${BUILD:-$HOME/aster-build}"

# Brak narzędzi albo nowych bibliotek (doszły w nowszej wersji kodu) → przygotowanie maszyny
rpm -q cmake kf6-kio-devel kf6-kservice-devel layer-shell-qt-devel >/dev/null 2>&1 || sh "$ROOT/tools/setup-vm.sh"

cmake -S "$ROOT/shell" -B "$BUILD" -G Ninja -DCMAKE_BUILD_TYPE=Debug >/dev/null
cmake --build "$BUILD"

# Poprzednia kopia powłoki (np. z innej Konsoli) — zamknij, żeby nie działały dwie naraz
pkill -x aster-shell || true
systemctl --user stop plasma-plasmashell.service || true
trap 'systemctl --user start plasma-plasmashell.service' EXIT INT TERM
ASTER_DATA_DIR="$ROOT/data" "$BUILD/aster-shell"
