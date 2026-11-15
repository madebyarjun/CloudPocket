import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:isolate';
import 'dart:typed_data';
import 'package:crypto/crypto.dart';
import 'package:image/image.dart' as img;
import 'package:path/path.dart' as p;
import 'package:cloud_pocket/models/share_session.dart';

/// High-speed thumbnail generation service with isolate execution, concurrency queue, and on-disk caching.
class ThumbnailService {
  static final ThumbnailService _instance = ThumbnailService._internal();
  factory ThumbnailService() => _instance;

  final Directory cacheDir;
  int _activeWorkers = 0;
  final List<Completer<void>> _waitQueue = [];
  final Map<String, Future<File?>> _inFlight = {};

  ThumbnailService._internal({Directory? customCacheDir})
      : cacheDir = customCacheDir ?? Directory(p.join(Directory.systemTemp.path, 'cloudpocket_thumbs')) {
    if (!cacheDir.existsSync()) {
      try {
        cacheDir.createSync(recursive: true);
      } catch (_) {}
    }
  }

  /// Testing constructor allowing custom temporary directory
  ThumbnailService.withDirectory(Directory directory) : cacheDir = directory {
    if (!cacheDir.existsSync()) {
      cacheDir.createSync(recursive: true);
    }
  }

  static const _supportedExtensions = {
    '.jpg',
    '.jpeg',
    '.png',
    '.webp',
    '.gif',
    '.bmp',
    '.ico',
    '.tga',
    '.tiff',
    '.tif',
  };

  /// Standard default thumbnail dimension in pixels (width/height bounded)
  static const int defaultSize = 512;

  /// Concurrency limiter ensuring at most maxConcurrent CPU-intensive image decodes run simultaneously
  Future<T> _runWithLimit<T>(Future<T> Function() task, {int maxConcurrent = 2}) async {
    while (_activeWorkers >= maxConcurrent) {
      final completer = Completer<void>();
      _waitQueue.add(completer);
      await completer.future;
    }
    _activeWorkers++;
    try {
      return await task();
    } finally {
      _activeWorkers--;
      if (_waitQueue.isNotEmpty) {
        _waitQueue.removeAt(0).complete();
      }
    }
  }

  /// Checks if the file is an image format that can be processed into a thumbnail
  static bool isSupportedImage(String filename) {
    final ext = p.extension(filename).toLowerCase();
    return _supportedExtensions.contains(ext);
  }

  /// Generates a cache key based on file path, last modified timestamp, file size, and target thumbnail size
  String getCacheKey(File file, FileStat stat, int size) {
    final raw = '${file.path}_${stat.modified.millisecondsSinceEpoch}_${stat.size}_$size';
    return md5.convert(utf8.encode(raw)).toString();
  }

  /// Generates or retrieves a cached thumbnail file.
  /// Deduplicates parallel requests and runs through concurrency queue.
  Future<File?> getThumbnail(File sourceFile, {int size = defaultSize}) async {
    if (!await sourceFile.exists()) return null;
    if (!isSupportedImage(sourceFile.path)) return null;

    final stat = await sourceFile.stat();
    final cacheKey = getCacheKey(sourceFile, stat, size);
    final cachedFile = File(p.join(cacheDir.path, '$cacheKey.jpg'));

    if (await cachedFile.exists()) {
      return cachedFile;
    }

    // If standard defaultSize was already preheated and cached on disk, reuse it directly!
    if (size != defaultSize) {
      final defaultKey = getCacheKey(sourceFile, stat, defaultSize);
      final defaultCachedFile = File(p.join(cacheDir.path, '$defaultKey.jpg'));
      if (await defaultCachedFile.exists()) {
        return defaultCachedFile;
      }
    }

    // Deduplicate in-flight requests for the exact same file/size
    if (_inFlight.containsKey(cacheKey)) {
      return await _inFlight[cacheKey];
    }

    final future = _runWithLimit(() async {
      try {
        final sourcePath = sourceFile.path;
        final thumbnailBytes = await Isolate.run(() => _resizeImageWorker(sourcePath, size));
        if (thumbnailBytes == null || thumbnailBytes.isEmpty) {
          return null;
        }

        await cachedFile.writeAsBytes(thumbnailBytes, flush: true);
        return cachedFile;
      } catch (_) {
        return null;
      }
    });

    _inFlight[cacheKey] = future;
    try {
      return await future;
    } finally {
      _inFlight.remove(cacheKey);
    }
  }

  /// Synchronously returns cached thumbnail file if already on disk, without triggering isolate generation.
  File? getCachedThumbnailSync(File sourceFile, {int size = defaultSize}) {
    if (!sourceFile.existsSync()) return null;
    if (!isSupportedImage(sourceFile.path)) return null;

    try {
      final stat = sourceFile.statSync();
      final cacheKey = getCacheKey(sourceFile, stat, size);
      final cachedFile = File(p.join(cacheDir.path, '$cacheKey.jpg'));
      if (cachedFile.existsSync()) {
        return cachedFile;
      }

      if (size != defaultSize) {
        final defaultKey = getCacheKey(sourceFile, stat, defaultSize);
        final defaultFile = File(p.join(cacheDir.path, '$defaultKey.jpg'));
        if (defaultFile.existsSync()) {
          return defaultFile;
        }
      }
    } catch (_) {}
    return null;
  }

  /// Asynchronously returns cached thumbnail file if already on disk, without triggering isolate generation.
  Future<File?> getCachedThumbnail(File sourceFile, {int size = defaultSize}) async {
    if (!await sourceFile.exists()) return null;
    if (!isSupportedImage(sourceFile.path)) return null;

    try {
      final stat = await sourceFile.stat();
      final cacheKey = getCacheKey(sourceFile, stat, size);
      final cachedFile = File(p.join(cacheDir.path, '$cacheKey.jpg'));
      if (await cachedFile.exists()) {
        return cachedFile;
      }

      if (size != defaultSize) {
        final defaultKey = getCacheKey(sourceFile, stat, defaultSize);
        final defaultFile = File(p.join(cacheDir.path, '$defaultKey.jpg'));
        if (await defaultFile.exists()) {
          return defaultFile;
        }
      }
    } catch (_) {}
    return null;
  }

  /// Discovers all image files in shared items (including inside shared directories)
  /// and pre-heats thumbnails in the background before sharing begins.
  Future<void> preheatItems(
    List<SharedItem> items, {
    int size = defaultSize,
    void Function(int completed, int total, String currentFile)? onProgress,
    bool Function()? isCancelled,
    int maxFolderDepth = 10,
    int? maxImages,
  }) async {
    final imageFiles = <File>[];
    final seenPaths = <String>{};

    for (final item in items) {
      if (isCancelled?.call() == true) return;
      if (!item.isDirectory) {
        if (isSupportedImage(item.path) && seenPaths.add(item.path)) {
          imageFiles.add(File(item.path));
          if (maxImages != null && imageFiles.length >= maxImages) break;
        }
      } else {
        final dir = Directory(item.path);
        if (dir.existsSync()) {
          try {
            await for (final entity in dir.list(recursive: maxFolderDepth > 1, followLinks: false)) {
              if (isCancelled?.call() == true) return;
              if (entity is File && isSupportedImage(entity.path) && seenPaths.add(entity.path)) {
                imageFiles.add(entity);
                if (maxImages != null && imageFiles.length >= maxImages) break;
              }
            }
          } catch (_) {}
        }
      }
      if (maxImages != null && imageFiles.length >= maxImages) break;
    }

    if (imageFiles.isEmpty) {
      onProgress?.call(0, 0, '');
      return;
    }

    final total = imageFiles.length;
    var completed = 0;

    // Check existing cached files first without spawning isolates
    for (final file in List<File>.from(imageFiles)) {
      if (isCancelled?.call() == true) return;
      final cached = await getCachedThumbnail(file, size: size);
      if (cached != null) {
        completed++;
        onProgress?.call(completed, total, p.basename(file.path));
        imageFiles.remove(file);
      }
    }

    if (imageFiles.isEmpty || isCancelled?.call() == true) {
      return;
    }

    // Process remaining images through concurrency-limited isolate workers
    await Future.wait(imageFiles.map((file) async {
      if (isCancelled?.call() == true) return;
      final filename = p.basename(file.path);
      try {
        await getThumbnail(file, size: size);
      } catch (_) {}
      completed++;
      if (isCancelled?.call() != true) {
        onProgress?.call(completed, total, filename);
      }
    }));
  }

  /// Top-level or static isolate worker function using high-fidelity cubic interpolation and 85 quality
  static Uint8List? _resizeImageWorker(String path, int size) {
    try {
      final file = File(path);
      if (!file.existsSync()) return null;

      final rawBytes = file.readAsBytesSync();
      final decoded = img.decodeImage(rawBytes);
      if (decoded == null) return null;

      int targetW;
      int targetH;
      if (decoded.width >= decoded.height) {
        targetW = size;
        targetH = (decoded.height * size / decoded.width).round().clamp(1, size);
      } else {
        targetH = size;
        targetW = (decoded.width * size / decoded.height).round().clamp(1, size);
      }

      // High-quality cubic interpolation avoids jaggies and pixelation
      final resized = img.copyResize(
        decoded,
        width: targetW,
        height: targetH,
        interpolation: img.Interpolation.cubic,
      );
      // Quality 85: sharp, crisp, vibrant output while staying lightweight (~35-60 KB)
      final encoded = img.encodeJpg(resized, quality: 85);
      return Uint8List.fromList(encoded);
    } catch (_) {
      return null;
    }
  }

  /// Evicts old cache entries exceeding maxAgeDays or total cache size limit
  Future<void> cleanCache({int maxAgeDays = 7, int maxCacheSizeBytes = 50 * 1024 * 1024}) async {
    if (!await cacheDir.exists()) return;

    try {
      var totalBytes = 0;
      final files = <File>[];

      await for (final entity in cacheDir.list(followLinks: false)) {
        if (entity is File && entity.path.endsWith('.jpg')) {
          final stat = await entity.stat();
          final age = DateTime.now().difference(stat.modified);
          if (age.inDays > maxAgeDays) {
            await entity.delete();
          } else {
            totalBytes += stat.size;
            files.add(entity);
          }
        }
      }

      if (totalBytes > maxCacheSizeBytes) {
        files.sort((a, b) => a.statSync().modified.compareTo(b.statSync().modified));
        for (final file in files) {
          if (totalBytes <= maxCacheSizeBytes) break;
          final size = (await file.stat()).size;
          await file.delete();
          totalBytes -= size;
        }
      }
    } catch (_) {}
  }
}
