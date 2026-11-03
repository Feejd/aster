#!/bin/sh
# Buduje Aster (powłokę i aplikacje) i uruchamia powłokę w zwykłej sesji Plasmy (w maszynie wirtualnej).
# Na czas działania zatrzymuje plasmashell; po Ctrl+C przywraca zwykły pulpit.
set -e
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
BUILD="${BUILD:-$HOME/aster-build}"

# Brak narzędzi albo nowych bibliotek (doszły w nowszej wersji kodu) → przygotowanie maszyny
rpm -q cmake kf6-kio-devel kf6-kservice-devel kf6-kconfig-devel libxcrypt-devel libvterm-devel polkit-qt6-1-devel jetbrains-mono-fonts-all layer-shell-qt-devel qt6-qtwebengine-devel plasma-workspace-devel exiv2-devel qt6-qtpdf-devel kf6-syntax-highlighting-devel qt6-qtmultimedia-devel taglib-devel libarchive-devel kf6-solid-devel plasma-wayland-protocols-devel kf6-kguiaddons-devel sane-backends-devel qt6-qtbase-private-devel pipewire-devel libsndfile-devel libsamplerate-devel alsa-lib-devel librsvg2-tools xcursorgen >/dev/null 2>&1 || sh "$ROOT/tools/setup-vm.sh"

# Stary katalog budowania z czasów, gdy budowała się sama powłoka — zacznij od nowa
[ -f "$BUILD/CMakeCache.txt" ] && ! grep -q "CMAKE_HOME_DIRECTORY:INTERNAL=$ROOT\$" "$BUILD/CMakeCache.txt" && rm -rf "$BUILD"

cmake -S "$ROOT" -B "$BUILD" -G Ninja -DCMAKE_BUILD_TYPE=Debug >/dev/null
cmake --build "$BUILD"

# Aplikacje z katalogu budowania widoczne w systemie (dok, Start, „Otwórz za pomocą”)
APPS="$HOME/.local/share/applications"
mkdir -p "$APPS"
for app in files browser webapps store settings tasks photos pdf editor calculator video music camera studio scanner phone; do
    sed "s|^Exec=aster-$app|Exec=env ASTER_DATA_DIR=$ROOT/data $BUILD/apps/$app/aster-$app|" "$ROOT/apps/$app/org.aster.$app.desktop" > "$APPS/org.aster.$app.desktop"
done
# Terminal: polecenie aster-terminal w ~/.local/bin (wołają je Pliki, KDE i xdg-terminal-exec)
mkdir -p "$HOME/.local/bin"
ln -sf "$BUILD/apps/terminal/aster-terminal" "$HOME/.local/bin/aster-terminal"
cp "$ROOT/apps/terminal/org.aster.terminal.desktop" "$APPS/"
kwriteconfig6 --file kdeglobals --group General --key TerminalApplication aster-terminal 2>/dev/null || true
kwriteconfig6 --file kdeglobals --group General --key TerminalService org.aster.terminal.desktop 2>/dev/null || true
printf 'org.aster.terminal.desktop\n' > "$HOME/.config/xdg-terminals.list"
# Menedżer zadań pod Ctrl+Shift+Esc (KGlobalAccel czyta skróty programów z share/kglobalaccel)
mkdir -p "$HOME/.local/share/kglobalaccel"
cp "$APPS/org.aster.tasks.desktop" "$HOME/.local/share/kglobalaccel/"
# Panel emoji pod Win+. — bez „env” w Exec: KWin rozpoznaje program po ścieżce (pozwolenie na wklejanie Ctrl+V)
sed "s|^Exec=aster-emoji|Exec=$BUILD/apps/emoji/aster-emoji|" "$ROOT/apps/emoji/org.aster.emoji.desktop" > "$APPS/org.aster.emoji.desktop"
cp "$APPS/org.aster.emoji.desktop" "$ROOT/apps/emoji/org.kde.plasma.emojier.desktop" "$HOME/.local/share/kglobalaccel/"
kwriteconfig6 --file kglobalaccelrc --group org.kde.plasma.emojier.desktop --key _launch "Meta+Ctrl+Alt+Shift+Space,Meta+Ctrl+Alt+Shift+Space,Emoji Selector" 2>/dev/null || true
update-desktop-database "$APPS" >/dev/null 2>&1 || true     # adresy aster-settings:wifi itp.
kbuildsycoca6 >/dev/null 2>&1 || true

# Kursor Aster (zbudowany z tools/make-cursors.py) dla tego użytkownika — od razu, także w programach GTK
if [ -f "$BUILD/cursors/Aster/index.theme" ]; then
    mkdir -p "$HOME/.local/share/icons"
    rm -rf "${HOME:?}/.local/share/icons/Aster" && cp -a "$BUILD/cursors/Aster" "$HOME/.local/share/icons/Aster"
    kwriteconfig6 --file kcminputrc --group Mouse --key cursorTheme Aster 2>/dev/null || true
    plasma-apply-cursortheme Aster >/dev/null 2>&1 || true
    # Przy otwieraniu programu sam kursor ładowania Aster — bez podskakującej ikony KDE (KWin startupfeedback)
    kwriteconfig6 --file klaunchrc --group BusyCursorSettings --key Bouncing false 2>/dev/null || true
    kwriteconfig6 --file klaunchrc --group BusyCursorSettings --key Blinking false 2>/dev/null || true
    gsettings set org.gnome.desktop.interface cursor-theme Aster 2>/dev/null || true
fi

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
# W sesji Aster (tools/install-vm.sh) po Ctrl+C wraca zainstalowana powłoka, w Plasmie — plasmashell
if [ "$ASTER_SESSION" = 1 ]; then
    systemctl --user stop aster-shell.service || true
    trap 'systemctl --user start aster-shell.service' EXIT INT TERM
else
    systemctl --user stop plasma-plasmashell.service || true
    trap 'systemctl --user start plasma-plasmashell.service' EXIT INT TERM
fi
ASTER_DATA_DIR="$ROOT/data" "$BUILD/shell/aster-shell"
