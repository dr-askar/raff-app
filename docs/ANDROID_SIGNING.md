# Persistent Android release signing

Implementation is present; production key provisioning is still pending.
This solves ephemeral signing in the distribution path once configured. It is
not evidence that the reported Xiaomi clean-install failure is solved.

## What changed

- Bootstrap supports a dedicated `raffRelease` signing configuration, loaded
  from environment variables. No secret values are written into Gradle source.
- Trusted main builds can obtain a private keystore from GitHub Actions Secrets.
  Pull-request builds do not prepare the signing material.
- The keystore lives in a private temporary file outside the checkout/artifacts
  and is deleted by an always-run cleanup step.
- A complete set of inputs is required. Partial or invalid configuration fails.
- No configured key means an internal test APK only: the release job is skipped.
- A configured key must produce exactly the expected certificate fingerprint,
  and an Android Debug certificate is rejected for distribution.
- Signature verification propagates errors even though its output is piped to
  a public certificate report.
- Eight Python checks cover missing/partial inputs, invalid encoding, private
  file permissions, fingerprint mismatch, debug rejection, release acceptance
  and idempotent Gradle generation.

## One-time secure configuration

A repository owner or authorized maintainer must provision a dedicated release
keystore and retain a separate secure backup. Never upload the key as a repository
file, Actions cache, public build artifact or chat attachment.

Configure these repository Actions Secrets:

| Secret | Value |
| --- | --- |
| `RAFF_ANDROID_KEYSTORE_BASE64` | Base64 encoding of the release keystore |
| `RAFF_ANDROID_STORE_PASSWORD` | Keystore password |
| `RAFF_ANDROID_KEY_ALIAS` | Release key alias |
| `RAFF_ANDROID_KEY_PASSWORD` | Private-key password |
| `RAFF_ANDROID_CERT_SHA256` | Public certificate SHA-256, 64 hex characters; colons allowed |

Secrets UI: Repository Settings → Secrets and variables → Actions.
Read the public certificate fingerprint using `keytool -list -v` against the
keystore; do not paste passwords into a command, a report or chat. Keep using the
same key for every release. Verify its signing validity and backup before
distribution.

The current GitHub connector cannot write repository Actions Secrets. No permanent
private key was generated, stored or provisioned during this change. Existing
0.4.0 and older APK private keys remain unavailable. A new key cannot update
those packages in place; data migration requires a verified external backup.

## Validation boundaries

The no-key internal build path can run in ordinary CI. The provisioned-key Gradle
build and installation/update on a physical phone still require real secret
configuration and device access. Do not label those checks passed based on Python
fixtures, or label a newly signed APK as a proven clean-install fix.

For incident status and the exact current APK evidence see
[ANDROID_INSTALLATION.md](ANDROID_INSTALLATION.md).
