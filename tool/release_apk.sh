#!/usr/bin/env bash
# Build the GitHub release APK for Masroufi.
#
# Why not `flutter build apk --release`?
#   That path fails at compileReleaseJavaWithJavac: the generated
#   GeneratedPluginRegistrant references the dev-only `integration_test`
#   plugin, whose native module is not on the release classpath
#   ("package dev.flutter.plugins.integration_test does not exist").
#   `flutter build appbundle --release` does NOT have this problem, so we
#   build the signed AAB and derive the installable universal APK from it
#   with bundletool. Same bytes, same signature.
#
# Usage: ./tool/release_apk.sh 1.1.0
# Output: releases/masroufi-vX.Y.Z.apk + .sha256 (release-key signed)
set -euo pipefail
cd "$(dirname "$0")/.."
source .tooling/env.sh

VER="${1:?usage: release_apk.sh <version, e.g. 1.1.0>}"
AAB="build/app/outputs/bundle/release/app-release.aab"
OUT="releases/masroufi-v${VER}.apk"
BT="/tmp/opencode/bundletool-all.jar"

[ -f "$BT" ] || curl -sL --max-time 300 \
  -o "$BT" https://github.com/google/bundletool/releases/download/1.18.3/bundletool-all-1.18.3.jar

flutter pub get
flutter build appbundle --release

python3 - <<'EOF'
props = {}
for line in open('android/key.properties'):
    line = line.strip()
    if line and not line.startswith('#') and '=' in line:
        k, v = line.split('=', 1)
        props[k.strip()] = v.strip()
import os
os.umask(0o077)
open('/tmp/opencode/ks.pass', 'w').write(props['storePassword'] + '\n')
open('/tmp/opencode/key.pass', 'w').write(props['keyPassword'] + '\n')
open('/tmp/opencode/alias.txt', 'w').write(props['keyAlias'])
sf = props['storeFile']
open('/tmp/opencode/ks.txt', 'w').write(sf if sf.startswith('/') else 'android/' + sf)
EOF
KS="$(cat /tmp/opencode/ks.txt)"
ALIAS="$(cat /tmp/opencode/alias.txt)"
"$JAVA_HOME/bin/java" -jar "$BT" build-apks \
  --bundle="$AAB" --output=/tmp/opencode/release.apks --mode=universal --overwrite \
  --ks="$KS" --ks-pass=file:/tmp/opencode/ks.pass \
  --ks-key-alias="$ALIAS" --key-pass=file:/tmp/opencode/key.pass
shred -u /tmp/opencode/ks.pass /tmp/opencode/key.pass /tmp/opencode/ks.txt /tmp/opencode/alias.txt
python3 -c "import zipfile; zipfile.ZipFile('/tmp/opencode/release.apks').extract('universal.apk','/tmp/opencode')"
mv /tmp/opencode/universal.apk "$OUT"
APKSIGNER="$(ls -d "$ANDROID_HOME"/build-tools/*/apksigner | sort -V | tail -n1)"
"$APKSIGNER" verify --print-certs "$OUT" | grep "Signer #1"
sha256sum "$OUT" | tee "$OUT.sha256"
echo "OK: $OUT"
