#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
IOS_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
ROOT_DIR="$(cd "$IOS_DIR/.." && pwd)"

PREBUILT_LIB="$ROOT_DIR/prebuilt/ios/libeasy_monitoring.a"
FRAMEWORKS_DIR="$IOS_DIR/Frameworks"
DEST_LIB="$FRAMEWORKS_DIR/libeasy_monitoring.a"

mkdir -p "$FRAMEWORKS_DIR"

if [ -f "$PREBUILT_LIB" ]; then
  cp "$PREBUILT_LIB" "$DEST_LIB"
  exit 0
fi

export PATH="$HOME/.cargo/bin:$PATH"
if command -v cargo >/dev/null 2>&1; then
  echo "[easy_monitoring] Building Rust static library for iOS..."
  cargo build --manifest-path "$ROOT_DIR/rust/Cargo.toml" --release --target aarch64-apple-ios || true
  if [ -f "$ROOT_DIR/rust/target/aarch64-apple-ios/release/libeasy_monitoring.a" ]; then
    mkdir -p "$(dirname "$PREBUILT_LIB")"
    cp "$ROOT_DIR/rust/target/aarch64-apple-ios/release/libeasy_monitoring.a" "$PREBUILT_LIB"
    cp "$PREBUILT_LIB" "$DEST_LIB"
    exit 0
  fi
fi

exit 0
