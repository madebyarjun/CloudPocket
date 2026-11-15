import 'dart:convert';
import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:shelf/shelf.dart';
import 'package:cloud_pocket/models/share_session.dart';
import 'package:cloud_pocket/providers/session_provider.dart';
import 'package:cloud_pocket/providers/received_files_provider.dart';
import 'package:cloud_pocket/server/file_handler.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  group('ShareSession Receive Mode & Tunnel Toggle Tests', () {
    test('ShareSession defaults isReceiveMode to false and enableTunnel to true', () {
      const session = ShareSession();
      expect(session.isReceiveMode, isFalse);
      expect(session.enableTunnel, isTrue);
      expect(session.allowUploads, isFalse);
    });

    test('ShareSession copyWith updates isReceiveMode and automatically activates allowUploads', () {
      const session = ShareSession();
      final receiveSession = session.copyWith(isReceiveMode: true);
      expect(receiveSession.isReceiveMode, isTrue);
      expect(receiveSession.allowUploads, isTrue);

      final sendSession = receiveSession.copyWith(isReceiveMode: false, allowUploads: false);
      expect(sendSession.isReceiveMode, isFalse);
      expect(sendSession.allowUploads, isFalse);
    });

    test('ShareSession copyWith toggles enableTunnel', () {
      const session = ShareSession();
      final localOnly = session.copyWith(enableTunnel: false);
      expect(localOnly.enableTunnel, isFalse);

      final withTunnel = localOnly.copyWith(enableTunnel: true);
      expect(withTunnel.enableTunnel, isTrue);
    });
  });

  group('SessionNotifier Receive Mode & Tunnel Toggle Provider Tests', () {
    test('setIsReceiveMode updates state and enables uploads', () {
      final container = ProviderContainer();
      addTearDown(container.dispose);

      final notifier = container.read(sessionProvider.notifier);
      expect(container.read(sessionProvider).isReceiveMode, isFalse);
      expect(container.read(sessionProvider).allowUploads, isFalse);

      notifier.setIsReceiveMode(true);
      expect(container.read(sessionProvider).isReceiveMode, isTrue);
      expect(container.read(sessionProvider).allowUploads, isTrue);

      // Ensure setIsDisposableRoom(false) never clobbers isReceiveMode
      notifier.setIsDisposableRoom(false);
      expect(container.read(sessionProvider).isReceiveMode, isTrue);

      notifier.setIsReceiveMode(false);
      expect(container.read(sessionProvider).isReceiveMode, isFalse);
    });

    test('setIsReceiveMode clears items to prevent residual file sharing in Receive Mode', () {
      final container = ProviderContainer();
      addTearDown(container.dispose);

      final notifier = container.read(sessionProvider.notifier);
      // Select files in Send Mode
      notifier.addItems([
        const SharedItem(path: '/dummy/photo.jpg', name: 'photo.jpg', sizeBytes: 1024, isDirectory: false, mimeType: 'image/jpeg'),
      ]);
      expect(container.read(sessionProvider).items.length, 1);

      // Switching to Receive Mode clears items
      notifier.setIsReceiveMode(true);
      expect(container.read(sessionProvider).isReceiveMode, isTrue);
      expect(container.read(sessionProvider).items.isEmpty, isTrue);
    });

    test('FileHandler.listFiles in Receive Mode returns empty items and allowUploads true', () async {
      const receiveSession = ShareSession(
        isReceiveMode: true,
        allowUploads: true,
        items: [
          SharedItem(path: '/dummy/leaked.png', name: 'leaked.png', sizeBytes: 2048, isDirectory: false, mimeType: 'image/png'),
        ],
      );
      final handler = FileHandler(receiveSession);
      final req = Request('GET', Uri.parse('http://localhost:8080/api/files'));
      final res = handler.listFiles(req);

      expect(res.statusCode, 200);
      final body = await res.readAsString();
      final json = jsonDecode(body) as Map<String, dynamic>;
      expect(json['items'], isEmpty);
      expect(json['allowUploads'], isTrue);
      expect(json['isReceiveMode'], isTrue);
    });

    test('setEnableTunnel toggles tunnel on and off', () {
      final container = ProviderContainer();
      addTearDown(container.dispose);

      final notifier = container.read(sessionProvider.notifier);
      expect(container.read(sessionProvider).enableTunnel, isTrue);

      notifier.setEnableTunnel(false);
      expect(container.read(sessionProvider).enableTunnel, isFalse);

      notifier.setEnableTunnel(true);
      expect(container.read(sessionProvider).enableTunnel, isTrue);
    });
  });

  group('ReceivedFileItem Model Tests', () {
    test('extension and category checks identify types accurately', () {
      final img = ReceivedFileItem(
        path: '/storage/photo.jpg',
        name: 'photo.jpg',
        sizeBytes: 1024 * 500, // 500 KB
        modified: DateTime(2026, 9, 21),
      );
      expect(img.extension, '.jpg');
      expect(img.isImage, isTrue);
      expect(img.isVideo, isFalse);
      expect(img.formattedSize, '500.0 KB');

      final vid = ReceivedFileItem(
        path: '/storage/clip.mp4',
        name: 'clip.mp4',
        sizeBytes: 1024 * 1024 * 25, // 25 MB
        modified: DateTime(2026, 9, 21),
      );
      expect(vid.isVideo, isTrue);
      expect(vid.formattedSize, '25.0 MB');

      final doc = ReceivedFileItem(
        path: '/storage/report.pdf',
        name: 'report.pdf',
        sizeBytes: 1024 * 1024 * 1024 * 2, // 2 GB
        modified: DateTime(2026, 9, 21),
      );
      expect(doc.isDocument, isTrue);
      expect(doc.formattedSize, '2.00 GB');

      final zip = ReceivedFileItem(
        path: '/storage/bundle.zip',
        name: 'bundle.zip',
        sizeBytes: 256, // 256 B
        modified: DateTime(2026, 9, 21),
      );
      expect(zip.isArchive, isTrue);
      expect(zip.formattedSize, '256 B');
    });

    test('ReceivedFilesState calculates totalCount and formattedTotalSize correctly', () {
      final files = [
        ReceivedFileItem(
          path: '/file1.jpg',
          name: 'file1.jpg',
          sizeBytes: 1024 * 1024 * 5, // 5 MB
          modified: DateTime.now(),
        ),
        ReceivedFileItem(
          path: '/file2.mp4',
          name: 'file2.mp4',
          sizeBytes: 1024 * 1024 * 10, // 10 MB
          modified: DateTime.now(),
        ),
      ];

      final state = ReceivedFilesState(files: files);
      expect(state.totalCount, 2);
      expect(state.totalBytes, 1024 * 1024 * 15);
      expect(state.formattedTotalSize, '15.0 MB');
    });
  });

  group('ReceivedFilesNotifier Delete File Test', () {
    test('deleteFile removes file and updates state', () async {
      final tempDir = await Directory.systemTemp.createTemp('cloudpocket_test_');
      final testFile = File('${tempDir.path}/uploaded_test.txt');
      await testFile.writeAsString('hello received file');

      expect(await testFile.exists(), isTrue);

      final container = ProviderContainer();
      addTearDown(() async {
        container.dispose();
        if (await tempDir.exists()) {
          await tempDir.delete(recursive: true);
        }
      });

      final notifier = container.read(receivedFilesProvider.notifier);
      final deleted = await notifier.deleteFile(testFile.path);
      expect(deleted, isTrue);
      expect(await testFile.exists(), isFalse);
    });
  });
}
