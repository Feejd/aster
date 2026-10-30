#!/bin/sh
# Uruchamia świeżo zbudowany aster-shell w zwykłej sesji Plasmy (w maszynie wirtualnej).
# Na czas działania zatrzymuje plasmashell; po Ctrl+C przywraca zwykły pulpit.
set -e
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
BUILD="${BUILD:-$HOME/aster-build}"

# Pierwsze uruchomienie: brak narzędzi → najpierw przygotowanie maszyny
command -v cmake >/dev/null || sh "$ROOT/tools/setup-vm.sh"

cmake -S "$ROOT/shell" -B "$BUILD" -G Ninja -DCMAKE_BUILD_TYPE=Debug >/dev/null
cmake --build "$BUILD"

systemctl --user stop plasma-plasmashell.service || true
trap 'systemctl --user start plasma-plasmashell.service' EXIT INT TERM
ASTER_DATA_DIR="$ROOT/data" "$BUILD/aster-shell"
