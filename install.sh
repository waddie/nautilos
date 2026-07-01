#!/usr/bin/env sh
# Nautilos installer: download the prebuilt binary for this OS/arch from the
# GitHub Release and drop it on PATH as `nautilos`.
#
#   curl -fsSL https://raw.githubusercontent.com/waddie/nautilos/main/install.sh | sh
#
# Env overrides:
#   NAUTILOS_BIN_DIR   install directory (default: $XDG_BIN_HOME or ~/.local/bin)
#   NAUTILOS_VERSION   release tag to pin, e.g. v0.2.1 (default: latest)
set -eu

repo="waddie/nautilos"

err() { printf 'nautilos install: %s\n' "$1" >&2; }
die() { err "$1"; exit 1; }

# --- OS / arch detection (mirrors skills/nautilos/scripts/nautilos) ----------
os=$(uname -s)
arch=$(uname -m)
case "$os" in
  Darwin) os=darwin ;;
  Linux)  os=linux ;;
  *) die "unsupported OS: $os (prebuilt binaries cover darwin and linux only; build from source with jpm)" ;;
esac
case "$arch" in
  arm64|aarch64) arch=arm64 ;;
  x86_64|amd64)  arch=x64 ;;
  *) die "unsupported arch: $arch (prebuilt binaries cover arm64 and x64 only; build from source with jpm)" ;;
esac

# Linux binaries are glibc-linked; refuse musl (Alpine) rather than install a
# binary that will fail to run.
if [ "$os" = linux ]; then
  if [ -f /etc/alpine-release ] || (ldd --version 2>&1 | grep -qi musl); then
    die "musl libc detected; the prebuilt Linux binaries are glibc-linked. Build from source with jpm."
  fi
fi

asset="nautilos-$os-$arch"

# --- downloader --------------------------------------------------------------
# fetch <url> <dest>; returns non-zero on HTTP error or transport failure.
if command -v curl >/dev/null 2>&1; then
  fetch() { curl -fsSL "$1" -o "$2"; }
elif command -v wget >/dev/null 2>&1; then
  fetch() { wget -q "$1" -O "$2"; }
else
  die "need curl or wget to download"
fi

# --- resolve release URLs ----------------------------------------------------
base="https://github.com/$repo/releases"
if [ -n "${NAUTILOS_VERSION:-}" ]; then
  url="$base/download/$NAUTILOS_VERSION/$asset"
  sums_url="$base/download/$NAUTILOS_VERSION/SHA256SUMS"
  version="$NAUTILOS_VERSION"
else
  url="$base/latest/download/$asset"
  sums_url="$base/latest/download/SHA256SUMS"
  version="latest"
fi

# --- download ----------------------------------------------------------------
tmp=$(mktemp -d "${TMPDIR:-/tmp}/nautilos.XXXXXX")
trap 'rm -rf "$tmp"' EXIT INT TERM

err "downloading $asset ($version)"
fetch "$url" "$tmp/$asset" || die "download failed: $url"
[ -s "$tmp/$asset" ] || die "downloaded file is empty: $url"

# --- integrity ---------------------------------------------------------------
if command -v sha256sum >/dev/null 2>&1; then
  sha_check() { grep " $asset\$" "$1" | sha256sum -c - >/dev/null 2>&1; }
elif command -v shasum >/dev/null 2>&1; then
  sha_check() { grep " $asset\$" "$1" | shasum -a 256 -c - >/dev/null 2>&1; }
else
  sha_check() { return 2; }
fi

if fetch "$sums_url" "$tmp/SHA256SUMS" 2>/dev/null && [ -s "$tmp/SHA256SUMS" ]; then
  ( cd "$tmp" && sha_check SHA256SUMS )
  case $? in
    0) err "checksum ok" ;;
    2) err "no sha256 tool found; skipping checksum verification" ;;
    *) die "checksum verification failed for $asset" ;;
  esac
else
  err "no SHA256SUMS published for this release; skipping checksum verification"
fi

# --- install -----------------------------------------------------------------
dest="${NAUTILOS_BIN_DIR:-${XDG_BIN_HOME:-$HOME/.local/bin}}"
mkdir -p "$dest"
chmod +x "$tmp/$asset"
mv -f "$tmp/$asset" "$dest/nautilos"

err "installed $dest/nautilos ($version)"

# --- PATH hint ---------------------------------------------------------------
case ":$PATH:" in
  *":$dest:"*) : ;;
  *)
    err "$dest is not on your PATH. Add it, e.g.:"
    printf '  export PATH="%s:$PATH"\n' "$dest" >&2
    ;;
esac
