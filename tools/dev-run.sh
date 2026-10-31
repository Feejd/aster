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
for app in files browser webapps store settings; do
    sed "s|^Exec=aster-$app|Exec=env ASTER_DATA_DIR=$ROOT/data $BUILD/apps/$app/aster-$app|" "$ROOT/apps/$app/org.aster.$app.desktop" > "$APPS/org.aster.$app.desktop"
done
update-desktop-database "$APPS" >/dev/null 2>&1 || true     # adresy aster-settings:wifi itp.
kbuildsycoca6 >/dev/null 2>&1 || true

# Czcionka Aster (Geist) dla tego użytkownika — także w programach KDE i na paskach tytułu
FONTS="$HOME/.local/share/fonts/aster-geist"
if ! cmp -s "$ROOT/data/fonts/geist/Geist-Regular.ttf" "$FONTS/Geist-Regular.ttf"; then
    mkdir -p "$FONTS" && cp "$ROOT"/data/fonts/geist/*.ttf "$FONTS/" && fc-cache -f "$FONTS" >/dev/null 2>&1 || true
fi
for key in font menuFont toolBarFont; do
    kwriteconfig6 --file kdeglobals --group General --key $key "Geist,10,-1,5,400,0,0,0,0,0,0,0,0,0,0,1" 2>/dev/null || true
done
kwriteconfig6 --file kdeglobals --group General --key smallestReadableFont "Geist,8,-1,5,400,0,0,0,0,0,0,0,0,0,0,1" 2>/dev/null || true
kwriteconfig6 --file kdeglobals --group WM --key activeFont "Geist,10,-1,5,600,0,0,0,0,0,0,0,0,0,0,1" 2>/dev/null || true

# Szkło jak w Aster: mocniejsze rozmycie KWin z odrobiną szumu (ustawienie KWin tego użytkownika)
kwriteconfig6 --file kwinrc --group Plugins --key blurEnabled true 2>/dev/null || true
kwriteconfig6 --file kwinrc --group Effect-blur --key BlurStrength 12 2>/dev/null || true
kwriteconfig6 --file kwinrc --group Effect-blur --key NoiseStrength 2 2>/dev/null || true
dbus-send --session --dest=org.kde.KWin /KWin org.kde.KWin.reconfigure 2>/dev/null || true

# Poprzednia kopia powłoki (np. z innej Konsoli) — zamknij, żeby nie działały dwie naraz
pkill -x aster-shell || true
systemctl --user stop plasma-plasmashell.service || true
trap 'systemctl --user start plasma-plasmashell.service' EXIT INT TERM
ASTER_DATA_DIR="$ROOT/data" "$BUILD/shell/aster-shell"
