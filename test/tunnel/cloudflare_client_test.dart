import 'dart:async';
import 'package:flutter_test/flutter_test.dart';
import 'package:cloud_pocket/tunnel/cloudflare_client.dart';
import 'package:cloud_pocket/tunnel/tunnel_config.dart';

void main() {
  group('CloudflareClient Quick Tunnel URL Extraction Tests', () {
    test('ignores api.trycloudflare.com startup log', () {
      const line = '2026-09-08T11:30:00Z INF Requesting new quick tunnel on trycloudflare.com from https://api.trycloudflare.com/tunnel';
      final url = CloudflareClient.extractQuickTunnelUrl(line);
      expect(url, isNull);
    });

    test('ignores pkg.trycloudflare.com update check', () {
      const line = '2026-09-08T11:30:01Z INF Checking package version at https://pkg.trycloudflare.com';
      final url = CloudflareClient.extractQuickTunnelUrl(line);
      expect(url, isNull);
    });

    test('correctly extracts randomized trycloudflare subdomain URL', () {
      const line = '| https://pocket-sharing-rocks-9182.trycloudflare.com |';
      final url = CloudflareClient.extractQuickTunnelUrl(line);
      expect(url, equals('https://pocket-sharing-rocks-9182.trycloudflare.com'));
    });

    test('extracts tunnel URL in standard cloudflared banner box format', () {
      const line = 'Your quick Tunnel has been created! Visit it at (it may take some time to be reachable): https://swift-alpha-bravo-12.trycloudflare.com';
      final url = CloudflareClient.extractQuickTunnelUrl(line);
      expect(url, equals('https://swift-alpha-bravo-12.trycloudflare.com'));
    });

    test('returns null for unrelated log lines', () {
      const line = '2026-09-08T11:30:02Z INF Connection 19a8d registered with protocol quic';
      final url = CloudflareClient.extractQuickTunnelUrl(line);
      expect(url, isNull);
    });
  });

  group('CloudflareClient Connection Registration Tests', () {
    test('detects Registered tunnel connection line', () {
      const line = '2026-09-08T11:30:08Z INF Registered tunnel connection connIndex=0 connection=abc location=DFW protocol=http2';
      expect(CloudflareClient.isConnectionRegistered(line), isTrue);
    });

    test('detects Connection registered line', () {
      const line = '2026-09-08T11:30:02Z INF Connection 19a8d registered with protocol quic';
      expect(CloudflareClient.isConnectionRegistered(line), isTrue);
    });

    test('returns false for non-registration log lines', () {
      const line1 = '| https://pocket-sharing-rocks-9182.trycloudflare.com |';
      const line2 = '2026-09-08T11:30:00Z INF Requesting new quick tunnel on trycloudflare.com';
      expect(CloudflareClient.isConnectionRegistered(line1), isFalse);
      expect(CloudflareClient.isConnectionRegistered(line2), isFalse);
    });
  });

  group('CloudflareClient Log Handling and Lifecycle Tests', () {
    test('Quick Tunnel: stashes URL and does not complete until registered', () {
      final client = CloudflareClient(
        localPort: 8080,
        config: const TunnelConfig().copyWith(provider: TunnelProvider.cloudflareQuick),
      );
      final completer = Completer<String>();

      // 1. URL banner appears: stashed, but tunnel is not ready yet
      client.handleLogLine(
        'Your quick Tunnel has been created! Visit it at: https://swift-alpha-bravo-12.trycloudflare.com',
        completer,
      );
      expect(completer.isCompleted, isFalse);
      expect(client.publicUrl, isNull);

      // 2. Unrelated log lines pass through without completing
      client.handleLogLine('2026-09-08T11:30:04Z INF Route propagating...', completer);
      expect(completer.isCompleted, isFalse);
      expect(client.publicUrl, isNull);

      // 3. Registered tunnel connection confirmed: now resolves completer
      client.handleLogLine(
        '2026-09-08T11:30:08Z INF Registered tunnel connection connIndex=0 connection=abc location=DFW protocol=http2',
        completer,
      );
      expect(completer.isCompleted, isTrue);
      expect(client.publicUrl, equals('https://swift-alpha-bravo-12.trycloudflare.com'));
      expect(completer.future, completion(equals('https://swift-alpha-bravo-12.trycloudflare.com')));
    });

    test('Quick Tunnel: completes if registration occurs before URL banner', () {
      final client = CloudflareClient(
        localPort: 8080,
        config: const TunnelConfig().copyWith(provider: TunnelProvider.cloudflareQuick),
      );
      final completer = Completer<String>();

      // 1. Edge registration seen first
      client.handleLogLine(
        '2026-09-08T11:30:01Z INF Connection 19a8d registered with protocol http2',
        completer,
      );
      expect(completer.isCompleted, isFalse);
      expect(client.publicUrl, isNull);

      // 2. URL banner seen next: completes immediately since edge is already registered
      client.handleLogLine(
        '| https://pocket-sharing-rocks-9182.trycloudflare.com |',
        completer,
      );
      expect(completer.isCompleted, isTrue);
      expect(client.publicUrl, equals('https://pocket-sharing-rocks-9182.trycloudflare.com'));
    });

    test('Quick Tunnel: multiple registration events do not error or re-complete', () {
      final client = CloudflareClient(
        localPort: 8080,
        config: const TunnelConfig().copyWith(provider: TunnelProvider.cloudflareQuick),
      );
      final completer = Completer<String>();

      client.handleLogLine(
        '| https://pocket-sharing-rocks-9182.trycloudflare.com |',
        completer,
      );
      client.handleLogLine(
        '2026-09-08T11:30:08Z INF Registered tunnel connection connIndex=0 connection=abc location=DFW protocol=http2',
        completer,
      );
      expect(completer.isCompleted, isTrue);

      // Subsequent registration lines (e.g. multi-connection to other edge points)
      expect(
        () => client.handleLogLine(
          '2026-09-08T11:30:09Z INF Registered tunnel connection connIndex=1 connection=def location=ORD protocol=http2',
          completer,
        ),
        returnsNormally,
      );
    });

    test('Hybrid Quick Tunnel: completes immediately when connection is registered with pre-stashed URL', () {
      final client = CloudflareClient(
        localPort: 8080,
        config: const TunnelConfig().copyWith(provider: TunnelProvider.cloudflareQuick),
      );
      client.stashedQuickUrl = 'https://rapid-silver-galaxy.trycloudflare.com';
      final completer = Completer<String>();

      client.handleLogLine(
        '2026-09-11T14:30:00Z INF Registered tunnel connection connIndex=0 connection=abc location=bom12 protocol=http2',
        completer,
      );

      expect(completer.isCompleted, isTrue);
      expect(client.publicUrl, equals('https://rapid-silver-galaxy.trycloudflare.com'));
    });

    test('Custom Domain: completes upon connection registration', () {
      final client = CloudflareClient(
        localPort: 8080,
        config: const TunnelConfig().copyWith(
          provider: TunnelProvider.cloudflareCustom,
          cloudflareTunnelToken: 'test_token',
          cloudflareDomain: 'tunnel.mycustomdomain.com',
        ),
      );
      final completer = Completer<String>();

      client.handleLogLine('2026-09-08T11:30:00Z INF Starting tunnel...', completer);
      expect(completer.isCompleted, isFalse);

      client.handleLogLine(
        '2026-09-08T11:30:05Z INF Registered tunnel connection connIndex=0 connection=abc location=DFW protocol=http2',
        completer,
      );
      expect(completer.isCompleted, isTrue);
      expect(client.publicUrl, equals('https://tunnel.mycustomdomain.com'));
    });
  });

  group('QuickTunnelCredentials Tests', () {
    test('constructs valid credentials model', () {
      const creds = QuickTunnelCredentials(
        accountTag: 'acc123',
        tunnelId: 'tun456',
        secret: 'sec789',
        hostname: 'test.trycloudflare.com',
        token: 'eyJhbGciOiJIUzI1NiJ9',
      );
      expect(creds.accountTag, equals('acc123'));
      expect(creds.tunnelId, equals('tun456'));
      expect(creds.secret, equals('sec789'));
      expect(creds.hostname, equals('test.trycloudflare.com'));
      expect(creds.token, equals('eyJhbGciOiJIUzI1NiJ9'));
    });
  });
}
