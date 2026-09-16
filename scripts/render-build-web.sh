#!/usr/bin/env bash
set -euo pipefail

# Match the Flutter release used to develop and validate this project.
flutter_version=3.47.4
: "${BACKEND_URL:?Set BACKEND_URL to the API service HTTPS URL in Render}"
if [[ ! "$BACKEND_URL" =~ ^https://[^/]+/?$ ]]; then
  echo 'BACKEND_URL must be an HTTPS origin, without a path.' >&2
  exit 1
fi
backend_origin="${BACKEND_URL%/}"
flutter_sdk="${TMPDIR:-/tmp}/buklin-flutter-${flutter_version}"
if [[ ! -d "$flutter_sdk/.git" ]]; then
  git clone --depth 1 --branch "$flutter_version" https://github.com/flutter/flutter.git "$flutter_sdk"
fi
export PATH="$flutter_sdk/bin:$PATH"
flutter config --no-analytics
flutter pub get
flutter build web --release --dart-define="BACKEND_URL=$backend_origin"
