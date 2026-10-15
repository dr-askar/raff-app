#!/usr/bin/env python3
"""Check 16 KB LOAD alignment of all 64-bit native libraries in an APK."""
from pathlib import Path
import subprocess
import sys
import tempfile
import zipfile

bad = []
count = 0
with zipfile.ZipFile(sys.argv[1]) as apk, tempfile.TemporaryDirectory() as tmp:
    for name in apk.namelist():
        if not name.endswith(".so") or not name.startswith(("lib/arm64-v8a/", "lib/x86_64/")):
            continue
        count += 1
        path = Path(tmp) / str(count)
        path.write_bytes(apk.read(name))
        result = subprocess.run(
            ["readelf", "-lW", str(path)], check=True, capture_output=True, text=True
        )
        loads = [line.split() for line in result.stdout.splitlines() if line.strip().startswith("LOAD ")]
        aligned = bool(loads) and all(
            int(row[-1], 16) >= 16384
            and (int(row[1], 16) - int(row[2], 16)) % 16384 == 0
            for row in loads
        )
        print(("ALIGNED " if aligned else "UNALIGNED ") + name)
        if not aligned:
            bad.append(name)
if count == 0:
    raise SystemExit("No 64-bit native libraries found; check APK architecture.")
if bad:
    raise SystemExit("16 KB alignment failed: " + ", ".join(bad))
print(f"Verified {count} 64-bit native libraries.")
