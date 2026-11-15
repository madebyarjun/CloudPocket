import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:cloud_pocket/models/room_config.dart';
import 'package:cloud_pocket/server/disposable_room.dart';

void main() {
  group('DisposableRoom Lifecycle & Sweep Tests', () {
    late Directory testTempBase;

    setUp(() async {
      testTempBase = await Directory.systemTemp.createTemp('disposable_room_unit_test_');
    });

    tearDown(() async {
      if (await testTempBase.exists()) {
        try {
          await testTempBase.delete(recursive: true);
        } catch (_) {}
      }
    });

    test('creates sandbox directory and purges completely on destroy', () async {
      final room = await DisposableRoom.create(
        config: const RoomConfig(duration: RoomDuration.min5),
        baseCacheDir: testTempBase,
      );

      expect(await room.tempDirectory.exists(), isTrue);

      // Create a test file in sandbox
      final dummyFile = File('${room.tempDirectory.path}${Platform.pathSeparator}test.bin');
      await dummyFile.writeAsString('sensitive data that must burn');
      expect(await dummyFile.exists(), isTrue);

      // Add messages in RAM
      room.chatHub.addSystemMessage('Welcome to secret room');
      expect(room.chatHub.messageCount, equals(1));

      // Destroy room
      await room.destroy('unit_test_burn');

      expect(room.isDestroyed, isTrue);
      expect(room.chatHub.messageCount, equals(0)); // RAM purged
      expect(await dummyFile.exists(), isFalse);     // Files purged
      expect(await room.tempDirectory.exists(), isFalse); // Directory purged
    });

    test('sweepOrphanedRoomDirectories deletes abandoned directories', () async {
      final orphan1 = Directory('${testTempBase.path}${Platform.pathSeparator}disposable_room_orphan_1');
      final orphan2 = Directory('${testTempBase.path}${Platform.pathSeparator}disposable_room_orphan_2');
      final normalDir = Directory('${testTempBase.path}${Platform.pathSeparator}normal_folder');

      await orphan1.create();
      await orphan2.create();
      await normalDir.create();

      await File('${orphan1.path}${Platform.pathSeparator}orphan_file.txt').writeAsString('orphan');

      expect(await orphan1.exists(), isTrue);
      expect(await orphan2.exists(), isTrue);
      expect(await normalDir.exists(), isTrue);

      await DisposableRoom.sweepOrphanedRoomDirectories(testTempBase);

      expect(await orphan1.exists(), isFalse);
      expect(await orphan2.exists(), isFalse);
      expect(await normalDir.exists(), isTrue); // Unrelated directories preserved!
    });
  });
}
