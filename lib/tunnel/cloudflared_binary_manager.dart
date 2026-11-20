import 'dart:async';
import 'dart:io';
import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

class CloudflaredBinaryManager {
  static const String _version = '2026.11.1'; // Pin or default release
  static const MethodChannel _nativeChannel = MethodChannel('com.cloudpocket.app/wifi_lock');

  /// Returns the path to an executable `cloudflared` binary.
  /// Checks Android native library first, then system PATH, then app storage, then downloads.
  static Future<String> ensureBinaryAvailable({
    void Function(double progress, String status)? onProgress,
  }) async {
    // 1. On Android: Check pre-bundled native library first
    if (Platform.isAndroid) {
      final nativePath = await _getAndroidNativeBinary();
      if (nativePath != null) {
        onProgress?.call(1.0, 'Cloudflare engine ready');
        return nativePath;
      }
      throw UnsupportedError(
        'Cloudflare engine (libcloudflared.so) could not be resolved from app installation.',
      );
    }

    if (Platform.isIOS) {
      throw UnsupportedError(
        'The cloudflared binary is not supported on iOS due to OS-level security restrictions.',
      );
    }

    // 2. Check if cloudflared is already in system PATH
    if (await _isSystemBinaryAvailable()) {
      onProgress?.call(1.0, 'Using system cloudflared');
      return 'cloudflared';
    }

    // 3. Check app-internal storage
    final binaryFile = await getLocalBinaryFile();
    if (await binaryFile.exists()) {
      // Ensure executable permissions
      await _ensureExecutable(binaryFile.path);
      onProgress?.call(1.0, 'Cloudflare engine ready');
      return binaryFile.path;
    }

    // 4. Download binary on-demand
    onProgress?.call(0.0, 'Downloading Cloudflare engine...');
    await _downloadBinary(binaryFile, onProgress);
    await _ensureExecutable(binaryFile.path);

    onProgress?.call(1.0, 'Cloudflare engine installed');
    return binaryFile.path;
  }

  static Future<String?> _getAndroidNativeBinary() async {
    if (!Platform.isAndroid) return null;
    try {
      final String? path = await _nativeChannel.invokeMethod('getNativeBinaryPath', {
        'name': 'libcloudflared.so',
      });
      if (path != null && await File(path).exists()) {
        return path;
      }
    } catch (_) {}
    return null;
  }

  /// Checks if a local binary is already cached.
  static Future<bool> isBinaryCached() async {
    if (Platform.isAndroid) {
      final nativePath = await _getAndroidNativeBinary();
      if (nativePath != null) return true;
    }
    if (await _isSystemBinaryAvailable()) return true;
    final file = await getLocalBinaryFile();
    return await file.exists();
  }

  /// Returns target local File where cloudflared is or should be stored.
  static Future<File> getLocalBinaryFile() async {
    final supportDir = await getApplicationSupportDirectory();
    final binDir = Directory(p.join(supportDir.path, 'bin'));
    if (!await binDir.exists()) {
      await binDir.create(recursive: true);
    }
    final binaryName = Platform.isWindows ? 'cloudflared.exe' : 'cloudflared';
    return File(p.join(binDir.path, binaryName));
  }

  static Future<bool> _isSystemBinaryAvailable() async {
    try {
      final result = await Process.run('cloudflared', ['--version']);
      return result.exitCode == 0;
    } catch (_) {
      return false;
    }
  }

  static Future<void> _downloadBinary(
    File targetFile,
    void Function(double progress, String status)? onProgress,
  ) async {
    final url = _resolveDownloadUrl();
    final request = http.Request('GET', Uri.parse(url));
    final response = await http.Client().send(request);

    if (response.statusCode != 200) {
      throw Exception('Failed to download cloudflared: HTTP ${response.statusCode}');
    }

    final totalBytes = response.contentLength ?? 20 * 1024 * 1024;
    var receivedBytes = 0;

    final tempFile = File('${targetFile.path}.tmp');
    if (await tempFile.exists()) await tempFile.delete();

    final sink = tempFile.openWrite();

    try {
      await response.stream.listen(
        (chunk) {
          sink.add(chunk);
          receivedBytes += chunk.length;
          final progress = (receivedBytes / totalBytes).clamp(0.0, 1.0);
          final mbReceived = (receivedBytes / (1024 * 1024)).toStringAsFixed(1);
          final mbTotal = (totalBytes / (1024 * 1024)).toStringAsFixed(1);
          onProgress?.call(progress, 'Downloading Cloudflare: $mbReceived MB / $mbTotal MB');
        },
        cancelOnError: true,
      ).asFuture();

      await sink.flush();
      await sink.close();

      if (await targetFile.exists()) await targetFile.delete();
      await tempFile.rename(targetFile.path);
    } catch (e) {
      await sink.close();
      if (await tempFile.exists()) await tempFile.delete();
      rethrow;
    }
  }

  static String _resolveDownloadUrl() {
    const base = 'https://github.com/cloudflare/cloudflared/releases/download/$_version';

    if (Platform.isWindows) {
      return '$base/cloudflared-windows-amd64.exe';
    } else if (Platform.isMacOS) {
      // Default to arm64 or amd64
      return '$base/cloudflared-darwin-amd64.tgz';
    } else if (Platform.isLinux || Platform.isAndroid) {
      // For Android / Linux
      // Most modern Android devices are aarch64 (arm64)
      return '$base/cloudflared-linux-arm64';
    }

    return '$base/cloudflared-linux-arm64';
  }

  static Future<void> _ensureExecutable(String filePath) async {
    if (!Platform.isWindows) {
      try {
        await Process.run('chmod', ['+x', filePath]);
      } catch (_) {}
    }
  }
}
