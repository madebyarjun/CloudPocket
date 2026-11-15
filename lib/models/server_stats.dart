class ServerStats {
  final int activeConnections;
  final int totalBytesSent;
  final int totalBytesReceived;
  final double bandwidthBytesPerSec;
  final List<String> connectedClients;
  final DateTime? sessionStartTime;

  const ServerStats({
    this.activeConnections = 0,
    this.totalBytesSent = 0,
    this.totalBytesReceived = 0,
    this.bandwidthBytesPerSec = 0.0,
    this.connectedClients = const [],
    this.sessionStartTime,
  });

  String get formattedSentBytes => formatBytes(totalBytesSent);
  String get formattedReceivedBytes => formatBytes(totalBytesReceived);
  String get formattedBandwidth => '${formatBytes(bandwidthBytesPerSec.toInt())}/s';

  Duration get elapsedDuration {
    if (sessionStartTime == null) return Duration.zero;
    return DateTime.now().difference(sessionStartTime!);
  }

  static String formatBytes(int bytes) {
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

  ServerStats copyWith({
    int? activeConnections,
    int? totalBytesSent,
    int? totalBytesReceived,
    double? bandwidthBytesPerSec,
    List<String>? connectedClients,
    DateTime? sessionStartTime,
  }) {
    return ServerStats(
      activeConnections: activeConnections ?? this.activeConnections,
      totalBytesSent: totalBytesSent ?? this.totalBytesSent,
      totalBytesReceived: totalBytesReceived ?? this.totalBytesReceived,
      bandwidthBytesPerSec: bandwidthBytesPerSec ?? this.bandwidthBytesPerSec,
      connectedClients: connectedClients ?? this.connectedClients,
      sessionStartTime: sessionStartTime ?? this.sessionStartTime,
    );
  }
}
