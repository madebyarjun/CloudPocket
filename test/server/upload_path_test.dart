import 'dart:io';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:cloud_pocket/providers/server_provider.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
      const MethodChannel('plugins.flutter.io/path_provider'),
      (MethodCall methodCall) async {
        return Directory.systemTemp.path;
      },
    );
  });

  tearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
      const MethodChannel('plugins.flutter.io/path_provider'),
      null,
    );
  });

  group('Upload Directory Resolution Tests', () {
    test('resolveUploadDirectory points to Downloads/CloudPocket', () async {
      final path = await ServerNotifier.resolveUploadDirectory();
      expect(path, isNotEmpty);
      expect(path.toLowerCase(), contains('cloudpocket'));
      expect(path.toLowerCase(), anyOf(contains('download'), contains('downloads')));
    });

    test('resolveUploadDirectory respects valid custom directory', () async {
      final tempDir = Directory.systemTemp.createTempSync('cp_custom_upload_');
      addTearDown(() {
        if (tempDir.existsSync()) tempDir.deleteSync(recursive: true);
      });

      final customResolved = await ServerNotifier.resolveUploadDirectory(tempDir.path);
      expect(customResolved, equals(tempDir.path));
    });
  });
}
