import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:mime/mime.dart';
import 'package:path/path.dart' as p;
import 'package:shelf/shelf.dart';
import 'package:cloud_pocket/models/share_session.dart';
import 'package:cloud_pocket/server/thumbnail_service.dart';
import 'package:cloud_pocket/server/vault_tracker.dart';
import 'package:cloud_pocket/server/zip_streamer.dart';

class FileHandler {
  final ShareSession session;
  final VaultTracker? vaultTracker;
  final ThumbnailService thumbnailService;
  final void Function(String filename, int bytesWritten, int totalBytes)? onProgress;
  final void Function(int bytesSent)? onChunkSent;
  final Future<void> Function(String filename)? pauseChecker;
  final void Function(String filename)? onTransferStarted;

  FileHandler(
    this.session, {
    this.vaultTracker,
    this.onProgress,
    this.onChunkSent,
    this.pauseChecker,
    this.onTransferStarted,
    ThumbnailService? thumbnailService,
  }) : thumbnailService = thumbnailService ?? ThumbnailService();

  /// Return JSON list of shared items
  Response listFiles(Request request) {
    if (session.isReceiveMode || session.isDisposableRoom) {
      return Response.ok(
        jsonEncode({
          'items': [],
          'allowUploads': !session.isDisposableRoom,
          'isVaultMode': false,
          'isReceiveMode': session.isReceiveMode,
        }),
        headers: {'content-type': 'application/json'},
      );
    }

    final rawSubpath = request.url.queryParameters['subpath'] ?? '';
    final subpath = rawSubpath.trim().replaceAll('\\', '/').replaceAll(RegExp(r'^/+|/+$'), '');
    final resultList = <Map<String, dynamic>>[];

    final isSingleFolderShare = session.items.length == 1 && session.items.first.isDirectory;

    if (subpath.isEmpty) {
      // If a single folder is shared, expand its contents immediately so clients see files right away
      if (isSingleFolderShare) {
        final singleDirItem = session.items.first;
        final targetDir = Directory(p.normalize(singleDirItem.path));
        if (targetDir.existsSync()) {
          try {
            final entities = targetDir.listSync(followLinks: false);
            for (final entity in entities) {
              if (entity is Link) continue;
              try {
                final name = p.basename(entity.path);
                if (name.startsWith('.')) continue; // Skip hidden/system files
                final stat = entity.statSync();
                final isDir = entity is Directory;
                final mimeType = isDir ? 'inode/directory' : (lookupMimeType(name) ?? 'application/octet-stream');

                final itemMap = <String, dynamic>{
                  'path': name,
                  'name': name,
                  'size': isDir ? 0 : stat.size,
                  'isDirectory': isDir,
                  'mimeType': mimeType,
                };
                if (vaultTracker != null && !isDir) {
                  itemMap['remainingDownloads'] = vaultTracker!.getRemainingDownloads(entity.path);
                }
                resultList.add(itemMap);
              } catch (_) {}
            }
            return Response.ok(
              jsonEncode({
                'items': resultList,
                'allowUploads': session.allowUploads,
                'isVaultMode': session.isVaultMode,
                'folderName': singleDirItem.name,
                'isSingleFolderShare': true,
              }),
              headers: {'content-type': 'application/json'},
            );
          } catch (_) {
            // Fall back to listing the container item if listSync fails
          }
        }
      }

      // Top-level items chosen by user (multi-item share)
      for (final item in session.items) {
        final json = item.toJson();
        if (vaultTracker != null && !item.isDirectory) {
          json['remainingDownloads'] = vaultTracker!.getRemainingDownloads(item.path);
        }
        resultList.add(json);
      }
      return Response.ok(
        jsonEncode({
          'items': resultList,
          'allowUploads': session.allowUploads,
          'isVaultMode': session.isVaultMode,
        }),
        headers: {'content-type': 'application/json'},
      );
    }

    // Navigating into a shared folder
    final resolvedDir = _resolveAllowedDirectory(subpath);
    if (resolvedDir == null || !resolvedDir.existsSync()) {
      return Response(404, body: jsonEncode({'error': 'Directory not found'}), headers: {'content-type': 'application/json'});
    }

    try {
      final entities = resolvedDir.listSync(followLinks: false);
      for (final entity in entities) {
        if (entity is Link) continue;
        try {
          final name = p.basename(entity.path);
          if (name.startsWith('.')) continue; // Skip hidden files
          final stat = entity.statSync();
          final isDir = entity is Directory;
          final mimeType = isDir ? 'inode/directory' : (lookupMimeType(name) ?? 'application/octet-stream');

          final itemMap = <String, dynamic>{
            'path': p.join(subpath, name).replaceAll('\\', '/'),
            'name': name,
            'size': isDir ? 0 : stat.size,
            'isDirectory': isDir,
            'mimeType': mimeType,
          };

          if (vaultTracker != null && !isDir) {
            itemMap['remainingDownloads'] = vaultTracker!.getRemainingDownloads(entity.path);
          }

          resultList.add(itemMap);
        } catch (_) {}
      }
      return Response.ok(
        jsonEncode({
          'items': resultList,
          'allowUploads': session.allowUploads,
          'isVaultMode': session.isVaultMode,
        }),
        headers: {'content-type': 'application/json'},
      );
    } catch (e) {
      return Response(500, body: jsonEncode({'error': 'Cannot list directory: $e'}), headers: {'content-type': 'application/json'});
    }
  }

  /// Stream a single file with HTTP Range support
  Future<Response> serveFile(Request request, String requestedPath) async {
    final decodedPath = Uri.decodeComponent(requestedPath);
    final targetFile = _resolveAllowedFile(decodedPath);

    if (targetFile == null) {
      return Response(403, body: jsonEncode({'error': 'Access Denied: Path outside shared scope'}), headers: {'content-type': 'application/json'});
    }

    if (!await targetFile.exists()) {
      return Response(404, body: jsonEncode({'error': 'File not found'}), headers: {'content-type': 'application/json'});
    }

    // Check Vault Mode download limit
    if (vaultTracker != null && !vaultTracker!.canDownload(targetFile.path)) {
      return Response(
        410,
        body: jsonEncode({'error': 'VaultLimitReached', 'message': 'Download limit reached for this file'}),
        headers: {'content-type': 'application/json'},
      );
    }

    final stat = await targetFile.stat();
    final fileSize = stat.size;
    final filename = p.basename(targetFile.path);
    onTransferStarted?.call(filename);
    final mimeType = lookupMimeType(filename) ?? 'application/octet-stream';
    final etag = '"${stat.modified.millisecondsSinceEpoch}-$fileSize"';
    final lastModified = HttpDate.format(stat.modified.toUtc());
    final isExplicitDownload = request.url.queryParameters['download'] == '1';
    final activeDocument = const {'text/html', 'image/svg+xml', 'application/xhtml+xml', 'application/xml', 'text/xml'}.contains(mimeType);
    final dispositionType = isExplicitDownload || activeDocument ? 'attachment' : 'inline';

    // Parse Range header
    final rangeHeader = request.headers['range'];
    if (rangeHeader != null && rangeHeader.startsWith('bytes=')) {
      final response = _serveRangeRequest(
        request,
        targetFile,
        fileSize,
        mimeType,
        filename,
        rangeHeader,
        etag: etag,
        lastModified: lastModified,
        dispositionType: dispositionType,
      );
      if (response.statusCode == 206 && !(vaultTracker?.reserveDownloads([targetFile.path]) ?? true)) {
        return Response(410, body: 'Download limit reached for this file');
      }
      return response;
    }

    if (!(vaultTracker?.reserveDownloads([targetFile.path]) ?? true)) {
      return Response(410, body: 'Download limit reached for this file');
    }
    final stream = _streamFile(targetFile, fileSize, filename);

    return Response.ok(
      stream,
      headers: {
        'content-type': mimeType,
        'content-length': fileSize.toString(),
        'accept-ranges': 'bytes',
        'etag': etag,
        'last-modified': lastModified,
        'content-disposition': '$dispositionType; filename="$filename"',
      },
    );
  }

  /// Fast on-the-fly thumbnail delivery with HTTP 304 ETag caching
  Future<Response> serveThumbnail(Request request) async {
    final rawPath = request.url.queryParameters['path'];
    if (rawPath == null || rawPath.trim().isEmpty) {
      return Response(400, body: jsonEncode({'error': 'Missing path parameter'}), headers: {'content-type': 'application/json'});
    }

    final decodedPath = Uri.decodeComponent(rawPath);
    final targetFile = _resolveAllowedFile(decodedPath);

    if (targetFile == null) {
      return Response(403, body: jsonEncode({'error': 'Access Denied: Path outside shared scope'}), headers: {'content-type': 'application/json'});
    }

    if (!await targetFile.exists()) {
      return Response(404, body: jsonEncode({'error': 'File not found'}), headers: {'content-type': 'application/json'});
    }

    final sizeParam = int.tryParse(request.url.queryParameters['size'] ?? '256') ?? 256;
    final size = sizeParam.clamp(64, 1024);

    final stat = await targetFile.stat();
    final etag = '"${stat.modified.millisecondsSinceEpoch}-${stat.size}-$size"';

    // HTTP 304 Not Modified validation
    final ifNoneMatch = request.headers['if-none-match'];
    if (ifNoneMatch != null && ifNoneMatch == etag) {
      return Response(
        304,
        headers: {
          'etag': etag,
          'cache-control': 'public, max-age=604800, immutable',
        },
      );
    }

    // Generate or retrieve cached thumbnail
    final thumbFile = await thumbnailService.getThumbnail(targetFile, size: size);

    // If thumbnail could not be generated (e.g. non-image or decode failure), return 404
    // NEVER fall back to full original file here as that pulls 10MB+ over mobile tunnels for a single preview
    if (thumbFile == null || !await thumbFile.exists()) {
      return Response.notFound(
        jsonEncode({'error': 'Thumbnail not available'}),
        headers: {'content-type': 'application/json'},
      );
    }

    final thumbStat = await thumbFile.stat();
    return Response.ok(
      thumbFile.openRead(),
      headers: {
        'content-type': 'image/jpeg',
        'content-length': thumbStat.size.toString(),
        'cache-control': 'public, max-age=604800, immutable',
        'etag': etag,
      },
    );
  }

  Stream<List<int>> _streamFile(File targetFile, int fileSize, String filename, {int start = 0, int? end, bool isRange = false}) async* {
    final raf = await targetFile.open(mode: FileMode.read);
    final endByte = end ?? fileSize;
    var bytesSent = start;
    var lastProgressMs = 0;

    if (start > 0) {
      await raf.setPosition(start);
    }

    // 256 KB chunk size gives 4x-8x throughput improvement over standard 64 KB
    const chunkSize = 256 * 1024;

    try {
      while (bytesSent < endByte) {
        if (pauseChecker != null) {
          await pauseChecker!(filename);
        }

        final remaining = endByte - bytesSent;
        final toRead = remaining < chunkSize ? remaining : chunkSize;
        final chunk = await raf.read(toRead);
        if (chunk.isEmpty) break;

        bytesSent += chunk.length;
        onChunkSent?.call(chunk.length);

        final now = DateTime.now().millisecondsSinceEpoch;
        if (bytesSent >= endByte || (now - lastProgressMs) >= 150) {
          lastProgressMs = now;
          onProgress?.call(filename, bytesSent, fileSize);
        }

        yield chunk;
      }

      onProgress?.call(filename, bytesSent, fileSize);

    } finally {
      await raf.close();
    }
  }

  Response _serveRangeRequest(
    Request request,
    File file,
    int fileSize,
    String mimeType,
    String filename,
    String rangeHeader, {
    String? etag,
    String? lastModified,
    String dispositionType = 'inline',
  }) {
    try {
      final rangeSpec = rangeHeader.substring(6).trim();
      final parts = rangeSpec.split('-');
      int start;
      int end;

      if (parts[0].isEmpty) {
        // Suffix range: bytes=-500 (last 500 bytes)
        final suffix = int.parse(parts[1]);
        if (suffix <= 0) {
          return Response(416, headers: {'content-range': 'bytes */$fileSize'});
        }
        start = (fileSize - suffix).clamp(0, fileSize - 1);
        end = fileSize - 1;
      } else {
        start = int.parse(parts[0]);
        end = parts.length > 1 && parts[1].isNotEmpty ? int.parse(parts[1]) : fileSize - 1;
      }

      if (start < 0 || start >= fileSize || end >= fileSize || start > end) {
        return Response(
          416, // Range Not Satisfiable
          headers: {'content-range': 'bytes */$fileSize'},
        );
      }

      final contentLength = end - start + 1;
      final stream = _streamFile(file, fileSize, filename, start: start, end: end + 1, isRange: true);

      return Response(
        206, // Partial Content
        body: stream,
        headers: {
          'content-type': mimeType,
          'content-length': contentLength.toString(),
          'content-range': 'bytes $start-$end/$fileSize',
          'accept-ranges': 'bytes',
          if (etag != null) 'etag': etag,
          if (lastModified != null) 'last-modified': lastModified,
          'content-disposition': '$dispositionType; filename="$filename"',
        },
      );
    } catch (_) {
      return Response(400, body: 'Invalid Range header');
    }
  }

  /// Download multiple files or folder as a streaming ZIP
  Future<Response> downloadZip(Request request) async {
    if (session.isReceiveMode || session.isDisposableRoom) return Response(403, body: 'File downloads are not available in this mode');
    String? pathsParam = request.url.queryParameters['paths'];
    if ((pathsParam == null || pathsParam.isEmpty) && request.method == 'POST') {
      try {
        final bodyStr = await request.readAsString();
        if (bodyStr.isNotEmpty) {
          final contentType = request.headers['content-type'] ?? '';
          if (contentType.contains('application/json')) {
            final parsed = jsonDecode(bodyStr);
            if (parsed is Map && parsed['paths'] != null) {
              if (parsed['paths'] is List) {
                pathsParam = (parsed['paths'] as List).join(',');
              } else {
                pathsParam = parsed['paths'].toString();
              }
            }
          } else {
            final formParams = Uri.splitQueryString(bodyStr);
            pathsParam = formParams['paths'] ?? bodyStr;
          }
        }
      } catch (_) {}
    }
    final filesToZip = <File>[];
    final entryPaths = <String, String>{};

    if (pathsParam != null && pathsParam.isNotEmpty) {
      final paths = pathsParam.split(',');
      for (final rawRelPath in paths) {
        final relPath = rawRelPath.trim();
        if (relPath.isEmpty) continue;
        final file = _resolveAllowedFile(relPath);
        if (file != null && await file.exists()) {
          if (vaultTracker == null || vaultTracker!.canDownload(file.path)) {
            filesToZip.add(file);
            entryPaths[file.path] = p.basename(file.path);
          }
        } else {
          final dir = _resolveAllowedDirectory(relPath);
          if (dir != null && await dir.exists()) {
            try {
              final dirNorm = p.normalize(dir.path).replaceAll('\\', '/');
              await for (final entity in dir.list(recursive: true, followLinks: false)) {
                if (entity is File && !p.basename(entity.path).startsWith('.')) {
                  if (vaultTracker == null || vaultTracker!.canDownload(entity.path)) {
                    filesToZip.add(entity);
                    final entityNorm = p.normalize(entity.path).replaceAll('\\', '/');
                    final sub = entityNorm.startsWith('$dirNorm/')
                        ? entityNorm.substring(dirNorm.length + 1)
                        : p.basename(entity.path);
                    entryPaths[entity.path] = p.join(p.basename(dir.path), sub).replaceAll('\\', '/');
                  }
                }
              }
            } catch (_) {}
          }
        }
      }
    } else {
      // Default: zip all configured shared items
      final isSingleFolder = session.items.length == 1 && session.items.first.isDirectory;
      for (final item in session.items) {
        if (!item.isDirectory) {
          final file = File(item.path);
          if (await file.exists()) {
            if (vaultTracker == null || vaultTracker!.canDownload(file.path)) {
              filesToZip.add(file);
              entryPaths[file.path] = item.name;
            }
          }
        } else {
          final dir = Directory(item.path);
          if (await dir.exists()) {
            try {
              final dirNorm = p.normalize(dir.path).replaceAll('\\', '/');
              await for (final entity in dir.list(recursive: true, followLinks: false)) {
                if (entity is File && !p.basename(entity.path).startsWith('.')) {
                  if (vaultTracker == null || vaultTracker!.canDownload(entity.path)) {
                    filesToZip.add(entity);
                    final entityNorm = p.normalize(entity.path).replaceAll('\\', '/');
                    final sub = entityNorm.startsWith('$dirNorm/')
                        ? entityNorm.substring(dirNorm.length + 1)
                        : p.basename(entity.path);
                    entryPaths[entity.path] = isSingleFolder ? sub : p.join(item.name, sub).replaceAll('\\', '/');
                  }
                }
              }
            } catch (_) {}
          }
        }
      }
    }

    if (filesToZip.isEmpty) {
      return Response(404, body: 'No valid files to archive');
    }

    // Recheck all quotas together after asynchronous filesystem enumeration.
    if (!(vaultTracker?.reserveDownloads(filesToZip.map((file) => file.path)) ?? true)) {
      return Response(410, body: 'Download limit reached for an archived file');
    }

    final zipStream = StreamingZipArchive.streamFiles(
      filesToZip,
      entryPathMap: entryPaths,
    );
    final timestamp = DateTime.now().millisecondsSinceEpoch;

    return Response.ok(
      zipStream,
      headers: {
        'content-type': 'application/zip',
        'content-disposition': 'attachment; filename="cloudpocket_archive_$timestamp.zip"',
      },
    );
  }

  File? _resolveAllowedFile(String clientRelativePath) {
    if (session.isReceiveMode || session.isDisposableRoom) return null;
    final clean = clientRelativePath.trim().replaceAll('\\', '/').replaceAll(RegExp(r'^/+|/+$'), '');
    if (clean.isEmpty) return null;

    final isSingleFolder = session.items.length == 1 && session.items.first.isDirectory;

    for (final item in session.items) {
      if (!item.isDirectory) {
        final itemBase = p.basename(p.normalize(item.path));
        if (clean == item.name || clean == itemBase || clean == item.path) {
          return File(item.path);
        }
      } else {
        final dirPath = p.normalize(item.path);
        final prefixes = <String>{
          item.name.trim().replaceAll('\\', '/').replaceAll(RegExp(r'^/+|/+$'), ''),
          p.basename(dirPath).replaceAll(RegExp(r'^/+|/+$'), ''),
        };

        for (final prefix in prefixes) {
          if (prefix.isNotEmpty && (clean.startsWith('$prefix/') || clean == prefix)) {
            final sub = clean.startsWith('$prefix/') ? clean.substring(prefix.length + 1) : '';
            if (sub.isNotEmpty) {
              final candidate = p.normalize(p.join(dirPath, sub));
              if (p.isWithin(dirPath, candidate)) {
                final f = File(candidate);
                if (f.existsSync() && _isCanonicalChild(dirPath, candidate)) return f;
              }
            }
          }
        }

        // When a single folder is shared, client relative path can be direct (e.g., 'sub/doc.txt' or 'doc.txt')
        if (isSingleFolder) {
          final candidate = p.normalize(p.join(dirPath, clean));
          if (p.isWithin(dirPath, candidate)) {
            final f = File(candidate);
            if (f.existsSync() && _isCanonicalChild(dirPath, candidate)) return f;
          }
        }
      }
    }
    return null;
  }

  Directory? _resolveAllowedDirectory(String clientRelativeSubpath) {
    if (session.isReceiveMode || session.isDisposableRoom) return null;
    final clean = clientRelativeSubpath.trim().replaceAll('\\', '/').replaceAll(RegExp(r'^/+|/+$'), '');
    if (clean.isEmpty) return null;

    final isSingleFolder = session.items.length == 1 && session.items.first.isDirectory;

    for (final item in session.items) {
      if (item.isDirectory) {
        final dirPath = p.normalize(item.path);
        final prefixes = <String>{
          item.name.trim().replaceAll('\\', '/').replaceAll(RegExp(r'^/+|/+$'), ''),
          p.basename(dirPath).replaceAll(RegExp(r'^/+|/+$'), ''),
        };

        for (final prefix in prefixes) {
          if (prefix.isNotEmpty) {
            if (clean == prefix) {
              return Directory(dirPath);
            }
            if (clean.startsWith('$prefix/')) {
              final sub = clean.substring(prefix.length + 1);
              final candidate = p.normalize(p.join(dirPath, sub));
              if (p.isWithin(dirPath, candidate) && _isCanonicalChild(dirPath, candidate)) {
                return Directory(candidate);
              }
            }
          }
        }

        // When a single folder is shared, client subpath can be relative to that folder directly
        if (isSingleFolder) {
          final candidate = p.normalize(p.join(dirPath, clean));
          if (p.isWithin(dirPath, candidate) && Directory(candidate).existsSync() && _isCanonicalChild(dirPath, candidate)) {
            return Directory(candidate);
          }
        }
      }
    }
    return null;
  }

  bool _isCanonicalChild(String root, String candidate) {
    try {
      final canonicalRoot = Directory(root).resolveSymbolicLinksSync();
      final canonicalTarget = FileSystemEntity.isDirectorySync(candidate)
          ? Directory(candidate).resolveSymbolicLinksSync()
          : File(candidate).resolveSymbolicLinksSync();
      return p.isWithin(canonicalRoot, canonicalTarget);
    } on FileSystemException {
      return false;
    }
  }
}
