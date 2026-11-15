import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:cloud_pocket/models/server_state.dart';
import 'package:cloud_pocket/models/share_session.dart';
import 'package:cloud_pocket/providers/session_provider.dart';
import 'package:cloud_pocket/providers/settings_provider.dart';
import 'package:cloud_pocket/tunnel/tunnel_config.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });
  group('ServerState copyWith clear flags and equality', () {
    test('clearTunnelUrl successfully clears tunnelUrl to null', () {
      const state = ServerState(
        status: ServerStatus.running,
        tunnelUrl: 'https://swift-tunnel.loca.lt',
        activeTunnelProvider: TunnelProvider.localtunnel,
      );

      final updated = state.copyWith(clearTunnelUrl: true);
      expect(updated.tunnelUrl, isNull);
      expect(updated.activeTunnelProvider, TunnelProvider.localtunnel);
    });

    test('clearActiveTunnelProvider and clearTunnelLatency work', () {
      const state = ServerState(
        status: ServerStatus.running,
        activeTunnelProvider: TunnelProvider.bore,
        tunnelLatencyMs: 42,
      );

      final updated = state.copyWith(
        clearActiveTunnelProvider: true,
        clearTunnelLatency: true,
      );
      expect(updated.activeTunnelProvider, isNull);
      expect(updated.tunnelLatencyMs, isNull);
    });

    test('ServerState equality and hashCode work correctly', () {
      const state1 = ServerState(
        status: ServerStatus.running,
        tunnelUrl: 'https://test.com',
      );
      const state2 = ServerState(
        status: ServerStatus.running,
        tunnelUrl: 'https://test.com',
      );
      const state3 = ServerState(
        status: ServerStatus.idle,
      );

      expect(state1, equals(state2));
      expect(state1.hashCode, equals(state2.hashCode));
      expect(state1, isNot(equals(state3)));
    });
  });

  group('SessionNotifier & ShareSession Tests', () {
    test('SessionNotifier preserves selected items across settings updates', () {
      final container = ProviderContainer();
      addTearDown(container.dispose);

      // Add item to session
      final notifier = container.read(sessionProvider.notifier);
      notifier.addItems([
        const SharedItem(
          path: '/storage/sample.pdf',
          name: 'sample.pdf',
          sizeBytes: 1024,
          isDirectory: false,
          mimeType: 'application/pdf',
        ),
      ]);

      expect(container.read(sessionProvider).items.length, 1);

      // Simulate settings change (e.g. user changing device name or theme)
      container.read(settingsProvider.notifier).setDeviceName('New Phone Name');

      // Verify that items are NOT wiped out
      expect(container.read(sessionProvider).items.length, 1);
      expect(container.read(sessionProvider).items.first.name, 'sample.pdf');
    });

    test('setPassword with empty string clears password and passwordHash', () {
      final container = ProviderContainer();
      addTearDown(container.dispose);

      final notifier = container.read(sessionProvider.notifier);
      notifier.setPassword('secret123');

      expect(container.read(sessionProvider).password, 'secret123');
      expect(container.read(sessionProvider).passwordHash, isNotNull);

      // Clear password
      notifier.setPassword('');
      expect(container.read(sessionProvider).password, isNull);
      expect(container.read(sessionProvider).passwordHash, isNull);
    });

    test('setVaultMode properly sets and clears vault settings', () {
      final container = ProviderContainer();
      addTearDown(container.dispose);

      final notifier = container.read(sessionProvider.notifier);
      notifier.setVaultMode(true, maxDownloads: 5, autoDelete: true);

      final session = container.read(sessionProvider);
      expect(session.isVaultMode, true);
      expect(session.maxDownloadsPerFile, 5);
      expect(session.autoDeleteAfterExpiry, true);

      // Disable vault
      notifier.setVaultMode(false);
      final disabled = container.read(sessionProvider);
      expect(disabled.isVaultMode, false);
      expect(disabled.maxDownloadsPerFile, isNull);
    });

    test('setSharedText sets and clears shared note text', () {
      final container = ProviderContainer();
      addTearDown(container.dispose);

      final notifier = container.read(sessionProvider.notifier);
      notifier.setSharedText('Meeting code: 12345');
      expect(container.read(sessionProvider).sharedText, 'Meeting code: 12345');

      // Clear shared text
      notifier.setSharedText(null);
      expect(container.read(sessionProvider).sharedText, isNull);

      notifier.setSharedText('   ');
      expect(container.read(sessionProvider).sharedText, isNull);
    });
  });
}
