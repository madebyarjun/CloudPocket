# Production hardening review — 2026-10-28

Status: release candidate. No signed release has been built or published.

## Implemented in this pass

- Replaced the embedded Send/Receive and room page styling with the app's shared blue accent, light/dark surfaces, rounded cards, grouped controls, responsive layouts, system fonts and reduced-motion support. Removed forced dark room mode. Added connection status, clearer empty/error states, accessible view selection and keyboard file-card activation, preview focus restoration and modal focus wrapping.
- Added explicit local HTTP plaintext chat warning when WebCrypto is unavailable. The fallback is restricted to local addresses; public HTTP and HTTPS clients without encryption cannot send. An encryption failure never silently downgrades a message. Disconnect disables sending. The room countdown waits for the authoritative first join.
- Fixed browser retries after host cancellation, terminal 4xx errors and misleading 100% success on failed uploads. Duplicate batch starts are blocked. Image fallback no longer repeats indefinitely.
- Fixed simultaneous upload temporary-name collisions and reserved destination names atomically. Upload metadata rejects invalid names, escaped folders and linked upload folders. Failed uploads clean up temporary files and reservations.
- Blocked residual Send listings, file bodies, thumbnails, ZIPs and general uploads in room mode; Receive file access remains isolated. Folder descendants are checked against canonical filesystem scope, and linked children are excluded from listings.
- Added same-origin request checks, no-store API responses, browser security headers and a content sandbox for served files. Active HTML/SVG documents are attachments. Control POST bodies are bounded to 64 KiB; file upload bodies retain streaming behavior.
- Fixed vault bypasses through Range and concurrent requests. Valid responses reserve access before streaming; ZIP entries reserve together. Invalid ranges do not consume access. Interrupted admitted requests consume access, as stated in the UI. Vault media cards download directly to avoid video-preview range preloads consuming the allowance.
- Awaited room orphan cleanup before starting a new room and excluded room sessions from persisted share history.
- Fixed native Open-link action to launch a validated HTTP(S) Android intent instead of treating a URL as a local file. Added native control semantics and corrected misleading deletion/encryption copy.
- Replaced the starter README, added a privacy draft and GitHub-first/Play-later release gates, and added `tool/check.ps1` for repeatable checks without building an APK.

## Verification

- Flutter analyzer: no issues.
- Flutter tests: 199 passed.
- Node client unit tests: six passed.
- JavaScript syntax checks passed for app.js, room.js and theme.js.
- Android debug build, installation, launch and hot restart succeeded on Pixel 5 API 32 x86_64 emulator. This does not verify ARM64 Cloudflare execution or a signed release build.
- 23 native render fixtures captured successfully. Open [the screenshot gallery](index.html) for element explanations. These use synthetic state and are explicitly labelled fixtures.
- Existing live transfer checks from the earlier review are recorded in [that walkthrough](../ui-review/REPORT.md); they were not repeated as physical-device evidence in this pass.

## Outstanding gates

Browser use was rejected again by a saved permission setting: the origin gate denies loopback port 18080. No alternate browser or raw browser automation was used. The new web CSS therefore has not been visually verified. Browser-specific layout, focus and real reconnect behavior still need review on allowed browsers.

Physical ARM64 and low-memory/background/network testing, private release signing and provider/account validation remain required. Play submission additionally requires a validated API/toolchain migration and native page-size/storage-policy review. See [the release checklist](../RELEASE.md). Current AES-GCM payload encryption does not establish secrecy from tunnel relay operators; plaintext local chat remains an intentional warned option.
