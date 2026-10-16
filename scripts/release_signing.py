#!/usr/bin/env python3
"""Prepare private CI signing input or verify a public APK signing certificate."""
import base64
import binascii
import os
from pathlib import Path
import re
import sys
import tempfile


NAMES = ("RAFF_ANDROID_KEYSTORE_BASE64", "RAFF_ANDROID_STORE_PASSWORD",
         "RAFF_ANDROID_KEY_ALIAS", "RAFF_ANDROID_KEY_PASSWORD",
         "RAFF_ANDROID_CERT_SHA256")


def output(name, value):
    with open(os.environ["GITHUB_OUTPUT"], "a") as handle:
        handle.write(f"{name}={value}\n")


def fingerprint(value):
    result = value.strip().replace(":", "").lower()
    if not re.fullmatch(r"[0-9a-f]{64}", result):
        raise ValueError("Expected signing certificate must be a SHA-256 fingerprint")
    return result


def prepare():
    values = [os.environ.get(name, "") for name in NAMES]
    if not any(values):
        output("ready", "false")
        print("No persistent signing configured: internal CI artifact only; publishing disabled.")
        return
    if not all(values):
        raise ValueError("Incomplete persistent signing configuration; refusing fallback")
    fingerprint(values[-1])
    try:
        key_bytes = base64.b64decode("".join(values[0].split()), validate=True)
    except (ValueError, binascii.Error):
        raise ValueError("Invalid keystore encoding") from None
    if not key_bytes:
        raise ValueError("Empty keystore")
    # mkstemp creates a private 0600 file outside the checkout and artifacts.
    fd, name = tempfile.mkstemp(prefix="raff-release-", suffix=".keystore",
                                dir=os.environ["RUNNER_TEMP"])
    try:
        with os.fdopen(fd, "wb") as handle:
            handle.write(key_bytes)
        with open(os.environ["GITHUB_ENV"], "a") as handle:
            if "\n" in name or "\r" in name:
                raise ValueError("Invalid runner temporary path")
            handle.write(f"RAFF_RELEASE_KEYSTORE={name}\n")
        output("ready", "true")
    except Exception:
        Path(name).unlink(missing_ok=True)
        raise
    print("Private signing input ready. Key material is not included in artifacts.")


def verify(log_path):
    expected = fingerprint(os.environ.get("RAFF_ANDROID_CERT_SHA256", ""))
    log = Path(log_path).read_text()
    actual = re.findall(r"certificate SHA-256 digest: ([0-9a-fA-F:]+)", log)
    if not actual or {fingerprint(value) for value in actual} != {expected}:
        raise ValueError("APK certificate does not match configured persistent certificate")
    if re.search(r"certificate DN:.*CN=Android Debug", log, re.I):
        raise ValueError("Debug signing certificate is not allowed for distribution")
    output("verified", "true")
    print("APK matches the configured persistent signing certificate.")


if __name__ == "__main__":
    try:
        if sys.argv[1:] == ["prepare"]:
            prepare()
        elif len(sys.argv) == 3 and sys.argv[1] == "verify":
            verify(sys.argv[2])
        else:
            raise ValueError("Usage: release_signing.py prepare | verify APKSIGNER_LOG")
    except (ValueError, KeyError, OSError):
        # Keep exception values, file paths and secret input out of CI logs.
        print("Release signing check failed; verify secure configuration and certificate.", file=sys.stderr)
        sys.exit(1)
