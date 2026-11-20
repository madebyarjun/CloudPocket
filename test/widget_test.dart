import 'package:cloud_pocket/ui/widgets/home_tour.dart';
import 'package:cloud_pocket/providers/session_provider.dart';
import 'package:cloud_pocket/models/share_session.dart';
import 'package:material_ui/material_ui.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:cloud_pocket/ui/widgets/smooth_curved_nav_bar.dart';
import 'package:cloud_pocket/ui/screens/settings_tab.dart';
import 'package:cloud_pocket/ui/widgets/sharing_live_view.dart';
import 'package:cloud_pocket/ui/screens/disposable_room_live_view.dart';
import 'package:cloud_pocket/providers/server_provider.dart';
import 'package:cloud_pocket/models/server_state.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:cloud_pocket/main.dart';

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({
      'cp_setting_is_first_launch': true, // hasLaunched = true => isFirstLaunch = false
    });
  });

  for (final brightness in Brightness.values) {
    testWidgets('Tour controls fit a small screen with large text in $brightness', (tester) async {
      await tester.binding.setSurfaceSize(const Size(320, 480));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      final key = GlobalKey();
      var dismissed = false;
      await tester.pumpWidget(MaterialApp(
        theme: ThemeData(brightness: brightness),
        home: Builder(builder: (context) => MediaQuery(
          data: MediaQuery.of(context).copyWith(textScaler: TextScaler.linear(2.5)),
          child: Stack(fit: StackFit.expand, children: [
            Align(alignment: Alignment.topRight, child: SizedBox(key: key, width: 42, height: 48)),
            HomeTour(step: 5, target: key, onShown: () {}, onNext: () => dismissed = true, onSkip: () {}),
          ]),
        )),
      ));
      await tester.pumpAndSettle();
      expect(find.text('6 of 6'), findsOneWidget);
      await tester.ensureVisible(find.text('Done'));
      await tester.tap(find.text('Done'));
      expect(dismissed, isTrue);
      expect(tester.takeException(), isNull);
    });
  }

  for (final skip in [false, true]) {
    testWidgets('First install guide persists completion (skip: $skip)', (tester) async {
      SharedPreferences.setMockInitialValues({});
      await tester.pumpWidget(const ProviderScope(child: CloudPocketApp()));
      await tester.pumpAndSettle();
      expect(find.text('1 of 6'), findsOneWidget);
      if (skip) {
        await tester.tap(find.text('Skip'));
      } else {
        for (var step = 2; step <= 6; step++) {
          await tester.tap(find.text('Next'));
          await tester.pumpAndSettle();
          expect(find.text('$step of 6'), findsOneWidget);
          expect(find.text('Skip'), findsOneWidget);
        }
        await tester.tap(find.text('Done'));
      }
      await tester.pumpAndSettle();
      expect(find.text('Choose files'), findsOneWidget);
      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getBool('cp_setting_is_first_launch'), isTrue);
    });
  }

  testWidgets('Settings replays the tour on Home', (tester) async {
    await tester.pumpWidget(const ProviderScope(child: CloudPocketApp()));
    await tester.pumpAndSettle();
    expect(find.text('1 of 6'), findsNothing);
    await tester.tap(find.byIcon(Icons.settings_outlined).last);
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.text('Replay tour'));
    await tester.tap(find.text('Replay tour'));
    await tester.pumpAndSettle();
    expect(find.text('1 of 6'), findsOneWidget);
    await tester.tap(find.text('Skip'));
    await tester.pumpAndSettle();
    expect(find.text('1 of 6'), findsNothing);
  });

  testWidgets('Returning user can open and close the guide from Settings', (tester) async {
    await tester.pumpWidget(const ProviderScope(child: CloudPocketApp()));
    await tester.pumpAndSettle();
    await tester.tap(find.byIcon(Icons.settings_outlined).last);
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.text('User guide'));
    await tester.tap(find.text('User guide'));
    await tester.pumpAndSettle();
    expect(find.text('Send a file'), findsOneWidget);
    await tester.tap(find.text('Close'));
    await tester.pumpAndSettle();
    expect(find.byType(SettingsTab), findsOneWidget);
    expect(find.text('User guide'), findsOneWidget);
  });

  testWidgets('CloudPocketApp smoke test - verifies v1.5 dashboard rendering', (WidgetTester tester) async {
    await tester.pumpWidget(
      const ProviderScope(
        child: CloudPocketApp(),
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 500));

    // Verify brand title and dashboard elements
    expect(find.text('CloudPocket'), findsWidgets);
    expect(find.textContaining('share'), findsWidgets);
    expect(find.text('Send Files'), findsOneWidget);
    expect(find.text('Receive Mode'), findsOneWidget);
    expect(find.text('Choose files'), findsOneWidget);
    expect(find.text('Sharing options'), findsOneWidget);

    // Verify curved bottom navigation bar items
    expect(find.byType(AppleFloatingTabBar), findsOneWidget);
    expect(find.byIcon(Icons.home_rounded), findsWidgets);
    expect(find.byIcon(Icons.folder_shared_outlined), findsWidgets);
    expect(find.byIcon(Icons.swap_vert_outlined), findsWidgets);
    expect(find.byIcon(Icons.schedule_outlined), findsWidgets);
    expect(find.byIcon(Icons.settings_outlined), findsWidgets);
  });

  testWidgets('Bottom navigation bar supports drag/swipe to switch tabs', (WidgetTester tester) async {
    await tester.pumpWidget(
      const ProviderScope(
        child: CloudPocketApp(),
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 500));

    // Initially tab 0 (Home) is active
    expect(find.byIcon(Icons.home_rounded), findsWidgets);

    // Find the AppleFloatingTabBar
    final navBarFinder = find.byType(AppleFloatingTabBar);
    expect(navBarFinder, findsOneWidget);

    final navBarCenter = tester.getCenter(navBarFinder);
    final navBarTopLeft = tester.getTopLeft(navBarFinder);
    final navBarBottomRight = tester.getBottomRight(navBarFinder);
    final width = navBarBottomRight.dx - navBarTopLeft.dx;

    // Drag from tab 0 (width * 0.1) across to tab 2 (width * 0.5)
    final start = Offset(navBarTopLeft.dx + width * 0.1, navBarCenter.dy);
    final end = Offset(navBarTopLeft.dx + width * 0.5, navBarCenter.dy);

    final gesture = await tester.startGesture(start);
    await tester.pump();
    await gesture.moveTo(end);
    await tester.pump();
    await gesture.up();
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 500));

    // Tab 2 (Transfers) should now be active with filled rounded icon
    expect(find.byIcon(Icons.swap_vert_rounded), findsWidgets);
  });

  testWidgets('Mode and timer swipes commit only the released option', (tester) async {
    await tester.pumpWidget(const ProviderScope(child: CloudPocketApp()));
    await tester.pumpAndSettle();
    final container = ProviderScope.containerOf(tester.element(find.byType(CloudPocketApp)));
    final mode = await tester.startGesture(tester.getCenter(find.text('Send Files')));
    await mode.moveTo(tester.getCenter(find.text('Receive Mode')));
    await tester.pump();
    expect(container.read(sessionProvider).isReceiveMode, isFalse);
    await mode.moveTo(tester.getCenter(find.text('Room')));
    await mode.up();
    await tester.pumpAndSettle();
    expect(find.text('Create Room'), findsOneWidget);

    final originalDuration = container.read(sessionProvider).expiryDuration;
    final timer = await tester.startGesture(tester.getCenter(find.text('15 min')));
    await timer.moveTo(tester.getCenter(find.text('2 hr')));
    await timer.cancel();
    await tester.pumpAndSettle();
    expect(container.read(sessionProvider).expiryDuration, originalDuration);
    await tester.dragFrom(tester.getCenter(find.text('15 min')),
        tester.getCenter(find.text('30 min')) - tester.getCenter(find.text('15 min')));
    await tester.pumpAndSettle();
    expect(container.read(sessionProvider).expiryDuration, ExpiryDuration.min30);
  });

  testWidgets('Tapping Receive Mode segmented button switches frontend to Receive Mode', (WidgetTester tester) async {
    await tester.pumpWidget(
      const ProviderScope(
        child: CloudPocketApp(),
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 500));

    // Initially in Send Files mode
    expect(find.text('Choose files'), findsOneWidget);
    expect(find.text('Ready to Receive Files'), findsNothing);

    // Tap Receive Mode on the SegmentedButton
    await tester.tap(find.text('Receive Mode'));
    await tester.pumpAndSettle();

    // Frontend should now display Receive Mode card and Start Receiving button
    expect(find.text('Ready to Receive Files'), findsOneWidget);
    expect(find.text('Start Receiving'), findsOneWidget);
    expect(find.text('Choose files'), findsNothing);
  });

  testWidgets('Tapping Settings tab 6 times opens the secret System Logs viewer', (WidgetTester tester) async {
    await tester.pumpWidget(
      const ProviderScope(
        child: CloudPocketApp(),
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 500));

    final navBarFinder = find.byType(AppleFloatingTabBar);
    final navBarTopLeft = tester.getTopLeft(navBarFinder);
    final navBarBottomRight = tester.getBottomRight(navBarFinder);
    final width = navBarBottomRight.dx - navBarTopLeft.dx;
    final centerY = (navBarTopLeft.dy + navBarBottomRight.dy) / 2;

    // Settings tab is index 4 (5th item -> center at width * 0.9)
    final settingsTapPoint = Offset(navBarTopLeft.dx + width * 0.9, centerY);

    for (var i = 0; i < 6; i++) {
      await tester.tapAt(settingsTapPoint);
      await tester.pump(const Duration(milliseconds: 50));
    }
    await tester.pumpAndSettle();

    // Verify LogViewerDialog opened
    expect(find.text('Diagnostics & Logs'), findsOneWidget);
  });

  testWidgets('Settings tab renders Background Protection grouped list and Fix all issues button', (WidgetTester tester) async {
    await tester.pumpWidget(
      const ProviderScope(
        child: MaterialApp(
          home: Scaffold(body: SettingsTab()),
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.ensureVisible(find.text('Background sharing'));
    await tester.tap(find.text('Background sharing'));
    await tester.pumpAndSettle();
    expect(find.text('Keep running'), findsOneWidget);
    expect(find.text('Fix all issues'), findsNothing);
    expect(find.text('Device'), findsOneWidget);
    expect(find.text('Appearance'), findsOneWidget);
  });

  testWidgets('SharingLiveView renders QR card, chips, actions and stop button', (WidgetTester tester) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          serverProvider.overrideWith(() => _MockServerNotifier()),
        ],
        child: const MaterialApp(
          home: Scaffold(body: SharingLiveView()),
        ),
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 650));

    expect(find.text('Sharing'), findsOneWidget);
    expect(find.text('Online'), findsOneWidget);
    expect(find.text('Wi‑Fi'), findsOneWidget);
    expect(find.text('Copy'), findsOneWidget);
    expect(find.text('Share link'), findsOneWidget);
    expect(find.text('Open'), findsOneWidget);
    expect(find.text('Stop Sharing'), findsOneWidget);
  });

  testWidgets('DisposableRoomLiveView renders room code, PIN, and invite link trigger', (WidgetTester tester) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          serverProvider.overrideWith(() => _MockServerNotifier()),
        ],
        child: const MaterialApp(
          home: Scaffold(body: DisposableRoomLiveView()),
        ),
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 650));

    expect(find.text('Disposable'), findsOneWidget);
    expect(find.text('Room'), findsOneWidget);
    expect(find.text('Waiting for share address…'), findsOneWidget);
    expect(find.text('Open Chat'), findsOneWidget);
    expect(find.text('End and Erase Room'), findsOneWidget);
  });
  testWidgets('SharingLiveView empty state renders when no usable network exists', (WidgetTester tester) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          sessionProvider.overrideWith(_LocalSession.new),
          serverProvider.overrideWith(() => _MockEmptyServerNotifier()),
        ],
        child: const MaterialApp(
          home: Scaffold(body: SharingLiveView()),
        ),
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 650));

    expect(find.text('No Network Available'), findsOneWidget);
    expect(find.text('Connect to Wi-Fi or turn on hotspot to share'), findsOneWidget);
  });

  testWidgets('SharingLiveView tunnel failed state displays retry button', (WidgetTester tester) async {
    final mockNotifier = _MockFailedTunnelServerNotifier();
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          serverProvider.overrideWith(() => mockNotifier),
        ],
        child: const MaterialApp(
          home: Scaffold(body: SharingLiveView()),
        ),
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 650));

    expect(find.text('Tunnel (Failed) · Retry'), findsOneWidget);
    await tester.tap(find.text('Tunnel (Failed) · Retry'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 2500)); // drain toast timer
    expect(mockNotifier.didRetry, isTrue);
  });

  testWidgets('SharingLiveView chip switch updates URL and QR payload to the same value', (WidgetTester tester) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          sessionProvider.overrideWith(_LocalSession.new),
          serverProvider.overrideWith(() => _MockMultiInterfaceServerNotifier()),
        ],
        child: const MaterialApp(
          home: Scaffold(body: SharingLiveView()),
        ),
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 650));

    expect(find.text('http://192.168.1.50:8080'), findsOneWidget);
    expect(find.text('Hotspot'), findsOneWidget);

    await tester.tap(find.text('Hotspot'));
    await tester.pumpAndSettle();

    expect(find.text('http://192.168.43.1:8080'), findsOneWidget);
  });
}

class _MockServerNotifier extends ServerNotifier {
  @override
  ServerState build() {
    return const ServerState(
      status: ServerStatus.running,
      localUrl: 'http://192.168.1.50:8080',
      allLocalUrls: ['http://192.168.1.50:8080'],
    );
  }
}

class _MockEmptyServerNotifier extends ServerNotifier {
  @override
  ServerState build() {
    return const ServerState(
      status: ServerStatus.running,
      localUrl: null,
      allLocalUrls: [],
    );
  }
}

class _MockFailedTunnelServerNotifier extends ServerNotifier {
  bool didRetry = false;

  @override
  ServerState build() {
    return const ServerState(
      status: ServerStatus.running,
      localUrl: 'http://192.168.1.50:8080',
      allLocalUrls: ['http://192.168.1.50:8080'],
      tunnelError: 'Failed to bind edge socket',
    );
  }

  @override
  Future<void> toggleTunnel(bool enable) async {
    didRetry = true;
  }
}

class _MockMultiInterfaceServerNotifier extends ServerNotifier {
  @override
  ServerState build() {
    return const ServerState(
      status: ServerStatus.running,
      localUrl: 'http://192.168.1.50:8080',
      allLocalUrls: [
        'http://192.168.1.50:8080',
        'http://192.168.43.1:8080',
      ],
    );
  }
}

class _LocalSession extends SessionNotifier {
  @override
  ShareSession build() => const ShareSession(enableTunnel: false);
}
