#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
MACOS_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
ROOT_DIR="$(cd "$MACOS_DIR/.." && pwd)"

PREBUILT_LIB="$ROOT_DIR/prebuilt/macos/libeasy_monitoring.dylib"
FRAMEWORKS_DIR="$MACOS_DIR/Frameworks"
DEST_LIB="$FRAMEWORKS_DIR/libeasy_monitoring.dylib"
SPM_RESOURCES_DIR="$MACOS_DIR/easy_monitoring/Sources/easy_monitoring/Resources"
SPM_DEST_LIB="$SPM_RESOURCES_DIR/libeasy_monitoring.dylib"

mkdir -p "$FRAMEWORKS_DIR"
mkdir -p "$SPM_RESOURCES_DIR"

copy_to_destinations() {
  cp "$PREBUILT_LIB" "$DEST_LIB"
  install_name_tool -id "@rpath/libeasy_monitoring.dylib" "$DEST_LIB" 2>/dev/null || true
  cp "$DEST_LIB" "$SPM_DEST_LIB"
}

# 1. Zero-Rust path: Use prebuilt binary if already present in prebuilt/macos/
if [ -f "$PREBUILT_LIB" ]; then
  copy_to_destinations
  exit 0
fi

# 2. Download from GitHub Releases if configured and prebuilt binary isn't bundled locally
RELEASE_URL="${EASY_MONITORING_RELEASE_URL:-https://github.com/AlBlanc/easy_monitoring/releases/latest/download/libeasy_monitoring-macos-universal.dylib}"
if command -v curl >/dev/null 2>&1 && [ "${EASY_MONITORING_SKIP_DOWNLOAD:-0}" != "1" ]; then
  echo "[easy_monitoring] Attempting to download precompiled macOS binary from $RELEASE_URL ..."
  mkdir -p "$(dirname "$PREBUILT_LIB")"
  if curl -fsSL "$RELEASE_URL" -o "$PREBUILT_LIB" 2>/dev/null; then
    chmod +x "$PREBUILT_LIB"
    copy_to_destinations
    exit 0
  else
    rm -f "$PREBUILT_LIB"
  fi
fi

# 3. Fallback for local plugin development: compile from Rust source using cargo
export PATH="$HOME/.cargo/bin:$PATH"
if command -v cargo >/dev/null 2>&1; then
  echo "[easy_monitoring] Building Rust library from source (cargo build --release)..."
  cargo build --manifest-path "$ROOT_DIR/rust/Cargo.toml" --release
  mkdir -p "$(dirname "$PREBUILT_LIB")"
  cp "$ROOT_DIR/rust/target/release/libeasy_monitoring.dylib" "$PREBUILT_LIB"
  install_name_tool -id "@rpath/libeasy_monitoring.dylib" "$PREBUILT_LIB" 2>/dev/null || true
  copy_to_destinations
  exit 0
fi

echo "[easy_monitoring] ERROR: Prebuilt library not found at $PREBUILT_LIB and Rust (cargo) is not installed." >&2
exit 1
