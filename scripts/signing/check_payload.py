#!/usr/bin/env python3
"""Confirm that re-signing did not alter application entries."""
import hashlib
import sys
import zipfile


def entries(path):
    with zipfile.ZipFile(path) as archive:
        result = {}
        for info in archive.infolist():
            name = info.filename
            upper = name.upper()
            signature = upper == "META-INF/MANIFEST.MF" or (
                upper.startswith("META-INF/") and upper.endswith((".SF", ".RSA", ".DSA", ".EC")))
            if not signature:
                if name in result:
                    raise ValueError("Duplicate ZIP entry")
                result[name] = hashlib.sha256(archive.read(name)).digest()
        return result


if __name__ == "__main__":
    if entries(sys.argv[1]) != entries(sys.argv[2]):
        raise SystemExit("Application payload changed during signing")
    print("All non-signature APK entries are unchanged.")
