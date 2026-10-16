# Excel shared-string repair (0.3.3 source)

Some mobile Excel editors keep duplicate and unused entries in sharedStrings.xml after editing a workbook. excel 4.0.6 deduplicates entries while loading them but leaves worksheet indices unchanged. Later cells may then resolve to the wrong text or throw a null-check exception before the import preview appears. This is independent of a fixed product-count limit.

The normalizer now resolves every shared-string cell against the original ordered table and writes inline text before decoding. Numeric/percentage normalization, leading zeros in text barcodes, whitespace, and row validation remain intact. Invalid string references produce an explicit FormatException. No user workbook or product data is committed.

A synthetic 113-product, single-worksheet fixture retains 192 duplicate shared-string entries. The baseline source fails with a null-check exception; the repaired source imports all 113 and finds every product again after reopening storage. flutter analyze and all 55 Flutter tests pass:
https://github.com/dr-askar/raff-app/actions/runs/38896170706

The supplied private workbook was also rewritten locally as a compatible XLSX; all 113 product rows and every cell value were compared against the original with openpyxl. The local file is a workaround for installed APKs; phone installation/import still needs user verification.

The fix is now included in the published 0.3.3 APK:
https://github.com/dr-askar/raff-app/releases/download/demo-47/raff-0.3.3-universal.apk

Build and 56 Flutter tests, 15 rules tests, and modern Android install checks:
https://github.com/dr-askar/raff-app/actions/runs/38896951517

Android 7 verification and publication of the exact same APK:
https://github.com/dr-askar/raff-app/actions/runs/38898047613

SHA-256: 12eee22df56fc4d22e6f95d204436f699a717655bdc80359737cb9c95290d549. Android release signing remains experimental and differs from earlier APKs; export and verify a backup outside the app before any removal of an installation with data. Never put private signing keys in a public repository or cache.
