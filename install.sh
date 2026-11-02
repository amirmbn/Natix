#!/usr/bin/env bash
# Natix standalone installer.
#
#   sudo bash -c "$(curl -fsSL https://raw.githubusercontent.com/amirmbn/Natix/main/install.sh)"
#
# Supports:
# 1. Local source directory or Natix.tar.gz alongside install.sh: sudo bash install.sh
# 2. GitHub Releases (precompiled binaries + SHA256SUMS, or Natix.tar.gz)
# 3. Automatic fallback to cloning/downloading from GitHub main branch.
set -euo pipefail

REPO="${NATIX_REPO:-amirmbn/Natix}"
GO_VERSION="${NATIX_GO_VERSION:-}"
[[ "$REPO" =~ ^[A-Za-z0-9_.-]+/[A-Za-z0-9_.-]+$ ]] || { echo "invalid repository" >&2; exit 1; }

die() { echo "error: $*" >&2; exit 1; }

resolve_installer_version() {
    local launch_name="$1" source_path="$2"
    shift 2
    [[ "$#" -le 1 ]] || die "expected at most one version argument"
    VERSION="${NATIX_VERSION:-latest}"
    if [[ "$#" -eq 1 ]]; then
        VERSION="$1"
    elif [[ -z "$source_path" && ( "$launch_name" == latest || "$launch_name" =~ ^v?[0-9] ) ]]; then
        VERSION="$launch_name"
    fi
    [[ "$VERSION" == latest || "$VERSION" =~ ^v?[0-9][A-Za-z0-9_.-]*$ ]] || die "invalid version"
    if [[ "$VERSION" != latest && "$VERSION" != v* ]]; then
        VERSION="v${VERSION}"
    fi
}
resolve_installer_version "$0" "${BASH_SOURCE[0]:-}" "$@"

[[ "${EUID:-$(id -u)}" -eq 0 ]] || die "run as root: sudo bash install.sh"
command -v systemctl >/dev/null 2>&1 || die "systemd is required"

case "$(uname -m)" in
    x86_64|amd64)  ARCH="amd64" ;;
    aarch64|arm64) ARCH="arm64" ;;
    *) die "unsupported architecture $(uname -m) (amd64 and arm64 only)" ;;
esac

command -v flock >/dev/null 2>&1 || die "install util-linux (flock) first"
exec 9>/run/natix-install.lock
flock -w 120 9 || die "another installation is running"

missing=()
command -v ip >/dev/null 2>&1        || missing+=(iproute2)
command -v iptables >/dev/null 2>&1  || missing+=(iptables)
command -v wg >/dev/null 2>&1        || missing+=(wireguard-tools)
command -v curl >/dev/null 2>&1      || missing+=(curl)
command -v git >/dev/null 2>&1       || missing+=(git)
command -v tar >/dev/null 2>&1       || missing+=(tar)
command -v sha256sum >/dev/null 2>&1 || missing+=(coreutils)
if ! command -v go >/dev/null 2>&1 && ! command -v python3 >/dev/null 2>&1; then
    missing+=(python3)
fi
if [[ "${#missing[@]}" -gt 0 ]]; then
    command -v apt-get >/dev/null 2>&1 || die "please install: ${missing[*]}"
    echo "Installing ${missing[*]}..."
    apt-get update -qq && apt-get install -y -qq "${missing[@]}"
fi

command -v wg >/dev/null 2>&1 || die "wireguard-tools installation failed; install wireguard-tools and retry"

ASSETS=(
    "natix-linux-${ARCH}"
    "natix-engine-linux-${ARCH}"
    "natix-kernel.sh"
    "natix@.service"
    "natix-engine@.service"
)

bootstrap_go() {
    local metadata_url='https://go.dev/dl/?mode=json' selection archive digest
    if [[ -n "$GO_VERSION" ]]; then
        [[ "$GO_VERSION" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]] || die "invalid Go version"
        metadata_url+='&include=all'
    fi
    curl -fsSL --retry 3 --connect-timeout 15 --max-time 120 "$metadata_url" -o "${WORK}/go-releases.json"
    selection="$(python3 - "${WORK}/go-releases.json" "$GO_VERSION" "$ARCH" <<'PYTHON'
import json
import re
import sys

try:
    with open(sys.argv[1], encoding="utf-8") as stream:
        releases = json.load(stream)
    requested, arch = sys.argv[2:]
    for release in releases:
        version = release["version"]
        if requested:
            if version != "go" + requested:
                continue
        elif not release.get("stable"):
            continue
        if not re.fullmatch(r"go[0-9]+\.[0-9]+\.[0-9]+", version):
            continue
        filename = f"{version}.linux-{arch}.tar.gz"
        for asset in release["files"]:
            if asset.get("filename") != filename or asset.get("kind") != "archive":
                continue
            digest = asset.get("sha256", "")
            if not re.fullmatch(r"[0-9a-f]{64}", digest):
                raise ValueError("invalid Go SHA-256 in download metadata")
            print(version[2:], digest)
            sys.exit(0)
    raise ValueError("requested Linux Go archive not found in download metadata")
except (OSError, ValueError, TypeError, KeyError) as error:
    print(f"Go download metadata: {error}", file=sys.stderr)
    sys.exit(1)
PYTHON
)" || die "cannot select a verified Go archive"
    read -r GO_VERSION digest <<< "$selection"
    archive="go${GO_VERSION}.linux-${ARCH}.tar.gz"
    echo "Go not found; downloading Go ${GO_VERSION}..."
    curl -fsSL --retry 3 --connect-timeout 15 --max-time 300 "https://go.dev/dl/${archive}" -o "${WORK}/go.tgz"
    printf '%s  %s\n' "$digest" "${WORK}/go.tgz" | sha256sum -c --status || die "Go checksum mismatch"
    tar -C "$WORK" -xzf "${WORK}/go.tgz"
    export PATH="${WORK}/go/bin:${PATH}"
}

use_checkout() {
    local src="$1"
    echo "Installing from source at ${src}..."
    if ! command -v go >/dev/null 2>&1; then
        bootstrap_go
    fi
    echo "Building Natix binaries from source..."
    (cd "${src}" && mkdir -p bin \
        && CGO_ENABLED=0 go build -trimpath -ldflags="-s -w" -o "bin/natix-linux-${ARCH}" ./cmd/natix \
        && CGO_ENABLED=0 go build -trimpath -ldflags="-s -w" -o "bin/natix-engine-linux-${ARCH}" ./cmd/natix-engine)
    cp "${src}/bin/natix-linux-${ARCH}" "${src}/bin/natix-engine-linux-${ARCH}" "${src}/scripts/natix-kernel.sh" "${src}"/systemd/*.service "${WORK}/"
}

use_tarball() {
    local tarball="$1"
    echo "Extracting ${tarball}..."
    mkdir -p "${WORK}/tar-src"
    tar -xzf "${tarball}" -C "${WORK}/tar-src"
    if [[ -f "${WORK}/tar-src/Natix/scripts/natix-kernel.sh" ]]; then
        use_checkout "${WORK}/tar-src/Natix"
    elif [[ -f "${WORK}/tar-src/scripts/natix-kernel.sh" ]]; then
        use_checkout "${WORK}/tar-src"
    else
        die "invalid Natix tarball structure"
    fi
}

clone_and_build() {
    if curl -fsSL --retry 2 --connect-timeout 15 --max-time 120 "https://raw.githubusercontent.com/${REPO}/main/Natix.tar.gz" -o "${WORK}/Natix.tar.gz" 2>/dev/null; then
        use_tarball "${WORK}/Natix.tar.gz"
        return 0
    fi
    echo "Cloning https://github.com/${REPO}.git and building from source..."
    git clone --depth 1 "https://github.com/${REPO}.git" "${WORK}/src" || die "cannot clone https://github.com/${REPO}.git (make sure the repository exists and is public)"
    if [[ -f "${WORK}/src/Natix.tar.gz" && ! -f "${WORK}/src/scripts/natix-kernel.sh" ]]; then
        use_tarball "${WORK}/src/Natix.tar.gz"
    else
        use_checkout "${WORK}/src"
    fi
}

fetch_release() {
    local base a line resolved=""
    if [[ "${VERSION}" == "latest" ]]; then
        resolved="$(curl -fsSL --retry 2 --connect-timeout 15 --max-time 30 -o /dev/null -w '%{url_effective}' "https://github.com/${REPO}/releases/latest" 2>/dev/null || true)"
        VERSION="${resolved##*/}"
        if [[ ! "$VERSION" =~ ^v[0-9][A-Za-z0-9_.-]*$ ]]; then
            clone_and_build
            return 0
        fi
        base="https://github.com/${REPO}/releases/download/${VERSION}"
    else
        [[ "${VERSION}" == v* ]] || VERSION="v${VERSION}"
        base="https://github.com/${REPO}/releases/download/${VERSION}"
    fi
    echo "Downloading Natix (${VERSION}) from github.com/${REPO}..."
    for a in SHA256SUMS "${ASSETS[@]}"; do
        if ! curl -fsSL --retry 3 --connect-timeout 15 --max-time 300 "${base}/${a}" -o "${WORK}/${a}" 2>/dev/null; then
            echo "Release asset ${a} not found; checking for release tarball or source..."
            if curl -fsSL --retry 2 --connect-timeout 15 --max-time 120 "${base}/Natix.tar.gz" -o "${WORK}/Natix.tar.gz" 2>/dev/null; then
                use_tarball "${WORK}/Natix.tar.gz"
                return 0
            fi
            clone_and_build
            return 0
        fi
    done

    echo "Verifying SHA-256..."
    for a in "${ASSETS[@]}"; do
        line="$(awk -v name="$a" '$2 == name && length($1) == 64 && $1 !~ /[^0-9a-fA-F]/ {print}' "${WORK}/SHA256SUMS")"
        [[ "$(printf '%s\n' "$line" | wc -l)" -eq 1 ]] || die "duplicate checksum for ${a}"
        [[ -n "${line}" ]] || die "${a} is not listed in SHA256SUMS. Nothing was installed."
        (cd "${WORK}" && echo "${line}" | sha256sum -c --status) \
            || die "checksum mismatch for ${a}: the download is corrupt or was modified. Nothing was installed."
    done
    echo "All ${#ASSETS[@]} files verified."
}

WORK="$(mktemp -d)"
trap 'rm -rf "${WORK}"' EXIT

script="${BASH_SOURCE[0]:-}"
script_dir=""
if [[ -n "${script}" && -f "${script}" ]]; then
    script_dir="$(cd "$(dirname "${script}")" && pwd)"
fi

if [[ "${NATIX_LOCAL:-1}" != "0" && -n "${script_dir}" && -f "${script_dir}/scripts/natix-kernel.sh" ]]; then
    use_checkout "${script_dir}"
elif [[ "${NATIX_LOCAL:-1}" != "0" && -n "${script_dir}" && -f "${script_dir}/Natix/scripts/natix-kernel.sh" ]]; then
    use_checkout "${script_dir}/Natix"
elif [[ "${NATIX_LOCAL:-1}" != "0" && -n "${script_dir}" && -f "${script_dir}/Natix.tar.gz" ]]; then
    use_tarball "${script_dir}/Natix.tar.gz"
elif [[ "${NATIX_LOCAL:-1}" != "0" && -f "./Natix.tar.gz" ]]; then
    use_tarball "$(pwd)/Natix.tar.gz"
else
    fetch_release
fi

atomic_binary() {
    local staged
    staged="$(mktemp "$(dirname "$2")/.natix-install.XXXXXX")"
    if ! install -m "${3:-0755}" "$1" "$staged" || ! mv -f "$staged" "$2"; then
        rm -f "$staged"
        die "cannot install $2"
    fi
}
atomic_binary "${WORK}/natix-linux-${ARCH}" /usr/local/bin/natix
atomic_binary "${WORK}/natix-engine-linux-${ARCH}" /usr/local/bin/natix-engine
install -d -m 0755 /usr/local/lib/natix
sed 's/\r$//' "${WORK}/natix-kernel.sh" > "${WORK}/kernel-normalized"
atomic_binary "${WORK}/kernel-normalized" /usr/local/lib/natix/natix-kernel
for unit in natix@.service natix-engine@.service; do
    sed 's/\r$//' "${WORK}/${unit}" > "${WORK}/unit-normalized"
    atomic_binary "${WORK}/unit-normalized" "/etc/systemd/system/${unit}" 0644
done
install -d -m 0700 /etc/natix /etc/natix/tunnels
systemctl daemon-reload

systemctl try-restart 'natix-engine@*.service' || die "files installed, but service restart failed; inspect journalctl"

echo
echo "Natix $(/usr/local/bin/natix version | awk '{print $2}') installed."
echo "Run: sudo natix"

launch_menu() {
    [[ "${NATIX_NO_MENU:-0}" != 1 && -t 0 && -t 1 ]] || return 0
    flock -u 9
    exec 9>&-
    rm -rf -- "$WORK"
    trap - EXIT
    exec /usr/local/bin/natix
}
launch_menu
