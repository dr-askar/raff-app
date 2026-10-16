#!/usr/bin/env python3
"""Capture targeted Android installation evidence; never uninstall or clear data."""
import argparse
import hashlib
import json
from pathlib import Path
import shutil
import subprocess
import sys
from datetime import datetime, timezone


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--apk", required=True, type=Path)
    parser.add_argument("--serial", help="ADB device serial when several are attached")
    parser.add_argument("--attempt-install", action="store_true",
                        help="Explicitly attempt adb install -r; default is read-only")
    parser.add_argument("--output", type=Path,
                        default=Path("android-install-report.json"))
    args = parser.parse_args()
    apk = args.apk.resolve()
    if not apk.is_file() or apk.suffix.lower() != ".apk":
        parser.error("--apk must be an existing .apk file")
    if args.output.resolve() == apk:
        parser.error("--output must not overwrite the APK")
    adb = shutil.which("adb")
    if not adb:
        parser.error("Install Android SDK Platform Tools and add adb to PATH")
    prefix = [adb] + (["-s", args.serial] if args.serial else [])
    digest = hashlib.sha256()
    with apk.open("rb") as handle:
        for chunk in iter(lambda: handle.read(1024 * 1024), b""):
            digest.update(chunk)
    report = {
        "time_utc": datetime.now(timezone.utc).isoformat(),
        "apk_name": apk.name,
        "apk_size": apk.stat().st_size,
        "apk_sha256": digest.hexdigest(),
        "installation_requested": args.attempt_install,
        "commands": [],
    }

    def run(*command, timeout=30):
        try:
            result = subprocess.run(prefix + list(command), capture_output=True,
                                    text=True, timeout=timeout, check=False)
            item = {"command": list(command), "exit_code": result.returncode,
                    "stdout": result.stdout, "stderr": result.stderr}
        except subprocess.TimeoutExpired as exc:
            def decode(value):
                return value.decode(errors="replace") if isinstance(value, bytes) else value
            item = {"command": list(command), "exit_code": None,
                    "stdout": decode(exc.stdout) or "",
                    "stderr": decode(exc.stderr) or "", "timed_out": True}
        report["commands"].append(item)
        return item

    def write_report():
        args.output.write_text(json.dumps(report, ensure_ascii=False, indent=2) + "\n")
        print("Report:", args.output.resolve())

    state = run("get-state")
    if state["exit_code"] != 0 or state["stdout"].strip() != "device":
        report["status"] = "device_unavailable_or_unauthorized"
        write_report()
        print("Connect one device, approve USB debugging, or use --serial.", file=sys.stderr)
        return 2
    for prop in ("ro.product.manufacturer", "ro.product.model",
                 "ro.build.version.release", "ro.build.version.sdk",
                 "ro.product.cpu.abilist"):
        run("shell", "getprop", prop)
    run("shell", "getconf", "PAGE_SIZE")  # Unsupported on some older phones; not fatal.
    run("shell", "pm", "list", "packages", "-u", "com.raffapp.raff")
    run("shell", "dumpsys", "package", "com.raffapp.raff")
    if args.attempt_install:
        result = run("install", "--no-streaming", "-r", str(apk), timeout=180)
        success = (result["exit_code"] == 0
                   and "Success" in result["stdout"].splitlines())
        report["status"] = "adb_install_success" if success else "adb_install_failed"
        report["physical_launch_verified"] = False
        print(result["stdout"], end="")
        print(result["stderr"], end="", file=sys.stderr)
        write_report()
        return 0 if success else 1
    report["status"] = "read_only_no_install_attempt"
    write_report()
    print("No installation attempted. Use --attempt-install only for an intended attempt.")
    return 0


if __name__ == "__main__":
    sys.exit(main())
