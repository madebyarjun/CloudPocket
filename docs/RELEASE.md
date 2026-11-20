# Release gates — GitHub first, Google Play later

## Published Android packages

GitHub release v1.0.4 contains separate ARM64 and ARMv7 APKs for Android 8.0+. Both passed Android SDK `apksigner verify --print-certs`. Their SHA-256 file hashes match the assets published on GitHub. The signing certificate subject is `CN=CloudPocket` and its SHA-256 fingerprint is `498ac15c9ed146ff74e0671750f5c0579b9c2eabf10426c9fae99a32fe31f34e`.

| Architecture | APK SHA-256 |
| --- | --- |
| arm64-v8a | `9b09f895fd0b55f8d4b0a6ffac51fda1cddd053ee8daaea5feba319403885efb` |
| armeabi-v7a | `d524a70d011e04313749488c94483c12129cb6ac8fc9ff9f363813a85d9d2d59` |

v1.0.0 was a debug-signed test release. v1.0.1 introduced the release key used for subsequent releases. Preserve the private keystore and its backup for updates. Configure signing locally in `android/key.properties`. [Release downloads](https://github.com/madebyarjun/CloudPocket/releases) · [Version history](../CHANGELOG.md)

## Device verification

A maintainer-supplied Android log shows Quick Tunnel allocation followed by a refused edge-discovery DNS lookup with hotspot off. A subsequent attempt registered over HTTP/2 with hotspot enabled. This establishes connector registration on that phone. Remote file delivery, hotspot-off reliability, two-phone NFC, locked-screen transfers, ARMv7 runtime behavior, and clean-install/upgrade testing remain open. CI covers analysis and automated tests.

Before the next release, exercise these paths on physical hardware and record the device, Android version, APK architecture and outcome. Also check camera scanning, room expiry, reconnect, and interrupted file transfers. Use each architecture's bundled cloudflared executable.

## Google Play migration

The published v1.0.4 APKs target API 36. [Google Play target requirements](https://developer.android.com/google/play/requirements/target-sdk)

Verify [16 KB page-size compatibility](https://developer.android.com/guide/practices/page-sizes) for Flutter, every native plugin and bundled cloudflared, including installation from a generated bundle. Do not infer compatibility from emulator startup.

Review storage access: the current all-files permission needs [Play policy review](https://support.google.com/googleplay/android-developer/answer/10467955). Prefer a scoped-storage/file-picker design where practical; do not assume approval. Review foreground-service declarations, background restrictions, Data safety, content rating, privacy-policy hosting, account/deletion disclosures if accounts are introduced, and Play App Signing/upload-key configuration before submission.

## Local release-mode test package

The user requested an optimized APK on 2026-10-28 while the original release signing key was unavailable. `CLOUDPOCKET_LOCAL_TEST_RELEASE=1` explicitly permits release compilation with the existing Android debug signing key. This option is unset after the build; normal production builds continue to require `android/key.properties`.

A local test package is unsuitable for a production GitHub/Play release. It cannot update an installed package signed with a different certificate. Keep the original release certificate for updates; uninstalling an existing package can delete its local app data.
