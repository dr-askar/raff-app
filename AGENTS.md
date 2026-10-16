# Raff project instructions

## Product entry conventions (0.4.1)

- The visible types are «طرد» and «وزن», defaulting to «طرد». The stored values
  remain `piece` and `kg` for compatibility. A pack-type barcode adds one piece
  to the basket; its per-piece cost is derived from the pack cost and count.
- Cost entry uses total pack cost in USD or SYP and positive pack content.
  Weighted products divide by kilograms; SYP costs do not follow the USD rate.
- An explicitly present, blank Excel type cell means pack. A legacy workbook
  without the type column preserves existing product types; new products default
  to pack. Keep Arabic types and legacy `piece/kg` import compatibility.
- Worker backup restoration is an independent, default-denied permission; it
  must not grant cost visibility, exporting, password changes or role changes.
- Keep the exchange summary compact so the materials list has more room.
  See [docs/FEATURES_0.4.1.md](docs/FEATURES_0.4.1.md) for examples and validation.

## Android installation incident — OPEN (2026-10-16)

Read [docs/ANDROID_INSTALLATION.md](docs/ANDROID_INSTALLATION.md) before changing
Android packaging, signing, release workflows, or responding to an install failure.

The user reports that `raff-0.4.0-universal.apk` still fails to install AFTER
removing the old application. Do not ask them to repeat that removal or repeat
the same download as a solution. The generic installer message does not establish
the cause. Different signing certificates explain rejected updates but do not,
by themselves, explain a clean-install rejection.

Required working rules:
- Keep this incident open until the affected physical phone installs and opens
  the exact candidate APK. Emulator success alone does not close it.
- The user has only the screenshot and does not want technical log requests.
  Continue repository/build/history investigation with available evidence.
  Use native installer diagnostics when device access becomes available, but do
  not make them a prerequisite for useful implementation work. Do not attribute
  the clean-install failure to a cause that has not been established.
- Never treat a filename containing "universal" or "verified" as evidence.
  Match exact bytes/hash, package/version, ABIs, SDK, signature, ZIP and native
  alignment. Record physical-device checks separately from emulator checks.
- No more user-facing installation-fix releases consisting only of a version
  bump, another download URL, or a freshly generated debug key.
- Before the next distributed release, configure persistent release signing in
  a secure secret store and verify that the APK certificate matches the intended
  certificate. This remains NOT configured; do not imply otherwise.
  Never put private keys/passwords in Git, public caches, artifacts, or chat.
  If secret access is unavailable, finish reviewable code and state the blocker.
- Verify fresh install AND an in-place update from the previous release signed
  with the same persistent key, including retention of local data.
  A new key cannot update older packages signed with lost keys.
- Never uninstall, clear application data, reset permissions, or change the
  package ID as an automatic troubleshooting step. If removal is necessary,
  first verify a backup outside the app when there are data to preserve.
- Never suggest disabling Android/Xiaomi security based only on a generic dialog.
- Support is Android 7/API 24 or newer for the current artifact, not "every Android".
- Keep release claims, README, incident evidence, and verification docs consistent.
  Do not replace the current public APK with an unverified candidate.

These rules preserve the user's request to stop repeating this installation
failure across sessions. They do not claim the physical-phone fault is fixed.
