import 'dart:async';
import 'dart:io';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:mime/mime.dart';
import 'package:path/path.dart' as p;
import 'package:cloud_pocket/models/chat_message.dart';
import 'package:cloud_pocket/models/room_config.dart';
import 'package:cloud_pocket/models/server_state.dart';
import 'package:cloud_pocket/providers/server_provider.dart';
import 'package:cloud_pocket/providers/session_provider.dart';
import 'package:cloud_pocket/services/e2e_encryption_service.dart';

enum RoomStatus {
  idle,
  configuring,
  launching,
  live,
  destroying,
  destroyed,
}

class RoomState {
  final RoomStatus status;
  final RoomConfig config;
  final int remainingSeconds;
  final bool isCountdownActive;
  final int participantCount;
  final int secureParticipants;
  final int browserParticipants;
  final int messageCount;
  final List<ChatMessage> messages;
  final bool isBurned;
  final String? burnReason;

  const RoomState({
    this.status = RoomStatus.idle,
    this.config = const RoomConfig(),
    this.remainingSeconds = 0,
    this.isCountdownActive = false,
    this.participantCount = 0,
    this.secureParticipants = 0,
    this.browserParticipants = 0,
    this.messageCount = 0,
    this.messages = const [],
    this.isBurned = false,
    this.burnReason,
  });

  String get formattedRemainingTime {
    final m = remainingSeconds ~/ 60;
    final s = remainingSeconds % 60;
    return '${m.toString().padLeft(2, '0')}:${s.toString().padLeft(2, '0')}';
  }

  RoomState copyWith({
    RoomStatus? status,
    RoomConfig? config,
    int? remainingSeconds,
    bool? isCountdownActive,
    int? participantCount,
    int? secureParticipants,
    int? browserParticipants,
    int? messageCount,
    List<ChatMessage>? messages,
    bool? isBurned,
    String? burnReason,
    bool clearBurnReason = false,
  }) {
    return RoomState(
      status: status ?? this.status,
      config: config ?? this.config,
      remainingSeconds: remainingSeconds ?? this.remainingSeconds,
      isCountdownActive: isCountdownActive ?? this.isCountdownActive,
      participantCount: participantCount ?? this.participantCount,
      secureParticipants: secureParticipants ?? this.secureParticipants,
      browserParticipants: browserParticipants ?? this.browserParticipants,
      messageCount: messageCount ?? this.messageCount,
      messages: messages ?? this.messages,
      isBurned: isBurned ?? this.isBurned,
      burnReason: clearBurnReason ? null : (burnReason ?? this.burnReason),
    );
  }
}

class RoomNotifier extends Notifier<RoomState> {
  Timer? _uiTicker;

  @override
  RoomState build() {
    ref.listen<ServerState>(serverProvider, (prev, next) {
      final session = ref.read(sessionProvider);
      if (!session.isDisposableRoom) return;

      if (next.isRunning && (prev == null || !prev.isRunning)) {
        _onRoomStarted();
      } else if (!next.isRunning && prev != null && prev.isRunning) {
        _onRoomStopped();
      }
    });

    final currentServer = ref.read(serverProvider);
    final currentSession = ref.read(sessionProvider);
    if (currentServer.isRunning && currentSession.isDisposableRoom) {
      Future.microtask(() => _onRoomStarted());
    }

    return const RoomState();
  }

  void startRoomSession() => _onRoomStarted();
  void stopRoomSession() => _onRoomStopped();

  void onNewMessage(ChatMessage msg) {
    // Avoid duplicate additions if msg already present
    if (state.messages.any((m) => m.seq == msg.seq && m.senderId == msg.senderId && m.timestamp == msg.timestamp)) {
      return;
    }

    ChatMessage processed = msg;
    if (msg.isE2e && msg.ciphertext != null && msg.iv != null && (msg.text == null || msg.text == '[Encrypted Message]')) {
      final session = ref.read(sessionProvider);
      final secret = E2eEncryptionService.computeSecret(
        token: session.roomConfig?.inviteToken,
        pin: session.roomConfig?.pin,
      );
      if (secret != null) {
        final e2e = E2eEncryptionService.fromSecret(secret);
        final decrypted = e2e.decrypt(ciphertext: msg.ciphertext!, iv: msg.iv!);
        if (decrypted != null) {
          processed = msg.copyWith(text: decrypted);
        }
      }
    }

    final updated = List<ChatMessage>.from(state.messages)..add(processed);
    state = state.copyWith(
      messages: updated,
      messageCount: updated.length,
    );
  }

  void onParticipantsChanged(int total, int secure, int browser) {
    state = state.copyWith(
      participantCount: total,
      secureParticipants: secure,
      browserParticipants: browser,
    );
  }

  void _onRoomStarted() {
    final engine = ref.read(serverProvider.notifier).engine;
    final room = engine?.disposableRoom;
    if (room == null) return;

    final session = ref.read(sessionProvider);
    final secret = E2eEncryptionService.computeSecret(
      token: session.roomConfig?.inviteToken,
      pin: session.roomConfig?.pin,
    );
    final e2e = secret != null ? E2eEncryptionService.fromSecret(secret) : null;

    final decryptedMessages = room.chatHub.messages.map((m) {
      if (e2e != null && m.isE2e && m.ciphertext != null && m.iv != null && (m.text == null || m.text == '[Encrypted Message]')) {
        final decrypted = e2e.decrypt(ciphertext: m.ciphertext!, iv: m.iv!);
        if (decrypted != null) {
          return m.copyWith(text: decrypted);
        }
      }
      return m;
    }).toList();

    _uiTicker?.cancel();
    state = state.copyWith(
      status: RoomStatus.live,
      remainingSeconds: room.remainingSeconds,
      isCountdownActive: room.isCountdownActive,
      participantCount: room.chatHub.participantCount,
      secureParticipants: room.chatHub.secureParticipantCount,
      browserParticipants: room.chatHub.browserParticipantCount,
      messageCount: room.chatHub.messageCount,
      messages: decryptedMessages,
      isBurned: false,
      clearBurnReason: true,
    );

    _uiTicker = Timer.periodic(const Duration(seconds: 1), (_) {
      final r = ref.read(serverProvider.notifier).engine?.disposableRoom;
      if (r != null && !r.isDestroyed) {
        state = state.copyWith(
          remainingSeconds: r.remainingSeconds,
          isCountdownActive: r.isCountdownActive,
          participantCount: r.chatHub.participantCount,
          secureParticipants: r.chatHub.secureParticipantCount,
          browserParticipants: r.chatHub.browserParticipantCount,
          messageCount: r.chatHub.messageCount,
        );
      }
    });
  }

  void _onRoomStopped() {
    _uiTicker?.cancel();
    _uiTicker = null;
    state = state.copyWith(
      status: RoomStatus.destroyed,
      isBurned: true,
      remainingSeconds: 0,
      isCountdownActive: false,
      burnReason: state.burnReason ?? 'Session ended',
    );
  }

  void updateConfig(RoomConfig newConfig) {
    state = state.copyWith(config: newConfig);
    ref.read(sessionProvider.notifier).setRoomConfig(newConfig);
  }

  void setDuration(RoomDuration duration) {
    updateConfig(state.config.copyWith(duration: duration));
  }

  void setMaxParticipants(int count) {
    updateConfig(state.config.copyWith(maxParticipants: count));
  }

  void setRequirePin(bool require, {String? pin}) {
    if (require && pin != null && pin.isNotEmpty) {
      updateConfig(state.config.copyWith(
        requirePin: true,
        pin: pin,
        pinHash: RoomConfig.hashPin(pin),
      ));
    } else {
      updateConfig(state.config.copyWith(
        requirePin: false,
        clearPin: true,
      ));
    }
  }

  void setAllowFileSharing(bool allow) {
    updateConfig(state.config.copyWith(allowFileSharing: allow));
  }

  Future<void> burnRoomNow() async {
    state = state.copyWith(status: RoomStatus.destroying, burnReason: 'Host burned room');
    final engine = ref.read(serverProvider.notifier).engine;
    if (engine?.disposableRoom != null) {
      await engine!.disposableRoom!.destroy('host_burned');
    }
    await ref.read(serverProvider.notifier).stopServer();
  }

  void sendHostMessage(String text) {
    final clean = text.trim();
    if (clean.isEmpty) return;

    final engine = ref.read(serverProvider.notifier).engine;
    if (engine?.disposableRoom != null) {
      final session = ref.read(sessionProvider);
      final secret = E2eEncryptionService.computeSecret(
        token: session.roomConfig?.inviteToken,
        pin: session.roomConfig?.pin,
      );
      if (secret != null) {
        final e2e = E2eEncryptionService.fromSecret(secret);
        final enc = e2e.encrypt(clean);
        engine!.disposableRoom!.chatHub.sendHostMessage(
          clean,
          isE2e: true,
          ciphertext: enc.ciphertext,
          iv: enc.iv,
        );
      } else {
        engine!.disposableRoom!.chatHub.sendHostMessage(
          clean,
          isE2e: false,
        );
      }
    }
  }

  Future<bool> sendHostFile(File sourceFile) async {
    final engine = ref.read(serverProvider.notifier).engine;
    final room = engine?.disposableRoom;
    if (room == null || room.isDestroyed) return false;
    if (!await sourceFile.exists()) return false;

    try {
      final rawName = p.basename(sourceFile.path);
      String finalName = rawName;
      File targetFile = File('${room.tempDirectory.path}${Platform.pathSeparator}$finalName');
      if (await targetFile.exists()) {
        final ext = p.extension(rawName);
        final base = p.basenameWithoutExtension(rawName);
        finalName = '${base}_${DateTime.now().millisecondsSinceEpoch}$ext';
        targetFile = File('${room.tempDirectory.path}${Platform.pathSeparator}$finalName');
      }

      // Stream copy (Zero-Buffer compliant)
      final sink = targetFile.openWrite();
      await sourceFile.openRead().pipe(sink);

      final fileSize = await targetFile.length();
      final mimeType = lookupMimeType(finalName) ?? 'application/octet-stream';
      final encodedName = Uri.encodeComponent(finalName);

      room.chatHub.addFileMessage(
        senderId: 'host_device',
        nickname: 'Host',
        filename: finalName,
        size: fileSize,
        mimeType: mimeType,
        downloadPath: '/api/room/files/$encodedName',
        isSecureClient: true,
        color: '#38BDF8',
      );
      return true;
    } catch (_) {
      return false;
    }
  }

  void resetRoom() {
    _uiTicker?.cancel();
    _uiTicker = null;
    state = const RoomState();
  }
}

final roomProvider = NotifierProvider<RoomNotifier, RoomState>(RoomNotifier.new);
