import 'package:crypto/crypto.dart';
import 'dart:convert';
import 'dart:math';
import 'package:cloud_pocket/tunnel/tunnel_config.dart';

enum RoomDuration {
  min5(Duration(minutes: 5), '5 Minutes'),
  min15(Duration(minutes: 15), '15 Minutes'),
  min30(Duration(minutes: 30), '30 Minutes'),
  hour1(Duration(hours: 1), '1 Hour'),
  hour2(Duration(hours: 2), '2 Hours');

  final Duration duration;
  final String label;
  const RoomDuration(this.duration, this.label);
}

class RoomConfig {
  final String roomName;
  final String roomCode;
  final String inviteToken;
  final RoomDuration duration;
  final int maxParticipants;
  final bool requirePin;
  final String? pin;
  final String? pinHash;
  final bool allowFileSharing;
  final int maxFileSizeMb;
  final int maxTotalMessages;
  final int maxMessageLength;
  final bool enableTunnel;
  final TunnelConfig tunnelConfig;
  final bool isTokenRevoked;

  const RoomConfig({
    this.roomName = 'Disposable Room',
    this.roomCode = '',
    this.inviteToken = '',
    this.duration = RoomDuration.min15,
    this.maxParticipants = 10,
    this.requirePin = false,
    this.pin,
    this.pinHash,
    this.allowFileSharing = true,
    this.maxFileSizeMb = 100,
    this.maxTotalMessages = 1000,
    this.maxMessageLength = 5000,
    this.enableTunnel = true,
    this.tunnelConfig = const TunnelConfig(),
    this.isTokenRevoked = false,
  });

  static String generateRoomCode() {
    const letters = 'ABCDEFGHJKLMNPQRSTUVWXYZ';
    final rand = Random();
    final l1 = letters[rand.nextInt(letters.length)];
    final l2 = letters[rand.nextInt(letters.length)];
    final num = 1000 + rand.nextInt(9000);
    return '$l1$l2-$num';
  }

  /// Generates a cryptographically secure 128-bit (16-byte, 32 hex char) invite token
  static String generateInviteToken() {
    final rand = Random.secure();
    final bytes = List<int>.generate(16, (_) => rand.nextInt(256));
    return bytes.map((b) => b.toRadixString(16).padLeft(2, '0')).join();
  }

  static String hashPin(String pin) {
    return sha256.convert(utf8.encode(pin)).toString();
  }

  bool verifyPin(String candidatePin) {
    if (!requirePin) return true;
    if (pinHash == null || pinHash!.isEmpty) return false;
    final hashed = hashPin(candidatePin.trim());
    return hashed == pinHash;
  }

  RoomConfig copyWith({
    String? roomName,
    String? roomCode,
    String? inviteToken,
    RoomDuration? duration,
    int? maxParticipants,
    bool? requirePin,
    String? pin,
    String? pinHash,
    bool clearPin = false,
    bool? allowFileSharing,
    int? maxFileSizeMb,
    int? maxTotalMessages,
    int? maxMessageLength,
    bool? enableTunnel,
    TunnelConfig? tunnelConfig,
    bool? isTokenRevoked,
  }) {
    return RoomConfig(
      roomName: roomName ?? this.roomName,
      roomCode: roomCode ?? this.roomCode,
      inviteToken: inviteToken ?? this.inviteToken,
      duration: duration ?? this.duration,
      maxParticipants: maxParticipants ?? this.maxParticipants,
      requirePin: requirePin ?? this.requirePin,
      pin: clearPin ? null : (pin ?? this.pin),
      pinHash: clearPin ? null : (pinHash ?? this.pinHash),
      allowFileSharing: allowFileSharing ?? this.allowFileSharing,
      maxFileSizeMb: maxFileSizeMb ?? this.maxFileSizeMb,
      maxTotalMessages: maxTotalMessages ?? this.maxTotalMessages,
      maxMessageLength: maxMessageLength ?? this.maxMessageLength,
      enableTunnel: enableTunnel ?? this.enableTunnel,
      tunnelConfig: tunnelConfig ?? this.tunnelConfig,
      isTokenRevoked: isTokenRevoked ?? this.isTokenRevoked,
    );
  }

  Map<String, dynamic> toJson() => {
    'roomName': roomName,
    'roomCode': roomCode,
    'durationSeconds': duration.duration.inSeconds,
    'durationLabel': duration.label,
    'maxParticipants': maxParticipants,
    'requirePin': requirePin,
    'allowFileSharing': allowFileSharing,
    'maxFileSizeMb': maxFileSizeMb,
  };
}
