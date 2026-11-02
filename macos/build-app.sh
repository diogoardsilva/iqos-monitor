#!/bin/bash
# Gera build/IqosMonitor.app e build/IqosMonitor-macOS.zip (precisa do Xcode 26 ou mais recente).
#   ./build-app.sh            versão tirada de iqos_monitor/version.py
#   ./build-app.sh 0.2.0      versão explícita
set -euo pipefail
cd "$(dirname "$0")"

VERSION="${1:-$(sed -n 's/^__version__ = "\(.*\)"/\1/p' ../iqos_monitor/version.py)}"
# Por omissão compila só para este Mac. UNIVERSAL=1 junta Apple Silicon e Intel
# (o Xcode 27 já não aceita x86_64 em alguns casos).
if [ "${UNIVERSAL:-0}" = 1 ]; then ARCHS=(--arch arm64 --arch x86_64); else ARCHS=(); fi

swift build -c release ${ARCHS[@]+"${ARCHS[@]}"}
BIN="$(swift build -c release ${ARCHS[@]+"${ARCHS[@]}"} --show-bin-path)/IqosMonitor"

APP=build/IqosMonitor.app
rm -rf "$APP" build/IqosMonitor-macOS.zip
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$BIN" "$APP/Contents/MacOS/IqosMonitor"
sed "s/__VERSION__/$VERSION/g" Support/Info.plist > "$APP/Contents/Info.plist"

# Ícone: AppIcon.png (1024 px) -> AppIcon.icns
ICONSET="$(mktemp -d)/AppIcon.iconset"
mkdir -p "$ICONSET"
for s in 16 32 128 256 512; do
  sips -z $s $s Support/AppIcon.png --out "$ICONSET/icon_${s}x${s}.png" >/dev/null
  sips -z $((s * 2)) $((s * 2)) Support/AppIcon.png --out "$ICONSET/icon_${s}x${s}@2x.png" >/dev/null
done
iconutil -c icns "$ICONSET" -o "$APP/Contents/Resources/AppIcon.icns"

# Assinatura ad hoc (sem conta de programador): chega para o Bluetooth e as notificações.
codesign --force --sign - --timestamp=none "$APP"

ditto -c -k --keepParent "$APP" build/IqosMonitor-macOS.zip
echo "Pronto: macos/$APP (versão $VERSION)"
