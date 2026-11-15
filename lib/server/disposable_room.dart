import 'dart:async';
import 'dart:io';
import 'package:uuid/uuid.dart';
import 'package:path/path.dart' as p;
import 'package:cloud_pocket/models/chat_message.dart';
import 'package:cloud_pocket/models/room_config.dart';
import 'package:cloud_pocket/server/chat_hub.dart';

class DisposableRoom {
  final String roomId;
  final RoomConfig config;
  final Directory tempDirectory;
  final ChatHub chatHub;
  final void Function(String reason)? onDestroyed;

  DateTime? _startedAt;
  DateTime? _expiresAt;
  Timer? _destructTimer;
  Timer? _heartbeatTimer;
  bool _isDestroyed = false;

  static const Uuid _uuid = Uuid();

  DisposableRoom._({
    required this.roomId,
    required this.config,
    required this.tempDirectory,
    required this.chatHub,
    this.onDestroyed,
  });

  static Future<DisposableRoom> create({
    required RoomConfig config,
    required Directory baseCacheDir,
    RoomParticipantCallback? onParticipantChanged,
    void Function(ChatMessage message)? onNewMessage,
    void Function(String reason)? onDestroyed,
  }) async {
    final roomId = _uuid.v4();
    final tempDir = Directory('${baseCacheDir.path}${Platform.pathSeparator}disposable_room_$roomId');
    if (!await tempDir.exists()) {
      await tempDir.create(recursive: true);
    }

    DisposableRoom? roomRef;
    final hub = ChatHub(
      config: config,
      onParticipantChanged: ({
        required int totalParticipants,
        required int secureParticipants,
        required int browserParticipants,
      }) {
        if (totalParticipants > 0) {
          roomRef?.activateCountdown();
        }
        onParticipantChanged?.call(
          totalParticipants: totalParticipants,
          secureParticipants: secureParticipants,
          browserParticipants: browserParticipants,
        );
      },
      onNewMessage: onNewMessage,
      getRemainingSeconds: () {
        roomRef?.activateCountdown();
        return roomRef?.remainingSeconds ?? 0;
      },
    );

    final room = DisposableRoom._(
      roomId: roomId,
      config: config,
      tempDirectory: tempDir,
      chatHub: hub,
      onDestroyed: onDestroyed,
    );
    roomRef = room;
    return room;
  }

  bool get isDestroyed => _isDestroyed;
  bool get isCountdownActive => !_isDestroyed && _expiresAt != null;
  DateTime? get expiresAt => _expiresAt;

  int get remainingSeconds {
    if (_isDestroyed) return 0;
    if (_expiresAt == null) return config.duration.duration.inSeconds;
    final diff = _expiresAt!.difference(DateTime.now()).inSeconds;
    return diff > 0 ? diff : 0;
  }

  void start() {
    if (_isDestroyed) return;

    // Heartbeat every 5 seconds
    _heartbeatTimer?.cancel();
    _heartbeatTimer = Timer.periodic(const Duration(seconds: 5), (_) {
      chatHub.broadcastHeartbeat(remainingSeconds: remainingSeconds);
    });

    chatHub.addSystemMessage(
      'Room created (${config.duration.label}). Timer starts when someone joins.',
    );
  }

  void activateCountdown() {
    if (_isDestroyed || _expiresAt != null) return;
    _startedAt = DateTime.now();
    _expiresAt = _startedAt!.add(config.duration.duration);

    // Authoritative self-destruct timer starts on first participant join
    _destructTimer?.cancel();
    _destructTimer = Timer(config.duration.duration, () {
      destroy('timer_expired');
    });

    chatHub.broadcastHeartbeat(remainingSeconds: remainingSeconds);
  }

  Future<void> destroy(String reason) async {
    if (_isDestroyed) return;
    _isDestroyed = true;

    _destructTimer?.cancel();
    _destructTimer = null;
    _heartbeatTimer?.cancel();
    _heartbeatTimer = null;

    // 1. Broadcast destruction to all participants
    chatHub.broadcastDestroyed(reason);

    // 2. Allow 200ms for network packets to flush
    await Future.delayed(const Duration(milliseconds: 200));

    // 3. Close all WebSockets and clear RAM message history
    chatHub.clearAndCloseAll();

    // 4. Safe recursive deletion of sandboxed room directory
    await _safelyDeleteDirectory(tempDirectory);

    // 5. Notify callback
    onDestroyed?.call(reason);
  }

  static Future<void> _safelyDeleteDirectory(Directory dir) async {
    try {
      if (await dir.exists()) {
        try {
          final entries = dir.listSync(recursive: true);
          for (final entry in entries) {
            if (entry is File) {
              try {
                entry.deleteSync();
              } catch (_) {}
            }
          }
        } catch (_) {}
        await dir.delete(recursive: true);
      }
    } catch (_) {
      // Retry once after 100ms
      await Future.delayed(const Duration(milliseconds: 100));
      try {
        if (await dir.exists()) {
          await dir.delete(recursive: true);
        }
      } catch (_) {}
    }
  }

  static Future<void> sweepOrphanedRoomDirectories(Directory baseCacheDir) async {
    try {
      if (!await baseCacheDir.exists()) return;
      final entities = baseCacheDir.listSync();
      for (final entity in entities) {
        if (entity is Directory && p.basename(entity.path).startsWith('disposable_room_')) {
          try {
            await _safelyDeleteDirectory(entity);
          } catch (_) {}
        }
      }
    } catch (_) {}
  }
}
