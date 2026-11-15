import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
import 'package:path/path.dart' as p;
import 'package:shelf/shelf.dart';

class UploadHandler {
  static int _uploadSequence = 0;
  final String saveDirectoryPath;
  final bool allowUploads;
  final void Function(String filename, int bytesWritten, int totalBytes)? onProgress;
  final void Function(int bytesReceived)? onChunkReceived;
  final Future<void> Function(String filename)? pauseChecker;
  final void Function(String filename)? onTransferStarted;

  UploadHandler({
    required this.saveDirectoryPath,
    required this.allowUploads,
    this.onProgress,
    this.onChunkReceived,
    this.pauseChecker,
    this.onTransferStarted,
  });

  Future<Response> handleUpload(Request request) async {
    if (!allowUploads) {
      return Response(
        403,
        body: jsonEncode({'error': 'UploadsDisabled', 'message': 'Owner has disabled uploads'}),
        headers: {'content-type': 'application/json'},
      );
    }

    File? pendingUpload;
    File? reservedFile;
    try {
      final saveDir = Directory(saveDirectoryPath);
      if (!await saveDir.exists()) {
        await saveDir.create(recursive: true);
      }

      // Check for subpath header to save inside subfolder if specified
      final rawSubpath = request.headers['x-subpath'] ?? request.url.queryParameters['subpath'];
      Directory targetDir = saveDir;
      if (rawSubpath != null && rawSubpath.trim().isNotEmpty) {
        final decodedSub = Uri.decodeComponent(rawSubpath.trim());
        final cleanSub = p.normalize(decodedSub.replaceAll('\\', '/')).replaceAll(RegExp(r'^/+|/+$'), '');
        final resolvedSub = Directory(p.normalize(p.join(saveDir.path, cleanSub)));
        if (p.isWithin(saveDir.path, resolvedSub.path) || resolvedSub.path == saveDir.path) {
          var ancestor = resolvedSub.path;
          while (p.isWithin(saveDir.path, ancestor)) {
            if (await FileSystemEntity.type(ancestor, followLinks: false) == FileSystemEntityType.link) {
              return Response(403, body: 'Upload folder must not contain symbolic links');
            }
            ancestor = p.dirname(ancestor);
          }
          if (!await resolvedSub.exists()) {
            await resolvedSub.create(recursive: true);
          }
          targetDir = resolvedSub;
        } else {
          return Response(403, body: 'Upload folder is outside the receive directory');
        }
      }

      // Check for filename header (sent by modern web clients via X-Filename or query param)
      var filename = request.headers['x-filename'] ?? request.url.queryParameters['name'];
      if (filename == null || filename.trim().isEmpty) {
        filename = 'upload_${DateTime.now().millisecondsSinceEpoch}.bin';
      } else {
        // Sanitize filename to prevent path traversal
        filename = p.basename(Uri.decodeComponent(filename).replaceAll('\\', '/'));
      }
      if (filename == '.' || filename == '..' || filename.isEmpty || RegExp(r'[\x00-\x1f<>:"|?*]').hasMatch(filename)) {
        return Response(400, body: 'Invalid filename');
      }

      // Check for filesize header (sent when reverse proxies like Cloudflare strip Content-Length)
      final rawFilesize = request.headers['x-filesize'] ?? request.url.queryParameters['filesize'];
      final headerFilesize = rawFilesize != null ? int.tryParse(rawFilesize) : null;
      final totalBytes = headerFilesize ?? request.contentLength ?? 0;

      final uploadId = '${DateTime.now().microsecondsSinceEpoch}_${_uploadSequence++}';
      onTransferStarted?.call(filename);
      final tempFile = File(p.join(targetDir.path, '.upload_$uploadId.tmp'));
      pendingUpload = tempFile;
      final sink = tempFile.openWrite();
      var bytesWritten = 0;
      var lastProgressMs = 0;
      var lastPauseCheckBytes = 0;
      const bufferFlushThreshold = 512 * 1024; // 512 KB buffer for FUSE alignment
      final writeBuffer = BytesBuilder(copy: false);
      final targetFilename = filename;

      try {
        await for (final chunk in request.read()) {
          writeBuffer.add(chunk);
          bytesWritten += chunk.length;
          onChunkReceived?.call(chunk.length);

          if (writeBuffer.length >= bufferFlushThreshold) {
            if (pauseChecker != null && (bytesWritten - lastPauseCheckBytes >= bufferFlushThreshold)) {
              lastPauseCheckBytes = bytesWritten;
              await pauseChecker!(targetFilename);
            }
            sink.add(writeBuffer.takeBytes());
            // Bound pending writes when the network is faster than storage.
            await sink.flush();
          }

          final now = DateTime.now().millisecondsSinceEpoch;
          final isFinished = totalBytes > 0 && bytesWritten >= totalBytes;
          if (isFinished || (now - lastProgressMs) >= 350) {
            lastProgressMs = now;
            onProgress?.call(targetFilename, bytesWritten, totalBytes);
          }
        }

        // Flush any remaining buffered bytes
        if (writeBuffer.isNotEmpty) {
          sink.add(writeBuffer.takeBytes());
        }
        await sink.flush();
      } catch (streamErr) {
        await sink.close();
        // Delete incomplete temp file on stream error or disconnect
        try {
          if (await tempFile.exists()) {
            await tempFile.delete();
          }
        } catch (_) {}
        rethrow;
      } finally {
        await sink.close();
      }

      // Reserve a destination atomically so simultaneous uploads never overwrite.
      var counter = 0;
      late File finalFile;
      while (true) {
        final name = counter == 0 ? filename : '${p.basenameWithoutExtension(filename)} ($counter)${p.extension(filename)}';
        finalFile = File(p.join(targetDir.path, name));
        try {
          await finalFile.create(exclusive: true);
          reservedFile = finalFile;
          break;
        } on FileSystemException {
          if (await FileSystemEntity.type(finalFile.path, followLinks: false) == FileSystemEntityType.notFound) rethrow;
          counter++;
        }
      }

      // Atomically move completed file
      await tempFile.rename(finalFile.path);
      pendingUpload = null;
      reservedFile = null;

      // Ensure 100% completion is always reported
      onProgress?.call(p.basename(finalFile.path), bytesWritten, totalBytes > 0 ? totalBytes : bytesWritten);

      return Response.ok(
        jsonEncode({
          'success': true,
          'filename': p.basename(finalFile.path),
          'size': bytesWritten,
        }),
        headers: {'content-type': 'application/json'},
      );
    } on FormatException {
      return Response(400, body: 'Invalid upload metadata');
    } catch (_) {
      return Response(
        500,
        body: jsonEncode({'error': 'UploadFailed', 'message': 'Upload could not be completed. Check available storage and try again.'}),
        headers: {'content-type': 'application/json'},
      );
    } finally {
      for (final leftover in [pendingUpload, reservedFile]) {
        if (leftover != null) {
          try { if (await leftover.exists()) await leftover.delete(); } catch (_) {}
        }
      }
    }
  }
}
