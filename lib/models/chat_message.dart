enum ChatMessageType {
  text,
  file,
  system,
}

class ChatMessage {
  final int seq;
  final ChatMessageType type;
  final String senderId;
  final String senderNickname;
  final String? text;
  final String? filename;
  final int? fileSize;
  final String? fileMimeType;
  final String? fileDownloadPath;
  final DateTime timestamp;
  final bool isSecureClient;
  final String color;
  final bool isE2e;
  final String? ciphertext;
  final String? iv;
  final String? alg;

  const ChatMessage({
    required this.seq,
    required this.type,
    required this.senderId,
    required this.senderNickname,
    this.text,
    this.filename,
    this.fileSize,
    this.fileMimeType,
    this.fileDownloadPath,
    required this.timestamp,
    this.isSecureClient = false,
    this.color = '#38BDF8',
    this.isE2e = false,
    this.ciphertext,
    this.iv,
    this.alg,
  });

  ChatMessage copyWith({
    String? text,
    bool? isE2e,
    String? ciphertext,
    String? iv,
    String? alg,
  }) {
    return ChatMessage(
      seq: seq,
      type: type,
      senderId: senderId,
      senderNickname: senderNickname,
      text: text ?? this.text,
      filename: filename,
      fileSize: fileSize,
      fileMimeType: fileMimeType,
      fileDownloadPath: fileDownloadPath,
      timestamp: timestamp,
      isSecureClient: isSecureClient,
      color: color,
      isE2e: isE2e ?? this.isE2e,
      ciphertext: ciphertext ?? this.ciphertext,
      iv: iv ?? this.iv,
      alg: alg ?? this.alg,
    );
  }

  Map<String, dynamic> toJson() => {
    'seq': seq,
    'type': type.name,
    'senderId': senderId,
    'senderNickname': senderNickname,
    'text': text,
    'filename': filename,
    'fileSize': fileSize,
    'fileMimeType': fileMimeType,
    'fileDownloadPath': fileDownloadPath,
    'timestamp': timestamp.millisecondsSinceEpoch,
    'isSecureClient': isSecureClient,
    'color': color,
    'isE2e': isE2e,
    if (ciphertext != null) 'ciphertext': ciphertext,
    if (iv != null) 'iv': iv,
    if (alg != null) 'alg': alg,
  };

  factory ChatMessage.fromJson(Map<String, dynamic> json) {
    return ChatMessage(
      seq: json['seq'] as int? ?? 0,
      type: ChatMessageType.values.firstWhere(
        (e) => e.name == (json['messageType'] ?? json['type']),
        orElse: () => ChatMessageType.text,
      ),
      senderId: json['senderId'] as String? ?? '',
      senderNickname: json['senderNickname'] as String? ?? 'Anonymous',
      text: json['text'] as String?,
      filename: json['filename'] as String?,
      fileSize: json['fileSize'] as int?,
      fileMimeType: json['fileMimeType'] as String?,
      fileDownloadPath: json['fileDownloadPath'] as String?,
      timestamp: DateTime.fromMillisecondsSinceEpoch(
        json['timestamp'] as int? ?? DateTime.now().millisecondsSinceEpoch,
      ),
      isSecureClient: json['isSecureClient'] as bool? ?? false,
      color: json['color'] as String? ?? '#38BDF8',
      isE2e: json['isE2e'] as bool? ?? (json['ciphertext'] != null),
      ciphertext: json['ciphertext'] as String?,
      iv: json['iv'] as String?,
      alg: json['alg'] as String?,
    );
  }
}
