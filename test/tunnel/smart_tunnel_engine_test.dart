import 'package:flutter_test/flutter_test.dart';
import 'package:cloud_pocket/tunnel/smart_tunnel_engine.dart';
import 'package:cloud_pocket/tunnel/tunnel_config.dart';

void main() {
  group('SmartTunnelEngine Tests', () {
    test('TunnelProbeResult holds latency and reachability', () {
      const result = TunnelProbeResult(
        provider: TunnelProvider.cloudflareQuick,
        latencyMs: 45,
        reachable: true,
      );

      expect(result.provider, equals(TunnelProvider.cloudflareQuick));
      expect(result.latencyMs, equals(45));
      expect(result.reachable, isTrue);
    });

    test('selectBestProvider returns a valid provider probe', () async {
      final probe = await SmartTunnelEngine.selectBestProvider();
      expect(probe.provider, isNotNull);
      expect(probe.latencyMs, greaterThanOrEqualTo(0));
    });
  });
}
