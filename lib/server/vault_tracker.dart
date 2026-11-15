class VaultTracker {
  final int? maxDownloadsPerFile;
  final bool isVaultMode;
  final Map<String, int> _downloadCounts = {};

  VaultTracker({
    this.maxDownloadsPerFile,
    this.isVaultMode = false,
  });

  bool canDownload(String filePath) {
    if (!isVaultMode || maxDownloadsPerFile == null) return true;
    final current = _downloadCounts[filePath] ?? 0;
    return current < maxDownloadsPerFile!;
  }

  void recordDownload(String filePath) {
    if (!isVaultMode) return;
    _downloadCounts[filePath] = (_downloadCounts[filePath] ?? 0) + 1;
  }

  /// Reserve response access before streaming. No awaits may split validation
  /// and accounting, including when a ZIP contains several files.
  bool reserveDownloads(Iterable<String> paths) {
    final unique = paths.toSet();
    if (unique.any((path) => !canDownload(path))) return false;
    for (final path in unique) {
      recordDownload(path);
    }
    return true;
  }

  int? getRemainingDownloads(String filePath) {
    if (!isVaultMode || maxDownloadsPerFile == null) return null;
    final current = _downloadCounts[filePath] ?? 0;
    final remaining = maxDownloadsPerFile! - current;
    return remaining < 0 ? 0 : remaining;
  }

  Map<String, int> get downloadCounts => Map.unmodifiable(_downloadCounts);
}
