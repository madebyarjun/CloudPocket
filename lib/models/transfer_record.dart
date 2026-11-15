enum TransferDirection { download, upload }

enum TransferStatus { queued, active, paused, completed, failed }

class TransferRecord {
  final String id;
  final String filename;
  final int totalBytes;
  final int transferredBytes;
  final TransferDirection direction;
  final TransferStatus status;
  final double speedBytesPerSec;
  final DateTime startTime;
  final String? clientIp;
  final String? errorMessage;

  const TransferRecord({
    required this.id,
    required this.filename,
    required this.totalBytes,
    this.transferredBytes = 0,
    required this.direction,
    this.status = TransferStatus.queued,
    this.speedBytesPerSec = 0.0,
    required this.startTime,
    this.clientIp,
    this.errorMessage,
  });

  double get progress {
    if (totalBytes <= 0) return 0.0;
    return (transferredBytes / totalBytes).clamp(0.0, 1.0);
  }

  String get formattedTotalBytes => _formatBytes(totalBytes);
  String get formattedTransferredBytes => _formatBytes(transferredBytes);
  String get formattedSpeed {
    if (status == TransferStatus.paused) return 'Paused';
    return '${_formatBytes(speedBytesPerSec.toInt())}/s';
  }

  String get estimatedTimeRemaining {
    if (status == TransferStatus.paused) return 'Paused';
    if (speedBytesPerSec <= 0 || status != TransferStatus.active) return '--';
    final remainingBytes = totalBytes - transferredBytes;
    if (remainingBytes <= 0) return 'Done';
    final seconds = (remainingBytes / speedBytesPerSec).round();
    if (seconds < 60) return '${seconds}s left';
    final minutes = seconds ~/ 60;
    final remainingSecs = seconds % 60;
    return '${minutes}m ${remainingSecs}s left';
  }

  static String _formatBytes(int bytes) {
    if (bytes <= 0) return '0 B';
    const suffixes = ['B', 'KB', 'MB', 'GB', 'TB'];
    var i = 0;
    double count = bytes.toDouble();
    while (count >= 1024 && i < suffixes.length - 1) {
      count /= 1024;
      i++;
    }
    return '${count.toStringAsFixed(i == 0 ? 0 : 1)} ${suffixes[i]}';
  }

  TransferRecord copyWith({
    String? id,
    String? filename,
    int? totalBytes,
    int? transferredBytes,
    TransferDirection? direction,
    TransferStatus? status,
    double? speedBytesPerSec,
    DateTime? startTime,
    String? clientIp,
    String? errorMessage,
  }) {
    return TransferRecord(
      id: id ?? this.id,
      filename: filename ?? this.filename,
      totalBytes: totalBytes ?? this.totalBytes,
      transferredBytes: transferredBytes ?? this.transferredBytes,
      direction: direction ?? this.direction,
      status: status ?? this.status,
      speedBytesPerSec: speedBytesPerSec ?? this.speedBytesPerSec,
      startTime: startTime ?? this.startTime,
      clientIp: clientIp ?? this.clientIp,
      errorMessage: errorMessage ?? this.errorMessage,
    );
  }
}
