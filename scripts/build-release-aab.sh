#!/usr/bin/env bash
# Build a signed standard-release AAB for Google Play (standard flavor).
# Signing from android/key.properties OR Cursor / CI env vars (see below).
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"

KEY_PROPS="$ROOT/android/key.properties"
KEYSTORE_PATH="${RUNNER_TEMP:-/tmp}/huddle-upload-keystore.jks"

# Cursor secrets / CI: decode keystore and write key.properties from env
if [[ ! -f "$KEY_PROPS" && -n "${ANDROID_KEYSTORE_BASE64:-}" ]]; then
  if [[ -z "${ANDROID_KEYSTORE_PASSWORD:-}" || -z "${ANDROID_KEY_ALIAS:-}" || -z "${ANDROID_KEY_PASSWORD:-}" ]]; then
    echo "Set ANDROID_KEYSTORE_PASSWORD, ANDROID_KEY_ALIAS, and ANDROID_KEY_PASSWORD with ANDROID_KEYSTORE_BASE64."
    exit 1
  fi
  echo "$ANDROID_KEYSTORE_BASE64" | base64 -d > "$KEYSTORE_PATH"
  cat > "$KEY_PROPS" <<EOF
storePassword=${ANDROID_KEYSTORE_PASSWORD}
keyPassword=${ANDROID_KEY_PASSWORD}
keyAlias=${ANDROID_KEY_ALIAS}
storeFile=${KEYSTORE_PATH}
EOF
  echo "Configured signing from ANDROID_KEYSTORE_* environment variables."
fi

if [[ ! -f "$KEY_PROPS" ]]; then
  echo "Missing android/key.properties and no ANDROID_KEYSTORE_BASE64 in environment."
  echo "Either:"
  echo "  • Copy android/key.properties.example → android/key.properties (local keystore path)"
  echo "  • Or add Cursor Secrets: ANDROID_KEYSTORE_BASE64, ANDROID_KEYSTORE_PASSWORD,"
  echo "    ANDROID_KEY_ALIAS, ANDROID_KEY_PASSWORD (Runtime Secret type for passwords)"
  exit 1
fi

: "${SUPABASE_URL:=}"
: "${SUPABASE_ANON_KEY:=}"
: "${RC_ANDROID_KEY:=}"

DART_DEFINES=()
if [[ -n "$SUPABASE_URL" ]]; then DART_DEFINES+=(--dart-define=SUPABASE_URL="$SUPABASE_URL"); fi
if [[ -n "$SUPABASE_ANON_KEY" ]]; then DART_DEFINES+=(--dart-define=SUPABASE_ANON_KEY="$SUPABASE_ANON_KEY"); fi
if [[ -n "$RC_ANDROID_KEY" ]]; then DART_DEFINES+=(--dart-define=RC_ANDROID_KEY="$RC_ANDROID_KEY"); fi

if ! command -v flutter >/dev/null 2>&1; then
  if [[ -x /opt/flutter/bin/flutter ]]; then
    export PATH="/opt/flutter/bin:$PATH"
  fi
fi

flutter pub get
flutter build appbundle --release --flavor standard -t lib/main.dart "${DART_DEFINES[@]}"

OUT="$ROOT/build/app/outputs/bundle/standardRelease/app-standard-release.aab"
echo "Built: $OUT"
ls -lh "$OUT"
