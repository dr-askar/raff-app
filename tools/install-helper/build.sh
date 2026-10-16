#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/../.."
test "${RAFF_RELEASE_KEYSTORE:+present}" = present
test "${RAFF_PASSWORD_FILE:+present}" = present
test -f tools/install-helper/assets/raff-0.4.1.apk
echo '5857b79d51300d3de282dd4454d0fab6a74e1c9c21bdb7d0fd2f703d817f6926  tools/install-helper/assets/raff-0.4.1.apk' | sha256sum --check
RAFF_TOOLS=$(find "$ANDROID_HOME/build-tools" -mindepth 1 -maxdepth 1 -type d | sort -V | tail -1)
RAFF_ANDROID_JAR="$ANDROID_HOME/platforms/android-36/android.jar"
RAFF_BUILD="$RUNNER_TEMP/raff-helper-build"
mkdir -p "$RAFF_BUILD/classes" "$RAFF_BUILD/dex" helper-apk
"$RAFF_TOOLS/aapt2" compile --dir tools/install-helper/res -o "$RAFF_BUILD/resources.zip"
"$RAFF_TOOLS/aapt2" link -o "$RAFF_BUILD/resources.apk" --manifest tools/install-helper/AndroidManifest.xml -I "$RAFF_ANDROID_JAR" --version-code 1 --version-name 1.0 -A tools/install-helper/assets -0 apk "$RAFF_BUILD/resources.zip"
javac -encoding UTF-8 --release 8 -cp "$RAFF_ANDROID_JAR" -d "$RAFF_BUILD/classes" tools/install-helper/src/com/raffapp/installcheck/*.java
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
import hashlib, zipfile
with zipfile.ZipFile('helper-apk/raff-install-helper.apk') as z:
    assert not any(n.startswith('lib/') for n in z.namelist())
    assert hashlib.sha256(z.read('assets/raff-0.4.1.apk')).hexdigest() == '5857b79d51300d3de282dd4454d0fab6a74e1c9c21bdb7d0fd2f703d817f6926'
print('Embedded Raff APK unchanged; helper has no native libraries.')
PY
(cd helper-apk && sha256sum raff-install-helper.apk > SHA256SUMS.txt)
# CI-only future-version fixture exercises a real PackageManager rejection.
# It has no code, is never published and is installed only in disposable emulators.
cat > "$RAFF_BUILD/fixture.xml" <<'XML'
<manifest xmlns:android="http://schemas.android.com/apk/res/android" package="com.raffapp.raff" android:versionCode="10" android:versionName="CI-only-future"><uses-sdk android:minSdkVersion="24" android:targetSdkVersion="36"/><application android:hasCode="false" android:label="CI ONLY"/></manifest>
XML
"$RAFF_TOOLS/aapt2" link -o "$RAFF_BUILD/fixture-unsigned.apk" --manifest "$RAFF_BUILD/fixture.xml" -I "$RAFF_ANDROID_JAR"
"$RAFF_TOOLS/zipalign" -f 4 "$RAFF_BUILD/fixture-unsigned.apk" "$RAFF_BUILD/fixture-aligned.apk"
"$RAFF_TOOLS/apksigner" sign --ks "$RAFF_RELEASE_KEYSTORE" --ks-key-alias raff-release --ks-pass "file:$RAFF_PASSWORD_FILE" --out helper-apk/ci-only-future.apk "$RAFF_BUILD/fixture-aligned.apk"
