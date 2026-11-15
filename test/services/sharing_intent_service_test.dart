import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:cloud_pocket/providers/session_provider.dart';
import 'package:cloud_pocket/services/sharing_intent_service.dart';
import 'package:cloud_pocket/ui/app_shell.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late ProviderContainer container;
  late Directory tempDir;
  late File sampleImage;
  late File samplePdf;

  setUp(() async {
    container = ProviderContainer();
    tempDir = await Directory.systemTemp.createTemp('sharing_intent_test_');
    sampleImage = File('${tempDir.path}/photo.jpg');
    await sampleImage.writeAsBytes(List.filled(1024 * 10, 0)); // 10 KB
    samplePdf = File('${tempDir.path}/document.pdf');
    await samplePdf.writeAsBytes(List.filled(1024 * 5, 0)); // 5 KB
  });

  tearDown(() async {
    container.dispose();
    if (await tempDir.exists()) {
      await tempDir.delete(recursive: true);
    }
  });

  test('processSharedData adds shared files, sets Send Mode, and navigates to Home tab', () {
    // Start in Receive Mode and on Settings Tab (index 4)
    container.read(sessionProvider.notifier).setIsReceiveMode(true);
    container.read(activeTabProvider.notifier).state = 4;
    expect(container.read(sessionProvider).isReceiveMode, isTrue);
    expect(container.read(activeTabProvider), 4);
    expect(container.read(sessionProvider).items, isEmpty);

    SharingIntentService.processSharedData(
      setIsReceiveMode: (val) => container.read(sessionProvider.notifier).setIsReceiveMode(val),
      addItems: (items) => container.read(sessionProvider.notifier).addItems(items),
      setActiveTab: (tab) => container.read(activeTabProvider.notifier).state = tab,
      setSharedText: (text) => container.read(sessionProvider.notifier).setSharedText(text),
      showFeedback: false,
      data: {
        'files': [sampleImage.path, samplePdf.path],
        'text': 'Check out these files',
      },
    );

    // Verify Send Mode is restored
    final session = container.read(sessionProvider);
    expect(session.isReceiveMode, isFalse);

    // Verify files were converted to SharedItems with proper metadata
    expect(session.items.length, 2);
    expect(session.items[0].name, 'photo.jpg');
    expect(session.items[0].mimeType, 'image/jpeg');
    expect(session.items[0].sizeBytes, 1024 * 10);
    expect(session.items[1].name, 'document.pdf');
    expect(session.items[1].mimeType, 'application/pdf');
    expect(session.items[1].sizeBytes, 1024 * 5);

    // Verify shared note text
    expect(session.sharedText, 'Check out these files');

    // Verify active tab switched to Home (0)
    expect(container.read(activeTabProvider), 0);
  });

  test('processSharedData handles text-only shares correctly', () {
    container.read(activeTabProvider.notifier).state = 2;

    SharingIntentService.processSharedData(
      setIsReceiveMode: (val) => container.read(sessionProvider.notifier).setIsReceiveMode(val),
      addItems: (items) => container.read(sessionProvider.notifier).addItems(items),
      setActiveTab: (tab) => container.read(activeTabProvider.notifier).state = tab,
      setSharedText: (text) => container.read(sessionProvider.notifier).setSharedText(text),
      showFeedback: false,
      data: {
        'text': 'https://cloudpocket.app/shared-note',
      },
    );

    final session = container.read(sessionProvider);
    expect(session.items, isEmpty);
    expect(session.sharedText, 'https://cloudpocket.app/shared-note');
    expect(container.read(activeTabProvider), 0);
  });
}
