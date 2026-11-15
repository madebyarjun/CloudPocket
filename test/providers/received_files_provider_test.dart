import 'package:flutter_test/flutter_test.dart';
import 'package:cloud_pocket/providers/received_files_provider.dart';

void main() {
  group('ReceivedFileItem and ReceivedFilesState Unit Tests', () {
    test('correctly identifies image extensions for thumbnails', () {
      final jpgItem = ReceivedFileItem(
        path: '/storage/downloads/photo.jpg',
        name: 'photo.jpg',
        sizeBytes: 1024 * 1024 * 2, // 2 MB
        modified: DateTime.now(),
      );

      final pngItem = ReceivedFileItem(
        path: '/storage/downloads/screen.png',
        name: 'screen.png',
        sizeBytes: 500 * 1024,
        modified: DateTime.now(),
      );

      final webpItem = ReceivedFileItem(
        path: '/storage/downloads/image.webp',
        name: 'image.webp',
        sizeBytes: 300 * 1024,
        modified: DateTime.now(),
      );

      final pdfItem = ReceivedFileItem(
        path: '/storage/downloads/report.pdf',
        name: 'report.pdf',
        sizeBytes: 1024 * 1024,
        modified: DateTime.now(),
      );

      final mp4Item = ReceivedFileItem(
        path: '/storage/downloads/clip.mp4',
        name: 'clip.mp4',
        sizeBytes: 1024 * 1024 * 10,
        modified: DateTime.now(),
      );

      expect(jpgItem.isImage, isTrue);
      expect(pngItem.isImage, isTrue);
      expect(webpItem.isImage, isTrue);
      expect(pdfItem.isImage, isFalse);
      expect(mp4Item.isImage, isFalse);
      expect(pdfItem.isDocument, isTrue);
      expect(mp4Item.isVideo, isTrue);
    });

    test('formats file sizes accurately', () {
      final smallItem = ReceivedFileItem(
        path: '/test/small.txt',
        name: 'small.txt',
        sizeBytes: 512,
        modified: DateTime.now(),
      );
      expect(smallItem.formattedSize, '512 B');

      final kbItem = ReceivedFileItem(
        path: '/test/kb.txt',
        name: 'kb.txt',
        sizeBytes: 2048,
        modified: DateTime.now(),
      );
      expect(kbItem.formattedSize, '2.0 KB');

      final mbItem = ReceivedFileItem(
        path: '/test/mb.bin',
        name: 'mb.bin',
        sizeBytes: 5 * 1024 * 1024,
        modified: DateTime.now(),
      );
      expect(mbItem.formattedSize, '5.0 MB');
    });

    test('computes ReceivedFilesState metrics correctly', () {
      final files = [
        ReceivedFileItem(path: '/a', name: 'a.jpg', sizeBytes: 1000, modified: DateTime.now()),
        ReceivedFileItem(path: '/b', name: 'b.png', sizeBytes: 2000, modified: DateTime.now()),
      ];

      final state = ReceivedFilesState(
        files: files,
        directoryPath: '/test/dir',
      );

      expect(state.totalCount, 2);
      expect(state.totalBytes, 3000);
      expect(state.formattedTotalSize, '2.9 KB');
    });
  });
}
