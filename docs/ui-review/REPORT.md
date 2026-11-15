# CloudPocket — screenshot walkthrough and control reference

Reviewed on 28 October 2026 using an existing Pixel 5 API 32 x86_64 emulator and an isolated Flutter 3.13.9 / Dart 3.1.5 SDK. A debug run was built and launched; no release APK was built. Native screenshots show the actual emulator. Flutter-rendered fixtures use the app widgets at 393 × 852 logical pixels with loaded fonts, controlled providers and synthetic data. Fixtures are explicitly labelled and are not proof of Android plugin behavior.

## Verification

- Full automated suite: 190 passing tests in the recorded run; final analyzer and rerun results are recorded in verification.txt.
- Native Receive start, successful test upload, list refresh, Receive file-list isolation, live counters, pause, cancel and incomplete-file cleanup were exercised.
- A deliberately throttled 64 MiB upload paused at 40.9 MB across two observations. Cancelling it terminated the client connection and removed the temporary file. These observations are functional evidence, not speed benchmarks.
- All test files created on the emulator were removed and the Receive session was stopped. The app remains available for review.
- Security tests cover normal-share password bypass prevention, token-only room media authorization, pending/rejected socket isolation, direct PIN throttling, host plaintext suppression and cancelled upload cleanup.
- Chat ID joins now require a PIN as requested. New discovery posts omit invite tokens, enforce ten-minute client expiry and renew every five minutes while the host is active.
- Android release signing no longer uses the debug key. Supply android/key.properties with storeFile, storePassword, keyAlias and keyPassword for a future explicitly authorized release. Keep that file and keystores out of source control.

## Scope and remaining limitations

- Browser-origin approval was denied for the local portal, so no browser screenshots or browser interaction claims are included. The denial was not bypassed.
- Cloudflare provisioning, public-provider reliability, physical ARM64 background survival, OEM battery flows, physical QR decoding and native media codecs/PDF rendering remain unverified in this review.
- Discovery topics are public and do not authenticate ownership of a URL. Client expiry and burn tombstones do not establish provider-side deletion. Historical posts from old versions may still be retained by the provider.
- The current admission exchange transmits credentials/key material through the selected transport. AES-GCM payload encryption does not establish secrecy from a relay that can inspect that exchange. Bore and local HTTP have no TLS transport protection.
- Rate limiting keys use the socket peer rather than spoofable forwarded headers. Guests sharing the same tunnel peer can therefore share a throttle bucket.
- The screen catalogue covers application pages and representative dialogs/states. It does not pretend every media type, account-provisioning result or hardware state has been exercised.

## 1. Welcome

Evidence: Native emulator.

[Open screenshot](D:/AntiGravity/CloudPocket/docs/ui-review/screenshots/native-01-launch.png)

| Element | Purpose / behavior |
| --- | --- |
| App icon and CloudPocket title | Branding on the first-launch screen. |
| Tagline | Introduces device-hosted sharing; it is explanatory text, not a control. |
| Direct Sharing / Secure Tunnels / Your Device | Three informational feature badges. |
| Get Started | Completes onboarding and opens Home. Onboarding does not repeat on the next launch. |
| Footer | Informational tagline. No action. |

## 2. Home: Send Files

Evidence: Flutter-rendered fixture.

[Open screenshot](D:/AntiGravity/CloudPocket/docs/ui-review/screenshots/02-home-send.png)

| Element | Purpose / behavior |
| --- | --- |
| CloudPocket / Share | App identity and screen title. |
| Network subtitle and IP pill | Shows detected network information. The fixture uses 192.168.1.42; native testing used the emulator's 10.0.2.15. The pill no longer invents an IP or pretends a server is already listening. |
| Send Files / Receive Mode / Room | Changes the selected task. Receive clears selected send files. Receive to Room now switches correctly; navigating between bottom tabs preserves the current selection. |
| Send files card | Explains browser-based sharing. Select Files / Folder opens the file selector; with selected items it shows their count and Edit. |
| PIN protection switch and row | Enables password protection and opens the security sheet. A password must actually be configured before launch; cancelling an empty setup no longer creates an effectively open room. |
| One-time downloads | Send-only vault control. It now sets an explicit limit of one download per file. It is disabled with an explanation in Receive and Room modes. |
| Internet tunnel row | Opens the provider selector, including configured providers and their setup dialogs. |
| Local / Cloudflare / Auto | Local disables public tunnelling; Cloudflare selects Quick Tunnel; Auto chooses automatic provider selection. Other custom providers do not falsely highlight Cloudflare. |
| Start Sharing | Starts the server for the selected files. Missing files produce an error; a PIN-enabled session without a configured password opens security setup. Repeated starts are disabled while starting. |
| QR caption / error text | Explains what launch produces and displays a start failure when present. Scroll if the action is below the floating navigation bar. |
| Bottom navigation | Home, Received, Transfers, History and Settings. Tap or drag across the bar. Tabs keep their local filter and mode state; inactive animations are disabled. Repeated drags now reset correctly. |

## 3. Home: Receive Mode

Evidence: Flutter-rendered fixture.

[Open screenshot](D:/AntiGravity/CloudPocket/docs/ui-review/screenshots/03-home-receive.png)

| Element | Purpose / behavior |
| --- | --- |
| Radar and download tile | Animated receiving illustration, not transfer progress. |
| Ready to Receive Files | Explains the local upload workflow. |
| Receive folder caption | Refers to the configured receive folder. The fabricated 48.2 GB free figure and progress bar were removed. |
| Privacy / connection controls | PIN and tunnel choices work as on Home. One-time downloads is explicitly unavailable because this screen accepts uploads. |
| Start Receiving | Starts the upload server. Verified with a real 58-byte test upload; the Received list refreshed and /api/files remained empty. |

## 4. Home: Room

Evidence: Flutter-rendered fixture.

[Open screenshot](D:/AntiGravity/CloudPocket/docs/ui-review/screenshots/04-home-room.png)

| Element | Purpose / behavior |
| --- | --- |
| Shield card | Introduces temporary rooms. Messages remain in memory; media uses temporary private cache. |
| 5 / 15 / 30 min / 1 / 2 hr | Writes the actual session expiry. Previously this changed only the highlight, and 24 hr was displayed despite the room engine supporting at most two hours. |
| Privacy controls | PIN and reach configure the room. One-time download limits are a Send Files feature. |
| Create Room | Opens room configuration. Local connection choice is now preserved on entering room setup. |

## 5. File selector

Evidence: Native emulator.

[Open screenshot](D:/AntiGravity/CloudPocket/docs/ui-review/screenshots/native-16-file-selector.png)

| Element | Purpose / behavior |
| --- | --- |
| Close and Done | Return to Home. Selection is managed in the session provider. |
| All / Files / Folders / Media | Filters the selected items; it does not scan all storage. |
| + Add Files | Opens the Android file picker. The picker and its media-permission handoff were exercised. |
| + Add Folder | Opens folder selection. A real folder selection was not completed in this review. |
| Item list / remove controls | Shows chosen items with type and size; removal changes the share selection. |
| Item count and byte total | Summary of selected items, not free disk capacity. |
| Confirm | Returns with the selected files. Disabled when there are no items. |

## 6. Live sharing / receiving

Evidence: Native emulator.

[Open screenshot](D:/AntiGravity/CloudPocket/docs/ui-review/screenshots/native-37-receive-live.png)

| Element | Purpose / behavior |
| --- | --- |
| Sharing or Receiving / Online | Current server mode and status. |
| QR card | Encodes the currently selected interface URL. Tap for the fullscreen QR view. |
| Wi-Fi / Hotspot / Tunnel chips | Select the URL appropriate to the interface. Tunnel states include connecting, failed/retry and available. |
| Alternative IP chips | Switches between detected interface addresses. The emulator exposes 10.0.2.15 and 10.0.2.16; those are emulator addresses, not this computer's LAN address. |
| URL field and connection hint | Shows the same target as the QR. The browser hint explains typing http:// for local sharing. |
| Copy | Copies the current connection URL. |
| Share | Opens the OS share sheet. No recipient was selected or message sent. |
| Open | Launches the URL in a browser. Browser inspection was blocked by the browser-origin permission gate and was not worked around. |
| People / MB/s / MB sent or received | Live server counters. These are observational counters, not benchmark guarantees. |
| Stop Sharing / Stop Receiving | Stops the session and its tunnel. Native Receive stop was verified. The current implementation stops directly after its exit animation. |

## 7. Fullscreen connection QR

Evidence: Native emulator.

[Open screenshot](D:/AntiGravity/CloudPocket/docs/ui-review/screenshots/native-41-fullscreen-qr.png)

| Element | Purpose / behavior |
| --- | --- |
| Large QR | Larger scan target for the selected connection URL. |
| Selectable URL | Text alternative to scanning. |
| Close or system Back | Dismisses the view. The brightness override is restored after dismissal. |

## 8. Tunnel failure

Evidence: Flutter-rendered fixture.

[Open screenshot](D:/AntiGravity/CloudPocket/docs/ui-review/screenshots/16-tunnel-error.png)

| Element | Purpose / behavior |
| --- | --- |
| Tunnel failed state | Explains that public allocation failed while the local server remains available. |
| Retry | Calls the tunnel retry action; covered by an existing widget test. |
| Local chips | Allow continuing with an available local interface. |

## 9. Received files

Evidence: Native emulator.

[Open screenshot](D:/AntiGravity/CloudPocket/docs/ui-review/screenshots/native-38-received-file.png)

| Element | Purpose / behavior |
| --- | --- |
| Byte summary | Total bytes in files scanned from the receive folder. Removed the fictitious 64 GB capacity and minimum 5% usage bar. |
| File count | Counts the receive folder, not just today's files. The label now matches that scope. |
| All / Photos / Videos / Docs / Audio | Filters the received-file list. |
| File row | Type badge, filename, size and modified-time label. Tapping opens the file through its associated app. |
| Trailing menu | Open, Share and Delete actions. Delete has a confirmation. No personal file was opened, shared or deleted. |
| Pull to refresh | Rescans the configured folder. Upload completion also triggers refresh. |
| Empty state | Explains that no received files match the list or filter. |

## 10. Transfers: empty and filters

Evidence: Flutter-rendered fixture.

[Open screenshot](D:/AntiGravity/CloudPocket/docs/ui-review/screenshots/06-transfers.png)

| Element | Purpose / behavior |
| --- | --- |
| Transfers / aggregate speed | Screen title and server-reported aggregate throughput. |
| All / Downloads / Uploads | Filters records by direction. |
| No active transfers | Empty list state. |

## 11. Transfers: active

Evidence: Native emulator.

[Open screenshot](D:/AntiGravity/CloudPocket/docs/ui-review/screenshots/native-44-transfer-active.png)

| Element | Purpose / behavior |
| --- | --- |
| Type badge and filename | Identifies the file in progress. |
| Transferred / total bytes and percentage | Server progress for that file. |
| Progress bar | Fraction transferred; completed records show Done. |
| Speed and ETA | Estimated from current throughput. The test source was deliberately throttled; the values are not performance benchmarks. |
| Pause / resume | Now controls the server's actual transfer wait rather than only changing the UI record. |
| Cancel | Now cancels the server stream, wakes paused waits and marks the record terminal. |

## 12. Transfers: pause verified

Evidence: Native emulator.

[Open screenshot](D:/AntiGravity/CloudPocket/docs/ui-review/screenshots/native-46-pause-verified.png)

| Element | Purpose / behavior |
| --- | --- |
| Paused / resume triangle | The same upload remained at 40.9 MB across two observations, with throughput dropping to zero. |
| Cancel while paused | Can terminate a paused transfer without resuming it first. |

## 13. Transfers: cancelled

Evidence: Native emulator.

[Open screenshot](D:/AntiGravity/CloudPocket/docs/ui-review/screenshots/native-47-transfer-cancelled.png)

| Element | Purpose / behavior |
| --- | --- |
| Cancelled status | Terminal record with no further pause/cancel controls. Other failures are labelled Failed. |
| Network result | The test client observed ECONNRESET. Android storage inspection showed no incomplete fixture file. |
| Completed record above | The earlier 58-byte test upload completed successfully. |

## 14. History

Evidence: Native emulator.

[Open screenshot](D:/AntiGravity/CloudPocket/docs/ui-review/screenshots/native-05-history.png)

| Element | Purpose / behavior |
| --- | --- |
| Transfer History title | Shows persisted completed file-sharing session records. |
| Empty state | No qualifying past Send session has been recorded. Receive-only sessions are not currently added by stopServer; rooms do not persist chat history. |
| Populated cards | When present, show session date, selected-item count, transferred bytes, duration and security label. |
| Swipe and Clear History | Remove a record or confirm clearing all records. No existing history was removed during this review. |

## 15. Settings: device and appearance

Evidence: Native emulator.

[Open screenshot](D:/AntiGravity/CloudPocket/docs/ui-review/screenshots/native-06-settings-top.png)

| Element | Purpose / behavior |
| --- | --- |
| Name | Opens Edit Device Name. Save persists a name; Cancel dismisses without applying it. |
| Port | Informational preferred port, 8080; it is not an editable input. The live connection URL carries the actual bound port. |
| Save Folder | Opens folder selection for incoming files and shows the current destination. |
| Auto / Light / Dark | Selects system-driven or explicit appearance. |
| Default reach | Local Wi-Fi only, Cloudflare tunnel, or Bore relay defaults. A custom Bore choice may open its configuration sheet. |

## 16. Edit device name

Evidence: Native emulator.

[Open screenshot](D:/AntiGravity/CloudPocket/docs/ui-review/screenshots/native-07-device-name.png)

| Element | Purpose / behavior |
| --- | --- |
| Name field | Editable device name. |
| Cancel / Save | Dismiss without change, or save and close. |

## 17. Settings: background and diagnostics

Evidence: Native emulator.

[Open screenshot](D:/AntiGravity/CloudPocket/docs/ui-review/screenshots/native-09-settings-bottom.png)

| Element | Purpose / behavior |
| --- | --- |
| Keep running | Controls the app's background/watchdog preference. |
| Service running | Reports the foreground service. Fix starts it only when a session is active; idle status does not mean a sharing session is broken. |
| Battery unrestricted | Reports battery-optimization exemption and can open the corresponding Android flow. |
| Notifications allowed | Reports notification permission/channel state. |
| Watchdog active | Reports the native watchdog state and offers its recovery flow. |
| Fix all issues | Runs the background-permission and OEM assistance flow. OEM-specific behavior was not verified on physical hardware. |
| System Logs | Opens the in-memory diagnostic log viewer. |
| Cloudflare Custom Domain | Opens custom-domain setup. Live provisioning requires user credentials and was not attempted. |

## 18. Diagnostic logs

Evidence: Native emulator.

[Open screenshot](D:/AntiGravity/CloudPocket/docs/ui-review/screenshots/native-10-system-logs.png)

| Element | Purpose / behavior |
| --- | --- |
| Entry count / log list | Live circular in-memory diagnostic entries. |
| Copy All | Copies available log entries. |
| Export & Share | Opens sharing for the log export. No export was sent. |
| Dismiss | Drag/dismiss the sheet or use its surrounding scrim. |

## 19. Cloudflare setup

Evidence: Native emulator, after fix.

[Open screenshot](D:/AntiGravity/CloudPocket/docs/ui-review/screenshots/native-53-cloudflare-fixed.png)

| Element | Purpose / behavior |
| --- | --- |
| Header / close | Names the setup task and dismisses the sheet. |
| API token guide | Opens the Cloudflare tab of Tunnel Setup Guide. |
| API token | Sensitive input with reveal/hide and paste buttons. Their containing width now fits both buttons; the native review reproduced a 52-pixel overflow before this fix. |
| Account ID (optional) | Optional account selection hint, with a paste button. |
| Fetch domains | Enabled when a token is present; fetches authorized accounts/zones. |
| Domain selection / subdomain / Save domain | Appear after fetching zones and automate tunnel/DNS setup. Not exercised against a real account. |

## 20. Bore relay setup

Evidence: Flutter-rendered fixture.

[Open screenshot](D:/AntiGravity/CloudPocket/docs/ui-review/screenshots/21-bore-setup.png)

| Element | Purpose / behavior |
| --- | --- |
| VPS setup guide | Opens the Custom Bore VPS help tab. |
| Hostname or IP / Control port | Relay configuration. The default control port is 7835. |
| Save relay | Validates and saves the relay choice. |
| Reset to bore.pub | Restores the public relay configuration. |
| Transport limitation | Bore uses plaintext transport; no speed or confidentiality guarantee is established by this review. |

## 21. Tunnel guide

Evidence: Native emulator.

[Open screenshot](D:/AntiGravity/CloudPocket/docs/ui-review/screenshots/native-13-api-guide.png)

| Element | Purpose / behavior |
| --- | --- |
| Cloudflare Custom tab | Token-permission and domain-setup instructions. |
| Custom Bore VPS tab | Relay deployment and firewall instructions. Third-party cost/speed claims in this help text were not independently verified. |
| Zero-Setup Modes tab | Explains the built-in tunnel choices. |
| Scrollable instructions / close | Read the selected guide and dismiss it. No external account or VPS configuration was performed. |

## 22. Room: host setup

Evidence: Flutter-rendered fixture.

[Open screenshot](D:/AntiGravity/CloudPocket/docs/ui-review/screenshots/11-room-host.png)

| Element | Purpose / behavior |
| --- | --- |
| Close / system Back | Returns to Home and clears room configuration mode; Send cannot accidentally start as a room after exiting setup. |
| Host Room / Join Room | Switches host and participant setup. |
| Temporary Burner Room card | Description of the room's intended temporary lifecycle. Attachments use private cache rather than RAM only. |
| Room Name | Sets the displayed room name. |
| Reach | Shows local-only or the selected public provider. A local choice from Home is now preserved. |
| Self-Destruct Timer | Opens supported durations. Defaults longer than the engine's two-hour room limit are normalized before presentation. |
| PIN Protection | Opens the room security sheet. |
| Hotspot notice | Displayed for Cloudflare Quick when applicable. Its Settings action opens Android hotspot settings. |
| Launch Disposable Room | Starts the configured room. Empty required PIN configuration is rejected before launch. |

## 23. Room timer sheet

Evidence: Native emulator.

[Open screenshot](D:/AntiGravity/CloudPocket/docs/ui-review/screenshots/native-24-timer.png)

| Element | Purpose / behavior |
| --- | --- |
| 5 / 15 / 30 Minutes / 1 / 2 Hours | Sets the actual expiry and closes the sheet. Unsupported six- and 24-hour room choices were removed. |
| Timer explanation | The authoritative countdown starts on the first successful join; it is not extended from this sheet once live. |
| Sheet scrolling | The sheet is scrollable and no longer overflows at a phone-sized viewport. |

## 24. Room security sheet

Evidence: Native emulator.

[Open screenshot](D:/AntiGravity/CloudPocket/docs/ui-review/screenshots/native-26-pin-sheet.png)

| Element | Purpose / behavior |
| --- | --- |
| Require PIN / Password | Toggles admission protection. |
| Password field / eye | Appears when enabled; changes the configured password and can reveal or obscure its display. |
| Done | Closes the sheet. A required but missing password cannot silently authorize joins. |

## 25. Room: join setup

Evidence: Flutter-rendered fixture.

[Open screenshot](D:/AntiGravity/CloudPocket/docs/ui-review/screenshots/12-room-join.png)

| Element | Purpose / behavior |
| --- | --- |
| Scan Host QR Code | Opens the camera scanner. |
| Chat ID or Room Link | Accepts a full invite URL or dynamic Chat ID. Chat ID resolution now requires a PIN and never downloads an invite token from public discovery. |
| Paste icon | Parses a copied room link and fills its supplied details. |
| Room PIN / eye | PIN required for Chat ID joins and for PIN-protected full links; eye toggles obscuring. |
| Your Nickname | Name used in the room. |
| Join Room (Secure Mode) | Validates input, resolves a Chat ID if needed and opens the native room chat. |

## 26. QR scanner

Evidence: Native emulator.

[Open screenshot](D:/AntiGravity/CloudPocket/docs/ui-review/screenshots/native-30-camera.png)

| Element | Purpose / behavior |
| --- | --- |
| Camera preview and reticle | Aims the camera at a CloudPocket QR. The emulator's synthetic camera preview opened successfully; decoding a physical QR was not verified. |
| Back | Returns to join setup. |
| Torch | Toggles the camera torch where supported. |
| Paste | Allows connecting from a copied link. |
| Inline error / permission fallback | Explains invalid or untrusted QR contents, or offers app settings and clipboard fallback if camera access fails. |

## 27. Live room

Evidence: Flutter-rendered fixture; synthetic credentials.

[Open screenshot](D:/AntiGravity/CloudPocket/docs/ui-review/screenshots/17-room-live.png)

| Element | Purpose / behavior |
| --- | --- |
| Room / Encrypted badge | Room status presentation. The badge is not proof that relays cannot obtain admission key material; see the security limitations below. |
| Countdown ring | Remaining lifetime and progress; pending-first-join state is separate from the authoritative running countdown. |
| Room code | Copies the dynamic code when useful. The caption explains that Chat ID joins need a PIN; token-only rooms use invite links. |
| PIN | Displays/copies the host-configured PIN where present. These screenshots contain fixtures, not user credentials. |
| Invite link & QR | Opens the invitation sheet, including QR/link sharing and browser-password options. |
| People / app/browser participant counts | Room participant statistics. |
| Open Chat | Joins the host chat with its room token and PIN. Previously token-only hosts omitted their own token. |
| End and Erase Room | Confirms ending the room, disconnecting participants, clearing chat RAM and unlinking cached media. It does not securely shred flash storage. |

## 28. Native chat

Evidence: Flutter-rendered live local WebSocket test.

[Open screenshot](D:/AntiGravity/CloudPocket/docs/ui-review/screenshots/24-room-chat.png)

| Element | Purpose / behavior |
| --- | --- |
| Room back control | Returns to the room dashboard. Closing chat no longer leaves asynchronous callbacks calling setState on a disposed screen. |
| Room code / timer | Uses the server's roomCode and remainingSeconds fields. |
| Message timeline | Loads the server's messages history and distinguishes text, system and media envelopes. A real local connection verified the rendered history fixture. |
| + attachment | Selects supported room media and streams an upload. Native requests now include room credentials for protected media endpoints. |
| Message field / send arrow | Sends typed text, using AES-GCM payload encryption when a room secret is available. |
| Media bubble | Opens the private viewer. Returning restores the chat's screenshot guard. |

## 29. Private media viewer

Evidence: Flutter-rendered fixture; Android capture guard retained.

[Open screenshot](D:/AntiGravity/CloudPocket/docs/ui-review/screenshots/23-media-text.png)

| Element | Purpose / behavior |
| --- | --- |
| Filename / view-only caption | Identifies the media and explains the in-app viewing policy. |
| Text viewer | Displays a bounded text preview. The screenshot uses a small synthetic text fixture. |
| Image / PDF / audio / video variants | The same screen selects image preview, page navigation or native player controls by media type. Native codec/PDF playback was not exercised on a physical ARM64 device. |
| Dismiss & Purge | Closes the view and removes temporary viewer copies where created. It does not promise secure flash erasure. |
| Screenshot protection | Native guarded screens were not captured or modified to bypass FLAG_SECURE. The image is from Flutter's test renderer, not an Android screenshot of protected content. |

## Reproduce

```powershell
& D:/Temp/cloudpocket-flutter-3.13.9/bin/flutter.bat analyze --no-pub
& D:/Temp/cloudpocket-flutter-3.13.9/bin/flutter.bat test --no-pub
& D:/Temp/cloudpocket-flutter-3.13.9/bin/flutter.bat test --no-pub --dart-define=UI_REVIEW_DIR=D:/AntiGravity/CloudPocket/docs/ui-review/screenshots test/ui/ui_review_test.dart
python docs/ui-review/build-guide.py
```

Native screenshots are captured with capture-android.ps1 while the emulator is running. This script targets emulator-5554 and does not launch a public tunnel.
