#!/bin/sh
# Buduje Aster (powłokę i aplikacje) i uruchamia powłokę w zwykłej sesji Plasmy (w maszynie wirtualnej).
# Na czas działania zatrzymuje plasmashell; po Ctrl+C przywraca zwykły pulpit.
set -e
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
BUILD="${BUILD:-$HOME/aster-build}"

# Brak narzędzi albo nowych bibliotek (doszły w nowszej wersji kodu) → przygotowanie maszyny
rpm -q cmake kf6-kio-devel kf6-kservice-devel layer-shell-qt-devel qt6-qtwebengine-devel plasma-workspace-devel >/dev/null 2>&1 || sh "$ROOT/tools/setup-vm.sh"

# Stary katalog budowania z czasów, gdy budowała się sama powłoka — zacznij od nowa
[ -f "$BUILD/CMakeCache.txt" ] && ! grep -q "CMAKE_HOME_DIRECTORY:INTERNAL=$ROOT\$" "$BUILD/CMakeCache.txt" && rm -rf "$BUILD"

cmake -S "$ROOT" -B "$BUILD" -G Ninja -DCMAKE_BUILD_TYPE=Debug >/dev/null
cmake --build "$BUILD"

# Aplikacje z katalogu budowania widoczne w systemie (dok, Start, „Otwórz za pomocą”)
APPS="$HOME/.local/share/applications"
mkdir -p "$APPS"
for app in files browser webapps; do
    sed "s|^Exec=aster-$app|Exec=$BUILD/apps/$app/aster-$app|" "$ROOT/apps/$app/org.aster.$app.desktop" > "$APPS/org.aster.$app.desktop"
done
kbuildsycoca6 >/dev/null 2>&1 || true

# Poprzednia kopia powłoki (np. z innej Konsoli) — zamknij, żeby nie działały dwie naraz
pkill -x aster-shell || true
systemctl --user stop plasma-plasmashell.service || true
trap 'systemctl --user start plasma-plasmashell.service' EXIT INT TERM
ASTER_DATA_DIR="$ROOT/data" "$BUILD/shell/aster-shell"
