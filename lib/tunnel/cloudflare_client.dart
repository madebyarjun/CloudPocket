import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:cloud_pocket/services/app_logger.dart';
import 'package:cloud_pocket/tunnel/cloudflared_binary_manager.dart';
import 'package:cloud_pocket/tunnel/micro_dns_server.dart';
import 'package:cloud_pocket/tunnel/tunnel_client.dart';
import 'package:cloud_pocket/tunnel/tunnel_config.dart';

class QuickTunnelCredentials {
  final String accountTag;
  final String tunnelId;
  final String secret;
  final String hostname;
  final String token;

  const QuickTunnelCredentials({
    required this.accountTag,
    required this.tunnelId,
    required this.secret,
    required this.hostname,
    required this.token,
  });
}

class CloudflareClient implements TunnelClient {
  final int localPort;
  final TunnelConfig config;
  final void Function(double progress, String status)? onStatusUpdate;
  final void Function()? onDisconnect;

  Process? _process;
  MicroDnsServer? _dnsServer;
  String? _publicUrl;
  String? _stashedQuickUrl;
  bool _connectionRegistered = false;
  bool _isRunning = false;

  CloudflareClient({
    required this.localPort,
    required this.config,
    this.onStatusUpdate,
    this.onDisconnect,
  });

  @override
  String? get publicUrl => _publicUrl;

  @override
  bool get isRunning => _isRunning && _process != null;

  /// Directly provisions a Cloudflare Quick Tunnel from api.trycloudflare.com using
  /// Dart's native network stack, bypassing cloudflared's DNS resolution issues on Android.
  static Future<QuickTunnelCredentials> requestQuickTunnelCredentials({
    Duration timeout = const Duration(seconds: 15),
    HttpClient? customHttpClient,
  }) async {
    final client = customHttpClient ?? HttpClient();
    try {
      final request = await client
          .postUrl(Uri.parse('https://api.trycloudflare.com/tunnel'))
          .timeout(timeout);
      final response = await request.close().timeout(timeout);
      final body = await response.transform(utf8.decoder).join();
      if (response.statusCode != 200) {
        throw Exception('Cloudflare API returned HTTP ${response.statusCode}: $body');
      }
      final data = jsonDecode(body) as Map<String, dynamic>;
      final result = data['result'] as Map<String, dynamic>?;
      if (result == null) {
        throw Exception('Invalid Cloudflare API response (missing result): $body');
      }
      final accountTag = result['account_tag'] as String;
      final tunnelId = result['id'] as String;
      final secret = result['secret'] as String;
      final hostname = result['hostname'] as String;

      final tokenPayload = jsonEncode({
        'a': accountTag,
        't': tunnelId,
        's': secret,
      });
      final token = base64Encode(utf8.encode(tokenPayload));

      return QuickTunnelCredentials(
        accountTag: accountTag,
        tunnelId: tunnelId,
        secret: secret,
        hostname: hostname,
        token: token,
      );
    } finally {
      if (customHttpClient == null) {
        client.close();
      }
    }
  }

  @override
  Future<String> start() async {
    _isRunning = false;
    _publicUrl = null;
    _stashedQuickUrl = null;
    _connectionRegistered = false;
    final completer = Completer<String>();
    Timer? timeoutTimer;

    try {
      // 1. Start local MicroDnsServer on loopback (127.0.0.1)
      // This permanently solves Android DNS limitations:
      // - Traffic to 127.0.0.1 is 100% immune to carrier UDP port 53 blocking (Jio, Airtel, Vi)
      // - Bypasses Android's lack of /etc/resolv.conf and prevents Go from querying [::1]:53
      // - Responds to edge SRV queries in 0.1ms with Anycast IPs
      _dnsServer = MicroDnsServer();
      final dnsPort = await _dnsServer!.start();

      // 2. Ensure binary is present
      onStatusUpdate?.call(0.2, 'Checking Cloudflare engine...');
      final binaryPath = await CloudflaredBinaryManager.ensureBinaryAvailable(
        onProgress: onStatusUpdate,
      );

      // 3. Prepare process arguments
      List<String> args;
      if (config.provider == TunnelProvider.cloudflareCustom) {
        if (config.cloudflareTunnelToken == null || config.cloudflareTunnelToken!.isEmpty) {
          throw Exception('Cloudflare Custom Domain requires a valid tunnel token.');
        }
        args = [
          'tunnel',
          '--protocol', 'http2',
          '--edge-ip-version', '4',
          '--retries', '5',
          'run',
          '--dns-resolver-addrs', '127.0.0.1:$dnsPort',
          '--token', config.cloudflareTunnelToken!,
        ];
      } else {
        // Quick tunnel mode:
        // On Android, cloudflared fails when attempting to POST to api.trycloudflare.com
        // because Android lacks /etc/resolv.conf, causing Go's resolver to query [::1]:53.
        // We solve this permanently by having Dart (which uses Android's Bionic/netd DNS)
        // allocate the quick tunnel and obtain the credentials directly, then running
        // cloudflared with the provisioned token pointing to our local port.
        onStatusUpdate?.call(0.4, 'Allocating Cloudflare Quick Tunnel...');
        final creds = await requestQuickTunnelCredentials();
        _stashedQuickUrl = 'https://${creds.hostname}';
        AppLogger().info('CLOUDFLARE', 'Allocated quick tunnel: $_stashedQuickUrl');

        args = [
          'tunnel',
          '--protocol', 'http2',
          '--edge-ip-version', '4',
          '--retries', '5',
          '--no-autoupdate',
          'run',
          '--dns-resolver-addrs', '127.0.0.1:$dnsPort',
          '--token', creds.token,
          '--url', 'http://127.0.0.1:$localPort',
        ];
      }

      // 4. Configure environment variables (TMPDIR, HOME, DNS resolvers)
      final env = Map<String, String>.from(Platform.environment);
      // Route all DNS queries directly to our loopback micro DNS server first,
      // with public resolvers as secondary fallbacks
      env['TUNNEL_DNS_RESOLVER_ADDRS'] = '127.0.0.1:$dnsPort,1.1.1.1:53,8.8.8.8:53';
      env['TUNNEL_EDGE_IP_VERSION'] = '4';
      env['TUNNEL_TRANSPORT_PROTOCOL'] = 'http2';

      String? workingDir;
      if (Platform.isAndroid) {
        try {
          final tempDir = await getTemporaryDirectory();
          final supportDir = await getApplicationSupportDirectory();
          env['TMPDIR'] = tempDir.path;
          env['HOME'] = supportDir.path;
          workingDir = tempDir.path;
        } catch (_) {
          final dir = p.dirname(binaryPath);
          env['TMPDIR'] = dir;
          env['HOME'] = dir;
        }
      }

      onStatusUpdate?.call(0.8, 'Connecting to Cloudflare edge...');
      try {
        _process = await Process.start(
          binaryPath,
          args,
          environment: env,
          workingDirectory: workingDir,
        );
      } catch (e) {
        throw Exception('Cannot launch Cloudflare engine ($binaryPath): $e');
      }
      _isRunning = true;

      final logHistory = <String>[];

      String recentLogs() {
        if (logHistory.isEmpty) return '';
        final start = logHistory.length > 10 ? logHistory.length - 10 : 0;
        return '\nLogs:\n${logHistory.sublist(start).join('\n')}';
      }

      // Handle premature process exit
      _process!.exitCode.then((code) {
        _isRunning = false;
        if (!completer.isCompleted) {
          completer.completeError(
            Exception('Cloudflare process exited with code $code before tunnel established${recentLogs()}'),
          );
        } else {
          onDisconnect?.call();
        }
      });

      void handleLine(String line) {
        if (logHistory.length > 50) logHistory.removeAt(0);
        logHistory.add(line);
        AppLogger().debug('CLOUDFLARE', line);
        handleLogLine(line, completer);
      }

      // Listen to stderr (cloudflared logs to stderr by default)
      _process!.stderr
          .transform(utf8.decoder)
          .transform(const LineSplitter())
          .listen(handleLine);

      // Also listen to stdout
      _process!.stdout
          .transform(utf8.decoder)
          .transform(const LineSplitter())
          .listen(handleLine);

      // Timeout after 30 seconds
      timeoutTimer = Timer(const Duration(seconds: 30), () {
        if (!completer.isCompleted) {
          completer.completeError(
            TimeoutException('Cloudflare tunnel connection timed out after 30 seconds${recentLogs()}'),
          );
        }
      });

      final url = await completer.future;
      timeoutTimer.cancel();
      return url;
    } catch (e) {
      timeoutTimer?.cancel();
      await stop();
      rethrow;
    }
  }

  static String? extractQuickTunnelUrl(String line) {
    final quickUrlRegex = RegExp(r'https://[a-zA-Z0-9-]+\.trycloudflare\.com');
    final match = quickUrlRegex.firstMatch(line);
    if (match != null) {
      final url = match.group(0)!;
      if (!url.contains('api.trycloudflare.com') && !url.contains('pkg.trycloudflare.com')) {
        return url;
      }
    }
    return null;
  }

  static bool isConnectionRegistered(String line) {
    final lower = line.toLowerCase();
    return lower.contains('registered tunnel connection') ||
        (lower.contains('connection') && lower.contains('registered'));
  }

  @visibleForTesting
  set stashedQuickUrl(String? url) => _stashedQuickUrl = url;

  @visibleForTesting
  void handleLogLine(String line, Completer<String> completer) {
    final registered = isConnectionRegistered(line);
    if (registered) {
      _connectionRegistered = true;
    }

    if (config.provider == TunnelProvider.cloudflareCustom) {
      // In custom domain mode, watch for connection confirmation
      if (registered) {
        final domain = config.cloudflareDomain ?? 'custom.cloudflared';
        final url = domain.startsWith('http') ? domain : 'https://$domain';
        _publicUrl = url;
        if (!completer.isCompleted) {
          onStatusUpdate?.call(1.0, 'Cloudflare Tunnel connected');
          completer.complete(url);
        }
      }
    } else {
      // Quick Tunnel mode: stash https://xxx.trycloudflare.com when seen,
      // but only complete once Cloudflare edge registration confirmation is received.
      final url = extractQuickTunnelUrl(line);
      if (url != null) {
        _stashedQuickUrl = url;
        if (!_connectionRegistered) {
          onStatusUpdate?.call(0.9, 'Tunnel URL assigned, awaiting edge registration...');
        }
      }
      if (_stashedQuickUrl != null && _connectionRegistered && !completer.isCompleted) {
        onStatusUpdate?.call(1.0, 'Cloudflare Tunnel connected');
        _publicUrl = _stashedQuickUrl;
        completer.complete(_stashedQuickUrl!);
      }
    }
  }

  @override
  Future<void> stop() async {
    _isRunning = false;
    _publicUrl = null;
    _stashedQuickUrl = null;
    _connectionRegistered = false;
    if (_process != null) {
      try {
        _process!.kill(ProcessSignal.sigterm);
      } catch (_) {
        _process!.kill();
      }
      _process = null;
    }
    if (_dnsServer != null) {
      try {
        await _dnsServer!.stop();
      } catch (_) {}
      _dnsServer = null;
    }
  }
}
