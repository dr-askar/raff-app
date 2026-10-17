#!/usr/bin/env python3
"""Drive the real helper + Android consent UI on disposable CI emulators only."""
import re
import os
import subprocess
import time
import xml.etree.ElementTree as ET
from pathlib import Path

HELPER = 'com.raffapp.installcheck'
RAFF = 'com.raffapp.raff'
APP_CODE = int(os.environ.get('RAFF_TEST_APP_CODE', '9'))


def adb(*args, check=True):
    return subprocess.run(['adb', *args], check=check, text=True, capture_output=True).stdout


def wait_for(fn, seconds=100):
    deadline = time.monotonic() + seconds
    while time.monotonic() < deadline:
        result = fn()
        if result:
            return result
        time.sleep(1)
    raise AssertionError('Timed out waiting for device condition')


def nodes():
    adb('shell', 'uiautomator', 'dump', '/data/local/tmp/raff-ui.xml', check=False)
    raw = adb('shell', 'cat', '/data/local/tmp/raff-ui.xml', check=False)
    try:
        return list(ET.fromstring(raw).iter('node'))
    except ET.ParseError:
        return []


def tap(node):
    x1, y1, x2, y2 = map(int, re.findall(r'\d+', node.attrib['bounds']))
    adb('shell', 'input', 'tap', str((x1+x2)//2), str((y1+y2)//2))


def click_text(text):
    def find():
        for n in nodes():
            if n.attrib.get('text') == text and n.attrib.get('enabled') == 'true':
                tap(n)
                return True
        return False
    wait_for(find)


def prefs():
    raw = adb('shell', 'cat', f'/data/user/0/{HELPER}/shared_prefs/install-result.xml', check=False)
    try:
        root = ET.fromstring(raw)
        return {n.attrib['name']: n.attrib.get('value', n.text or '') for n in root}
    except ET.ParseError:
        return {}


def approve_or_finish():
    def progress():
        p = prefs()
        if p.get('status') not in (None, '-2', '-1'):
            return p
        for n in nodes():
            package = n.attrib.get('package', '')
            text = n.attrib.get('text', '').strip().lower()
            if package != HELPER and text in ('install', 'update') and n.attrib.get('enabled') == 'true':
                tap(n)
                break
        return None
    return wait_for(progress, seconds=150)


adb('root')
adb('wait-for-device')
baseline_prefs = None
if Path('apk/baseline.apk').exists():
    assert adb('shell', 'getprop', 'ro.kernel.qemu').strip() == '1', 'Disposable CI emulator required'
    adb('install', '--no-streaming', 'apk/candidate.apk')
    adb('shell', 'am', 'start', '-W', '-n', RAFF + '/.MainActivity')
    time.sleep(5)
    assert adb('shell', 'pidof', RAFF).strip()
    adb('uninstall', RAFF)  # Synthetic CI fresh-install check only.
    adb('install', '--no-streaming', 'apk/baseline.apk')
    adb('shell', 'am', 'start', '-W', '-n', RAFF + '/.MainActivity')
    time.sleep(5)
    adb('shell', 'am', 'force-stop', RAFF)
    baseline_prefs = adb('shell', 'cat', f'/data/user/0/{RAFF}/shared_prefs/FlutterSharedPreferences.xml')
    assert 'flutter.' in baseline_prefs
adb('install', '--no-streaming', 'apk/raff-install-helper.apk')
adb('shell', 'appops', 'set', HELPER, 'REQUEST_INSTALL_PACKAGES', 'allow')
adb('shell', 'am', 'start', '-W', '-n', HELPER + '/.MainActivity')
click_text('تثبيت رفّ وإظهار النتيجة')
first = approve_or_finish()
assert first.get('status') == '0', first
assert f'versionCode={APP_CODE}' in adb('shell', 'dumpsys', 'package', RAFF)
if baseline_prefs is not None:
    assert baseline_prefs == adb('shell', 'cat', f'/data/user/0/{RAFF}/shared_prefs/FlutterSharedPreferences.xml')
    print('PASS: real previous-release upgrade retained Raff preferences.', flush=True)
print('PASS: helper installed the exact Raff APK through Android consent UI.', flush=True)
adb('shell', 'am', 'start', '-W', '-n', RAFF + '/.MainActivity')
time.sleep(5)
assert adb('shell', 'pidof', RAFF).strip()
adb('shell', 'am', 'force-stop', RAFF)
before = adb('shell', 'cat', f'/data/user/0/{RAFF}/shared_prefs/FlutterSharedPreferences.xml')
assert 'flutter.' in before
adb('shell', 'am', 'start', '-W', '-n', HELPER + '/.MainActivity')
click_text('تثبيت رفّ وإظهار النتيجة')
second = approve_or_finish()
assert second.get('status') == '0', second
after = adb('shell', 'cat', f'/data/user/0/{RAFF}/shared_prefs/FlutterSharedPreferences.xml')
assert before == after
print('PASS: helper re-install retained actual Raff preferences.', flush=True)
adb('install', '--no-streaming', '-r', 'apk/ci-only-future.apk')
adb('shell', 'am', 'start', '-W', '-n', HELPER + '/.MainActivity')
click_text('تثبيت رفّ وإظهار النتيجة')
failure = approve_or_finish()
assert failure.get('status') not in ('0', '-1', '-2'), failure
assert 'INSTALL_FAILED_VERSION_DOWNGRADE' in failure.get('message', ''), failure
assert f'versionCode={APP_CODE+1}' in adb('shell', 'dumpsys', 'package', RAFF)
assert before == adb('shell', 'cat', f'/data/user/0/{RAFF}/shared_prefs/FlutterSharedPreferences.xml')
wait_for(lambda: any('INSTALL_FAILED_VERSION_DOWNGRADE' in n.attrib.get('text', '') for n in nodes()))
print('PASS: actual Android rejection code displayed in helper UI; installed package/data unchanged.', flush=True)
Path('helper-test-result.txt').write_text(str(failure))
