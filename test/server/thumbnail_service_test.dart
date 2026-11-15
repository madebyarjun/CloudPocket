import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:path/path.dart' as p;
import 'package:shelf/shelf.dart';
import 'package:cloud_pocket/models/share_session.dart';
import 'package:cloud_pocket/server/file_handler.dart';
import 'package:cloud_pocket/server/thumbnail_service.dart';

void main() {
  late Directory tempDir;
  late Directory cacheDir;
  late ThumbnailService thumbnailService;

  setUp(() async {
    tempDir = await Directory.systemTemp.createTemp('cp_thumb_test_');
    cacheDir = Directory(p.join(tempDir.path, 'cache'));
    await cacheDir.create(recursive: true);
    thumbnailService = ThumbnailService.withDirectory(cacheDir);
  });

  tearDown(() async {
    if (await tempDir.exists()) {
      await tempDir.delete(recursive: true);
    }
  });

  group('ThumbnailService Unit Tests', () {
    test('isSupportedImage correctly identifies image file extensions', () {
      expect(ThumbnailService.isSupportedImage('photo.jpg'), isTrue);
      expect(ThumbnailService.isSupportedImage('photo.JPEG'), isTrue);
      expect(ThumbnailService.isSupportedImage('photo.png'), isTrue);
      expect(ThumbnailService.isSupportedImage('photo.webp'), isTrue);
      expect(ThumbnailService.isSupportedImage('doc.pdf'), isFalse);
      expect(ThumbnailService.isSupportedImage('archive.zip'), isFalse);
      expect(ThumbnailService.isSupportedImage('video.mp4'), isFalse);
    });

    test('getThumbnail generates and caches downscaled JPEG', () async {
      // Create a test 800x600 PNG image
      final testImage = img.Image(width: 800, height: 600);
      img.fill(testImage, color: img.ColorRgb8(255, 0, 0));
      final sourceFile = File(p.join(tempDir.path, 'sample.png'));
      await sourceFile.writeAsBytes(img.encodePng(testImage));

      final thumbFile = await thumbnailService.getThumbnail(sourceFile, size: 256);
      expect(thumbFile, isNotNull);
      expect(await thumbFile!.exists(), isTrue);

      // Verify decoded thumbnail dimensions
      final thumbBytes = await thumbFile.readAsBytes();
      final decodedThumb = img.decodeJpg(thumbBytes);
      expect(decodedThumb, isNotNull);
      expect(decodedThumb!.width, equals(256));
      expect(decodedThumb.height, equals(192)); // 800:600 -> 256:192

      // Second call should return cached file immediately
      final cachedThumb = await thumbnailService.getThumbnail(sourceFile, size: 256);
      expect(cachedThumb!.path, equals(thumbFile.path));
    });

    test('cleanCache removes files older than maxAgeDays', () async {
      final oldFile = File(p.join(cacheDir.path, 'old_thumb.jpg'));
      await oldFile.writeAsString('dummy');
      // Set modification time to 10 days ago
      final tenDaysAgo = DateTime.now().subtract(const Duration(days: 10));
      await oldFile.setLastModified(tenDaysAgo);

      final freshFile = File(p.join(cacheDir.path, 'fresh_thumb.jpg'));
      await freshFile.writeAsString('dummy');

      await thumbnailService.cleanCache(maxAgeDays: 7);
      expect(await oldFile.exists(), isFalse);
      expect(await freshFile.exists(), isTrue);
    });
  });

  group('FileHandler serveThumbnail Integration Tests', () {
    late File sharedImageFile;
    late ShareSession session;
    late FileHandler fileHandler;

    setUp(() async {
      final image = img.Image(width: 500, height: 500);
      img.fill(image, color: img.ColorRgb8(0, 255, 0));
      sharedImageFile = File(p.join(tempDir.path, 'wallpaper.jpg'));
      await sharedImageFile.writeAsBytes(img.encodeJpg(image));

      session = ShareSession(
        items: [
          SharedItem(
            name: 'wallpaper.jpg',
            path: sharedImageFile.path,
            sizeBytes: await sharedImageFile.length(),
            isDirectory: false,
            mimeType: 'image/jpeg',
          ),
        ],
      );

      fileHandler = FileHandler(
        session,
        thumbnailService: thumbnailService,
      );
    });

    test('serveThumbnail returns 400 when path parameter is missing', () async {
      final request = Request('GET', Uri.parse('http://localhost/api/thumbnail'));
      final response = await fileHandler.serveThumbnail(request);
      expect(response.statusCode, equals(400));
    });

    test('serveThumbnail returns 403 when requested file is outside shared scope', () async {
      final request = Request('GET', Uri.parse('http://localhost/api/thumbnail?path=../etc/passwd'));
      final response = await fileHandler.serveThumbnail(request);
      expect(response.statusCode, equals(403));
    });

    test('serveThumbnail returns 200 with cache-control and etag headers', () async {
      final request = Request('GET', Uri.parse('http://localhost/api/thumbnail?path=wallpaper.jpg&size=256'));
      final response = await fileHandler.serveThumbnail(request);

      expect(response.statusCode, equals(200));
      expect(response.headers['content-type'], equals('image/jpeg'));
      expect(response.headers['cache-control'], contains('public, max-age=604800'));
      expect(response.headers['etag'], isNotNull);

      final etag = response.headers['etag']!;

      // Second request with matching If-None-Match should return 304 Not Modified
      final conditionalRequest = Request(
        'GET',
        Uri.parse('http://localhost/api/thumbnail?path=wallpaper.jpg&size=256'),
        headers: {'if-none-match': etag},
      );
      final notModifiedResponse = await fileHandler.serveThumbnail(conditionalRequest);
      expect(notModifiedResponse.statusCode, equals(304));
      expect(notModifiedResponse.headers['etag'], equals(etag));
    });

    test('serveThumbnail returns 404 and does not stream full file on non-image file', () async {
      final docFile = File(p.join(tempDir.path, 'notes.txt'));
      await docFile.writeAsString('Confidential notes');

      final sessionWithDoc = ShareSession(
        items: [
          SharedItem(
            name: 'notes.txt',
            path: docFile.path,
            sizeBytes: await docFile.length(),
            isDirectory: false,
            mimeType: 'text/plain',
          ),
        ],
      );

      final handler = FileHandler(
        sessionWithDoc,
        thumbnailService: thumbnailService,
      );

      final request = Request('GET', Uri.parse('http://localhost/api/thumbnail?path=notes.txt'));
      final response = await handler.serveThumbnail(request);

      // Must return 404, not the full file!
      expect(response.statusCode, equals(404));
    });

    test('getThumbnail deduplicates in-flight parallel requests for same file', () async {
      final testImage = img.Image(width: 400, height: 300);
      img.fill(testImage, color: img.ColorRgb8(0, 255, 0));
      final sourceFile = File(p.join(tempDir.path, 'parallel.png'));
      await sourceFile.writeAsBytes(img.encodePng(testImage));

      // Fire 3 simultaneous requests for the same un-cached image
      final futures = [
        thumbnailService.getThumbnail(sourceFile, size: 200),
        thumbnailService.getThumbnail(sourceFile, size: 200),
        thumbnailService.getThumbnail(sourceFile, size: 200),
      ];

      final results = await Future.wait(futures);
      expect(results[0], isNotNull);
      expect(results[1]!.path, equals(results[0]!.path));
      expect(results[2]!.path, equals(results[0]!.path));
    });

    test('preheatItems pre-caches thumbnails and reports progress', () async {
      final img1 = img.Image(width: 300, height: 300);
      img.fill(img1, color: img.ColorRgb8(10, 20, 30));
      final file1 = File(p.join(tempDir.path, 'preheat1.png'));
      await file1.writeAsBytes(img.encodePng(img1));

      final img2 = img.Image(width: 300, height: 300);
      img.fill(img2, color: img.ColorRgb8(40, 50, 60));
      final file2 = File(p.join(tempDir.path, 'preheat2.jpg'));
      await file2.writeAsBytes(img.encodeJpg(img2));

      final progressUpdates = <int>[];
      await thumbnailService.preheatItems(
        [
          SharedItem(
            name: 'preheat1.png',
            path: file1.path,
            sizeBytes: await file1.length(),
            isDirectory: false,
            mimeType: 'image/png',
          ),
          SharedItem(
            name: 'preheat2.jpg',
            path: file2.path,
            sizeBytes: await file2.length(),
            isDirectory: false,
            mimeType: 'image/jpeg',
          ),
        ],
        onProgress: (done, total, cur) {
          progressUpdates.add(done);
        },
      );

      expect(progressUpdates.contains(2), isTrue);

      // Verify thumbnails are available synchronously without isolate run
      final cached1 = thumbnailService.getCachedThumbnailSync(file1);
      final cached2 = thumbnailService.getCachedThumbnailSync(file2);
      expect(cached1, isNotNull);
      expect(cached2, isNotNull);
      expect(await cached1!.exists(), isTrue);
      expect(await cached2!.exists(), isTrue);

      // Requesting size 200 should reuse default preheated thumbnail
      final reused = await thumbnailService.getThumbnail(file1, size: 200);
      expect(reused, isNotNull);
      expect(reused!.path, equals(cached1.path));
    });

    test('preheatItems discovers images inside shared folder', () async {
      final subFolder = Directory(p.join(tempDir.path, 'album'))..createSync();
      final innerImg = img.Image(width: 200, height: 200);
      img.fill(innerImg, color: img.ColorRgb8(200, 100, 50));
      final innerFile = File(p.join(subFolder.path, 'photo.jpg'));
      await innerFile.writeAsBytes(img.encodeJpg(innerImg));

      var reportedDone = 0;
      await thumbnailService.preheatItems(
        [
          SharedItem(
            name: 'album',
            path: subFolder.path,
            sizeBytes: await innerFile.length(),
            isDirectory: true,
            mimeType: 'inode/directory',
          ),
        ],
        onProgress: (done, total, cur) {
          reportedDone = done;
        },
      );

      expect(reportedDone, equals(1));
      expect(thumbnailService.getCachedThumbnailSync(innerFile), isNotNull);
    });
  });
}

