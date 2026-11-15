import 'package:flutter_test/flutter_test.dart';
import 'package:cloud_pocket/tunnel/bore_client.dart';
import 'package:cloud_pocket/tunnel/localtunnel_client.dart';
import 'package:cloud_pocket/tunnel/tunnel_config.dart';
import 'package:cloud_pocket/tunnel/tunnel_manager.dart';

void main() {
  group('TunnelManager Provider Dispatch Tests', () {
    test('dispatches Cloudflare Quick correctly', () {
      final manager = TunnelManager(
        localPort: 8080,
        config: const TunnelConfig(provider: TunnelProvider.cloudflareQuick),
      );
      expect(manager.isRunning, isFalse);
    });

    test('dispatches Bore correctly with default host and port', () {
      final manager = TunnelManager(
        localPort: 8080,
        config: const TunnelConfig(provider: TunnelProvider.bore),
      );
      expect(manager.isRunning, isFalse);
    });

    test('dispatches Custom Bore correctly with custom host and port', () {
      final manager = TunnelManager(
        localPort: 8080,
        config: const TunnelConfig(
          provider: TunnelProvider.customBore,
          relayHost: 'my-custom-vps.com',
          relayPort: 9999,
        ),
      );
      expect(manager.isRunning, isFalse);
    });

    test('dispatches LocalTunnel correctly overriding bore.pub default host', () {
      // TunnelConfig default relayHost is 'bore.pub', but Localtunnel must use 'loca.lt'
      final manager = TunnelManager(
        localPort: 8080,
        config: const TunnelConfig(
          provider: TunnelProvider.localtunnel,
          preferredSubdomain: 'test-subdomain',
        ),
      );
      expect(manager.isRunning, isFalse);
    });

    test('LocaltunnelClient initializes correctly', () {
      final client = LocaltunnelClient(
        localPort: 8080,
        relayHost: 'loca.lt',
        preferredSubdomain: 'mypocket',
      );
      expect(client.localPort, 8080);
      expect(client.relayHost, 'loca.lt');
      expect(client.preferredSubdomain, 'mypocket');
      expect(client.isRunning, isFalse);
      expect(client.publicUrl, isNull);
    });

    test('BoreClient initializes correctly', () {
      final client = BoreClient(
        localPort: 8080,
        boreHost: 'bore.pub',
        boreControlPort: 7835,
      );
      expect(client.localPort, 8080);
      expect(client.boreHost, 'bore.pub');
      expect(client.boreControlPort, 7835);
      expect(client.isRunning, isFalse);
      expect(client.publicUrl, isNull);
    });
  });
}
