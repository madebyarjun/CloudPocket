class ShareHistoryRecord {
  final String id;
  final DateTime timestamp;
  final int itemCount;
  final int totalBytes;
  final int durationSeconds;
  final String securityLabel;

  const ShareHistoryRecord({
    required this.id,
    required this.timestamp,
    required this.itemCount,
    required this.totalBytes,
    required this.durationSeconds,
    required this.securityLabel,
  });

  Map<String, dynamic> toJson() => {
    'id': id,
    'timestamp': timestamp.toIso8601String(),
    'itemCount': itemCount,
    'totalBytes': totalBytes,
    'durationSeconds': durationSeconds,
    'securityLabel': securityLabel,
  };

  factory ShareHistoryRecord.fromJson(Map<String, dynamic> json) {
    var rawLabel = json['securityLabel'] as String? ?? 'Open Access';
    if (rawLabel.contains('No Authentication') || rawLabel == 'Open' || rawLabel.isEmpty) {
      rawLabel = 'Open Access';
    } else if (rawLabel.contains('Password') && !rawLabel.contains('2-Factor')) {
      rawLabel = 'Password Protected';
    } else if (rawLabel.contains('2-Factor')) {
      rawLabel = 'Protected (2-Factor)';
    }
    return ShareHistoryRecord(
      id: json['id'] as String,
      timestamp: DateTime.parse(json['timestamp'] as String),
      itemCount: json['itemCount'] as int,
      totalBytes: json['totalBytes'] as int,
      durationSeconds: json['durationSeconds'] as int,
      securityLabel: rawLabel,
    );
  }
}
