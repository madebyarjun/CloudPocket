import 'dart:io';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:cloud_pocket/models/share_session.dart';
import 'package:cloud_pocket/providers/session_provider.dart';
import 'package:cloud_pocket/server/thumbnail_service.dart';

/// Immutable state describing background thumbnail pre-generation progress
class ThumbnailProgressState {
  final bool isGenerating;
  final int completed;
  final int total;
  final String? currentFile;
  final bool isDone;
  final int revision;

  const ThumbnailProgressState({
    this.isGenerating = false,
    this.completed = 0,
    this.total = 0,
    this.currentFile,
    this.isDone = false,
    this.revision = 0,
  });

  double get progress => total > 0 ? (completed / total).clamp(0.0, 1.0) : 0.0;
  int get percent => (progress * 100).toInt();
  bool get hasImages => total > 0;

  ThumbnailProgressState copyWith({
    bool? isGenerating,
    int? completed,
    int? total,
    String? currentFile,
    bool? isDone,
    int? revision,
    bool clearCurrentFile = false,
  }) {
    return ThumbnailProgressState(
      isGenerating: isGenerating ?? this.isGenerating,
      completed: completed ?? this.completed,
      total: total ?? this.total,
      currentFile: clearCurrentFile ? null : (currentFile ?? this.currentFile),
      isDone: isDone ?? this.isDone,
      revision: revision ?? this.revision,
    );
  }
}

/// Manages background preheating of thumbnails as soon as files or folders are picked.
class ThumbnailProgressNotifier extends Notifier<ThumbnailProgressState> {
  int _runId = 0;

  @override
  ThumbnailProgressState build() {
    // Automatically observe session item changes
    ref.listen<ShareSession>(sessionProvider, (previous, next) {
      if (previous == null || previous.items != next.items) {
        startPreheat(next.items);
      }
    });

    // If session already has items upon notifier initialization, trigger preheat
    final initialItems = ref.read(sessionProvider).items;
    if (initialItems.isNotEmpty) {
      Future.microtask(() => startPreheat(initialItems));
    }

    return const ThumbnailProgressState();
  }

  /// Initiates non-blocking background thumbnail preheating for the given items
  Future<void> startPreheat(List<SharedItem> items) async {
    final currentRun = ++_runId;

    if (items.isEmpty) {
      state = const ThumbnailProgressState();
      return;
    }

    // Fast initial scan to count images without blocking
    final candidateCount = _countCandidateImages(items);
    if (candidateCount == 0) {
      state = const ThumbnailProgressState(isGenerating: false, isDone: true, total: 0);
      return;
    }

    state = state.copyWith(
      isGenerating: true,
      completed: 0,
      total: candidateCount,
      clearCurrentFile: true,
      isDone: false,
    );

    final thumbService = ThumbnailService();

    await thumbService.preheatItems(
      items,
      size: ThumbnailService.defaultSize,
      onProgress: (completed, total, currentFile) {
        if (currentRun != _runId) return;
        state = state.copyWith(
          completed: completed,
          total: total > 0 ? total : state.total,
          currentFile: currentFile.isNotEmpty ? currentFile : state.currentFile,
          isGenerating: completed < total,
          isDone: completed >= total,
          revision: state.revision + 1,
        );
      },
      isCancelled: () => currentRun != _runId,
    );

    if (currentRun == _runId) {
      state = state.copyWith(
        isGenerating: false,
        isDone: true,
        revision: state.revision + 1,
      );
    }
  }

  int _countCandidateImages(List<SharedItem> items) {
    var count = 0;
    for (final item in items) {
      if (!item.isDirectory) {
        if (ThumbnailService.isSupportedImage(item.path)) {
          count++;
        }
      } else {
        final dir = Directory(item.path);
        if (dir.existsSync()) {
          try {
            for (final entity in dir.listSync(recursive: true, followLinks: false)) {
              if (entity is File && ThumbnailService.isSupportedImage(entity.path)) {
                count++;
              }
            }
          } catch (_) {}
        }
      }
    }
    return count;
  }

  /// Cancels in-flight preheating
  void cancel() {
    _runId++;
    state = const ThumbnailProgressState();
  }
}

final thumbnailProgressProvider =
    NotifierProvider<ThumbnailProgressNotifier, ThumbnailProgressState>(
  ThumbnailProgressNotifier.new,
);
