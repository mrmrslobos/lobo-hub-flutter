#!/usr/bin/env bash
# Build a signed standard-release AAB for Google Play (Production / Open testing).
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"

if [[ ! -f android/key.properties ]]; then
  echo "Missing android/key.properties — copy android/key.properties.example and point storeFile to your upload keystore."
  echo "Open beta / production require the same upload key Google Play already knows."
  exit 1
fi

: "${SUPABASE_URL:=}"
: "${SUPABASE_ANON_KEY:=}"
: "${RC_ANDROID_KEY:=}"

DART_DEFINES=()
if [[ -n "$SUPABASE_URL" ]]; then DART_DEFINES+=(--dart-define=SUPABASE_URL="$SUPABASE_URL"); fi
if [[ -n "$SUPABASE_ANON_KEY" ]]; then DART_DEFINES+=(--dart-define=SUPABASE_ANON_KEY="$SUPABASE_ANON_KEY"); fi
if [[ -n "$RC_ANDROID_KEY" ]]; then DART_DEFINES+=(--dart-define=RC_ANDROID_KEY="$RC_ANDROID_KEY"); fi

flutter pub get
flutter build appbundle --release --flavor standard -t lib/main.dart "${DART_DEFINES[@]}"

OUT="$ROOT/build/app/outputs/bundle/standardRelease/app-standard-release.aab"
echo "Built: $OUT"
ls -lh "$OUT"
