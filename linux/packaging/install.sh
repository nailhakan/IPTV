#!/usr/bin/env bash
# Installs the release build for the current user (no root needed):
#   ~/.local/opt/iptv            the app
#   ~/.local/bin/iptv            launcher command
#   ~/.local/share/applications  menu entry, ~/.local/share/icons  icon
# Build first:  flutter build linux --release
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
BUNDLE="$ROOT/build/linux/x64/release/bundle"
APP_ID="dev.nailhakan.iptv_app"
PREFIX="${PREFIX:-$HOME/.local}"

[ -x "$BUNDLE/iptv_app" ] || { echo "Release build not found. Run: flutter build linux --release" >&2; exit 1; }
command -v mpv >/dev/null || echo "Warning: mpv/libmpv not found. Install it (Arch: sudo pacman -S mpv) or playback will not work." >&2

rm -rf "$PREFIX/opt/iptv"
mkdir -p "$PREFIX/opt/iptv" "$PREFIX/bin" "$PREFIX/share/applications" "$PREFIX/share/icons/hicolor/256x256/apps"
cp -r "$BUNDLE"/. "$PREFIX/opt/iptv/"
cp "$ROOT/linux/packaging/iptv.png" "$PREFIX/share/icons/hicolor/256x256/apps/$APP_ID.png"
ln -sf "$PREFIX/opt/iptv/iptv_app" "$PREFIX/bin/iptv"

cat > "$PREFIX/share/applications/$APP_ID.desktop" <<DESKTOP
[Desktop Entry]
Type=Application
Name=IPTV
Comment=IPTV player (Xtream Codes)
Exec=$PREFIX/opt/iptv/iptv_app
Icon=$APP_ID
Terminal=false
Categories=AudioVideo;Video;Player;TV;
StartupWMClass=$APP_ID
DESKTOP

update-desktop-database "$PREFIX/share/applications" 2>/dev/null || true
gtk-update-icon-cache -q "$PREFIX/share/icons/hicolor" 2>/dev/null || true
echo "Installed to $PREFIX/opt/iptv  (command: iptv, menu entry: IPTV)"
