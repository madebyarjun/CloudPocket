import 'dart:io';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:path/path.dart' as p;
import 'package:cloud_pocket/models/share_session.dart';
import 'package:cloud_pocket/providers/session_provider.dart';
import 'package:cloud_pocket/providers/thumbnail_provider.dart';

void main() {
  late Directory tempDir;

  setUp(() async {
    tempDir = await Directory.systemTemp.createTemp('cp_thumb_provider_test_');
  });

  tearDown(() async {
    if (await tempDir.exists()) {
      await tempDir.delete(recursive: true);
    }
  });

  test('thumbnailProgressProvider starts preheat automatically when session items are added', () async {
    // Generate two sample images
    final img1 = img.Image(width: 100, height: 100);
    img.fill(img1, color: img.ColorRgb8(255, 0, 0));
    final file1 = File(p.join(tempDir.path, 'img1.png'))..writeAsBytesSync(img.encodePng(img1));

    final img2 = img.Image(width: 100, height: 100);
    img.fill(img2, color: img.ColorRgb8(0, 255, 0));
    final file2 = File(p.join(tempDir.path, 'img2.jpg'))..writeAsBytesSync(img.encodeJpg(img2));

    final container = ProviderContainer();
    addTearDown(container.dispose);

    // Initial state is idle
    final initial = container.read(thumbnailProgressProvider);
    expect(initial.isGenerating, isFalse);
    expect(initial.total, equals(0));

    // Add items to session
    container.read(sessionProvider.notifier).addItems([
      SharedItem(
        name: 'img1.png',
        path: file1.path,
        sizeBytes: file1.lengthSync(),
        isDirectory: false,
        mimeType: 'image/png',
      ),
      SharedItem(
        name: 'img2.jpg',
        path: file2.path,
        sizeBytes: file2.lengthSync(),
        isDirectory: false,
        mimeType: 'image/jpeg',
      ),
    ]);

    // Give microtasks and preheat time to execute
    // Wait until preheating completes
    var attempts = 0;
    while (attempts < 50) {
      await Future.delayed(const Duration(milliseconds: 50));
      final current = container.read(thumbnailProgressProvider);
      if (current.isDone && current.completed == 2) {
        break;
      }
      attempts++;
    }

    final finalState = container.read(thumbnailProgressProvider);
    expect(finalState.isDone, isTrue);
    expect(finalState.completed, equals(2));
    expect(finalState.total, equals(2));
    expect(finalState.progress, equals(1.0));
    expect(finalState.percent, equals(100));
  });

  test('thumbnailProgressProvider resets on session clear', () async {
    final container = ProviderContainer();
    addTearDown(container.dispose);

    container.read(sessionProvider.notifier).addItems([
      const SharedItem(
        name: 'test.png',
        path: '/tmp/test.png',
        sizeBytes: 100,
        isDirectory: false,
        mimeType: 'image/png',
      ),
    ]);

    container.read(sessionProvider.notifier).clearItems();
    final state = container.read(thumbnailProgressProvider);
    expect(state.completed, equals(0));
    expect(state.total, equals(0));
  });
}
