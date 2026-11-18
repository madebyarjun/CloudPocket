import 'dart:async';
import 'dart:convert';
import 'package:web_socket_channel/web_socket_channel.dart';
import 'package:uuid/uuid.dart';
import 'package:cloud_pocket/models/chat_message.dart';
import 'package:cloud_pocket/models/room_config.dart';
import 'package:cloud_pocket/server/room_pin_rate_limiter.dart';

class RoomParticipant {
  final String id;
  String nickname;
  final WebSocketChannel channel;
  final bool isSecureClient;
  final String color;
  final DateTime joinedAt;
  final String? clientId;
  final String? attachmentKey;
  final List<DateTime> messageTimestamps = [];

  RoomParticipant({
    required this.id,
    required this.nickname,
    required this.channel,
    required this.isSecureClient,
    required this.color,
    required this.joinedAt,
    this.clientId,
    this.attachmentKey,
  });

  Map<String, dynamic> toJson() => {
    'id': id,
    'nickname': nickname,
    'secureMode': isSecureClient,
    'color': color,
  };
}

typedef RoomParticipantCallback = void Function({
  required int totalParticipants,
  required int secureParticipants,
  required int browserParticipants,
});

class ChatHub {
  final RoomConfig config;
  final RoomParticipantCallback? onParticipantChanged;
  final void Function(ChatMessage message)? onNewMessage;

  final Map<WebSocketChannel, RoomParticipant> _participants = {};
  final Map<WebSocketChannel, RoomParticipant> _pendingParticipants = {};
  final Map<WebSocketChannel, Timer> _joinTimers = {};
  final List<ChatMessage> _messages = [];
  final Map<String, Timer> _typingTimers = {};
  int _seq = 0;
  static const Uuid _uuid = Uuid();

  static const List<String> _avatarColors = [
    '#38BDF8', // Sky
    '#10B981', // Emerald
    '#F59E0B', // Amber
    '#EC4899', // Pink
    '#8B5CF6', // Purple
    '#06B6D4', // Cyan
    '#F97316', // Orange
    '#14B8A6', // Teal
    '#A855F7', // Violet
  ];

  final int Function()? getRemainingSeconds;

  ChatHub({
    required this.config,
    this.onParticipantChanged,
    this.onNewMessage,
    this.getRemainingSeconds,
  });

  bool mayViewAttachment(String? key) => key != null &&
      _participants.values.any((participant) => participant.attachmentKey == key);

  int get participantCount => _participants.length;
  int get secureParticipantCount =>
      _participants.values.where((p) => p.isSecureClient).length;
  int get browserParticipantCount =>
      _participants.values.where((p) => !p.isSecureClient).length;
  int get messageCount => _messages.length;
  List<ChatMessage> get messages => List.unmodifiable(_messages);
  List<RoomParticipant> get participants => _participants.values.toList();

  String _pickColor(String id) {
    final hash = id.codeUnits.fold<int>(0, (prev, elem) => prev + elem);
    return _avatarColors[hash % _avatarColors.length];
  }

  void handleWebSocket(WebSocketChannel channel, {int remainingSeconds = 0, String? clientId}) {
    if (_participants.length + _pendingParticipants.length >= config.maxParticipants) {
      channel.sink.add(jsonEncode({
        'type': 'error',
        'code': 'ROOM_FULL',
        'message': 'Room has reached maximum capacity (${config.maxParticipants} participants)',
      }));
      channel.sink.close();
      return;
    }

    final participantId = 'p_${_uuid.v4().replaceAll('-', '').substring(0, 8)}';
    final participant = RoomParticipant(
      id: participantId,
      nickname: 'Guest',
      channel: channel,
      isSecureClient: false,
      color: _pickColor(participantId),
      joinedAt: DateTime.now(),
      clientId: clientId,
    );

    _pendingParticipants[channel] = participant;
    _joinTimers[channel] = Timer(const Duration(seconds: 10), () {
      _pendingParticipants.remove(channel);
      _joinTimers.remove(channel);
      channel.sink.close();
    });

    channel.stream.listen(
      (data) {
        _handleIncomingData(channel, data);
      },
      onDone: () {
        _handleDisconnect(channel);
      },
      onError: (_) {
        _handleDisconnect(channel);
      },
      cancelOnError: true,
    );
  }

  void _handleIncomingData(WebSocketChannel channel, dynamic raw) {
    final participant = _participants[channel] ?? _pendingParticipants[channel];
    if (participant == null) return;

    try {
      final decoded = jsonDecode(raw.toString()) as Map<String, dynamic>;
      final type = decoded['type'] as String?;
      if (!_participants.containsKey(channel) && type != 'join') return;
      if (_participants.containsKey(channel) && type == 'join') return;

      switch (type) {
        case 'join':
          _handleJoin(channel, participant, decoded);
          break;
        case 'message':
          _handleTextMessage(participant, decoded);
          break;
        case 'typing':
          _handleTyping(participant, decoded);
          break;
        default:
          break;
      }
    } catch (_) {}
  }

  void _handleJoin(WebSocketChannel channel, RoomParticipant participant, Map<String, dynamic> data) {
    if (config.isTokenRevoked) {
      channel.sink.add(jsonEncode({'type': 'error', 'code': 'TOKEN_REVOKED', 'message': 'Room invite has been revoked'}));
      return;
    }
    final nickname = (data['nickname'] as String? ?? 'Guest').trim();
    final clientType = data['client'] as String? ?? 'browser';
    final isSecure = clientType == 'app' || (data['secureMode'] == true);

    final inputPin = data['pin'] as String?;
    final inputToken = data['token'] as String?;
    final rateLimiter = RoomPinRateLimiter();
    final rateLimitKey = participant.clientId ?? participant.id;
    if (rateLimiter.isLockedOut(rateLimitKey)) {
      channel.sink.add(jsonEncode({'type': 'error', 'code': 'LOCKED_OUT', 'message': 'Too many failed attempts. Try again in 60 seconds.'}));
      return;
    }

    // 1. If an invite token is configured, check token validation if supplied
    if (config.inviteToken.isNotEmpty && inputToken != null && inputToken.isNotEmpty) {
      if (inputToken != config.inviteToken) {
        rateLimiter.recordFailure(rateLimitKey);
        channel.sink.add(jsonEncode({
          'type': 'error',
          'code': 'INVALID_TOKEN',
          'message': 'Invalid invite token for this room',
        }));
        return;
      }
    }

    // 2. If PIN is required, a valid PIN is mandatory and CANNOT be bypassed by an invite token
    if (config.requirePin) {
      if (rateLimiter.isLockedOut(rateLimitKey)) {
        channel.sink.add(jsonEncode({
          'type': 'error',
          'code': 'LOCKED_OUT',
          'message': 'Too many failed PIN attempts. Locked out for 60 seconds.',
        }));
        return;
      }

      final isPinValid = inputPin != null && inputPin.isNotEmpty && config.verifyPin(inputPin);
      if (!isPinValid) {
        rateLimiter.recordFailure(rateLimitKey);
        final isLocked = rateLimiter.isLockedOut(rateLimitKey);
        channel.sink.add(jsonEncode({
          'type': 'error',
          'code': isLocked ? 'LOCKED_OUT' : ((inputPin == null || inputPin.isEmpty) ? 'PIN_REQUIRED' : 'INVALID_PIN'),
          'message': isLocked
              ? 'Too many failed PIN attempts. Locked out for 60 seconds.'
              : 'This room requires a valid PIN to enter',
        }));
        return;
      }
      rateLimiter.recordSuccess(rateLimitKey);
    } else if (config.inviteToken.isNotEmpty) {
      // In token-only rooms without PIN, a valid invite token is required to enter
      final isTokenValid = inputToken != null && inputToken == config.inviteToken;
      if (!isTokenValid) {
        rateLimiter.recordFailure(rateLimitKey);
        channel.sink.add(jsonEncode({
          'type': 'error',
          'code': (inputToken == null || inputToken.isEmpty) ? 'TOKEN_REQUIRED' : 'INVALID_TOKEN',
          'message': 'This room requires a valid invite token to enter',
        }));
        return;
      }
    }

    participant.nickname = nickname.isEmpty ? 'Guest' : nickname.length > 30 ? nickname.substring(0, 30) : nickname;
    rateLimiter.recordSuccess(rateLimitKey);
    // Update participant fields
    final updated = RoomParticipant(
      id: participant.id,
      nickname: participant.nickname,
      channel: participant.channel,
      isSecureClient: isSecure,
      color: participant.color,
      joinedAt: participant.joinedAt,
      clientId: participant.clientId,
      attachmentKey: clientType == 'app' ? _uuid.v4() : null,
    );
    _pendingParticipants.remove(channel);
    _joinTimers.remove(channel)?.cancel();
    _participants[channel] = updated;

    // Send welcome to this participant
    channel.sink.add(jsonEncode({
      'type': 'welcome',
      'participantId': updated.id,
      if (updated.attachmentKey != null) 'attachmentKey': updated.attachmentKey,
      'nickname': updated.nickname,
      'roomName': config.roomName,
      'roomCode': config.roomCode,
      'color': updated.color,
      'isSecureClient': updated.isSecureClient,
      'maxParticipants': config.maxParticipants,
      'allowFileSharing': config.allowFileSharing,
      // Sent only after successful admission. PIN-only joins need this key material.
      'roomToken': config.inviteToken,
      'remainingSeconds': getRemainingSeconds?.call() ?? 0,
      'messages': _messages.map((m) => m.toJson()
        ..['messageType'] = m.type.name
        ..['type'] = 'chat_message').toList(),
      'participants': _participants.values.map((p) => p.toJson()).toList(),
    }));

    // Broadcast join to other participants
    _broadcastExcept(channel, {
      'type': 'participant_joined',
      'participant': updated.toJson(),
    });

    // Add system notification in message stream
    addSystemMessage('${updated.nickname} joined the room');

    _notifyParticipantCount();
  }

  void _handleTextMessage(RoomParticipant participant, Map<String, dynamic> data) {
    final text = (data['text'] as String? ?? '').trim();
    final isE2e = data['e2e'] == true || data['isE2e'] == true;
    final ciphertext = data['ciphertext'] as String?;
    final iv = data['iv'] as String?;

    if (text.isEmpty && ciphertext == null) return;

    // Length check
    if (text.length > config.maxMessageLength || (ciphertext != null && ciphertext.length > config.maxMessageLength * 2)) {
      participant.channel.sink.add(jsonEncode({
        'type': 'error',
        'code': 'MSG_TOO_LONG',
        'message': 'Message exceeds maximum length of ${config.maxMessageLength} characters',
      }));
      return;
    }

    // Rate limit check: max 10 messages in last 1 second
    final now = DateTime.now();
    participant.messageTimestamps.removeWhere(
      (ts) => now.difference(ts).inMilliseconds > 1000,
    );
    if (participant.messageTimestamps.length >= 10) {
      participant.channel.sink.add(jsonEncode({
        'type': 'error',
        'code': 'RATE_LIMITED',
        'message': 'You are sending messages too quickly. Please wait.',
      }));
      return;
    }
    participant.messageTimestamps.add(now);

    final alg = data['alg'] as String? ?? (isE2e ? 'AES-GCM' : null);

    final msg = ChatMessage(
      seq: ++_seq,
      type: ChatMessageType.text,
      senderId: participant.id,
      senderNickname: participant.nickname,
      text: isE2e ? '[Encrypted Message]' : text,
      timestamp: now,
      isSecureClient: participant.isSecureClient,
      color: participant.color,
      isE2e: isE2e,
      ciphertext: ciphertext,
      iv: iv,
      alg: alg,
    );

    _appendAndBroadcastMessage(msg);
  }

  void _handleTyping(RoomParticipant participant, Map<String, dynamic> data) {
    final isTyping = data['isTyping'] as bool? ?? false;

    _typingTimers[participant.id]?.cancel();

    _broadcast({
      'type': 'typing_indicator',
      'participantId': participant.id,
      'nickname': participant.nickname,
      'isTyping': isTyping,
    });

    if (isTyping) {
      _typingTimers[participant.id] = Timer(const Duration(seconds: 3), () {
        _broadcast({
          'type': 'typing_indicator',
          'participantId': participant.id,
          'nickname': participant.nickname,
          'isTyping': false,
        });
      });
    }
  }

  void _handleDisconnect(WebSocketChannel channel) {
    _pendingParticipants.remove(channel);
    _joinTimers.remove(channel)?.cancel();
    final participant = _participants.remove(channel);
    if (participant != null) {
      _typingTimers[participant.id]?.cancel();
      _typingTimers.remove(participant.id);

      _broadcast({
        'type': 'participant_left',
        'participantId': participant.id,
        'nickname': participant.nickname,
      });

      addSystemMessage('${participant.nickname} left the room');
      _notifyParticipantCount();
    }
  }

  void addSystemMessage(String text) {
    final msg = ChatMessage(
      seq: ++_seq,
      type: ChatMessageType.system,
      senderId: 'system',
      senderNickname: 'System',
      text: text,
      timestamp: DateTime.now(),
      color: '#94A3B8',
    );
    _appendAndBroadcastMessage(msg);
  }

  void sendHostMessage(String text, {bool isE2e = false, String? ciphertext, String? iv, String? alg}) {
    final msg = ChatMessage(
      seq: ++_seq,
      type: ChatMessageType.text,
      senderId: 'host_device',
      senderNickname: 'Host (You)',
      text: isE2e ? '[Encrypted Message]' : text,
      timestamp: DateTime.now(),
      isSecureClient: true,
      color: '#10B981',
      isE2e: isE2e,
      ciphertext: ciphertext,
      iv: iv,
      alg: alg ?? (isE2e ? 'AES-GCM' : null),
    );
    _appendAndBroadcastMessage(msg);
  }

  void addFileMessage({
    required String senderId,
    required String nickname,
    required String filename,
    required int size,
    required String mimeType,
    required String downloadPath,
    required bool isSecureClient,
    required String color,
  }) {
    final msg = ChatMessage(
      seq: ++_seq,
      type: ChatMessageType.file,
      senderId: senderId,
      senderNickname: nickname,
      filename: filename,
      fileSize: size,
      fileMimeType: mimeType,
      fileDownloadPath: downloadPath,
      timestamp: DateTime.now(),
      isSecureClient: isSecureClient,
      color: color,
    );
    _appendAndBroadcastMessage(msg);
  }

  void _appendAndBroadcastMessage(ChatMessage msg) {
    _messages.add(msg);
    if (_messages.length > config.maxTotalMessages) {
      _messages.removeAt(0);
    }
    _broadcast(msg.toJson()
      ..['messageType'] = msg.type.name
      ..['type'] = 'chat_message');
    onNewMessage?.call(msg);
  }

  void broadcastHeartbeat({required int remainingSeconds}) {
    _broadcast({
      'type': 'heartbeat',
      'remainingSeconds': remainingSeconds,
      'participantCount': participantCount,
      'secureParticipants': secureParticipantCount,
      'browserParticipants': browserParticipantCount,
      'messageCount': messageCount,
    });
  }

  void broadcastDestroyed(String reason) {
    _broadcast({
      'type': 'room_destroyed',
      'reason': reason,
    });
  }

  void _broadcast(Map<String, dynamic> data) {
    final encoded = jsonEncode(data);
    for (final p in _participants.values) {
      try {
        p.channel.sink.add(encoded);
      } catch (_) {}
    }
  }

  void _broadcastExcept(WebSocketChannel exclude, Map<String, dynamic> data) {
    final encoded = jsonEncode(data);
    for (final entry in _participants.entries) {
      if (entry.key != exclude) {
        try {
          entry.value.channel.sink.add(encoded);
        } catch (_) {}
      }
    }
  }

  void _notifyParticipantCount() {
    onParticipantChanged?.call(
      totalParticipants: participantCount,
      secureParticipants: secureParticipantCount,
      browserParticipants: browserParticipantCount,
    );
    broadcastHeartbeat(remainingSeconds: getRemainingSeconds?.call() ?? 0);
  }

  void clearAndCloseAll() {
    for (final timer in _joinTimers.values) {
      timer.cancel();
    }
    _joinTimers.clear();
    for (final pending in _pendingParticipants.values) {
      pending.channel.sink.close();
    }
    _pendingParticipants.clear();
    for (final t in _typingTimers.values) {
      t.cancel();
    }
    _typingTimers.clear();

    for (final p in _participants.values) {
      try {
        p.channel.sink.close();
      } catch (_) {}
    }
    _participants.clear();
    _messages.clear();
  }
}
