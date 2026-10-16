import base64
import importlib.util
import os
from pathlib import Path
import subprocess
import sys
import tempfile
import unittest
from unittest.mock import patch

ROOT = Path(__file__).resolve().parents[2]
SPEC = importlib.util.spec_from_file_location("release_signing", ROOT / "scripts/release_signing.py")
SIGN = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(SIGN)


class SigningTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.addCleanup(self.temp.cleanup)
        self.root = Path(self.temp.name)
        self.env = {"GITHUB_OUTPUT": str(self.root / "out"),
                    "GITHUB_ENV": str(self.root / "env"),
                    "RUNNER_TEMP": str(self.root)}
        self.patcher = patch.dict(os.environ, self.env, clear=True)
        self.patcher.start()
        self.addCleanup(self.patcher.stop)

    def configure(self):
        os.environ.update(dict(zip(SIGN.NAMES, [
            base64.b64encode(b"private test fixture").decode(),
            "test-store-password", "fixture-key", "test-key-password", "a" * 64])))

    def test_missing_secrets_disable_distribution(self):
        SIGN.prepare()
        self.assertEqual((self.root / "out").read_text(), "ready=false\n")
        self.assertEqual(list(self.root.glob("*.keystore")), [])

    def test_partial_secrets_never_fall_back(self):
        os.environ[SIGN.NAMES[1]] = "test-password"
        with self.assertRaises(ValueError):
            SIGN.prepare()
        self.assertFalse((self.root / "out").exists())

    def test_private_file_outside_artifacts(self):
        self.configure()
        SIGN.prepare()
        path = Path((self.root / "env").read_text().strip().split("=", 1)[1])
        self.assertEqual(path.read_bytes(), b"private test fixture")
        self.assertEqual(path.stat().st_mode & 0o777, 0o600)
        self.assertEqual((self.root / "out").read_text(), "ready=true\n")
        self.assertNotIn("password", (self.root / "env").read_text())

    def test_bad_encoding_never_readies(self):
        self.configure()
        os.environ[SIGN.NAMES[0]] = "invalid!"
        with self.assertRaises(ValueError):
            SIGN.prepare()
        self.assertFalse((self.root / "out").exists())

    def test_certificate_mismatch_rejected(self):
        self.configure()
        log = self.root / "cert.txt"
        log.write_text("Signer #1 certificate SHA-256 digest: " + "b" * 64)
        with self.assertRaises(ValueError):
            SIGN.verify(log)
        self.assertFalse((self.root / "out").exists())

    def test_debug_certificate_rejected_even_when_fingerprint_matches(self):
        self.configure()
        log = self.root / "cert.txt"
        log.write_text("Signer #1 certificate DN: C=US, O=Android, CN=Android Debug\n"
                       "Signer #1 certificate SHA-256 digest: " + "a" * 64)
        with self.assertRaises(ValueError):
            SIGN.verify(log)

    def test_release_certificate_accepted(self):
        self.configure()
        log = self.root / "cert.txt"
        log.write_text("Signer #1 certificate DN: CN=Raff Release\n"
                       "Signer #1 certificate SHA-256 digest: " + "a" * 64)
        SIGN.verify(log)
        self.assertEqual((self.root / "out").read_text(), "verified=true\n")

    def test_bootstrap_is_idempotent_and_does_not_embed_secrets(self):
        manifest = self.root / "android/app/src/main/AndroidManifest.xml"
        manifest.parent.mkdir(parents=True)
        manifest.write_text('<manifest xmlns:android="http://schemas.android.com/apk/res/android"><application /></manifest>')
        gradle = self.root / "android/app/build.gradle.kts"
        gradle.write_text("android { defaultConfig { minSdk = flutter.minSdkVersion }\n"
                          "buildTypes { release { signingConfig = signingConfigs.getByName(\"debug\") } } }")
        command = [sys.executable, str(ROOT / "scripts/configure_android.py")]
        subprocess.run(command, cwd=self.root, check=True, capture_output=True)
        first = gradle.read_text()
        subprocess.run(command, cwd=self.root, check=True, capture_output=True)
        self.assertEqual(first, gradle.read_text())
        self.assertEqual(first.count("// Raff persistent release signing"), 1)
        self.assertIn('create("raffRelease")', first)
        self.assertIn('System.getenv("RAFF_ANDROID_STORE_PASSWORD")', first)
        self.assertNotIn("test-store-password", first)


if __name__ == "__main__":
    unittest.main()
