from pathlib import Path
import xml.etree.ElementTree as ET

path = Path('android/app/src/main/AndroidManifest.xml')
ns = 'http://schemas.android.com/apk/res/android'
ET.register_namespace('android', ns)
tree = ET.parse(path)
root = tree.getroot()
for permission in ['android.permission.INTERNET', 'android.permission.CAMERA']:
    if not any(p.get(f'{{{ns}}}name') == permission for p in root.findall('uses-permission')):
        ET.SubElement(root, 'uses-permission', {f'{{{ns}}}name': permission})
if not any(p.get(f'{{{ns}}}name') == 'android.hardware.camera' for p in root.findall('uses-feature')):
    ET.SubElement(root, 'uses-feature', {f'{{{ns}}}name': 'android.hardware.camera', f'{{{ns}}}required': 'false'})
root.find('application').set(f'{{{ns}}}label', 'رفّ')
# Extract native libraries during installation for older/OEM installers.
root.find('application').set(f'{{{ns}}}extractNativeLibs', 'true')
tree.write(path, encoding='utf-8', xml_declaration=True)
# Firebase Auth and the camera plugin require API 23 or newer.
gradle = Path('android/app/build.gradle.kts')
if gradle.exists():
    source = gradle.read_text()
    source = source.replace('minSdk = flutter.minSdkVersion', 'minSdk = maxOf(23, flutter.minSdkVersion)')
    # Keep release builds small via Flutter AOT; defer Android code shrinking until
    # the native barcode/file plugins have been tested on the shop's phones.
    if 'isMinifyEnabled = false' not in source:
        source = source.replace('release {', 'release {\n            isMinifyEnabled = false\n            isShrinkResources = false', 1)
    # Universal APK: compressed native libraries avoid relying on in-place mmap
    # support in OEM installers. Keep both Android signature schemes available.
    if '// Raff installer compatibility' not in source:
        source += '''
// Raff installer compatibility
android {
    packaging {
        jniLibs {
            useLegacyPackaging = true
        }
    }
    signingConfigs {
        getByName("debug") {
            enableV1Signing = true
            enableV2Signing = true
        }
    }
}
'''
    gradle.write_text(source)
# Remove the generated counter-app test; this project supplies its own tests.
test = Path('test/widget_test.dart')
if test.exists() and 'MyApp' in test.read_text():
    test.unlink()
