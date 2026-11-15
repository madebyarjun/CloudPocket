import 'package:flutter_test/flutter_test.dart';
import 'package:cloud_pocket/models/room_config.dart';

void main() {
  group('RoomConfig Tests', () {
    test('default configuration values are sensible', () {
      const config = RoomConfig();
      expect(config.duration, equals(RoomDuration.min15));
      expect(config.maxParticipants, equals(10));
      expect(config.requirePin, isFalse);
      expect(config.allowFileSharing, isTrue);
      expect(config.maxFileSizeMb, equals(100));
      expect(config.maxTotalMessages, equals(1000));
      expect(config.maxMessageLength, equals(5000));
    });

    test('PIN verification with hashing works correctly', () {
      final pinHash = RoomConfig.hashPin('4321');
      final config = RoomConfig(
        requirePin: true,
        pin: '4321',
        pinHash: pinHash,
      );

      expect(config.verifyPin('4321'), isTrue);
      expect(config.verifyPin('0000'), isFalse);
      expect(config.verifyPin(''), isFalse);
    });

    test('verifyPin returns true when requirePin is false', () {
      const config = RoomConfig(requirePin: false);
      expect(config.verifyPin('anything'), isTrue);
    });

    test('copyWith updates fields and clearPin works', () {
      const config = RoomConfig(requirePin: true, pin: '9999');
      final updated = config.copyWith(duration: RoomDuration.hour1, clearPin: true);

      expect(updated.duration, equals(RoomDuration.hour1));
      expect(updated.pin, isNull);
    });

    test('roomName, roomCode, and inviteToken are generated and verified', () {
      final code = RoomConfig.generateRoomCode();
      final token = RoomConfig.generateInviteToken();

      // Format is random 2 letters + 4 digits: e.g. AB-4829
      expect(RegExp(r'^[A-Z]{2}-\d{4}$').hasMatch(code), isTrue);
      // Cryptographically secure 128-bit invite token (32 hex chars)
      expect(token.length, equals(32));

      final config = RoomConfig(
        roomName: 'Confidential Sync',
        roomCode: code,
        inviteToken: token,
        requirePin: true,
        pin: '1234',
        pinHash: RoomConfig.hashPin('1234'),
      );

      expect(config.roomName, equals('Confidential Sync'));
      expect(config.roomCode, equals(code));
      expect(config.inviteToken, equals(token));

      // Strict PIN verification: only secret PIN is valid
      expect(config.verifyPin('1234'), isTrue);
      expect(config.verifyPin(code), isFalse);
      expect(config.verifyPin('wrong'), isFalse);
    });
  });
}
