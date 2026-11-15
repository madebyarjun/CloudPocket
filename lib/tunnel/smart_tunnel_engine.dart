import 'dart:async';
import 'dart:io';
import 'package:http/http.dart' as http;
import 'package:cloud_pocket/tunnel/tunnel_config.dart';

class TunnelProbeResult {
  final TunnelProvider provider;
  final int latencyMs;
  final bool reachable;
  final String? errorMessage;

  const TunnelProbeResult({
    required this.provider,
    required this.latencyMs,
    required this.reachable,
    this.errorMessage,
  });
}

class SmartTunnelEngine {
  static const Duration _probeTimeout = Duration(milliseconds: 3500);

  /// Probes all major public tunnel providers in parallel within ~3 seconds
  /// and returns them sorted by lowest latency.
  static Future<List<TunnelProbeResult>> probeAll() async {
    final futures = [
      _probeCloudflare(),
      _probeLocalTunnel(),
      _probeBore(),
    ];

    final allResults = await Future.wait(futures);
    final results = allResults.where((r) => TunnelConfig.isProviderSupported(r.provider)).toList();

    // Sort reachable by lowest latency first, then unreachable.
    // Standard HTTP/HTTPS tunnels (Cloudflare Quick, LocalTunnel on port 443) work across all mobile carriers,
    // whereas Bore uses random high TCP ports (40000+) which cellular firewalls often block.
    results.sort((a, b) {
      if (a.reachable && !b.reachable) return -1;
      if (!a.reachable && b.reachable) return 1;
      final aIsWeb = a.provider == TunnelProvider.cloudflareQuick || a.provider == TunnelProvider.localtunnel;
      final bIsWeb = b.provider == TunnelProvider.cloudflareQuick || b.provider == TunnelProvider.localtunnel;
      if (aIsWeb && !bIsWeb) return -1;
      if (!aIsWeb && bIsWeb) return 1;
      return a.latencyMs.compareTo(b.latencyMs);
    });

    return results;
  }

  /// Probe Cloudflare edge
  static Future<TunnelProbeResult> _probeCloudflare() async {
    final sw = Stopwatch()..start();
    try {
      final response = await http
          .head(Uri.parse('https://trycloudflare.com'))
          .timeout(_probeTimeout);
      sw.stop();
      return TunnelProbeResult(
        provider: TunnelProvider.cloudflareQuick,
        latencyMs: sw.elapsedMilliseconds,
        reachable: response.statusCode < 500,
      );
    } catch (e) {
      sw.stop();
      return TunnelProbeResult(
        provider: TunnelProvider.cloudflareQuick,
        latencyMs: sw.elapsedMilliseconds,
        reachable: false,
        errorMessage: e.toString(),
      );
    }
  }

  /// Probe LocalTunnel proxy
  static Future<TunnelProbeResult> _probeLocalTunnel() async {
    final sw = Stopwatch()..start();
    try {
      final response = await http
          .head(
            Uri.parse('https://loca.lt/'),
            headers: {'bypass-tunnel-reminder': 'true'},
          )
          .timeout(_probeTimeout);
      sw.stop();
      return TunnelProbeResult(
        provider: TunnelProvider.localtunnel,
        latencyMs: sw.elapsedMilliseconds,
        reachable: response.statusCode < 500,
      );
    } catch (e) {
      sw.stop();
      return TunnelProbeResult(
        provider: TunnelProvider.localtunnel,
        latencyMs: sw.elapsedMilliseconds,
        reachable: false,
        errorMessage: e.toString(),
      );
    }
  }

  /// Probe Bore TCP port reachability
  static Future<TunnelProbeResult> _probeBore() async {
    final sw = Stopwatch()..start();
    try {
      dynamic target = 'bore.pub';
      try {
        final ips = await InternetAddress.lookup('bore.pub', type: InternetAddressType.IPv4).timeout(_probeTimeout);
        if (ips.isNotEmpty) target = ips.first;
      } catch (_) {}

      final socket = await Socket.connect(target, 7835, timeout: _probeTimeout);
      sw.stop();
      socket.destroy();
      return TunnelProbeResult(
        provider: TunnelProvider.bore,
        latencyMs: sw.elapsedMilliseconds,
        reachable: true,
      );
    } catch (e) {
      sw.stop();
      return TunnelProbeResult(
        provider: TunnelProvider.bore,
        latencyMs: sw.elapsedMilliseconds,
        reachable: false,
        errorMessage: e.toString(),
      );
    }
  }

  /// Determines the best provider based on probe ranking
  static Future<TunnelProbeResult> selectBestProvider() async {
    final probes = await probeAll();
    final viable = probes.where((p) => p.reachable).toList();

    if (viable.isNotEmpty) {
      return viable.first;
    }

    // Default fallback if all offline or in flight
    return const TunnelProbeResult(
      provider: TunnelProvider.cloudflareQuick,
      latencyMs: 150,
      reachable: true,
    );
  }
}
