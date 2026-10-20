#!/usr/bin/env bash
# Stage LGPL, audio-capable `ffmpeg` and `ffprobe` executables for a desktop
# build into build/ffmpeg/<os>-<arch>/. Binaries are never committed.
#
# Usage: bash scripts/fetch_desktop_ffmpeg.sh [<os>-<arch>]
#   <os>-<arch> defaults to the host: macos-arm64, macos-x64, linux-x64,
#   linux-arm64, windows-x64 or windows-arm64.
#
# Output: build/ffmpeg/<os>-<arch>/ffmpeg[.exe], ffprobe[.exe], LICENSE.txt
# and SOURCE.txt (where the build came from, for the LGPL source offer).
#
# Sources:
#   Linux, Windows: BtbN/FFmpeg-Builds static "lgpl" variants (no GPL or
#     nonfree parts; includes libmp3lame, libopus and TLS). The archive is
#     checked against the checksums.sha256 file of the same release.
#     MORNYE_FFMPEG_BTBN_TAG (default: latest) selects the release and
#     MORNYE_FFMPEG_BTBN_ASSET overrides the archive name, which a dated
#     autobuild tag needs.
#   macOS: built from source (FFmpeg, LAME, Opus) with pinned SHA-256 sums.
#     No known prebuilt macOS FFmpeg is LGPL. The FFmpeg configure line is:
#       ./configure --prefix=<deps> --disable-gpl --disable-nonfree
#         --disable-shared --enable-static --disable-autodetect
#         --disable-doc --disable-ffplay --disable-debug
#         --enable-zlib --enable-audiotoolbox --enable-securetransport
#         --enable-libmp3lame --enable-libopus --pkg-config-flags=--static
#     LAME and Opus are built as static libraries into the same prefix.
#     macOS x64 is cross-compiled with `-arch x86_64` on Apple Silicon.
#
# Bundle layout (the desktop bundling must place the staged files here; the
# app resolves them in lib/services/ffmpeg_desktop.dart):
#   macOS:   Mornye.app/Contents/Resources/ffmpeg/{ffmpeg,ffprobe}
#            (Contents/MacOS/{ffmpeg,ffprobe} is also accepted)
#   Windows: <folder of the .exe>\ffmpeg\{ffmpeg.exe,ffprobe.exe}
#   Linux:   <folder of the executable>/lib/ffmpeg/{ffmpeg,ffprobe}
# Ship LICENSE.txt and SOURCE.txt next to the binaries.
#
# Runtime lookup order: $MORNYE_FFMPEG_DIR, then the bundle layout above,
# then PATH. PATH is a developer fallback only: a package manager FFmpeg
# (for example Homebrew's) is usually built with --enable-gpl and must never
# be bundled. This script refuses to stage a build whose configuration
# reports --enable-gpl or --enable-nonfree.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(dirname "$SCRIPT_DIR")"

FFMPEG_VERSION="8.1.3"
FFMPEG_SHA256="7138d28c96d9d3e3af4ee3d8cad72741f8ffb40da90c1112235dea3ecd3178a3"
LAME_VERSION="3.100"
LAME_SHA256="ddfe36cab873794038ae2c1210557ad34857a4b6bdc515785d1da9e175b1da1e"
OPUS_VERSION="1.5.2"
OPUS_SHA256="65c1d2f78b9f2fb20082c38cbe47c951ad5839345876e46941612ee87f9a7ce1"
BTBN_BRANCH="8.1"
BTBN_TAG="${MORNYE_FFMPEG_BTBN_TAG:-latest}"
MACOS_MIN_VERSION="12.0"

host_target() {
  local os arch
  case "$(uname -s)" in
    Darwin) os=macos ;;
    Linux) os=linux ;;
    MINGW*|MSYS*|CYGWIN*) os=windows ;;
    *) echo "Error: unsupported host OS $(uname -s)." >&2; exit 1 ;;
  esac
  case "$(uname -m)" in
    x86_64|amd64) arch=x64 ;;
    arm64|aarch64) arch=arm64 ;;
    *) echo "Error: unsupported host architecture $(uname -m)." >&2; exit 1 ;;
  esac
  echo "$os-$arch"
}

TARGET="${1:-$(host_target)}"
case "$TARGET" in
  macos-x64|macos-arm64|linux-x64|linux-arm64|windows-x64|windows-arm64) ;;
  *)
    echo "Usage: bash scripts/fetch_desktop_ffmpeg.sh [macos-arm64|macos-x64|linux-x64|linux-arm64|windows-x64|windows-arm64]" >&2
    exit 1
    ;;
esac
OS="${TARGET%-*}"
ARCH="${TARGET#*-}"

OUT_DIR="$PROJECT_DIR/build/ffmpeg/$TARGET"
WORK_DIR="$PROJECT_DIR/build/ffmpeg/.work/$TARGET"
EXE=""
[[ "$OS" == "windows" ]] && EXE=".exe"

sha256_of() {
  if command -v sha256sum >/dev/null 2>&1; then
    sha256sum "$1" | awk '{print $1}'
  else
    shasum -a 256 "$1" | awk '{print $1}'
  fi
}

download() {
  local url="$1" dest="$2"
  if [[ ! -f "$dest" ]]; then
    echo "Downloading $url"
    curl -fL --retry 3 -o "$dest.part" "$url"
    mv "$dest.part" "$dest"
  fi
}

verify() {
  local file="$1" expected="$2" actual
  actual="$(sha256_of "$file")"
  if [[ "$actual" != "$expected" ]]; then
    rm -f "$file"
    echo "Error: checksum mismatch for $(basename "$file")." >&2
    echo "  expected $expected" >&2
    echo "  actual   $actual" >&2
    exit 1
  fi
}

fetch_btbn() {
  local platform asset ext base checksum
  case "$TARGET" in
    linux-x64) platform=linux64 ext=tar.xz ;;
    linux-arm64) platform=linuxarm64 ext=tar.xz ;;
    windows-x64) platform=win64 ext=zip ;;
    windows-arm64) platform=winarm64 ext=zip ;;
  esac
  asset="${MORNYE_FFMPEG_BTBN_ASSET:-ffmpeg-n$BTBN_BRANCH-latest-$platform-lgpl-$BTBN_BRANCH.$ext}"
  base="https://github.com/BtbN/FFmpeg-Builds/releases/download/$BTBN_TAG"

  # "latest" moves; always fetch the checksums that match the archive.
  rm -f "$WORK_DIR/$asset" "$WORK_DIR/checksums.sha256"
  download "$base/checksums.sha256" "$WORK_DIR/checksums.sha256"
  download "$base/$asset" "$WORK_DIR/$asset"
  checksum="$(awk -v name="$asset" '$2 == name || $2 == "*" name {print $1}' "$WORK_DIR/checksums.sha256")"
  if [[ -z "$checksum" ]]; then
    echo "Error: $asset is not listed in the release checksums." >&2
    exit 1
  fi
  verify "$WORK_DIR/$asset" "$checksum"

  rm -rf "$WORK_DIR/extract"
  mkdir -p "$WORK_DIR/extract"
  if [[ "$ext" == "zip" ]]; then
    unzip -q "$WORK_DIR/$asset" -d "$WORK_DIR/extract"
  else
    tar -xJf "$WORK_DIR/$asset" -C "$WORK_DIR/extract"
  fi
  local root
  root="$(find "$WORK_DIR/extract" -mindepth 1 -maxdepth 1 -type d | head -n 1)"
  cp "$root/bin/ffmpeg$EXE" "$root/bin/ffprobe$EXE" "$OUT_DIR/"
  cp "$root/LICENSE.txt" "$OUT_DIR/LICENSE.txt"
  {
    echo "FFmpeg LGPL build from BtbN/FFmpeg-Builds."
    echo "Release: https://github.com/BtbN/FFmpeg-Builds/releases/tag/$BTBN_TAG"
    echo "Archive: $asset (sha256 $checksum)"
    echo "Build scripts: https://github.com/BtbN/FFmpeg-Builds"
    echo "FFmpeg source: https://ffmpeg.org/download.html (release branch $BTBN_BRANCH)"
  } > "$OUT_DIR/SOURCE.txt"
}

build_macos() {
  if [[ "$(uname -s)" != "Darwin" ]]; then
    echo "Error: macOS FFmpeg is built from source on a macOS host." >&2
    exit 1
  fi
  local clang_arch host_triple ffmpeg_arch jobs prefix
  case "$ARCH" in
    arm64) clang_arch=arm64 host_triple=aarch64-apple-darwin ffmpeg_arch=arm64 ;;
    x64) clang_arch=x86_64 host_triple=x86_64-apple-darwin ffmpeg_arch=x86_64 ;;
  esac
  jobs="$(sysctl -n hw.ncpu)"
  prefix="$WORK_DIR/deps"
  local flags="-arch $clang_arch -mmacosx-version-min=$MACOS_MIN_VERSION -O2"

  download "https://ffmpeg.org/releases/ffmpeg-$FFMPEG_VERSION.tar.xz" \
    "$WORK_DIR/ffmpeg-$FFMPEG_VERSION.tar.xz"
  verify "$WORK_DIR/ffmpeg-$FFMPEG_VERSION.tar.xz" "$FFMPEG_SHA256"
  download "https://downloads.sourceforge.net/project/lame/lame/$LAME_VERSION/lame-$LAME_VERSION.tar.gz" \
    "$WORK_DIR/lame-$LAME_VERSION.tar.gz"
  verify "$WORK_DIR/lame-$LAME_VERSION.tar.gz" "$LAME_SHA256"
  download "https://downloads.xiph.org/releases/opus/opus-$OPUS_VERSION.tar.gz" \
    "$WORK_DIR/opus-$OPUS_VERSION.tar.gz"
  verify "$WORK_DIR/opus-$OPUS_VERSION.tar.gz" "$OPUS_SHA256"

  rm -rf "$WORK_DIR/src" "$prefix"
  mkdir -p "$WORK_DIR/src" "$prefix"
  tar -xJf "$WORK_DIR/ffmpeg-$FFMPEG_VERSION.tar.xz" -C "$WORK_DIR/src"
  tar -xzf "$WORK_DIR/lame-$LAME_VERSION.tar.gz" -C "$WORK_DIR/src"
  tar -xzf "$WORK_DIR/opus-$OPUS_VERSION.tar.gz" -C "$WORK_DIR/src"

  # Keep package managers' libraries (for example Homebrew's) out of the
  # build so the binaries only link system frameworks.
  export PKG_CONFIG_LIBDIR="$prefix/lib/pkgconfig"
  export PKG_CONFIG_PATH=""

  (
    cd "$WORK_DIR/src/lame-$LAME_VERSION"
    # LAME 3.100 exports a symbol that no longer exists.
    sed -i '' '/lame_init_old/d' include/libmp3lame.sym
    CFLAGS="$flags" LDFLAGS="-arch $clang_arch" ./configure \
      --host="$host_triple" --prefix="$prefix" \
      --disable-shared --enable-static --disable-frontend --disable-decoder \
      --disable-dependency-tracking
    make -j"$jobs"
    make install
  )
  (
    cd "$WORK_DIR/src/opus-$OPUS_VERSION"
    CFLAGS="$flags" LDFLAGS="-arch $clang_arch" ./configure \
      --host="$host_triple" --prefix="$prefix" \
      --disable-shared --enable-static --disable-doc --disable-extra-programs \
      --disable-dependency-tracking
    make -j"$jobs"
    make install
  )
  (
    cd "$WORK_DIR/src/ffmpeg-$FFMPEG_VERSION"
    local cross=()
    [[ "$clang_arch" != "$(uname -m)" ]] && cross=(--enable-cross-compile)
    ./configure \
      --prefix="$prefix" \
      --arch="$ffmpeg_arch" --target-os=darwin --cc=clang "${cross[@]}" \
      --extra-cflags="$flags -I$prefix/include" \
      --extra-ldflags="-arch $clang_arch -mmacosx-version-min=$MACOS_MIN_VERSION -L$prefix/lib" \
      --disable-gpl --disable-nonfree \
      --disable-shared --enable-static --disable-autodetect \
      --disable-doc --disable-ffplay --disable-debug \
      --enable-zlib --enable-audiotoolbox --enable-securetransport \
      --enable-libmp3lame --enable-libopus \
      --pkg-config-flags=--static
    make -j"$jobs"
    cp ffmpeg ffprobe "$OUT_DIR/"
    cp COPYING.LGPLv2.1 "$OUT_DIR/LICENSE.txt"
  )
  {
    echo "FFmpeg $FFMPEG_VERSION built from source by scripts/fetch_desktop_ffmpeg.sh."
    echo "FFmpeg: https://ffmpeg.org/releases/ffmpeg-$FFMPEG_VERSION.tar.xz (sha256 $FFMPEG_SHA256)"
    echo "LAME: https://downloads.sourceforge.net/project/lame/lame/$LAME_VERSION/lame-$LAME_VERSION.tar.gz (sha256 $LAME_SHA256)"
    echo "Opus: https://downloads.xiph.org/releases/opus/opus-$OPUS_VERSION.tar.gz (sha256 $OPUS_SHA256)"
  } > "$OUT_DIR/SOURCE.txt"
}

# Rejects GPL or nonfree builds when the binary can run on this host.
check_license() {
  local binary="$OUT_DIR/ffmpeg$EXE" config
  if ! config="$("$binary" -hide_banner -version 2>/dev/null)"; then
    echo "Note: $TARGET binaries cannot run on this host; license check skipped."
    return
  fi
  if grep -Eq -- '--enable-(gpl|nonfree)( |$)' <<< "$config"; then
    rm -f "$OUT_DIR/ffmpeg$EXE" "$OUT_DIR/ffprobe$EXE"
    echo "Error: the staged FFmpeg is GPL or nonfree and cannot be bundled." >&2
    exit 1
  fi
  local encoders
  encoders="$("$binary" -hide_banner -encoders 2>/dev/null || true)"
  if ! grep -q libmp3lame <<< "$encoders" || ! grep -q libopus <<< "$encoders"; then
    echo "Error: the staged FFmpeg lacks the libmp3lame or libopus encoder." >&2
    exit 1
  fi
}

mkdir -p "$OUT_DIR" "$WORK_DIR"
rm -f "$OUT_DIR/ffmpeg$EXE" "$OUT_DIR/ffprobe$EXE"
case "$OS" in
  macos) build_macos ;;
  linux|windows) fetch_btbn ;;
esac
chmod +x "$OUT_DIR/ffmpeg$EXE" "$OUT_DIR/ffprobe$EXE"
check_license
echo "Staged LGPL FFmpeg for $TARGET in $OUT_DIR"
