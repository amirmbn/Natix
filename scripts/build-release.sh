#!/usr/bin/env bash
# Builds the release assets into dist/: static linux/amd64 and linux/arm64 binaries,
# the kernel helper, the systemd units and SHA256SUMS, which install.sh verifies.
# Usage: scripts/build-release.sh [version]
set -euo pipefail

cd "$(dirname "${BASH_SOURCE[0]}")/.."
VERSION="${1:-$(sed -n 's/^var Version = "\(.*\)"/\1/p' pkg/version/version.go)}"
LDFLAGS="-s -w -X natix/pkg/version.Version=${VERSION}"

rm -rf dist
mkdir -p dist
for arch in amd64 arm64; do
    CGO_ENABLED=0 GOOS=linux GOARCH="${arch}" go build -trimpath -ldflags="${LDFLAGS}" -o "dist/natix-linux-${arch}" ./cmd/natix
    CGO_ENABLED=0 GOOS=linux GOARCH="${arch}" go build -trimpath -ldflags="${LDFLAGS}" -o "dist/natix-engine-linux-${arch}" ./cmd/natix-engine
done
cp scripts/natix-kernel.sh systemd/*.service dist/
[[ -f install.sh ]] && cp install.sh dist/
(cd dist && sha256sum natix-linux-* natix-engine-linux-* natix-kernel.sh ./*.service | sed 's#  \./#  #' > SHA256SUMS)
cat dist/SHA256SUMS
