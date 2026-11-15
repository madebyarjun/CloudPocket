# CloudPocket

Share files directly from your Android phone over Wi-Fi, a hotspot, or an optional public tunnel. Recipients open a link in their browser; temporary rooms add chat and media sharing.

**Version:** 1.5.0+1 · **Primary platform:** Android 8.0+ · **Status:** Release candidate

Device testing and release gates remain outstanding. See [release readiness](docs/RELEASE.md) before distributing a production package.

## Features

- **Send files:** Share selected files and folders through the embedded web portal, with byte-range downloads and streaming ZIP archives.
- **Receive files:** Let browser users upload files to your phone through a dedicated drop zone with streaming uploads.
- **Local or internet sharing:** Use Wi-Fi/hotspot locally, or enable Cloudflare, LocalTunnel, Bore, or a custom Bore relay. Auto mode probes available providers and supports failover.
- **Disposable rooms:** Host temporary chat rooms with PIN protection, invite links, QR codes, and media viewing. Messages and participant state remain in RAM; media uses a temporary app-cache sandbox.
- **Transfer controls:** Track uploads and downloads, view session history, and configure download limits with Vault mode.
- **Android integration:** Background foreground service, network interface selection, camera QR scanning, and guarded room media viewing.

## Getting started

1. Install and open CloudPocket on an Android device, then grant the permissions needed for your chosen operation.
2. Choose **Send**, **Receive**, or a **Disposable Room**.
3. For local sharing, connect the devices to the same Wi-Fi or hotspot and disable public tunneling. For remote access, select a tunnel provider.
4. Start the session and share its displayed link or QR code. File-sharing recipients can use a browser without installing the app.
5. Stop the session or close the room when finished.

Tunnel availability depends on the provider and network. Cloudflare custom-domain provisioning requires your own account and credentials and has not been fully verified live.

## Development setup

This branch uses:

| Requirement | Version / notes |
| --- | --- |
| Flutter | 3.13.9 stable |
| Dart | 3.1.5; package constraint `>=3.1.5 <4.0.0` |
| Android SDK | Compile/target 34; minimum 26 |
| Java | 17 for Android tooling |
| Node.js | 18+ for browser unit tests |
| Android release architecture | ARM64 (`arm64-v8a`) |

From the project root:

```powershell
flutter pub get
flutter run
```

Use a physical ARM64 Android device to exercise the bundled Cloudflare executable. An x86_64 debug emulator can exercise local sharing but cannot run that ARM64 binary; use LocalTunnel or Bore when testing other tunnel paths.

Platform scaffold directories are included for other Flutter targets; their presence does not establish feature parity or release support.

## Verification

```powershell
flutter analyze
flutter test
node --test test/web/client.test.cjs
```

On Windows, the combined check script also validates JavaScript syntax:

```powershell
./tool/check.ps1 -FlutterRoot <path-to-Flutter-3.13.9>
```

These checks do not build an APK. APK builds require explicit authorization under the repository's engineering rules. Production signing requires private configuration in `android/key.properties`; never commit signing keys or credentials. See [testing](docs/TESTING.md) and [release gates](docs/RELEASE.md) for device checks and publishing requirements.

## Security and privacy

- Local file sharing uses HTTP. Network observers may see files and credentials. Local browser chat may fall back to plaintext when encryption is unavailable, with a visible warning; public HTTP chat without encryption is blocked.
- Cloudflare and LocalTunnel terminate HTTPS at their relays. AES-256-GCM protects encrypted chat payloads, but the current credential exchange does not establish secrecy from relay operators. Bore uses unencrypted HTTP.
- Room messages and participant state stay in memory. Temporary media is stored in an app-cache sandbox and removed during cleanup. Deletion unlinks files; it does not securely erase flash storage.
- Android uses `FLAG_SECURE` for protected room views where supported. Browser controls and watermarks cannot prevent screenshots or copying by recipients.
- Public Chat ID discovery uses `ntfy.sh`, requires a PIN, and does not publish the invite token. Discovery topics are public and do not authenticate room ownership.

Read the [security model](docs/SECURITY.md) and [privacy disclosure](docs/PRIVACY.md) before sharing sensitive content.

## Project structure

```text
lib/models/       Session, room, message, and transfer models
lib/providers/    Riverpod application state
lib/server/       Embedded Shelf server, streaming I/O, and chat hub
lib/services/     Encryption, networking, permissions, and Android services
lib/tunnel/       Tunnel clients, provider selection, and health monitoring
lib/ui/           Flutter screens and widgets
assets/web/       Browser file-sharing and chat clients
test/             Flutter and browser unit tests
tool/             Verification and preview utilities
docs/             Architecture, security, testing, and release guidance
```

## Documentation and contributing

- [Architecture](docs/ARCHITECTURE.md)
- [Testing guide](docs/TESTING.md)
- [Release readiness](docs/RELEASE.md)
- [UI and functionality guide](docs/UI_UX_AND_FUNCTIONALITY_GUIDE.md)
- [UI review](docs/ui-review/REPORT.md)

Keep contributions limited to the requested feature or fix, preserve streaming file I/O, and keep chat state ephemeral. Run the relevant checks and report device-dependent behavior as unverified until tested.

## License

[MIT](LICENSE) - Copyright (c) 2026 madebyarjun. Third-party dependencies and bundled binaries retain their respective licenses.

