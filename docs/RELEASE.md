# Release gates — GitHub first, Google Play later

Updated 2026-10-28. This is an engineering checklist, not a claim of production certification.

## Current verification

- Flutter 3.13.9 / Dart 3.1.5: analyzer reports no issues.
- 199 Flutter tests pass, including nine new production boundary tests.
- Six Node browser unit tests cover theme mode, cancellation, terminal HTTP errors, failed-batch state, accessibility selection and local-only plaintext fallback.
- Android debug installation and launch succeeded on Pixel 5 API 32 x86_64 emulator.
- Latest web pages have not been visually approved: the browser origin permission gate still denies loopback access. `node tool/web_preview.cjs` serves synthetic preview data at loopback port 18080; it is not a production server or a functional room fixture.
- No production-key-signed release has been built or published. A release-mode ARM64 test APK can be built using the existing local Android test key as described below.

## GitHub release blockers

1. Complete browser visual review on mobile and desktop, light/dark, Send/Receive, password gate, folder/list/grid, preview/download dialogs, join/chat/ended states. Test real HTTP and HTTPS endpoints; the synthetic preview does not supply WebSockets.
2. Test the release on physical ARM64 hardware: Cloudflare process, provider failover, hotspot switching, background/locked screen transfers, notification denial, battery restrictions, camera, media viewer, room expiry and reconnect. The x86 emulator cannot validate the ARM64 tunnel binary.
3. Configure a stable private release signing key and retain a secure backup. `android/key.properties` must contain storeFile, storePassword, keyAlias and keyPassword. The Gradle production release guard refuses missing signing configuration. The explicit CLOUDPOCKET_LOCAL_TEST_RELEASE=1 environment option selects the existing Android debug key for a local release-mode test package only; it does not create a production signing identity.
4. Before publishing, review dependency/native-binary provenance, licenses, bundled cloudflared version, third-party service terms, final privacy notice and a maintainer contact. These have not been independently audited.
5. Authorize the release build explicitly, then verify signing certificate, ARM64 ABI, clean-install and upgrade paths. Publish the signed APK with its SHA-256 checksum and accurate release notes. Never publish a debug APK as the production package.
6. Stress-test real large transfers on low-memory devices, simultaneous sessions, low disk, network interruption and host termination. Existing streaming tests do not prove reliability on every device.
7. Verify the vault request policy on real browsers: the first admitted file response consumes access, including range requests and interrupted downloads. ZIP files reserve their entries together. Vault cards download directly and do not preload video ranges. This limits server access; it cannot prevent a recipient copying received content.

## Google Play migration

This branch targets API 34. Current [Google Play target requirements](https://developer.android.com/google/play/requirements/target-sdk) require API 36 for new apps/updates. Migrate Flutter, Android Gradle tooling, SDKs and affected plugins in a dedicated compatibility change; changing the target number alone is insufficient.

Verify [16 KB page-size compatibility](https://developer.android.com/guide/practices/page-sizes) for Flutter, every native plugin and bundled cloudflared, including installation from a generated bundle. Do not infer compatibility from emulator startup.

Review storage access: the current all-files permission needs [Play policy review](https://support.google.com/googleplay/android-developer/answer/10467955). Prefer a scoped-storage/file-picker design where practical; do not assume approval. Review foreground-service declarations, background restrictions, Data safety, content rating, privacy-policy hosting, account/deletion disclosures if accounts are introduced, and Play App Signing/upload-key configuration before submission.

## Local release-mode test package

The user requested an optimized APK on 2026-10-28 while the original release signing key was unavailable. `CLOUDPOCKET_LOCAL_TEST_RELEASE=1` explicitly permits release compilation with the existing Android debug signing key. This option is unset after the build; normal production builds continue to require `android/key.properties`.

A local test package is unsuitable for a production GitHub/Play release. It cannot update an installed package signed with a different certificate. Keep the original release certificate for updates; uninstalling an existing package can delete its local app data.
