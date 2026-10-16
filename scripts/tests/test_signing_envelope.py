import importlib.util
from pathlib import Path
import tempfile
import unittest
from cryptography.exceptions import InvalidTag

ROOT = Path(__file__).resolve().parents[2]
SPEC = importlib.util.spec_from_file_location("envelope", ROOT / "scripts/signing/envelope.py")
MOD = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(MOD)


class EnvelopeTests(unittest.TestCase):
    def test_authenticated_roundtrip_and_no_plaintext(self):
        with tempfile.TemporaryDirectory() as name:
            root = Path(name)
            ctx = MOD.context("123", "a" * 40, "b" * 64)
            public = MOD.recipient(root, ctx)
            original = {"keystore": "fixture", "password": "private-test-value"}
            envelope = MOD.seal(public, ctx, original)
            self.assertNotIn("private-test-value", str(envelope))
            self.assertEqual(MOD.unseal(root, envelope, ctx), original)
            changed = dict(envelope, ciphertext=MOD.encoded(b"invalid"))
            with self.assertRaises(InvalidTag):
                MOD.unseal(root, changed, ctx)

    def test_other_session_and_expiry_are_rejected(self):
        with tempfile.TemporaryDirectory() as name:
            ctx = MOD.context("123", "a" * 40, "b" * 64)
            public = MOD.recipient(Path(name), ctx)
            wrong = dict(ctx, session="999")
            with self.assertRaises(ValueError):
                MOD.seal(public, wrong, {})
            public["expires"] = 0
            with self.assertRaises(ValueError):
                MOD.seal(public, ctx, {})

    def test_another_recipient_cannot_open_envelope(self):
        with tempfile.TemporaryDirectory() as a, tempfile.TemporaryDirectory() as b:
            ctx = MOD.context("123", "a" * 40, "b" * 64)
            public = MOD.recipient(Path(a), ctx)
            MOD.recipient(Path(b), ctx)
            sealed = MOD.seal(public, ctx, {"fixture": True})
            with self.assertRaises(ValueError):
                MOD.unseal(Path(b), sealed, ctx)

    def test_stable_key_is_reused_and_missing_pinned_key_is_not_replaced(self):
        with tempfile.TemporaryDirectory() as name:
            root = Path(name); directory = root / "private"; pin = root / "pin.txt"
            first = MOD.init(directory, pin)
            raw = (directory / "release.p12").read_bytes()
            self.assertEqual(MOD.init(directory, pin), first)
            self.assertEqual((directory / "release.p12").read_bytes(), raw)
            (directory / "release.p12").unlink()
            with self.assertRaises(ValueError):
                MOD.init(directory, pin)
