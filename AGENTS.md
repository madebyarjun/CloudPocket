# AGENTS.md — CloudPocket Operational & Engineering Guide (v1.5.0+1)

This document is the authoritative engineering manual and operational contract for developers and autonomous AI agents working within the **CloudPocket** codebase. Every claim, path, and convention in this document has been verified against the actual repository source code and test suite as of **October 26, 2026**.

---

## 1. Developer & AI Agent Operating Rules

Anyone modifying this repository—human or AI agent—must strictly adhere to the following core guardrails:

> [!IMPORTANT]
> **RULE 1: NEVER RUN `flutter build apk` WITHOUT EXPLICIT USER AUTHORIZATION.**
> Building Android APKs is resource-heavy, time-consuming, and strictly restricted to explicit release requests from the user. Use `flutter test` and `flutter analyze` for verification.

> [!CAUTION]
> **RULE 2 (CRITICAL): ZERO UNSOLICITED TOUCH POLICY & STRICT BLAST RADIUS ISOLATION.**
> If any feature, screen, navigation route, network mode, or function is currently working, **IT IS LOCKED**.
> - Working features, UI layouts, navigation flows, state handlers, and existing logic must **NEVER** be modified, refactored, reorganized, added to, or altered unless the user explicitly and exclusively asks for that exact part to be changed.
> - When fixing a bug or adding a feature in one area (e.g., Disposable Chat Room or background execution), changes **MUST** be strictly isolated to that specific area's files.
> - **NEVER** touch shared core files (such as [`app.js`](file:///f:/Project/CloudPocket/assets/web/app.js), [`server_engine.dart`](file:///f:/Project/CloudPocket/lib/server/server_engine.dart), [`server_provider.dart`](file:///f:/Project/CloudPocket/lib/providers/server_provider.dart), or [`file_handler.dart`](file:///f:/Project/CloudPocket/lib/server/file_handler.dart)) in ways that introduce side effects into unrelated working modes (e.g., local Wi-Fi Receive Mode or Send Mode).
> - Do not make speculative refactors, alter UI styling without instruction, remove working features, or arbitrarily upgrade dependencies in `pubspec.yaml`.

> [!IMPORTANT]
> **RULE 3: ZERO MEMORY BUFFERING FOR FILE TRANSFERS.**
> Mobile devices have strict RAM ceilings (~150–250 MB heap before LMK crashes). Never read entire files into memory using `readAsBytes()`. Always stream file I/O via `request.read()` into `IOSink` for uploads, and `file.openRead()` for downloads.

> [!IMPORTANT]
> **RULE 4: RAM-ONLY EPHEMERAL CHAT PERSISTENCE.**
> Disposable Chat Room messages and participant states must remain exclusively in RAM within `ChatHub`. Never write chat transcripts, message history, or secret keys to disk, databases, or `SharedPreferences`.

> [!IMPORTANT]
> **RULE 5: ZERO SECRET LOGGING.**
> Never write room PINs, invite tokens, session cookies, Google auth tokens, or decrypted chat contents to `AppLogger` or console output.

> [!IMPORTANT]
> **RULE 6: VERIFIED REPORTING & TRUTHFULNESS.**
> Never fabricate benchmark metrics, security guarantees (e.g. claiming flash storage shredding), or provider abilities. If a feature or platform cannot be verified, state it explicitly as unverified.

---

## 2. Developer Onboarding & Environment Setup

### 2.1 Prerequisites
- **Flutter SDK**: `3.13.9` (Channel stable)
- **Dart SDK**: `3.1.5` (Constraint: `>=3.1.5 <4.0.0`)
- **Android SDK**: `compileSdkVersion 34`, `targetSdkVersion 34`, `minSdkVersion 26` (Android 8.0 Oreo)
- **Android NDK**: Required for bundled native libraries. ABI Filter: `arm64-v8a` only.
- **Operating Systems Tested**: Windows 11 host (Dev/Test), Android 10–14 (Target hardware).

### 2.2 Setup & Verification Commands
Execute these commands from the repository root (`f:/Project/CloudPocket`):

```powershell
# 1. Install and verify Flutter dependencies
flutter pub get

# 2. Run static analyzer (Must report 0 issues)
flutter analyze

# 3. Run entire automated test suite (160 tests across 33 files)
flutter test

# 4. Run specific test suites
flutter test test/server/receive_mode_and_tunnel_toggle_test.dart
flutter test test/services/network_monitor_test.dart
flutter test test/server/disposable_room_test.dart
flutter test test/services/e2e_encryption_service_test.dart
flutter test test/benchmark_speed_test.dart
```

### 2.3 Native Binary & Emulator Gotchas
- **ARM64 Native Binary**: The repository bundles `libcloudflared.so` (37.3 MB) inside [`android/app/src/main/jniLibs/arm64-v8a/`](file:///f:/Project/CloudPocket/android/app/src/main/jniLibs/arm64-v8a/).
- **x86_64 Emulators**: Standard Android Studio x86_64 emulators will **not** execute the bundled ARM64 binary. When debugging on x86 emulators, use **LocalTunnel** or **Bore** tunnel providers, or test on physical ARM64 Android devices.
- **Carrier UDP Port 53 Blocking**: In regions where cellular carriers block outbound UDP port 53 (e.g. Jio, Airtel, Vi), CloudPocket automatically runs `MicroDnsServer` on `127.0.0.1:<dynamic_port>` to answer Cloudflare edge SRV and A queries locally.

---

## 3. Verified Feature Status & Audit Matrix

Every major feature in CloudPocket has been audited and classified according to actual code inspection and automated test runs (October 26, 2026):

| Feature | Classification | Implementation Location | Test & Verification Evidence |
| :--- | :--- | :--- | :--- |
| **Local File Sharing (Send Mode)** | **Implemented & verified** | [`lib/server/file_handler.dart`](file:///f:/Project/CloudPocket/lib/server/file_handler.dart) | Verified via `file_handler_test.dart`, `e2e_server_test.dart`, and `benchmark_speed_test.dart`. Supports byte ranges (HTTP 206). |
| **Dedicated Receive Mode & Drop-Zone** | **Implemented & verified** | [`lib/providers/session_provider.dart`](file:///f:/Project/CloudPocket/lib/providers/session_provider.dart), [`assets/web/app.js`](file:///f:/Project/CloudPocket/assets/web/app.js) | Verified via `receive_mode_and_tunnel_toggle_test.dart` and `widget_test.dart`. Clears selected files, enables upload endpoint, provides full-page web drag-and-drop zone and folder batch uploads. |
| **Zero-Buffer Streaming Uploads** | **Implemented & verified** | [`lib/server/upload_handler.dart`](file:///f:/Project/CloudPocket/lib/server/upload_handler.dart) | Verified via `upload_handler_test.dart`. Direct pipe `request.read() -> IOSink`. Collision renaming and path traversal sanitization verified. |
| **Multi-Interface IP & Hotspot Switcher** | **Implemented & verified** | [`lib/services/network_monitor.dart`](file:///f:/Project/CloudPocket/lib/services/network_monitor.dart), [`lib/ui/widgets/sharing_live_view.dart`](file:///f:/Project/CloudPocket/lib/ui/widgets/sharing_live_view.dart) | Verified via `network_monitor_test.dart`. Detects Wi-Fi, Hotspot (`swlan0`, `ap0`, `rndis0`, Wi-Fi Direct `192.168.49.x`), and native Android tethering IPs with live UI chip switching. |
| **Streaming ZIP Archive** | **Implemented & verified** | [`lib/server/zip_streamer.dart`](file:///f:/Project/CloudPocket/lib/server/zip_streamer.dart) | Verified via `zip_streamer_test.dart`. On-the-fly streaming of multiple files into a single ZIP stream without temporary disk storage. |
| **Thumbnail Generation & Caching** | **Implemented & verified** | [`lib/server/thumbnail_service.dart`](file:///f:/Project/CloudPocket/lib/server/thumbnail_service.dart) | Verified via `thumbnail_service_test.dart`. Background isolate image decoding, disk caching in `cache/thumbnails/`, and HTTP 304 browser validation. |
| **Vault Mode Limits** | **Implemented & verified** | [`lib/server/vault_tracker.dart`](file:///f:/Project/CloudPocket/lib/server/vault_tracker.dart) | Verified via `vault_tracker_test.dart`. Enforces per-file download counters; returns HTTP 410 Gone when exhausted. |
| **Cloudflare Quick Tunnel** | **Implemented & verified** | [`lib/tunnel/cloudflare_client.dart`](file:///f:/Project/CloudPocket/lib/tunnel/cloudflare_client.dart) | Verified on ARM64 Android and Windows. Uses native `netd` token allocation + embedded `MicroDnsServer` + `libcloudflared.so`. |
| **LocalTunnel Client** | **Implemented & verified** | [`lib/tunnel/localtunnel_client.dart`](file:///f:/Project/CloudPocket/lib/tunnel/localtunnel_client.dart) | Verified via `localtunnel_client_test.dart` and benchmark suite. Pure Dart HTTP allocation over `loca.lt/?new` + multiplexed TCP pool. |
| **Bore & Custom VPS Client** | **Implemented & verified** | [`lib/tunnel/bore_client.dart`](file:///f:/Project/CloudPocket/lib/tunnel/bore_client.dart) | Verified in live benchmark. Pure Dart TCP client connecting to `bore.pub:7835` or custom relay. *Caveat: Unencrypted HTTP over raw TCP.* |
| **Auto Smart Tunnel Engine** | **Implemented & verified** | [`lib/tunnel/smart_tunnel_engine.dart`](file:///f:/Project/CloudPocket/lib/tunnel/smart_tunnel_engine.dart) | Verified via `smart_tunnel_engine_test.dart`. Parallel HTTP latency probing (<2s) and provider ranking. |
| **Tunnel Health & Failover** | **Implemented & verified** | [`lib/tunnel/tunnel_health_monitor.dart`](file:///f:/Project/CloudPocket/lib/tunnel/tunnel_health_monitor.dart) | Verified via `tunnel_manager_test.dart`. Active 30s heartbeat probes and automatic failover in Auto Mode. |
| **Local-Only Server & Tunnel Toggle** | **Implemented & verified** | [`lib/providers/session_provider.dart`](file:///f:/Project/CloudPocket/lib/providers/session_provider.dart), [`lib/providers/server_provider.dart`](file:///f:/Project/CloudPocket/lib/providers/server_provider.dart) | Verified via `receive_mode_and_tunnel_toggle_test.dart`. Allows disabling public tunnels to restrict traffic strictly to local Wi-Fi / Hotspot perimeter. |
| **Disposable Chat Rooms** | **Implemented & verified** | [`lib/server/chat_hub.dart`](file:///f:/Project/CloudPocket/lib/server/chat_hub.dart), [`disposable_room.dart`](file:///f:/Project/CloudPocket/lib/server/disposable_room.dart) | Verified via `chat_hub_test.dart` and `disposable_room_test.dart`. In-memory RAM buffer, strict countdown timers, and sandbox cache deletion. |
| **Hardware-Secured Media Viewer** | **Implemented & verified** | [`lib/ui/widgets/room_media_viewer.dart`](file:///f:/Project/CloudPocket/lib/ui/widgets/room_media_viewer.dart), [`MainActivity.kt`](file:///f:/Project/CloudPocket/android/app/src/main/kotlin/com/cloudpocket/app/cloud_pocket/MainActivity.kt) | View/play-only media viewer (Images, Video, Audio, PDF, Text) with `FLAG_SECURE` OS capture prevention, native `PdfRenderer`, zero save options, and cache unlinking on dismiss. |
| **Dual-Layer E2E Crypto** | **Implemented & verified** | [`lib/services/e2e_encryption_service.dart`](file:///f:/Project/CloudPocket/lib/services/e2e_encryption_service.dart), [`room.js`](file:///f:/Project/CloudPocket/assets/web/room.js) | Verified via `e2e_encryption_service_test.dart`. Authenticated AES-256-GCM (96-bit nonce, 128-bit tag) with backward-compatible AES-256-CBC legacy migration. Interoperable with browser WebCrypto. |
| **Dynamic Chat ID Discovery**| **Implemented & verified** | [`lib/services/room_discovery_service.dart`](file:///f:/Project/CloudPocket/lib/services/room_discovery_service.dart) | Verified via `room_discovery_service_test.dart`. Publishes and resolves `[A-Z]{2}-\d{4}` codes over volatile `ntfy.sh` topics. |
| **Native Screenshot Guard** | **Implemented & verified** | [`MainActivity.kt`](file:///f:/Project/CloudPocket/android/app/src/main/kotlin/com/cloudpocket/app/cloud_pocket/MainActivity.kt#L125) | Hardware-enforced OS `FLAG_SECURE` window management on Android. Verified manually on physical devices. |
| **Web Watermark & CSS Guard**| **Implemented & verified** | [`assets/web/room.js`](file:///f:/Project/CloudPocket/assets/web/room.js), [`room.css`](file:///f:/Project/CloudPocket/assets/web/room.css) | Client-side DOM watermark, `controlsList="nodownload"`, right-click context menu suppression, and CSS print/selection suppression. |
| **Android Background Server & Locks** | **Implemented & verified** | [`lib/services/foreground_service.dart`](file:///f:/Project/CloudPocket/lib/services/foreground_service.dart), [`MainActivity.kt`](file:///f:/Project/CloudPocket/android/app/src/main/kotlin/com/cloudpocket/app/cloud_pocket/MainActivity.kt) | `flutter_foreground_task` dataSync service + `PARTIAL_WAKE_LOCK` + `WifiLock` (High-Perf & Low-Latency) + `MulticastLock`. |
| **OEM Background & Battery Suite** | **Implemented & verified** | [`MainActivity.kt`](file:///f:/Project/CloudPocket/android/app/src/main/kotlin/com/cloudpocket/app/cloud_pocket/MainActivity.kt), [`lib/services/permission_service.dart`](file:///f:/Project/CloudPocket/lib/services/permission_service.dart) | Direct OEM auto-start intents for Xiaomi MIUI/HyperOS, Oppo/Realme ColorOS, Vivo/iQOO, Huawei/Honor EMUI, Samsung battery settings, and battery optimization bypass. |
| **Camera QR Code Scanner** | **Implemented & verified** | [`lib/ui/widgets/qr_scanner_sheet.dart`](file:///f:/Project/CloudPocket/lib/ui/widgets/qr_scanner_sheet.dart) | Uses `mobile_scanner` (v4.0.1) to decode room URLs, tokens, and PINs. Requires physical camera. |
| **Clipboard Auto-Detection** | **Implemented & verified** | [`lib/services/room_link_detector.dart`](file:///f:/Project/CloudPocket/lib/services/room_link_detector.dart) | Verified via `room_link_detector_test.dart`. Parses copied room links and triggers in-app join snackbar. |
| **Cloudflare Custom Domain** | **Implemented but not fully verified** | [`lib/tunnel/cloudflare_setup_service.dart`](file:///f:/Project/CloudPocket/lib/tunnel/cloudflare_setup_service.dart) | REST automation logic verified in unit test; live automated provisioning requires active paid Cloudflare account with API token. |

---

## 4. Discrepancies Corrected & Security Vulnerabilities Resolved

A comprehensive code audit and security review identified and resolved the following key items:

1. **"Multi-Pass Data Shredding / Zero-Byte Overwriting" Claim**:
   - *Audit Finding*: Code invokes standard Dart `File.deleteSync()` and `Directory.delete(recursive: true)`. No zero-byte overwriting exists, nor is it effective on flash/NAND storage with wear-leveling.
   - *Resolution*: Corrected documentation to accurately reflect standard operating system filesystem unlinking.
2. **PIN Bypass Condition Resolved**:
   - *Vulnerability*: In earlier versions of `ChatHub._handleJoin`, checking `isTokenValid || isPinValid` allowed invite token bearers to bypass a required host PIN.
   - *Resolution*: Strictly enforced that when `requirePin` is set, a valid PIN is mandatory regardless of token possession. Validated across WebSocket handshake and HTTP endpoints (`/api/room/auth`, `/api/room/upload`, `/api/room/files/*`).
3. **Bore Tunnel Transport Security Clarification**:
   - *Audit Finding*: Bore tunnels operate over raw unencrypted TCP (`http://$boreHost:$port`). All traffic across Bore is plaintext HTTP on the wire.
   - *Resolution*: Clarified in documentation and added `TunnelProvider.isEncryptedTransport` property (Bore returns `false`, Cloudflare and LocalTunnel return `true`).
4. **E2E Cipher Integrity Resolved (AES-256-GCM Migration)**:
   - *Vulnerability*: Client-side E2E encryption previously used unauthenticated AES-256-CBC, leaving ciphertexts malleable to bit-flipping.
   - *Resolution*: Migrated both Flutter client (`E2eEncryptionService`) and web client (`room.js`) to authenticated **AES-256-GCM** (96-bit nonce, 128-bit authentication tag). Maintained backward-compatible decryption fallback for legacy AES-CBC payloads. Removed all hardcoded fallback secrets.
5. **Receive Mode State Isolation & Residual Leak Prevention**:
   - *Vulnerability*: Switching between Send Mode and Receive Mode previously risked residual files selected in Send Mode being served in Receive Mode.
   - *Resolution*: `SessionNotifier.setIsReceiveMode(true)` automatically purges `items.clear()` and sets `allowUploads = true`. In addition, `FileHandler.listFiles` guarantees an empty `items: []` payload whenever `session.isReceiveMode` is true. Verified via `receive_mode_and_tunnel_toggle_test.dart`.
6. **Ephemeral Room Media Sandbox Lifecycle & Zero-Export Safeguards**:
   - *Audit Finding*: Disposable chat room media must not persist on disk or be accessible after the room terminates.
   - *Resolution*: Room uploads are isolated in `cache/disposable_room/` and never written to public storage. Flutter viewers render media through `RoomMediaViewerScreen` with hardware `FLAG_SECURE`, zero export buttons, and immediate deletion of temporary decrypt caches upon screen exit. When the room expires or is manually closed, `DisposableRoom.dispose()` removes the sandbox directory completely.

---

## 5. Architectural Map & Codebase Structure

```
f:/Project/CloudPocket/
├── .agents/
│   └── rules/
│       └── no_unsolicited_modifications.md # Strict blast-radius & no unsolicited edits contract
├── android/
│   └── app/src/main/
│       ├── AndroidManifest.xml           # Foreground service, permissions, deep links
│       ├── jniLibs/arm64-v8a/
│       │   └── libcloudflared.so         # Bundled native ARM64 Cloudflare binary (37.3 MB)
│       └── kotlin/.../MainActivity.kt    # MethodChannels: wifi_lock, security, sharing_intent, room_media
├── assets/
│   └── web/
│       ├── app.js                        # File sharing web client (Send/Receive, batch upload, XHR)
│       ├── index.html                    # AirDrop-style file sharing portal
│       ├── room.css                      # Disposable room styling, watermark, print suppression
│       ├── room.html                     # Disposable room web portal
│       ├── room.js                       # Web client WebSocket, WebCrypto AES-GCM, view-only media
│       └── styles.css                    # File portal dark theme styles
├── docs/                                 # Detailed Technical Documentation
│   ├── ARCHITECTURE.md                   # Full subsystem design, data flow & Mermaid diagrams
│   ├── SECURITY.md                       # Threat model, cryptographic audit, trust boundaries
│   └── TESTING.md                        # Test inventory, execution guides, regression checklists
├── lib/
│   ├── main.dart                         # Entrypoint, Riverpod ProviderScope, AppShell
│   ├── models/                           # Immutable data models
│   │   ├── chat_message.dart             # Ephemeral chat message & media attachment payload model
│   │   ├── room_config.dart              # Room duration, PIN hash, invite token
│   │   ├── server_state.dart             # Server lifecycle state, tunnel metadata, allLocalUrls
│   │   ├── server_stats.dart             # Real-time bandwidth & client metrics
│   │   ├── share_history.dart            # Persisted past share session records
│   │   ├── share_session.dart            # Active session config, files, receiveMode, enableTunnel
│   │   └── transfer_record.dart          # Live upload/download transfer progress
│   ├── providers/                        # Riverpod StateNotifiers
│   │   ├── history_provider.dart         # Share history persistence via SharedPreferences
│   │   ├── network_provider.dart         # IP and connectivity monitoring
│   │   ├── received_files_provider.dart  # Received uploaded files scanner and notifier
│   │   ├── room_provider.dart            # Disposable room state & countdown control
│   │   ├── server_provider.dart          # ServerEngine & TunnelManager lifecycle
│   │   ├── session_provider.dart         # Selected files, security settings, tunnel choice, receive mode
│   │   ├── settings_provider.dart        # User preferences (deviceName, default tunnel)
│   │   ├── stats_provider.dart           # Real-time throughput and connection counters
│   │   ├── thumbnail_provider.dart       # Thumbnail queue & isolate preheater
│   │   └── transfers_provider.dart       # Real-time transfer list updates
│   ├── server/                           # Shelf embedded web server
│   │   ├── auth_middleware.dart          # Session cookies, room tokens & PIN validation
│   │   ├── chat_hub.dart                 # In-memory WebSocket hub (RAM only)
│   │   ├── disposable_room.dart          # Room timers, sandbox cache, safe deletion
│   │   ├── file_handler.dart             # Byte ranges (HTTP 206), directory browsing, receive mode
│   │   ├── server_engine.dart            # Shelf pipeline, CORS, traffic tracker, router
│   │   ├── thumbnail_service.dart        # On-demand isolate thumbnail generator & disk cache
│   │   ├── upload_handler.dart           # Zero-buffer streaming upload to disk
│   │   ├── vault_tracker.dart            # Per-file download limits (HTTP 410 Gone)
│   │   └── zip_streamer.dart             # StreamingZipArchive dynamic ZIP streamer
│   ├── services/                         # App-wide auxiliary services
│   │   ├── app_logger.dart               # Circular in-memory log buffer
│   │   ├── e2e_encryption_service.dart   # Pointycastle AES-256-GCM client crypto (legacy CBC fallback)
│   │   ├── foreground_service.dart       # flutter_foreground_task Android service
│   │   ├── network_monitor.dart          # Wi-Fi / Hotspot interface resolution (allIps) & probe
│   │   ├── permission_service.dart       # Storage, notification, and battery optimization checks
│   │   ├── pocket_link_generator.dart    # 3-word slug generator
│   │   ├── pocket_link_words.dart        # Curated word banks for memorable slugs
│   │   ├── room_discovery_service.dart   # Ephemeral [A-Z]{2}-\d{4} discovery on ntfy.sh
│   │   ├── room_link_detector.dart       # Clipboard URL parser & deep link recognizer
│   │   └── sharing_intent_service.dart   # Share-sheet and cloudpocket://room deep link receiver
│   ├── tunnel/                           # Public internet tunneling
│   │   ├── bore_client.dart              # Pure Dart TCP client for bore.pub / custom VPS
│   │   ├── cloudflare_client.dart        # Runner process for libcloudflared.so
│   │   ├── cloudflare_setup_service.dart # REST API automation for Cloudflare domains
│   │   ├── cloudflared_binary_manager.dart# Binary locator and extractor
│   │   ├── localtunnel_client.dart       # Pure Dart HTTP allocation & socket pool for loca.lt
│   │   ├── micro_dns_server.dart         # RFC 1035 UDP DNS proxy on 127.0.0.1
│   │   ├── smart_tunnel_engine.dart      # Parallel latency probing & fastest selection
│   │   ├── tunnel_client.dart            # Abstract TunnelClient interface
│   │   ├── tunnel_config.dart            # TunnelProvider enum & configs
│   │   ├── tunnel_health_monitor.dart    # Active 30s heartbeat probe & failover
│   │   └── tunnel_manager.dart           # Orchestrates tunnel lifecycle
│   └── ui/                               # Flutter presentation layer
│       ├── app_shell.dart                # Animated bottom navigation scaffold
│       ├── theme.dart                    # Material Design 3 tokens & dark palette
│       ├── screens/                      # Main feature screens
│       │   ├── disposable_room_live_view.dart # Host dashboard for active disposable room
│       │   ├── disposable_room_setup_screen.dart # Room configuration and Join hub
│       │   ├── file_selector_screen.dart # Categorized file selection browser
│       │   ├── history_tab.dart          # Past sharing history log
│       │   ├── home_screen.dart          # Sharing setup dashboard (Send & Receive toggles)
│       │   ├── onboarding_screen.dart    # First-launch welcome walkthrough
│       │   ├── received_files_tab.dart   # Browser for files received via upload
│       │   ├── room_chat_screen.dart     # Native participant chat with FLAG_SECURE
│       │   ├── settings_tab.dart         # Preferences, network status, storage paths
│       │   └── transfers_tab.dart        # Live transfer cards & SpeedSparkline graph
│       └── widgets/                      # Reusable UI widgets
│           ├── cloudflare_setup_dialog.dart # Custom domain configuration dialog
│           ├── custom_bore_dialog.dart   # Custom Bore VPS server input dialog
│           ├── file_selector_list.dart   # Selected files item list widget
│           ├── hotspot_prompt_dialog.dart# Hotspot guidance dialog
│           ├── log_viewer_dialog.dart    # Developer system logs viewer
│           ├── qr_display_card.dart      # QR code generator widget
│           ├── qr_scanner_sheet.dart     # Camera QR code scanner sheet
│           ├── room_media_viewer.dart    # View-only secure media viewer (Photo, Video, Audio, PDF, Text)
│           ├── sharing_live_view.dart    # Live file sharing dashboard & multi-IP chips
│           ├── smooth_curved_nav_bar.dart# Animated navigation bar
│           ├── stats_dashboard.dart      # Bandwidth & visitor metrics card
│           ├── thumbnail_loading_indicator.dart # Thumbnail placeholder & progress
│           └── tunnel_guide_dialog.dart  # Guide for internet tunneling providers
├── test/                                 # 33 automated test files (160 tests, all passing)
│   ├── benchmark_speed_test.dart         # End-to-end performance & throughput benchmark
│   ├── widget_test.dart                  # UI smoke tests, tab swipe, receive mode switch, logs
│   ├── models/                           # Model serialization tests
│   │   ├── chat_message_test.dart
│   │   └── room_config_test.dart
│   ├── providers/                        # Riverpod provider tests
│   │   ├── received_files_provider_test.dart
│   │   └── thumbnail_provider_test.dart
│   ├── server/                           # Shelf server endpoint & stream tests
│   │   ├── auth_middleware_test.dart
│   │   ├── chat_hub_test.dart
│   │   ├── disposable_room_test.dart
│   │   ├── e2e_server_test.dart
│   │   ├── file_handler_test.dart
│   │   ├── receive_mode_and_tunnel_toggle_test.dart
│   │   ├── session_and_state_test.dart
│   │   ├── theme_sync_and_sharing_defaults_test.dart
│   │   ├── thumbnail_service_test.dart
│   │   ├── upload_handler_test.dart
│   │   ├── upload_path_test.dart
│   │   ├── vault_tracker_test.dart
│   │   └── zip_streamer_test.dart
│   ├── services/                         # App service unit tests
│   │   ├── app_logger_test.dart
│   │   ├── e2e_encryption_service_test.dart
│   │   ├── network_monitor_test.dart
│   │   ├── pocket_link_generator_test.dart
│   │   ├── room_discovery_service_test.dart
│   │   ├── room_link_detector_test.dart
│   │   └── sharing_intent_service_test.dart
│   └── tunnel/                           # Public tunnel client tests
│       ├── cloudflare_client_test.dart
│       ├── cloudflare_setup_service_test.dart
│       ├── localtunnel_client_test.dart
│       ├── micro_dns_server_test.dart
│       ├── smart_tunnel_engine_test.dart
│       ├── tunnel_config_test.dart
│       └── tunnel_manager_test.dart
├── GEMINI.md                             # Gemini agent guardrails & zero unsolicited touch policy
└── pubspec.yaml                          # Dependencies and asset registrations
```

---

## 6. Detailed Technical Documentation References

For exhaustive subsystem specifications, refer to the dedicated modular documents:
- **System Architecture & Data Flows**: Read [`docs/ARCHITECTURE.md`](file:///f:/Project/CloudPocket/docs/ARCHITECTURE.md) for complete pipeline diagrams, Shelf routing inventory, and state models.
- **Security & Threat Model**: Read [`docs/SECURITY.md`](file:///f:/Project/CloudPocket/docs/SECURITY.md) for cryptographic audit details, trust boundaries, and limitation analysis.
- **Testing & Verification**: Read [`docs/TESTING.md`](file:///f:/Project/CloudPocket/docs/TESTING.md) for automated test inventories, commands, and manual regression scenarios.
