#!/usr/bin/env bash
# Builds an installable Debian candidate from the exact Flutter release bundle.
set -euo pipefail
cd "$(dirname "$0")/.."
version="${QINGFAN_VERSION:-2.0.0~dev4}"
bundle="build/linux/x64/release/bundle"
[[ -x "$bundle/qingfan" ]] || { echo "Missing Linux release bundle" >&2; exit 1; }
command -v dpkg-deb >/dev/null
tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"' EXIT
root="$tmp/pkg"
mkdir -p "$root/DEBIAN" "$root/usr/lib/qingfan" "$root/usr/share/applications" \
  "$root/usr/share/icons/hicolor/scalable/apps"
cp -a "$bundle/." "$root/usr/lib/qingfan/"
cp "../assets/qingfan.svg" "$root/usr/share/icons/hicolor/scalable/apps/qingfan.svg"
cat > "$root/DEBIAN/control" <<EOF
Package: qingfan
Version: $version
Section: utils
Priority: optional
Architecture: amd64
Maintainer: Qingfan developers <noreply@github.com>
Depends: libc6, libstdc++6, libgtk-3-0, libglib2.0-0, liblzma5, fonts-noto-cjk
Description: Qingfan desktop Pomodoro focus clock (Flutter V2 candidate)
 Local-first, single-window focus timer.
EOF
cat > "$root/usr/share/applications/qingfan.desktop" <<'EOF'
[Desktop Entry]
Type=Application
Name=青番
Name[en]=Qingfan
Comment=安静专注的桌面番茄钟
Exec=/usr/lib/qingfan/qingfan
Icon=qingfan
Terminal=false
Categories=Utility;Office;
StartupNotify=true
EOF
mkdir -p dist
dpkg-deb --root-owner-group --build "$root" "dist/qingfan_${version}_amd64.deb"
dpkg-deb --info "dist/qingfan_${version}_amd64.deb"
dpkg-deb --contents "dist/qingfan_${version}_amd64.deb" | grep -E '(/qingfan$|qingfan.desktop$|app.so$)'
echo "LINUX_DEB_PACKAGE_PASS"
