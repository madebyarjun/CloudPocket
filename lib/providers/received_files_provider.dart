import 'dart:io';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path/path.dart' as p;
import 'package:cloud_pocket/providers/server_provider.dart';
import 'package:cloud_pocket/providers/settings_provider.dart';

class ReceivedFileItem {
  final String path;
  final String name;
  final int sizeBytes;
  final DateTime modified;

  const ReceivedFileItem({
    required this.path,
    required this.name,
    required this.sizeBytes,
    required this.modified,
  });

  String get extension => p.extension(name).toLowerCase();

  String get formattedSize {
    if (sizeBytes < 1024) return '$sizeBytes B';
    if (sizeBytes < 1024 * 1024) return '${(sizeBytes / 1024).toStringAsFixed(1)} KB';
    if (sizeBytes < 1024 * 1024 * 1024) return '${(sizeBytes / (1024 * 1024)).toStringAsFixed(1)} MB';
    return '${(sizeBytes / (1024 * 1024 * 1024)).toStringAsFixed(2)} GB';
  }

  bool get isImage => const ['.jpg', '.jpeg', '.png', '.gif', '.webp', '.bmp', '.svg'].contains(extension);
  bool get isVideo => const ['.mp4', '.mkv', '.mov', '.avi', '.webm', '.flv'].contains(extension);
  bool get isAudio => const ['.mp3', '.wav', '.flac', '.aac', '.m4a', '.ogg'].contains(extension);
  bool get isDocument => const ['.pdf', '.doc', '.docx', '.xls', '.xlsx', '.ppt', '.pptx', '.txt', '.md', '.csv', '.json'].contains(extension);
  bool get isArchive => const ['.zip', '.rar', '.7z', '.tar', '.gz'].contains(extension);
}

class ReceivedFilesState {
  final List<ReceivedFileItem> files;
  final bool isLoading;
  final String? directoryPath;
  final String? error;

  const ReceivedFilesState({
    this.files = const [],
    this.isLoading = false,
    this.directoryPath,
    this.error,
  });

  int get totalCount => files.length;
  int get totalBytes => files.fold(0, (sum, item) => sum + item.sizeBytes);

  String get formattedTotalSize {
    final bytes = totalBytes;
    if (bytes < 1024) return '$bytes B';
    if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(1)} KB';
    if (bytes < 1024 * 1024 * 1024) return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
    return '${(bytes / (1024 * 1024 * 1024)).toStringAsFixed(2)} GB';
  }

  ReceivedFilesState copyWith({
    List<ReceivedFileItem>? files,
    bool? isLoading,
    String? directoryPath,
    String? error,
    bool clearError = false,
  }) {
    return ReceivedFilesState(
      files: files ?? this.files,
      isLoading: isLoading ?? this.isLoading,
      directoryPath: directoryPath ?? this.directoryPath,
      error: clearError ? null : (error ?? this.error),
    );
  }
}

class ReceivedFilesNotifier extends AsyncNotifier<ReceivedFilesState> {
  @override
  Future<ReceivedFilesState> build() async {
    return _scanDirectory();
  }

  Future<ReceivedFilesState> _scanDirectory() async {
    final settings = ref.read(settingsProvider);
    final dirPath = await ServerNotifier.resolveUploadDirectory(settings.customUploadDirectory);
    final targetDir = Directory(dirPath);

    if (!await targetDir.exists()) {
      return ReceivedFilesState(directoryPath: dirPath, files: const []);
    }

    try {
      final items = <ReceivedFileItem>[];
      final entities = targetDir.listSync(followLinks: false);

      for (final entity in entities) {
        if (entity is File) {
          try {
            final stat = entity.statSync();
            final name = p.basename(entity.path);
            if (name.startsWith('.')) continue; // skip hidden files

            items.add(ReceivedFileItem(
              path: entity.path,
              name: name,
              sizeBytes: stat.size,
              modified: stat.modified,
            ));
          } catch (_) {}
        }
      }

      // Sort newest first
      items.sort((a, b) => b.modified.compareTo(a.modified));

      return ReceivedFilesState(
        files: items,
        directoryPath: dirPath,
        isLoading: false,
      );
    } catch (e) {
      return ReceivedFilesState(
        files: const [],
        directoryPath: dirPath,
        isLoading: false,
        error: 'Failed to read directory: $e',
      );
    }
  }

  Future<void> refresh() async {
    state = const AsyncValue.loading();
    state = await AsyncValue.guard(() => _scanDirectory());
  }

  Future<bool> deleteFile(String path) async {
    try {
      final file = File(path);
      if (await file.exists()) {
        await file.delete();
      }
      await refresh();
      return true;
    } catch (e) {
      return false;
    }
  }
}

final receivedFilesProvider = AsyncNotifierProvider<ReceivedFilesNotifier, ReceivedFilesState>(
  ReceivedFilesNotifier.new,
);
