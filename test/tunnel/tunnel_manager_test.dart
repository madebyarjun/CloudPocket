import 'package:flutter_test/flutter_test.dart';
import 'package:cloud_pocket/models/server_state.dart';
import 'package:cloud_pocket/tunnel/tunnel_config.dart';
import 'package:cloud_pocket/tunnel/tunnel_health_monitor.dart';
import 'package:cloud_pocket/tunnel/tunnel_manager.dart';

void main() {
  group('TunnelManager & Error Propagation Tests', () {
    test('TunnelException contains formatted error messages', () {
      final details = {
        TunnelProvider.cloudflareQuick: 'Not supported on mobile',
        TunnelProvider.bore: 'Connection timed out',
      };
      final exception = TunnelException(
        'Unable to establish internet tunnel:\nCloudflare: failed\nBore: failed',
        details,
      );

      expect(exception.message, contains('Unable to establish internet tunnel'));
      expect(exception.failureDetails.length, equals(2));
      expect(exception.toString(), equals(exception.message));
    });

    test('ServerState correctly holds and clears tunnelError', () {
      var state = const ServerState();
      expect(state.tunnelError, isNull);

      state = state.copyWith(tunnelError: 'Connection failed');
      expect(state.tunnelError, equals('Connection failed'));

      state = state.copyWith(tunnelUrl: 'https://bore.pub:1234', clearTunnelError: true);
      expect(state.tunnelUrl, equals('https://bore.pub:1234'));
      expect(state.tunnelError, isNull);
    });

    test('TunnelManager initializes with onTunnelChanged callback', () {
      var callbackFired = false;
      final manager = TunnelManager(
        localPort: 8080,
        config: const TunnelConfig(provider: TunnelProvider.auto),
        onTunnelChanged: (url, provider, latency) {
          callbackFired = true;
        },
      );

      expect(manager.localPort, equals(8080));
      expect(manager.config.provider, equals(TunnelProvider.auto));
      expect(callbackFired, isFalse);
    });

    test('TunnelHealthMonitor stops safely without firing unhealthy callback', () async {
      var failoverFired = false;
      final monitor = TunnelHealthMonitor(
        tunnelUrl: 'http://127.0.0.1:1', // Invalid port that will fail
        onUnhealthy: () async {
          failoverFired = true;
        },
        checkInterval: const Duration(milliseconds: 10),
      );

      monitor.start();
      // Immediately stop before 3 failures accumulate
      monitor.stop();

      await Future.delayed(const Duration(milliseconds: 50));
      expect(failoverFired, isFalse);
    });
  });
}
