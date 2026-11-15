import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:cloud_pocket/services/room_discovery_service.dart';

void main() {
  group('RoomDiscoveryService Tests', () {
    test('registers and resolves ephemeral room by Chat ID', () async {
      final mockStorage = <String, String>{};

      final mockClient = MockClient((request) async {
        final path = request.url.path;
        if (request.method == 'POST') {
          mockStorage[path] = request.body;
          return http.Response('{"id":"mock"}', 200);
        } else if (request.method == 'GET') {
          // Poll returns json line
          final cleanPath = path.replaceFirst('/json', '');
          final stored = mockStorage[cleanPath];
          if (stored != null) {
            final line = jsonEncode({
              'id': 'mock',
              'message': stored,
            });
            return http.Response(line, 200);
          }
          return http.Response('', 200);
        }
        return http.Response('Not Found', 404);
      });

      const testCode = 'AB-4829';
      const testUrl = 'https://unit-test-discovery.loca.lt';

      final registered = await RoomDiscoveryService.registerRoom(
        roomCode: testCode,
        tunnelUrl: testUrl,
        roomName: 'Discovery Unit Test',
        requirePin: true,
        httpClient: mockClient,
      );
      expect(registered, isTrue);

      final discovered = await RoomDiscoveryService.resolveRoom(
        testCode,
        httpClient: mockClient,
      );
      expect(discovered, isNotNull);
      expect(discovered!.roomUrl, equals(testUrl));
      expect(discovered.roomName, equals('Discovery Unit Test'));
      expect(discovered.inviteToken, isNull);
      expect(jsonDecode(mockStorage['/cp-room-ab4829']!)['token'], isNull);

      // Test burned
      await RoomDiscoveryService.unregisterRoom(testCode, httpClient: mockClient);
      final afterBurn = await RoomDiscoveryService.resolveRoom(testCode, httpClient: mockClient);
      expect(afterBurn, isNull);
    });

    test('resolveRoom returns null for invalid or too short code', () async {
      final result = await RoomDiscoveryService.resolveRoom('ab');
      expect(result, isNull);
    });

    test('Token-only rooms are not published to public discovery', () async {
      final client = MockClient((_) async => throw StateError('Must not publish'));
      expect(await RoomDiscoveryService.registerRoom(roomCode: 'AB-4829', tunnelUrl: 'https://example.test', httpClient: client), isFalse);
    });

    test('Expired and legacy token-bearing registrations are rejected', () async {
      for (final payload in [
        {'url': 'https://example.test', 'token': 'legacy'},
        {'url': 'https://example.test', 'requirePin': true, 'expiresAt': 1},
      ]) {
        final client = MockClient((_) async => http.Response(jsonEncode({'message': jsonEncode(payload)}), 200));
        expect(await RoomDiscoveryService.resolveRoom('AB-4829', httpClient: client), isNull);
      }
    });
  });
}
