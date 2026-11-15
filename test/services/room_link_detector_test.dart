import 'package:flutter_test/flutter_test.dart';
import 'package:cloud_pocket/services/room_link_detector.dart';

void main() {
  group('RoomLinkDetector Tests', () {
    test('parses clean room URL without credentials', () {
      const url = 'https://example-subdomain.trycloudflare.com/room';
      final parsed = RoomLinkDetector.parse(url);

      expect(parsed, isNotNull);
      expect(parsed!.roomUrl, equals('https://example-subdomain.trycloudflare.com'));
      expect(parsed.pin, isNull);
      expect(parsed.token, isNull);
    });

    test('extracts client-side hash fragment token (#k=...)', () {
      const url = 'https://example-subdomain.trycloudflare.com/room#k=c489fab2108d4b3e';
      final parsed = RoomLinkDetector.parse(url);

      expect(parsed, isNotNull);
      expect(parsed!.roomUrl, equals('https://example-subdomain.trycloudflare.com'));
      expect(parsed.token, equals('c489fab2108d4b3e'));
      expect(parsed.pin, isNull);
    });

    test('extracts cloudpocket://room deep link with token', () {
      final deepLink = RoomLinkDetector.buildDeepLink(
        roomUrl: 'https://myserver.loca.lt',
        nickname: 'Alice',
        token: 'f93d182b0a',
      );

      final parsed = RoomLinkDetector.parse(deepLink);
      expect(parsed, isNotNull);
      expect(parsed!.roomUrl, equals('https://myserver.loca.lt'));
      expect(parsed.nickname, equals('Alice'));
      expect(parsed.token, equals('f93d182b0a'));
    });

    test('buildEncryptedInviteUrl constructs fragment-based URL', () {
      final invite = RoomLinkDetector.buildEncryptedInviteUrl(
        roomUrl: 'https://room.trycloudflare.com',
        token: 'a1b2c3d4e5f6',
      );

      expect(invite, equals('https://room.trycloudflare.com/room#k=a1b2c3d4e5f6'));
      final parsed = RoomLinkDetector.parse(invite);
      expect(parsed, isNotNull);
      expect(parsed!.token, equals('a1b2c3d4e5f6'));
    });
  });
}
