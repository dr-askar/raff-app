# Raff project instructions

## Excel conventions (0.4.2)

- New Products exports use Arabic headers, pack cost and currency, pack content,
  whole pack count and loose pieces. Weighted rows use kg stock and kg pack
  content. Do not export per-unit cost or ambiguous `quantity` in new files.
- Pack-based manual sale prices are divided by pack content on import too;
  derived pack sale price/exchange rate columns are informational only.
- Keep reading legacy `pack`, `quantity`, `cost_usd`, `cost_syp`, `manual_price`
  with their original per-piece/per-kg semantics. Never reinterpret old numbers
  as pack costs. Mixed contradictory bases are row warnings, not guessed values.
- Empty quantity/cost fields preserve existing values, new name-only rows work,
  zero is an explicit update, and weighted quantities retain fractions.
- See docs/FEATURES_0.4.2.md for the exact field meanings and examples.

## Product entry conventions

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

## Physical installation — 0.4.1 RUNNING VIA HELPER; OEM PATH UNEXPLAINED (2026-10-17)

Latest physical evidence: the user pasted helper 1 output for the pinned 0.4.1
APK on Xiaomi 2506BPN68G, Android 17/API 37, arm64-v8a. It reports installed
version 0.4.1/code 9, Status 0, Legacy 1, `INSTALL_SUCCEEDED: Session installed`.
Record physical installation via PackageInstaller as successful. The user subsequently supplied product-editor and Excel screenshots
210439.jpg / 210436.jpg while using the app, confirming launch. The 0.4.1 user
installation block is resolved through the helper; retain the unexplained OEM
file-manager path separately. New 0.4.2 physical upgrade confirmation is pending.
Do not ask the user to download or install the same APK again.

Read [docs/ANDROID_INSTALLATION.md](docs/ANDROID_INSTALLATION.md) before changing
Android packaging, signing, release workflows, or responding to an install failure.

The user reports that `raff-0.4.0-universal.apk` still fails to install AFTER
removing the old application, and the signed `raff-0.4.1.apk` also fails (latest
screenshot 209979.jpg, 41.34 MB). Do not ask them to repeat that removal or repeat
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
- `tools/install-helper` is a separate native diagnostic installer, not a renamed
  Raff or a claimed causal fix. It embeds an unchanged, hash-pinned release APK;
  `build.sh` generates ReleaseInfo with the approved version/code/digest. Helper
  1 embeds 0.4.1; helper 2 is built for 0.4.2. Always verify exact embedded bytes.
  uses normal PackageInstaller consent and displays the platform result. Keep
  its receiver private, callbacks session-bound, and reports local. Do not add
  uninstall/clear-data/downgrade/security-bypass behavior. Its synthetic future
  version fixture is for disposable CI emulators only, never a user release.
- A persistent release key now exists in the protected local directory
  `/workspace/.raff-private-signing` (directory 0700, secret files 0600). Its
  public certificate pin is `config/android-release-cert.sha256`. Never replace
  that key or pin automatically. If the private files are missing, restore the
  original key before distributing another update.
- GitHub Actions Secrets are NOT provisioned. The alternative signing workflow
  accepts an RSA-OAEP/SHA-256 + AES-256-GCM envelope bound to one CI run, approved
  source commit and artifact digest. Only encrypted envelopes/public recipients
  may appear on the `raff-signing-transfer` branch; never plaintext private keys,
  passwords or reusable decryption secrets in Git, caches, artifacts, or chat.
  For a new tested release, pass explicit approved --source and --artifact-digest
  to recipient/seal/open; both are authenticated with the CI head and run ID.
  The CI recipient and decrypted key files must be destroyed after signing.
  An external private backup of the persistent local key is still pending;
  do not claim complete production key provisioning or disaster recovery.
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
