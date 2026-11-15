import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pretty_qr_code/pretty_qr_code.dart';
import 'package:cloud_pocket/models/share_session.dart';
import 'package:cloud_pocket/models/room_config.dart';
import 'package:cloud_pocket/tunnel/tunnel_config.dart';
import 'package:cloud_pocket/server/room_pin_rate_limiter.dart';
import 'package:cloud_pocket/services/cloudpocket_link_builder.dart';

void main() {
  group('CloudPocketLinkBuilder Unit Tests', () {
    test('QrImage can generate 1024px image bytes', () async {
      final qrCode = QrCode.fromData(
        data: 'https://test.cloudpocket.io',
        errorCorrectLevel: QrErrorCorrectLevel.M,
      );
      final qrImage = QrImage(qrCode);
      final bytes = await qrImage.toImageAsBytes(
        size: 1024,
        format: ui.ImageByteFormat.png,
        decoration: const PrettyQrDecoration(
          quietZone: PrettyQrQuietZone.modules(4),
          shape: PrettyQrSmoothSymbol(
            color: Colors.black,
            roundFactor: 0.15,
          ),
        ),
      );
      expect(bytes, isNotNull);
      expect(bytes!.lengthInBytes, greaterThan(100));
      final uint8 = bytes.buffer.asUint8List();
      expect(uint8.length, greaterThan(100));
    });

    test('buildUrl for LAN / Hotspot generates http scheme', () {
      const session = ShareSession();
      final url = CloudPocketLinkBuilder.buildUrl(
        interfaceAddress: '192.168.1.50',
        mode: SharingLinkMode.fileSharing,
        session: session,
        defaultPort: 8080,
      );
      expect(url, equals('http://192.168.1.50:8080'));
    });

    test('buildUrl with PIN places token in URL fragment (#t=...), never in query string', () {
      final session = const ShareSession().copyWith(
        requirePassword: true,
        password: 'secret',
        sessionToken: 'a1b2c3d4e5f6',
      );
      final url = CloudPocketLinkBuilder.buildUrl(
        interfaceAddress: '192.168.1.50:8080',
        mode: SharingLinkMode.fileSharing,
        session: session,
      );
      expect(url, equals('http://192.168.1.50:8080/#t=a1b2c3d4e5f6'));
      expect(url.contains('?'), isFalse);
      expect(url.contains('secret'), isFalse);
    });

    test('buildUrl for trycloudflare tunnel generates https scheme', () {
      const session = ShareSession();
      final url = CloudPocketLinkBuilder.buildUrl(
        interfaceAddress: 'https://swift-pocket-relay.trycloudflare.com',
        mode: SharingLinkMode.fileSharing,
        session: session,
      );
      expect(url, equals('https://swift-pocket-relay.trycloudflare.com'));
    });

    test('buildUrl for Bore tunnel generates http scheme (unencrypted transport)', () {
      const session = ShareSession();
      final url = CloudPocketLinkBuilder.buildUrl(
        interfaceAddress: 'http://bore.pub:38491',
        mode: SharingLinkMode.fileSharing,
        session: session,
      );
      expect(url, equals('http://bore.pub:38491'));
    });

    test('buildUrl for custom Cloudflare domain generates https scheme', () {
      const session = ShareSession(
        tunnelConfig: TunnelConfig(
          provider: TunnelProvider.cloudflareCustom,
          cloudflareDomain: 'share.mycompany.org',
        ),
      );
      final url = CloudPocketLinkBuilder.buildUrl(
        interfaceAddress: 'share.mycompany.org',
        mode: SharingLinkMode.fileSharing,
        session: session,
        defaultPort: 443,
      );
      expect(url, equals('https://share.mycompany.org'));
    });

    test('buildUrl for roomInvite contains token only in fragment, never PIN', () {
      const session = ShareSession(
        isDisposableRoom: true,
        password: '9988',
        roomConfig: RoomConfig(
          inviteToken: 'd8f0e2b1c4a567890123456789abcdef',
          requirePin: true,
          pin: '9988',
        ),
      );
      final url = CloudPocketLinkBuilder.buildUrl(
        interfaceAddress: '192.168.1.10:8080',
        mode: SharingLinkMode.roomInvite,
        session: session,
      );
      expect(url, equals('http://192.168.1.10:8080/room#token=d8f0e2b1c4a567890123456789abcdef'));
      expect(url.contains('9988'), isFalse);
    });

    test('buildUrl for roomQr contains token and PIN in fragment while room is active', () {
      const session = ShareSession(
        isDisposableRoom: true,
        password: '9988',
        roomConfig: RoomConfig(
          inviteToken: 'd8f0e2b1c4a567890123456789abcdef',
          requirePin: true,
          pin: '9988',
        ),
      );
      final activeUrl = CloudPocketLinkBuilder.buildUrl(
        interfaceAddress: '192.168.1.10:8080',
        mode: SharingLinkMode.roomQr,
        session: session,
        isRoomActive: true,
      );
      expect(activeUrl, equals('http://192.168.1.10:8080/room#token=d8f0e2b1c4a567890123456789abcdef&pin=9988'));

      final expiredUrl = CloudPocketLinkBuilder.buildUrl(
        interfaceAddress: '192.168.1.10:8080',
        mode: SharingLinkMode.roomQr,
        session: session,
        isRoomActive: false,
      );
      expect(expiredUrl, equals('http://192.168.1.10:8080/room#token=d8f0e2b1c4a567890123456789abcdef'));
      expect(expiredUrl.contains('pin='), isFalse);
    });

    test('isValidCloudPocketHost strictly allows private IPv4 and tunnels and rejects foreign hosts', () {
      expect(CloudPocketLinkBuilder.isValidCloudPocketHost('192.168.1.5'), isTrue);
      expect(CloudPocketLinkBuilder.isValidCloudPocketHost('10.0.0.12'), isTrue);
      expect(CloudPocketLinkBuilder.isValidCloudPocketHost('172.20.10.4'), isTrue);
      expect(CloudPocketLinkBuilder.isValidCloudPocketHost('my-room.trycloudflare.com'), isTrue);
      expect(CloudPocketLinkBuilder.isValidCloudPocketHost('quick-share.loca.lt'), isTrue);
      expect(CloudPocketLinkBuilder.isValidCloudPocketHost('bore.pub'), isTrue);
      expect(CloudPocketLinkBuilder.isValidCloudPocketHost('127.0.0.1'), isTrue);
      expect(CloudPocketLinkBuilder.isValidCloudPocketHost('localhost'), isTrue);

      // Foreign and public unauthorized hosts
      expect(CloudPocketLinkBuilder.isValidCloudPocketHost('google.com'), isFalse);
      expect(CloudPocketLinkBuilder.isValidCloudPocketHost('evil-phishing.com'), isFalse);
      expect(CloudPocketLinkBuilder.isValidCloudPocketHost('8.8.8.8'), isFalse);
      expect(CloudPocketLinkBuilder.isValidCloudPocketHost('1.1.1.1'), isFalse);
    });

    test('filterAndSortIps sorts Wi-Fi first, then Hotspot, then other LAN IPs', () {
      final input = [
        'http://192.168.43.1:8080', // Hotspot
        'http://192.168.1.105:8080', // Wi-Fi LAN
        'http://10.15.2.1:8080', // Other LAN
        'http://127.0.0.1:8080', // Loopback (discarded)
        'http://169.254.10.20:8080', // Link-local (discarded)
      ];
      final categorized = CloudPocketLinkBuilder.filterAndSortIps(input);
      expect(categorized.wifiIps, contains('http://192.168.1.105:8080'));
      expect(categorized.hotspotIps, contains('http://192.168.43.1:8080'));
      expect(categorized.all, isNot(contains('http://127.0.0.1:8080')));
      expect(categorized.all, isNot(contains('http://169.254.10.20:8080')));
    });

    test('RoomPinRateLimiter enforces 5 attempts then 60s lockout', () {
      final limiter = RoomPinRateLimiter();
      const client = '192.168.1.88';
      limiter.reset();

      expect(limiter.isLockedOut(client), isFalse);
      for (int i = 0; i < 4; i++) {
        limiter.recordFailure(client);
        expect(limiter.isLockedOut(client), isFalse);
      }
      limiter.recordFailure(client); // 5th failure
      expect(limiter.isLockedOut(client), isTrue);
      expect(limiter.remainingLockout(client)?.inSeconds, inInclusiveRange(55, 60));

      limiter.recordSuccess(client);
      expect(limiter.isLockedOut(client), isFalse);
    });
  });
}
