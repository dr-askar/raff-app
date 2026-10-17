#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/../.."
test "${RAFF_RELEASE_KEYSTORE:+present}" = present
test "${RAFF_PASSWORD_FILE:+present}" = present
export RAFF_APP_VERSION="${RAFF_APP_VERSION:-0.4.1}"
export RAFF_APP_CODE="${RAFF_APP_CODE:-9}"
export RAFF_APP_DIGEST="${RAFF_APP_DIGEST:-5857b79d51300d3de282dd4454d0fab6a74e1c9c21bdb7d0fd2f703d817f6926}"
export RAFF_HELPER_CODE="${RAFF_HELPER_CODE:-1}"
RAFF_EMBEDDED_APK="${RAFF_EMBEDDED_APK:-tools/install-helper/assets/raff-$RAFF_APP_VERSION.apk}"
test -f "$RAFF_EMBEDDED_APK"
echo "$RAFF_APP_DIGEST  $RAFF_EMBEDDED_APK" | sha256sum --check
RAFF_TOOLS=$(find "$ANDROID_HOME/build-tools" -mindepth 1 -maxdepth 1 -type d | sort -V | tail -1)
RAFF_ANDROID_JAR="$ANDROID_HOME/platforms/android-36/android.jar"
export RAFF_BUILD="$RUNNER_TEMP/raff-helper-build"
mkdir -p "$RAFF_BUILD/classes" "$RAFF_BUILD/dex" "$RAFF_BUILD/assets" helper-apk
cp "$RAFF_EMBEDDED_APK" "$RAFF_BUILD/assets/raff-app.apk"
python3 - <<'PY'
import json, os, re
from pathlib import Path
v, h = os.environ['RAFF_APP_VERSION'], os.environ['RAFF_APP_DIGEST']
c, helper = int(os.environ['RAFF_APP_CODE']), int(os.environ['RAFF_HELPER_CODE'])
assert re.fullmatch(r'\d+\.\d+\.\d+', v) and re.fullmatch(r'[0-9a-f]{64}', h)
assert 0 < c < 2100000000 and 0 < helper < 2100000000
p = Path(os.environ['RAFF_BUILD'])
(p / 'ReleaseInfo.java').write_text('package com.raffapp.installcheck; final class ReleaseInfo {'
    + f'static final String VERSION={json.dumps(v)}, HASH={json.dumps(h)};'
    + f'static final int CODE={c}, HELPER={helper};' + '}')
(p / 'fixture.xml').write_text(f'<manifest xmlns:android="http://schemas.android.com/apk/res/android" package="com.raffapp.raff" android:versionCode="{c+1}" android:versionName="CI-only-future"><uses-sdk android:minSdkVersion="24" android:targetSdkVersion="36"/><application android:hasCode="false" android:label="CI ONLY"/></manifest>')
PY
"$RAFF_TOOLS/aapt2" compile --dir tools/install-helper/res -o "$RAFF_BUILD/resources.zip"
"$RAFF_TOOLS/aapt2" link -o "$RAFF_BUILD/resources.apk" --manifest tools/install-helper/AndroidManifest.xml -I "$RAFF_ANDROID_JAR" --version-code "$RAFF_HELPER_CODE" --version-name "$RAFF_HELPER_CODE.0" -A "$RAFF_BUILD/assets" -0 apk "$RAFF_BUILD/resources.zip"
javac -encoding UTF-8 --release 8 -cp "$RAFF_ANDROID_JAR" -d "$RAFF_BUILD/classes" tools/install-helper/src/com/raffapp/installcheck/*.java "$RAFF_BUILD/ReleaseInfo.java"
jar cf "$RAFF_BUILD/classes.jar" -C "$RAFF_BUILD/classes" .
"$RAFF_TOOLS/d8" --release --min-api 24 --lib "$RAFF_ANDROID_JAR" --output "$RAFF_BUILD/dex" "$RAFF_BUILD/classes.jar"
cp "$RAFF_BUILD/resources.apk" "$RAFF_BUILD/unsigned.apk"
python3 - "$RAFF_BUILD" <<'PY'
from pathlib import Path
import sys, zipfile
p = Path(sys.argv[1])
with zipfile.ZipFile(p / 'unsigned.apk', 'a') as z:
    z.write(p / 'dex/classes.dex', 'classes.dex', compress_type=zipfile.ZIP_DEFLATED)
PY
"$RAFF_TOOLS/zipalign" -f -P 16 4 "$RAFF_BUILD/unsigned.apk" "$RAFF_BUILD/aligned.apk"
"$RAFF_TOOLS/apksigner" sign --ks "$RAFF_RELEASE_KEYSTORE" --ks-key-alias raff-release --ks-pass "file:$RAFF_PASSWORD_FILE" --v1-signing-enabled true --v2-signing-enabled true --v3-signing-enabled true --v4-signing-enabled false --out helper-apk/raff-install-helper.apk "$RAFF_BUILD/aligned.apk"
"$RAFF_TOOLS/apksigner" verify --verbose --print-certs helper-apk/raff-install-helper.apk | tee "$RAFF_BUILD/cert.txt"
RAFF_ANDROID_CERT_SHA256=$(cat config/android-release-cert.sha256) python3 scripts/release_signing.py verify "$RAFF_BUILD/cert.txt"
"$RAFF_TOOLS/zipalign" -c -P 16 4 helper-apk/raff-install-helper.apk
"$RAFF_TOOLS/aapt" dump badging helper-apk/raff-install-helper.apk | head -30
unzip -t helper-apk/raff-install-helper.apk | tail -1
python3 - <<'PY'
import hashlib, os, zipfile
with zipfile.ZipFile('helper-apk/raff-install-helper.apk') as z:
    assert not any(n.startswith('lib/') for n in z.namelist())
    assert hashlib.sha256(z.read('assets/raff-app.apk')).hexdigest() == os.environ['RAFF_APP_DIGEST']
print('Embedded Raff APK unchanged; helper has no native libraries.')
PY
(cd helper-apk && sha256sum raff-install-helper.apk > SHA256SUMS.txt)
# CI-only future-version fixture exercises a real PackageManager rejection.
# It has no code, is never published and is installed only in disposable emulators.
"$RAFF_TOOLS/aapt2" link -o "$RAFF_BUILD/fixture-unsigned.apk" --manifest "$RAFF_BUILD/fixture.xml" -I "$RAFF_ANDROID_JAR"
"$RAFF_TOOLS/zipalign" -f 4 "$RAFF_BUILD/fixture-unsigned.apk" "$RAFF_BUILD/fixture-aligned.apk"
"$RAFF_TOOLS/apksigner" sign --ks "$RAFF_RELEASE_KEYSTORE" --ks-key-alias raff-release --ks-pass "file:$RAFF_PASSWORD_FILE" --out helper-apk/ci-only-future.apk "$RAFF_BUILD/fixture-aligned.apk"
