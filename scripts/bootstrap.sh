#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/.."
command -v flutter >/dev/null || { echo 'Install Flutter stable and add it to PATH first.'; exit 1; }
# Flutter generates standard platform runners. Existing application source is retained.
flutter create --no-pub --platforms=android,web --org com.raffapp --project-name raff .
python3 scripts/configure_android.py
flutter pub get
echo 'Ready: flutter run (local demo), or use --dart-define-from-file=config/firebase.json for cloud mode.'
