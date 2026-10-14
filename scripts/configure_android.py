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
tree.write(path, encoding='utf-8', xml_declaration=True)
# Firebase Auth and the camera plugin require API 23 or newer.
gradle = Path('android/app/build.gradle.kts')
if gradle.exists():
    source = gradle.read_text()
    source = source.replace('minSdk = flutter.minSdkVersion', 'minSdk = maxOf(23, flutter.minSdkVersion)')
    gradle.write_text(source)
# Remove the generated counter-app test; this project supplies its own tests.
test = Path('test/widget_test.dart')
if test.exists() and 'MyApp' in test.read_text():
    test.unlink()
