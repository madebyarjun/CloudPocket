# CloudPocket — Verification & Testing Manual

This document details the test inventory, static analysis procedures, regression checklists, and test reproduction commands for **CloudPocket** (v1.5.0+1).

---

## 1. Automated Test Suite Overview

CloudPocket maintains an automated test suite executed via Flutter's test runner.

### 1.1 Test Suite Status & Baseline Execution
- **Total Test Files**: 32 files
- **Total Unit & Integration Tests**: 148 tests
- **Static Analysis Result**: `0 issues found` (clean across all files)
- **Automated Test Run Result**: `148 passed / 0 failed` (Execution time: ~38 seconds on host machine)
- **Last Verified Date**: October 9, 2026
- **Test Environment**: Windows host / Dart SDK 3.1.5 / Flutter 3.13.9

---

## 2. Reconciled Automated Test Inventory

Every test file in `test/` has been verified and accounted for:

| # | Category | File | Test Count | Key Areas Covered |
| :-: | :--- | :--- | :---: | :--- |
| 1 | **Models** | `test/models/chat_message_test.dart` | 3 | JSON serialization, timestamp parsing, system messages, payload & `alg` validation. |
| 2 | | `test/models/room_config_test.dart` | 5 | Duration intervals, PIN hashing, SHA-256 verification, token generation. |
| 3 | **Providers** | `test/providers/received_files_provider_test.dart` | 3 | Directory listing, file deletion, sorting, refresh triggers. |
| 4 | | `test/providers/thumbnail_provider_test.dart` | 2 | Background preheating queue, cache lookup, isolate task distribution. |
| 5 | **Server & Handlers**| `test/server/auth_middleware_test.dart` | 6 | Cookie generation, token extraction, public route exemptions, 401 rejection. |
| 6 | | `test/server/chat_hub_test.dart` | 8 | WebSocket connection, join handshake, PIN bypass prevention, broadcast in RAM, participant leave. |
| 7 | | `test/server/disposable_room_test.dart` | 2 | Countdown timer tick, sandbox folder creation, Burn Now, orphan sweeper. |
| 8 | | `test/server/e2e_server_test.dart` | 4 | Shelf pipeline end-to-end: GET `/`, GET `/room`, CORS preflight, visitor tracking. |
| 9 | | `test/server/file_handler_test.dart` | 6 | File listing JSON, single file download, HTTP 206 partial byte ranges. |
| 10 | | `test/server/upload_handler_test.dart` | 6 | Chunked streaming upload, collision renaming (`file (1).ext`), path sanitization. |
| 11 | | `test/server/upload_path_test.dart` | 2 | Android Public Download directory resolution and fallback logic. |
| 12 | | `test/server/vault_tracker_test.dart` | 2 | Per-file download limit tracking, HTTP 410 Gone enforcement, session self-destruct. |
| 13 | | `test/server/zip_streamer_test.dart` | 2 | Multi-file dynamic streaming ZIP generation without whole-file buffering. |
| 14 | | `test/server/thumbnail_service_test.dart` | 10 | On-the-fly image thumbnail resizing, cache hit/miss, unsupported formats. |
| 15 | | `test/server/receive_mode_and_tunnel_toggle_test.dart` | 8 | Toggling receive mode, live tunnel switching without server restart. |
| 16 | | `test/server/session_and_state_test.dart` | 7 | ServerState transitions (idle, starting, running, error, stopping). |
| 17 | | `test/server/theme_sync_and_sharing_defaults_test.dart` | 5 | Default expiration settings, dark theme persistence. |
| 18 | **Services** | `test/services/app_logger_test.dart` | 5 | In-memory circular log buffer, severity filtering (DEBUG, INFO, WARN, ERROR). |
| 19 | | `test/services/e2e_encryption_service_test.dart` | 9 | Authenticated AES-256-GCM encryption/decryption, ciphertext & IV tampering rejection, legacy CBC migration, empty secret rejection. |
| 20 | | `test/services/pocket_link_generator_test.dart` | 3 | Memorable 3-word slug generation, collision probability, formatting. |
| 21 | | `test/services/room_discovery_service_test.dart` | 2 | Ephemeral Chat ID publishing and resolving via volatile topic service. |
| 22 | | `test/services/room_link_detector_test.dart` | 4 | URL pattern detection, deep link (`cloudpocket://room`) parsing, PIN extraction. |
| 23 | | `test/services/sharing_intent_service_test.dart` | 2 | Parsing incoming Android Share Sheet URI streams. |
| 24 | **Tunnel** | `test/tunnel/cloudflare_client_test.dart` | 14 | Log parsing, tunnel token allocation, connection registration detection. |
| 25 | | `test/tunnel/cloudflare_setup_service_test.dart` | 3 | REST API validation for custom domain setup. |
| 26 | | `test/tunnel/localtunnel_client_test.dart` | 6 | HTTP allocation parsing (`loca.lt/?new`), socket proxy bridging, reconnect logic. |
| 27 | | `test/tunnel/micro_dns_server_test.dart` | 5 | Loopback UDP binding (127.0.0.1), SRV query response, Anycast A record resolution. |
| 28 | | `test/tunnel/smart_tunnel_engine_test.dart` | 11 | Parallel latency probing, fastest provider ranking, error handling. |
| 29 | | `test/tunnel/tunnel_config_test.dart` | 5 | Platform provider support, default tunnel selection, `isEncryptedTransport`. |
| 30 | | `test/tunnel/tunnel_manager_test.dart` | 4 | TunnelManager lifecycle, provider switching, failover callbacks. |
| 31 | **UI** | `test/widget_test.dart` | 2 | Dashboard smoke tests and tab switching verification. |
| 32 | **Performance**| `test/benchmark_speed_test.dart` | 1 | End-to-end throughput benchmarks (1MB, 10MB, 25MB transfers, Range requests). |
| **Total** | | **32 files** | **148 tests** | **100% Passing** |

---

## 3. Test Execution Commands

### 3.1 Run All Tests
```powershell
flutter test
```

### 3.2 Run Static Analysis
```powershell
flutter analyze
```

### 3.3 Run Targeted Test Suites
```powershell
# Run E2E Encryption Tests (AES-GCM, tampering rejection, legacy CBC)
flutter test test/services/e2e_encryption_service_test.dart

# Run ChatHub Tests (PIN bypass prevention and credential combinations)
flutter test test/server/chat_hub_test.dart

# Run Upload Pipeline & Path Traversal Tests
flutter test test/server/upload_handler_test.dart

# Run Micro DNS Server Tests
flutter test test/tunnel/micro_dns_server_test.dart

# Run Live Throughput Benchmark
flutter test test/benchmark_speed_test.dart
```

---

## 4. Coverage Gaps & Remaining Unverified Areas

While core server algorithms, protocols, and security rules are thoroughly tested, incoming developers should note the following remaining gaps:

1. **Native Android Platform Code (`MainActivity.kt`)**:
   - The MethodChannel implementations for `com.cloudpocket.app/wifi_lock`, `com.cloudpocket.app/security`, and `com.cloudpocket.app/sharing_intent` have no Android instrumented unit tests (`androidTest/`).
   - Hardware locks (`WifiLock.createWifiLock`, `WakeLock.acquire`) and `FLAG_SECURE` window flags must be verified manually on a physical Android device.
2. **Camera QR Scanning (`mobile_scanner`)**:
   - `QrScannerSheet` requires physical camera hardware and Android runtime permissions (`CAMERA`); cannot be tested in desktop headless test runners.
3. **Physical Cloudflare Native Binary on Android**:
   - `libcloudflared.so` execution on Android is tested manually on ARM64 hardware; unit tests mock tunnel execution or test Pure Dart tunnels (LocalTunnel, Bore, MicroDnsServer).
4. **Cloudflare Custom Domain REST Automation**:
   - Live automated provisioning requires an active paid Cloudflare account with a valid zone ID and API token.

---

## 5. Manual Regression Testing Checklists

Perform these manual tests before any production release:

### Checklist A: Local File Sharing
- [ ] Connect host phone and a guest laptop to the same Wi-Fi router or Mobile Hotspot.
- [ ] Launch CloudPocket, select multiple files (images, PDFs, a large video > 500 MB), and start sharing in Local Mode.
- [ ] Open the displayed local IP URL in a browser on the laptop.
- [ ] Verify file listing renders with accurate file names, icons, and formatted sizes.
- [ ] Download an individual file; verify download speed and transfer completion in `TransfersTab`.
- [ ] Test HTTP Range: Seek a video file directly in the browser; verify smooth playback without whole-file buffering.
- [ ] Test "Download All as ZIP": Verify ZIP archive streams dynamically without high memory consumption.
- [ ] Upload a file from the laptop browser: Verify it appears in the device's `Download/CloudPocket` directory.
- [ ] Upload the same file again: Verify collision handling creates `filename (1).ext`.

### Checklist B: Remote Tunnels & Smart Failover
- [ ] Switch tunnel mode to **Auto (Smart Tunnel)** with cellular data enabled.
- [ ] Verify that parallel latency probing completes in <2 seconds and selects the fastest reachable provider.
- [ ] Open the generated public URL on a remote device connected to a different network.
- [ ] Verify public access works seamlessly.
- [ ] Switch to **LocalTunnel** and **Bore** individually; verify connection establishment.
- [ ] Confirm that Bore displays the unencrypted plaintext HTTP warning indicator.

### Checklist C: Disposable Chat Room Lifecycle & PIN Enforcement
- [ ] Launch a Disposable Chat Room with a 5-minute timer and a 4-digit PIN.
- [ ] Verify the host UI displays the strict countdown timer and dynamic Chat ID (e.g. `AB-4829`).
- [ ] Connect with the invite URL containing `?token=...`: Verify the client is **prompted for the PIN** (possessing the invite token does NOT bypass the PIN).
- [ ] Enter an incorrect PIN: Verify access is strictly rejected with `INVALID_PIN`.
- [ ] Enter the correct PIN: Verify entry is granted and `welcome` frame received.
- [ ] Test hardware screenshot prevention on the native app: Press Power + Vol Down on the participant phone; verify Android blocks the screenshot (`"Can't take screenshot due to security policy"`).
- [ ] Click **"Burn Now"** on the host phone: Verify both client screens transition immediately to the room destroyed screen, and the sandboxed directory `cache/disposable_room_<id>` is removed from disk.

### Checklist D: Android Background Execution
- [ ] Start a sharing session with large files.
- [ ] Lock the host phone screen or switch to a heavy foreground app (e.g., YouTube or camera).
- [ ] Start a download from the connected browser client.
- [ ] Verify transfer continues uninterrupted without Android killing the Shelf server process.
