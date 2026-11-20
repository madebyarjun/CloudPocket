# Changelog

## v1.0.4

- Updated the Android toolchain to Flutter 3.50 and target API 36. Both ARM architectures still support Android 8.0 and later.
- Updated the Android tunnel executable to cloudflared 2026.11.1 and migrated sharing, file picking, notifications and secure storage to the updated plugin APIs.
- Fixed ink feedback in the sharing and room setup screens after the Material upgrade.

## v1.0.3

- **Added** a six-step Home tour and an illustrated user guide in Settings.
- **Changed** first launch to introduce sharing controls directly on Home after startup permission requests finish.
- **Fixed** first-launch detection waiting on unrelated secure-storage reads. The tour can be skipped or replayed from Settings.

## v1.0.2

- **Added** foreground NFC listening for nearby room invitations.
- **Changed** chat, sharing and setup screens to keep the primary actions visible with less explanatory text.
- **Fixed** room tap handling when a hosting app and a joining app are both open. Physical two-phone verification is pending.

## v1.0.1

- **Added** NFC room invites and in-chat attachment viewing.
- **Changed** distribution to release-signed ARM64 and ARMv7 APKs. The new key may require a fresh install over v1.0.0, which can erase local app data.
- **Fixed** tunnel invites showing a local address while the public link was being prepared.

## v1.0.0

- **Added** the first public Android test APK with local hosting, public tunnels and disposable chat rooms.
- **Changed** the app version to 1.0.0+1 for GitHub distribution as an ARM64 test-signed package.
- **Fixed** — no separate fixes were documented for this initial release.
