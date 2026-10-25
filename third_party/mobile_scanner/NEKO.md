# mobile_scanner in NekoVPN

This is [mobile_scanner](https://github.com/juliansteenbakker/mobile_scanner)
7.4.2 (BSD-3-Clause, see `LICENSE`), the version upstream FlClash pins,
taken from the pub.dev archive (sha256
`5a51ea79f0cf8293f616a5d08baae185b59b5e6bb24df01f2a63037ade0bade0`) and
changed by NekoVPN on 2026-10-25 (client plan E36):

- **Android decodes with [zxing-cpp](https://github.com/zxing-cpp/zxing-cpp)**
  (`io.github.zxing-cpp:android`, Apache-2.0) instead of Google ML Kit. ML Kit
  is closed source and ships Google's telemetry transport (`datatransport`);
  the NekoVPN release check fails an APK that carries either.
  - `android/src/main/kotlin/dev/steenbakker/mobile_scanner/NekoScanner.kt` is
    new: the format mapping (the Dart side keeps ML Kit's numbers), the
    barcode serialization the Dart side parses, the synchronous decoder.
  - `MobileScanner.kt` (the camera analyzer and `analyzeImage`) and
    `MobileScannerHandler.kt` (start options) call it.
  - `MobileScannerUtilities.kt` and `objects/BarcodeFormats.kt`, both ML Kit
    types only, are removed.
  - `autoZoom` is ignored: zxing-cpp has no zoom suggestions.
  - `build.gradle.kts` depends on zxing-cpp; `proguard-rules.pro` drops the
    ML Kit rules.
- Left out of this copy: `example/` and `android/src/test/` (ML Kit mocks),
  CODE_OF_CONDUCT.md, CONTRIBUTING.md, SECURITY.md, release-please-config.json.
- iOS, macOS and the Dart code are unchanged.

To take a newer mobile_scanner, copy its release over this directory again and
re-apply the list above.
