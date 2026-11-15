"""Build the local, offline screenshot walkthrough from captured review evidence."""
from pathlib import Path
from html import escape
import json

ROOT = Path(__file__).resolve().parent
PAGES = [
    ("Welcome", "native-01-launch.png", "Native emulator", [
        ("App icon and CloudPocket title", "Branding on the first-launch screen."),
        ("Tagline", "Introduces device-hosted sharing; it is explanatory text, not a control."),
        ("Direct Sharing / Secure Tunnels / Your Device", "Three informational feature badges."),
        ("Get Started", "Completes onboarding and opens Home. Onboarding does not repeat on the next launch."),
        ("Footer", "Informational tagline. No action."),
    ]),
    ("Home: Send Files", "02-home-send.png", "Flutter-rendered fixture", [
        ("CloudPocket / Share", "App identity and screen title."),
        ("Network subtitle and IP pill", "Shows detected network information. The fixture uses 192.168.1.42; native testing used the emulator's 10.0.2.15. The pill no longer invents an IP or pretends a server is already listening."),
        ("Send Files / Receive Mode / Room", "Changes the selected task. Receive clears selected send files. Receive to Room now switches correctly; navigating between bottom tabs preserves the current selection."),
        ("Send files card", "Explains browser-based sharing. Select Files / Folder opens the file selector; with selected items it shows their count and Edit."),
        ("PIN protection switch and row", "Enables password protection and opens the security sheet. A password must actually be configured before launch; cancelling an empty setup no longer creates an effectively open room."),
        ("One-time downloads", "Send-only vault control. It now sets an explicit limit of one download per file. It is disabled with an explanation in Receive and Room modes."),
        ("Internet tunnel row", "Opens the provider selector, including configured providers and their setup dialogs."),
        ("Local / Cloudflare / Auto", "Local disables public tunnelling; Cloudflare selects Quick Tunnel; Auto chooses automatic provider selection. Other custom providers do not falsely highlight Cloudflare."),
        ("Start Sharing", "Starts the server for the selected files. Missing files produce an error; a PIN-enabled session without a configured password opens security setup. Repeated starts are disabled while starting."),
        ("QR caption / error text", "Explains what launch produces and displays a start failure when present. Scroll if the action is below the floating navigation bar."),
        ("Bottom navigation", "Home, Received, Transfers, History and Settings. Tap or drag across the bar. Tabs keep their local filter and mode state; inactive animations are disabled. Repeated drags now reset correctly."),
    ]),
    ("Home: Receive Mode", "03-home-receive.png", "Flutter-rendered fixture", [
        ("Radar and download tile", "Animated receiving illustration, not transfer progress."),
        ("Ready to Receive Files", "Explains the local upload workflow."),
        ("Receive folder caption", "Refers to the configured receive folder. The fabricated 48.2 GB free figure and progress bar were removed."),
        ("Privacy / connection controls", "PIN and tunnel choices work as on Home. One-time downloads is explicitly unavailable because this screen accepts uploads."),
        ("Start Receiving", "Starts the upload server. Verified with a real 58-byte test upload; the Received list refreshed and /api/files remained empty."),
    ]),
    ("Home: Room", "04-home-room.png", "Flutter-rendered fixture", [
        ("Shield card", "Introduces temporary rooms. Messages remain in memory; media uses temporary private cache."),
        ("5 / 15 / 30 min / 1 / 2 hr", "Writes the actual session expiry. Previously this changed only the highlight, and 24 hr was displayed despite the room engine supporting at most two hours."),
        ("Privacy controls", "PIN and reach configure the room. One-time download limits are a Send Files feature."),
        ("Create Room", "Opens room configuration. Local connection choice is now preserved on entering room setup."),
    ]),
    ("File selector", "native-16-file-selector.png", "Native emulator", [
        ("Close and Done", "Return to Home. Selection is managed in the session provider."),
        ("All / Files / Folders / Media", "Filters the selected items; it does not scan all storage."),
        ("+ Add Files", "Opens the Android file picker. The picker and its media-permission handoff were exercised."),
        ("+ Add Folder", "Opens folder selection. A real folder selection was not completed in this review."),
        ("Item list / remove controls", "Shows chosen items with type and size; removal changes the share selection."),
        ("Item count and byte total", "Summary of selected items, not free disk capacity."),
        ("Confirm", "Returns with the selected files. Disabled when there are no items."),
    ]),
    ("Live sharing / receiving", "native-37-receive-live.png", "Native emulator", [
        ("Sharing or Receiving / Online", "Current server mode and status."),
        ("QR card", "Encodes the currently selected interface URL. Tap for the fullscreen QR view."),
        ("Wi-Fi / Hotspot / Tunnel chips", "Select the URL appropriate to the interface. Tunnel states include connecting, failed/retry and available."),
        ("Alternative IP chips", "Switches between detected interface addresses. The emulator exposes 10.0.2.15 and 10.0.2.16; those are emulator addresses, not this computer's LAN address."),
        ("URL field and connection hint", "Shows the same target as the QR. The browser hint explains typing http:// for local sharing."),
        ("Copy", "Copies the current connection URL."),
        ("Share", "Opens the OS share sheet. No recipient was selected or message sent."),
        ("Open", "Launches the URL in a browser. Browser inspection was blocked by the browser-origin permission gate and was not worked around."),
        ("People / MB/s / MB sent or received", "Live server counters. These are observational counters, not benchmark guarantees."),
        ("Stop Sharing / Stop Receiving", "Stops the session and its tunnel. Native Receive stop was verified. The current implementation stops directly after its exit animation."),
    ]),
    ("Fullscreen connection QR", "native-41-fullscreen-qr.png", "Native emulator", [
        ("Large QR", "Larger scan target for the selected connection URL."),
        ("Selectable URL", "Text alternative to scanning."),
        ("Close or system Back", "Dismisses the view. The brightness override is restored after dismissal."),
    ]),
    ("Tunnel failure", "16-tunnel-error.png", "Flutter-rendered fixture", [
        ("Tunnel failed state", "Explains that public allocation failed while the local server remains available."),
        ("Retry", "Calls the tunnel retry action; covered by an existing widget test."),
        ("Local chips", "Allow continuing with an available local interface."),
    ]),
    ("Received files", "native-38-received-file.png", "Native emulator", [
        ("Byte summary", "Total bytes in files scanned from the receive folder. Removed the fictitious 64 GB capacity and minimum 5% usage bar."),
        ("File count", "Counts the receive folder, not just today's files. The label now matches that scope."),
        ("All / Photos / Videos / Docs / Audio", "Filters the received-file list."),
        ("File row", "Type badge, filename, size and modified-time label. Tapping opens the file through its associated app."),
        ("Trailing menu", "Open, Share and Delete actions. Delete has a confirmation. No personal file was opened, shared or deleted."),
        ("Pull to refresh", "Rescans the configured folder. Upload completion also triggers refresh."),
        ("Empty state", "Explains that no received files match the list or filter."),
    ]),
    ("Transfers: empty and filters", "06-transfers.png", "Flutter-rendered fixture", [
        ("Transfers / aggregate speed", "Screen title and server-reported aggregate throughput."),
        ("All / Downloads / Uploads", "Filters records by direction."),
        ("No active transfers", "Empty list state."),
    ]),
    ("Transfers: active", "native-44-transfer-active.png", "Native emulator", [
        ("Type badge and filename", "Identifies the file in progress."),
        ("Transferred / total bytes and percentage", "Server progress for that file."),
        ("Progress bar", "Fraction transferred; completed records show Done."),
        ("Speed and ETA", "Estimated from current throughput. The test source was deliberately throttled; the values are not performance benchmarks."),
        ("Pause / resume", "Now controls the server's actual transfer wait rather than only changing the UI record."),
        ("Cancel", "Now cancels the server stream, wakes paused waits and marks the record terminal."),
    ]),
    ("Transfers: pause verified", "native-46-pause-verified.png", "Native emulator", [
        ("Paused / resume triangle", "The same upload remained at 40.9 MB across two observations, with throughput dropping to zero."),
        ("Cancel while paused", "Can terminate a paused transfer without resuming it first."),
    ]),
    ("Transfers: cancelled", "native-47-transfer-cancelled.png", "Native emulator", [
        ("Cancelled status", "Terminal record with no further pause/cancel controls. Other failures are labelled Failed."),
        ("Network result", "The test client observed ECONNRESET. Android storage inspection showed no incomplete fixture file."),
        ("Completed record above", "The earlier 58-byte test upload completed successfully."),
    ]),
    ("History", "native-05-history.png", "Native emulator", [
        ("Transfer History title", "Shows persisted completed file-sharing session records."),
        ("Empty state", "No qualifying past Send session has been recorded. Receive-only sessions are not currently added by stopServer; rooms do not persist chat history."),
        ("Populated cards", "When present, show session date, selected-item count, transferred bytes, duration and security label."),
        ("Swipe and Clear History", "Remove a record or confirm clearing all records. No existing history was removed during this review."),
    ]),
    ("Settings: device and appearance", "native-06-settings-top.png", "Native emulator", [
        ("Name", "Opens Edit Device Name. Save persists a name; Cancel dismisses without applying it."),
        ("Port", "Informational preferred port, 8080; it is not an editable input. The live connection URL carries the actual bound port."),
        ("Save Folder", "Opens folder selection for incoming files and shows the current destination."),
        ("Auto / Light / Dark", "Selects system-driven or explicit appearance."),
        ("Default reach", "Local Wi-Fi only, Cloudflare tunnel, or Bore relay defaults. A custom Bore choice may open its configuration sheet."),
    ]),
    ("Edit device name", "native-07-device-name.png", "Native emulator", [
        ("Name field", "Editable device name."),
        ("Cancel / Save", "Dismiss without change, or save and close."),
    ]),
    ("Settings: background and diagnostics", "native-09-settings-bottom.png", "Native emulator", [
        ("Keep running", "Controls the app's background/watchdog preference."),
        ("Service running", "Reports the foreground service. Fix starts it only when a session is active; idle status does not mean a sharing session is broken."),
        ("Battery unrestricted", "Reports battery-optimization exemption and can open the corresponding Android flow."),
        ("Notifications allowed", "Reports notification permission/channel state."),
        ("Watchdog active", "Reports the native watchdog state and offers its recovery flow."),
        ("Fix all issues", "Runs the background-permission and OEM assistance flow. OEM-specific behavior was not verified on physical hardware."),
        ("System Logs", "Opens the in-memory diagnostic log viewer."),
        ("Cloudflare Custom Domain", "Opens custom-domain setup. Live provisioning requires user credentials and was not attempted."),
    ]),
    ("Diagnostic logs", "native-10-system-logs.png", "Native emulator", [
        ("Entry count / log list", "Live circular in-memory diagnostic entries."),
        ("Copy All", "Copies available log entries."),
        ("Export & Share", "Opens sharing for the log export. No export was sent."),
        ("Dismiss", "Drag/dismiss the sheet or use its surrounding scrim."),
    ]),
    ("Cloudflare setup", "native-53-cloudflare-fixed.png", "Native emulator, after fix", [
        ("Header / close", "Names the setup task and dismisses the sheet."),
        ("API token guide", "Opens the Cloudflare tab of Tunnel Setup Guide."),
        ("API token", "Sensitive input with reveal/hide and paste buttons. Their containing width now fits both buttons; the native review reproduced a 52-pixel overflow before this fix."),
        ("Account ID (optional)", "Optional account selection hint, with a paste button."),
        ("Fetch domains", "Enabled when a token is present; fetches authorized accounts/zones."),
        ("Domain selection / subdomain / Save domain", "Appear after fetching zones and automate tunnel/DNS setup. Not exercised against a real account."),
    ]),
    ("Bore relay setup", "21-bore-setup.png", "Flutter-rendered fixture", [
        ("VPS setup guide", "Opens the Custom Bore VPS help tab."),
        ("Hostname or IP / Control port", "Relay configuration. The default control port is 7835."),
        ("Save relay", "Validates and saves the relay choice."),
        ("Reset to bore.pub", "Restores the public relay configuration."),
        ("Transport limitation", "Bore uses plaintext transport; no speed or confidentiality guarantee is established by this review."),
    ]),
    ("Tunnel guide", "native-13-api-guide.png", "Native emulator", [
        ("Cloudflare Custom tab", "Token-permission and domain-setup instructions."),
        ("Custom Bore VPS tab", "Relay deployment and firewall instructions. Third-party cost/speed claims in this help text were not independently verified."),
        ("Zero-Setup Modes tab", "Explains the built-in tunnel choices."),
        ("Scrollable instructions / close", "Read the selected guide and dismiss it. No external account or VPS configuration was performed."),
    ]),
    ("Room: host setup", "11-room-host.png", "Flutter-rendered fixture", [
        ("Close / system Back", "Returns to Home and clears room configuration mode; Send cannot accidentally start as a room after exiting setup."),
        ("Host Room / Join Room", "Switches host and participant setup."),
        ("Temporary Burner Room card", "Description of the room's intended temporary lifecycle. Attachments use private cache rather than RAM only."),
        ("Room Name", "Sets the displayed room name."),
        ("Reach", "Shows local-only or the selected public provider. A local choice from Home is now preserved."),
        ("Self-Destruct Timer", "Opens supported durations. Defaults longer than the engine's two-hour room limit are normalized before presentation."),
        ("PIN Protection", "Opens the room security sheet."),
        ("Hotspot notice", "Displayed for Cloudflare Quick when applicable. Its Settings action opens Android hotspot settings."),
        ("Launch Disposable Room", "Starts the configured room. Empty required PIN configuration is rejected before launch."),
    ]),
    ("Room timer sheet", "native-24-timer.png", "Native emulator", [
        ("5 / 15 / 30 Minutes / 1 / 2 Hours", "Sets the actual expiry and closes the sheet. Unsupported six- and 24-hour room choices were removed."),
        ("Timer explanation", "The authoritative countdown starts on the first successful join; it is not extended from this sheet once live."),
        ("Sheet scrolling", "The sheet is scrollable and no longer overflows at a phone-sized viewport."),
    ]),
    ("Room security sheet", "native-26-pin-sheet.png", "Native emulator", [
        ("Require PIN / Password", "Toggles admission protection."),
        ("Password field / eye", "Appears when enabled; changes the configured password and can reveal or obscure its display."),
        ("Done", "Closes the sheet. A required but missing password cannot silently authorize joins."),
    ]),
    ("Room: join setup", "12-room-join.png", "Flutter-rendered fixture", [
        ("Scan Host QR Code", "Opens the camera scanner."),
        ("Chat ID or Room Link", "Accepts a full invite URL or dynamic Chat ID. Chat ID resolution now requires a PIN and never downloads an invite token from public discovery."),
        ("Paste icon", "Parses a copied room link and fills its supplied details."),
        ("Room PIN / eye", "PIN required for Chat ID joins and for PIN-protected full links; eye toggles obscuring."),
        ("Your Nickname", "Name used in the room."),
        ("Join Room (Secure Mode)", "Validates input, resolves a Chat ID if needed and opens the native room chat."),
    ]),
    ("QR scanner", "native-30-camera.png", "Native emulator", [
        ("Camera preview and reticle", "Aims the camera at a CloudPocket QR. The emulator's synthetic camera preview opened successfully; decoding a physical QR was not verified."),
        ("Back", "Returns to join setup."),
        ("Torch", "Toggles the camera torch where supported."),
        ("Paste", "Allows connecting from a copied link."),
        ("Inline error / permission fallback", "Explains invalid or untrusted QR contents, or offers app settings and clipboard fallback if camera access fails."),
    ]),
    ("Live room", "17-room-live.png", "Flutter-rendered fixture; synthetic credentials", [
        ("Room / Encrypted badge", "Room status presentation. The badge is not proof that relays cannot obtain admission key material; see the security limitations below."),
        ("Countdown ring", "Remaining lifetime and progress; pending-first-join state is separate from the authoritative running countdown."),
        ("Room code", "Copies the dynamic code when useful. The caption explains that Chat ID joins need a PIN; token-only rooms use invite links."),
        ("PIN", "Displays/copies the host-configured PIN where present. These screenshots contain fixtures, not user credentials."),
        ("Invite link & QR", "Opens the invitation sheet, including QR/link sharing and browser-password options."),
        ("People / app/browser participant counts", "Room participant statistics."),
        ("Open Chat", "Joins the host chat with its room token and PIN. Previously token-only hosts omitted their own token."),
        ("End and Erase Room", "Confirms ending the room, disconnecting participants, clearing chat RAM and unlinking cached media. It does not securely shred flash storage."),
    ]),
    ("Native chat", "24-room-chat.png", "Flutter-rendered live local WebSocket test", [
        ("Room back control", "Returns to the room dashboard. Closing chat no longer leaves asynchronous callbacks calling setState on a disposed screen."),
        ("Room code / timer", "Uses the server's roomCode and remainingSeconds fields."),
        ("Message timeline", "Loads the server's messages history and distinguishes text, system and media envelopes. A real local connection verified the rendered history fixture."),
        ("+ attachment", "Selects supported room media and streams an upload. Native requests now include room credentials for protected media endpoints."),
        ("Message field / send arrow", "Sends typed text, using AES-GCM payload encryption when a room secret is available."),
        ("Media bubble", "Opens the private viewer. Returning restores the chat's screenshot guard."),
    ]),
    ("Private media viewer", "23-media-text.png", "Flutter-rendered fixture; Android capture guard retained", [
        ("Filename / view-only caption", "Identifies the media and explains the in-app viewing policy."),
        ("Text viewer", "Displays a bounded text preview. The screenshot uses a small synthetic text fixture."),
        ("Image / PDF / audio / video variants", "The same screen selects image preview, page navigation or native player controls by media type. Native codec/PDF playback was not exercised on a physical ARM64 device."),
        ("Dismiss & Purge", "Closes the view and removes temporary viewer copies where created. It does not promise secure flash erasure."),
        ("Screenshot protection", "Native guarded screens were not captured or modified to bypass FLAG_SECURE. The image is from Flutter's test renderer, not an Android screenshot of protected content."),
    ]),
]

intro = """Reviewed on 28 October 2026 using an existing Pixel 5 API 32 x86_64 emulator and an isolated Flutter 3.13.9 / Dart 3.1.5 SDK. A debug run was built and launched; no release APK was built. Native screenshots show the actual emulator. Flutter-rendered fixtures use the app widgets at 393 × 852 logical pixels with loaded fonts, controlled providers and synthetic data. Fixtures are explicitly labelled and are not proof of Android plugin behavior."""
verification = [
    "Full automated suite: 190 passing tests in the recorded run; final analyzer and rerun results are recorded in verification.txt.",
    "Native Receive start, successful test upload, list refresh, Receive file-list isolation, live counters, pause, cancel and incomplete-file cleanup were exercised.",
    "A deliberately throttled 64 MiB upload paused at 40.9 MB across two observations. Cancelling it terminated the client connection and removed the temporary file. These observations are functional evidence, not speed benchmarks.",
    "All test files created on the emulator were removed and the Receive session was stopped. The app remains available for review.",
    "Security tests cover normal-share password bypass prevention, token-only room media authorization, pending/rejected socket isolation, direct PIN throttling, host plaintext suppression and cancelled upload cleanup.",
    "Chat ID joins now require a PIN as requested. New discovery posts omit invite tokens, enforce ten-minute client expiry and renew every five minutes while the host is active.",
    "Android release signing no longer uses the debug key. Supply android/key.properties with storeFile, storePassword, keyAlias and keyPassword for a future explicitly authorized release. Keep that file and keystores out of source control.",
]
limitations = [
    "Browser-origin approval was denied for the local portal, so no browser screenshots or browser interaction claims are included. The denial was not bypassed.",
    "Cloudflare provisioning, public-provider reliability, physical ARM64 background survival, OEM battery flows, physical QR decoding and native media codecs/PDF rendering remain unverified in this review.",
    "Discovery topics are public and do not authenticate ownership of a URL. Client expiry and burn tombstones do not establish provider-side deletion. Historical posts from old versions may still be retained by the provider.",
    "The current admission exchange transmits credentials/key material through the selected transport. AES-GCM payload encryption does not establish secrecy from a relay that can inspect that exchange. Bore and local HTTP have no TLS transport protection.",
    "Rate limiting keys use the socket peer rather than spoofable forwarded headers. Guests sharing the same tunnel peer can therefore share a throttle bucket.",
    "The screen catalogue covers application pages and representative dialogs/states. It does not pretend every media type, account-provisioning result or hardware state has been exercised.",
]

def build():
    for _, filename, _, _ in PAGES:
        if not (ROOT / "screenshots" / filename).is_file():
            raise FileNotFoundError(filename)
    md = ["# CloudPocket — screenshot walkthrough and control reference", "", intro, "", "## Verification", ""]
    md += ["- " + item for item in verification]
    md += ["", "## Scope and remaining limitations", ""] + ["- " + item for item in limitations]
    sections = []
    for index, (title, filename, source, controls) in enumerate(PAGES, 1):
        target = (ROOT / "screenshots" / filename).as_posix()
        md += ["", f"## {index}. {title}", "", f"Evidence: {source}.", "", f"[Open screenshot]({target})", "", "| Element | Purpose / behavior |", "| --- | --- |"]
        md += [f"| {name.replace('|', '/')} | {detail.replace('|', '/')} |" for name, detail in controls]
        rows = "".join(f"<tr><th>{escape(name)}</th><td>{escape(detail)}</td></tr>" for name, detail in controls)
        sections.append(f'<section id="page-{index}"><header><span>{index:02d}</span><h2>{escape(title)}</h2><p>{escape(source)}</p></header><div class="content"><a href="screenshots/{filename}"><img loading="lazy" src="screenshots/{filename}" alt="{escape(title)}"></a><table>{rows}</table></div></section>')
    md += ["", "## Reproduce", "", "```powershell", "& D:/Temp/cloudpocket-flutter-3.13.9/bin/flutter.bat analyze --no-pub", "& D:/Temp/cloudpocket-flutter-3.13.9/bin/flutter.bat test --no-pub", "& D:/Temp/cloudpocket-flutter-3.13.9/bin/flutter.bat test --no-pub --dart-define=UI_REVIEW_DIR=D:/AntiGravity/CloudPocket/docs/ui-review/screenshots test/ui/ui_review_test.dart", "python docs/ui-review/build-guide.py", "```", "", "Native screenshots are captured with capture-android.ps1 while the emulator is running. This script targets emulator-5554 and does not launch a public tunnel.", ""]
    (ROOT / "REPORT.md").write_text("\n".join(md), encoding="utf-8")
    nav = "".join(f'<a href="#page-{i}">{i:02d} {escape(page[0])}</a>' for i, page in enumerate(PAGES, 1))
    raw = "".join(f'<a href="screenshots/{p.name}">{escape(p.name)}</a>' for p in sorted((ROOT / "screenshots").glob("*.png")))
    html = f'''<!doctype html><html lang="en"><meta charset="utf-8"><meta name="viewport" content="width=device-width,initial-scale=1"><title>CloudPocket UI review</title>
<style>body{{margin:0;background:#f3f5f8;color:#182236;font:16px/1.55 system-ui,sans-serif}}main{{max-width:1220px;margin:auto;padding:32px}}h1{{font-size:38px;line-height:1.15;letter-spacing:-1px}}h2{{margin:0;font-size:25px}}.intro,section,.summary{{background:white;border:1px solid #dbe2ec;border-radius:18px;padding:24px;margin-bottom:24px}}.badge{{display:inline-block;border-radius:99px;background:#e1f4e9;color:#126b3d;padding:6px 12px;font-weight:650}}nav,.raw{{display:flex;gap:8px;flex-wrap:wrap;margin:24px 0}}a{{color:#1257b7}}nav a{{background:white;border:1px solid #dbe2ec;border-radius:8px;padding:6px 10px;text-decoration:none;font-size:13px}}section{{scroll-margin-top:20px}}header{{border-bottom:1px solid #e5e9ef;padding-bottom:14px;margin-bottom:20px}}header span{{font-size:13px;color:#657187}}header p{{margin:6px 0 0;color:#657187;font-size:14px}}.content{{display:grid;grid-template-columns:270px 1fr;gap:28px;align-items:start}}img{{display:block;width:100%;height:auto;border:1px solid #dbe2ec;border-radius:14px}}table{{border-collapse:collapse;width:100%;font-size:14px}}th,td{{padding:12px;border-bottom:1px solid #e5e9ef;vertical-align:top;text-align:left}}th{{width:27%;font-weight:650}}.raw a{{font-size:12px}}.warning{{background:#fff8e8}}@media(max-width:740px){{main{{padding:16px}}.content{{grid-template-columns:1fr}}.content>a{{max-width:360px;margin:auto}}h1{{font-size:30px}}th,td{{padding:8px}}}}@media print{{nav,.raw{{display:none}}section{{break-inside:avoid}}main{{padding:0}}}}</style>
<main><div class="intro"><div class="badge">Native app launched · Screens documented</div><h1>CloudPocket<br>UI walkthrough & control reference</h1><p>{escape(intro)}</p><p>Each screenshot is labelled by evidence type. Click a screenshot for its full resolution. No external scripts, fonts or network requests are used by this guide.</p></div>
<div class="summary"><h2>Verification</h2><ul>{''.join('<li>'+escape(s)+'</li>' for s in verification)}</ul></div>
<div class="summary warning"><h2>Scope and remaining limitations</h2><ul>{''.join('<li>'+escape(s)+'</li>' for s in limitations)}</ul></div>
<nav>{nav}</nav>{''.join(sections)}<div class="summary"><h2>All capture files</h2><p>Includes intermediate native observations and earlier states. Use the labelled walkthrough above for current behavior.</p><div class="raw">{raw}</div></div></main></html>'''
    (ROOT / "index.html").write_text(html, encoding="utf-8")
    (ROOT / "catalogue.json").write_text(json.dumps([dict(title=p[0], screenshot=p[1], evidence=p[2], elements=p[3]) for p in PAGES], indent=2), encoding="utf-8")
    print(f"Built {len(PAGES)} documented views with {sum(len(p[3]) for p in PAGES)} element explanations.")

if __name__ == "__main__":
    build()
