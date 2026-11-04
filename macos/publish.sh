#!/bin/bash
# Compila a app do Mac e junta-a a uma release do GitHub, para as apps instaladas
# se atualizarem sozinhas. Os Macs do GitHub Actions nem sempre estão disponíveis,
# por isso isto corre no teu Mac.
#
#   ./publish.sh v0.2.0
#
# Precisa do GitHub CLI com sessão iniciada:  brew install gh && gh auth login
set -euo pipefail
cd "$(dirname "$0")"

TAG="${1:?Indique a tag da release, por exemplo: ./publish.sh v0.2.0}"
VERSION="${TAG#v}"
REPO="diogoardsilva/iqos-monitor"

./build-app.sh "$VERSION"
shasum -a 256 build/IqosMonitor-macOS.zip | cut -d' ' -f1 > build/IqosMonitor-macOS.zip.sha256

# Cria a release se ainda não existir (o Windows junta o .exe quando a tag chegar ao GitHub).
gh release view "$TAG" --repo "$REPO" >/dev/null 2>&1 \
  || gh release create "$TAG" --repo "$REPO" --title "IQOS Monitor $TAG" --generate-notes
gh release upload "$TAG" --repo "$REPO" --clobber \
  build/IqosMonitor-macOS.zip build/IqosMonitor-macOS.zip.sha256
echo "Publicado: $TAG (as apps do Mac atualizam-se em até 6 horas, ou já em Definições → Procurar atualizações)"
