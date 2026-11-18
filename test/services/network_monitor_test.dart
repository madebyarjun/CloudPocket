import 'package:cloud_pocket/providers/session_provider.dart';
import 'package:cloud_pocket/models/share_session.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:cloud_pocket/models/server_state.dart';
import 'package:cloud_pocket/providers/server_provider.dart';
import 'package:cloud_pocket/services/network_monitor.dart';
import 'package:cloud_pocket/ui/theme.dart';
import 'package:cloud_pocket/ui/widgets/sharing_live_view.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  group('NetworkInfoState Model Tests', () {
    test('default constructor initializes correctly', () {
      const state = NetworkInfoState();
      expect(state.localIp, isNull);
      expect(state.isWifi, isFalse);
      expect(state.isHotspot, isFalse);
      expect(state.isConnected, isFalse);
      expect(state.allIps, isEmpty);
    });

    test('custom constructor holds all fields including allIps', () {
      const state = NetworkInfoState(
        localIp: '192.168.225.1',
        isWifi: false,
        isHotspot: true,
        isConnected: true,
        allIps: ['192.168.225.1', '192.168.1.50'],
      );
      expect(state.localIp, '192.168.225.1');
      expect(state.isHotspot, isTrue);
      expect(state.isWifi, isFalse);
      expect(state.isConnected, isTrue);
      expect(state.allIps.length, 2);
      expect(state.allIps, contains('192.168.225.1'));
      expect(state.allIps, contains('192.168.1.50'));
    });
  });

  group('NetworkMonitor Live Resolution Tests', () {
    test('getNetworkState returns valid state on current environment', () async {
      final state = await NetworkMonitor.getNetworkState();
      expect(state, isNotNull);
      // On any test machine, it either resolves a valid local IP or stays null if disconnected
      if (state.isConnected) {
        expect(state.localIp, isNotNull);
        expect(state.allIps, isNotEmpty);
        expect(state.allIps, contains(state.localIp));
      }
    });

    test('probeServer returns false for closed / unreachable port', () async {
      final reachable = await NetworkMonitor.probeServer(
        '127.0.0.1',
        59999, // Unused port
        timeout: const Duration(milliseconds: 300),
      );
      expect(reachable, isFalse);
    });
  });

  group('ServerState allLocalUrls & Equality Tests', () {
    test('ServerState preserves allLocalUrls and supports copyWith', () {
      const state = ServerState(
        status: ServerStatus.running,
        localUrl: 'http://192.168.225.1:8080',
        allLocalUrls: [
          'http://192.168.225.1:8080',
          'http://192.168.1.15:8080',
        ],
      );

      expect(state.allLocalUrls.length, 2);
      expect(state.allLocalUrls[0], 'http://192.168.225.1:8080');

      final updated = state.copyWith(
        localUrl: 'http://192.168.1.15:8080',
      );
      expect(updated.localUrl, 'http://192.168.1.15:8080');
      expect(updated.allLocalUrls.length, 2);
    });

    test('ServerState equality checks allLocalUrls correctly', () {
      const state1 = ServerState(
        status: ServerStatus.running,
        localUrl: 'http://192.168.225.1:8080',
        allLocalUrls: ['http://192.168.225.1:8080'],
      );
      const state2 = ServerState(
        status: ServerStatus.running,
        localUrl: 'http://192.168.225.1:8080',
        allLocalUrls: ['http://192.168.225.1:8080'],
      );
      const state3 = ServerState(
        status: ServerStatus.running,
        localUrl: 'http://192.168.225.1:8080',
        allLocalUrls: ['http://192.168.1.100:8080'],
      );

      expect(state1, equals(state2));
      expect(state1.hashCode, equals(state2.hashCode));
      expect(state1, isNot(equals(state3)));
    });
  });

  group('SharingLiveView Laptop Guidance & Multi-IP Switcher UI Tests', () {
    testWidgets('displays laptop connection guidance and http:// tip', (tester) async {
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            sessionProvider.overrideWith(_LocalSession.new),
          serverProvider.overrideWith(() => _MockServerNotifier(
                  const ServerState(
                    status: ServerStatus.running,
                    localUrl: 'http://192.168.225.1:8080',
                    allLocalUrls: ['http://192.168.225.1:8080'],
                  ),
                )),
          ],
          child: MaterialApp(
            theme: CloudPocketTheme.darkTheme,
            home: const Scaffold(
              body: SharingLiveView(),
            ),
          ),
        ),
      );

      await tester.pumpAndSettle();

      // Verify the local link is displayed
      expect(find.text('http://192.168.225.1:8080'), findsWidgets);

      // Verify laptop guidance tip with http:// instruction is displayed
      expect(find.byIcon(Icons.laptop_chromebook_rounded), findsOneWidget);
      expect(
        find.textContaining('Connecting from laptop? Type http:// in the address bar'),
        findsOneWidget,
      );
      expect(
        find.textContaining('Globe icon is normal for offline sharing.'),
        findsOneWidget,
      );
    });

    testWidgets('displays alternative IP chips when multiple interfaces exist and switches on tap', (tester) async {
      final mockNotifier = _MockServerNotifier(
        const ServerState(
          status: ServerStatus.running,
          localUrl: 'http://192.168.225.1:8080',
          allLocalUrls: [
            'http://192.168.225.1:8080',
            'http://192.168.1.42:8080',
          ],
        ),
      );

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            sessionProvider.overrideWith(_LocalSession.new),
          serverProvider.overrideWith(() => mockNotifier),
          ],
          child: MaterialApp(
            theme: CloudPocketTheme.darkTheme,
            home: const Scaffold(
              body: SharingLiveView(),
            ),
          ),
        ),
      );

      await tester.pumpAndSettle();

      // Verify alternative IP header is shown
      expect(find.text('Alternative IPs (Tap to switch):'), findsOneWidget);

      // Verify both chips are present
      expect(find.text('192.168.225.1:8080'), findsOneWidget);
      expect(find.text('192.168.1.42:8080'), findsOneWidget);

      // Tap the second IP chip
      await tester.tap(find.text('192.168.1.42:8080'));
      await tester.pumpAndSettle();

      // Verify setLocalUrl was called on notifier
      expect(mockNotifier.state.localUrl, 'http://192.168.1.42:8080');
    });
  });
}

class _MockServerNotifier extends ServerNotifier {
  final ServerState _initialState;
  _MockServerNotifier(this._initialState);

  @override
  ServerState build() => _initialState;

  @override
  void setLocalUrl(String url) {
    state = state.copyWith(localUrl: url);
  }
}

class _LocalSession extends SessionNotifier {
  @override
  ShareSession build() => const ShareSession(enableTunnel: false);
}
