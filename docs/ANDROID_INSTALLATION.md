# Android installation incident

**Status: OPEN — physical-device cause not yet established. Updated 2026-10-16.**

## Confirmed facts

- The user identified a Xiaomi 15T Pro, HyperOS 3.0.336.0, Android 17.
- The latest screenshot shows `raff-0.4.0-universal.apk`, 41.30 MB, and
  "App nicht installiert". This dialog contains no specific failure code.
- The user explicitly confirmed the old app was deleted before this attempt.
  Do not repeat uninstall advice or diagnose this as an update-signature conflict
  without evidence of another installed package/user.
- Current artifact: package `com.raffapp.raff`, version 0.4.0 / code 8,
  minimum SDK 24, target SDK 36; ARM32, ARM64 and x86_64.
- Exact size: 41,296,509 bytes.
- SHA-256: `8f5647916554a2477a1f8f184a40e140410db4ca4ab23c725911bf952760f542`.
- Signing certificate SHA-256:
  `ed823b84830522ea8ce76aee177a0737102cb409e7156f9772304c4fee8dd0ea`.
- Signature/ZIP/16 KB alignment checks and installation/start on x86_64 emulators
  API 24, 30, 35, 36 and 37 passed in
  [run 38918624792](https://github.com/dr-askar/raff-app/actions/runs/38918624792).
  None of these establishes success on the affected physical Xiaomi.
- The published 0.4.0 used an ephemeral debug key. This was a separate confirmed
  update-distribution defect. Lost old private keys cannot be recovered from APKs.

## Signed 0.4.1 candidate

**Physical-device attempt FAILED.** Screenshot `209979.jpg` shows
`raff-0.4.1.apk`, 41.34 MB, with the same generic German installer rejection.
The fixed release certificate and five passing emulator checks did not resolve
or identify this physical-phone failure. No specific PackageManager error has
been obtained. Do not offer the same APK download as a new fix.

A fixed release key is now provisioned in protected local storage. Candidate
0.4.1 uses certificate c9155ec138d5ba2101d80acc86301bef507e7adfc3b6675a5d5e264386eb0f86.
[Verification and download](VERIFICATION_0.4.1.md). This candidate's signature,
payload and emulator installation/update checks are separate from the remaining
physical-phone incident. Do not close it without user confirmation.
GitHub signing Secrets and an external private key backup remain unconfigured.

The separate [native installer helper](INSTALL_HELPER.md) attempts the unchanged
hash-pinned APK through the public PackageInstaller session API and displays its
status/message locally, without a computer or broad device logs. It never
uninstalls Raff or changes its package ID. It remains a diagnostic path, not a
proven fix. If it cannot itself install, that path supplies no platform result.

## Repository-side remediation

The build now supports a persistent release keystore and verifies its expected
certificate before permitting the main release job. Without provisioned secrets,
The original Checks workflow keeps artifacts internal when its Secrets are absent.
The alternative one-use-envelope signing route now uses the protected fixed local
key. GitHub signing Secrets remain unconfigured. See [ANDROID_SIGNING.md](ANDROID_SIGNING.md).

The earlier packaging-compatibility change in commit
`5011bfcf0a82df2715fab00ee45a6c833e8db2d8` remains in the current source:
native libraries are compressed and extracted at install time. It was not lost
between releases. The 0.4.0 build log confirms v2 signature verification, minimum
SDK 24 and target SDK 36. These observations do not identify the phone's failure.
The user has no further diagnostic information beyond the screenshot; continue
available repository-side work without repeatedly requesting technical logs.

## Next diagnostic step

A screenshot of this generic dialog cannot reveal the reason. With consent and
access to the affected phone, use Android SDK Platform Tools on a computer,
connect by USB, enable USB debugging, and approve that computer on the phone.
These are developer diagnostics, not steps the shop worker must normally perform.

First collect read-only device/package information:

```bash
python3 scripts/diagnose_android_install.py --apk /path/to/raff-0.4.0-universal.apk
```

For a single explicitly requested installation attempt that captures the real
PackageManager result:

```bash
python3 scripts/diagnose_android_install.py --apk /path/to/raff-0.4.0-universal.apk --attempt-install
```

When several devices are connected, add `--serial DEVICE_SERIAL`.
The script checks that the device is authorized, hashes the supplied APK,
records API/ABI/page size and targeted package metadata, and writes a local JSON
report. The default invocation does not install anything. The explicit attempt
uses `adb install --no-streaming -r` without uninstall, clear-data, downgrade,
security bypass, or permission-grant switches. Failed attempts exit nonzero.
ADB may report `Success` even when the interactive OEM installer behaves
differently: in that case the on-phone installation flow still needs investigation.

Reports are ignored by Git and may contain device/package information. Inspect
before sharing; never commit reports, private workbooks, device dumps or keys.
No broad logcat is collected. If the phone is not available to the developer,
state that physical-device diagnostics remain blocked rather than inventing a cause.

## Act on the actual result

| Evidence | Required follow-up |
| --- | --- |
| APK hash differs from expected release | Check transfer/download integrity; inspect that exact file before blaming Android. |
| `INSTALL_FAILED_UPDATE_INCOMPATIBLE` | Inspect installed package/users and certificate evidence. Preserve external backup before any deliberate removal. |
| `INSTALL_FAILED_NO_MATCHING_ABIS` | Compare actual device ABI list to native libraries in that exact APK. |
| `INSTALL_FAILED_OLDER_SDK` | Compare actual device API to the APK's minimum SDK. |
| `INSTALL_FAILED_VERSION_DOWNGRADE` | Inspect installed version; fix release versioning rather than bypassing downgrade protection. |
| `INSTALL_PARSE_FAILED_*` / `INSTALL_FAILED_INVALID_APK` | Use the detailed message to inspect signature, archive, manifest and native packaging. |
| Storage/policy/verifier rejection | Follow the specific error and OEM context; do not blindly disable security. |
| Other failure | Preserve exact text, investigate that code, and add a regression check for the proven cause. |

## Release and closure requirements

1. Diagnose the affected physical-device path; document actual error and causal fix.
2. Configure one persistent release key through a secure secret store. This is
   pending, not implemented by this document. Do not publish keys in caches.
3. Validate certificate continuity, SDK/ABIs, signature, ZIP integrity and native
   alignment on the exact candidate APK.
4. Verify fresh installation and launch on the affected Xiaomi. Separately test
   in-place update with the persistent key and retention of sample local data.
5. Keep emulator coverage and app/import/permission tests as additional gates.
6. Publish that same tested APK, its hash and supported Android range. Mirror
   byte-for-byte; do not rebuild or re-sign after verification.
7. Close this incident only after the physical phone succeeds. Record confirmation
   here; a documentation commit alone does not resolve installation.
