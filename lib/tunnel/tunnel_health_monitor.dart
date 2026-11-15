import 'dart:async';
import 'dart:io';
import 'package:http/http.dart' as http;

typedef TunnelFailoverCallback = Future<void> Function();

class TunnelHealthMonitor {
  final String tunnelUrl;
  final TunnelFailoverCallback onUnhealthy;
  final Duration checkInterval;

  Timer? _timer;
  int _consecutiveFailures = 0;
  bool _isMonitoring = false;

  TunnelHealthMonitor({
    required this.tunnelUrl,
    required this.onUnhealthy,
    this.checkInterval = const Duration(seconds: 30),
  });

  void start() {
    if (_isMonitoring) return;
    _isMonitoring = true;
    _consecutiveFailures = 0;

    _timer = Timer.periodic(checkInterval, (_) => _checkHealth());
  }

  Future<void> _checkHealth() async {
    if (!_isMonitoring) return;

    try {
      final uri = Uri.parse(tunnelUrl);
      if (uri.host.contains('bore')) {
        // Bore forwards raw TCP and only listens on IPv4
        dynamic target = uri.host;
        try {
          final ips = await InternetAddress.lookup(uri.host, type: InternetAddressType.IPv4);
          if (ips.isNotEmpty) target = ips.first;
        } catch (_) {}
        final socket = await Socket.connect(target, uri.port, timeout: const Duration(seconds: 5));
        socket.destroy();
        _consecutiveFailures = 0;
        return;
      }

      final response = await http
          .get(
            uri,
            headers: {
              'User-Agent': 'CloudPocket-HealthCheck/1.5',
              'bypass-tunnel-reminder': 'true',
            },
          )
          .timeout(const Duration(seconds: 8));

      // Any HTTP response under 500 (even 200, 302, 401, 403, 404) proves reachability
      if (response.statusCode < 500) {
        _consecutiveFailures = 0;
      } else {
        _consecutiveFailures++;
      }
    } catch (_) {
      _consecutiveFailures++;
    }

    if (!_isMonitoring) return;

    if (_consecutiveFailures >= 3) {
      stop();
      await onUnhealthy();
    }
  }

  void stop() {
    _isMonitoring = false;
    _timer?.cancel();
    _timer = null;
  }
}
