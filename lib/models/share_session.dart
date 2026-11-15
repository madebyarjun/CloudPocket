import 'package:crypto/crypto.dart';
import 'dart:convert';
import 'dart:math';
import 'package:cloud_pocket/tunnel/tunnel_config.dart';
import 'package:cloud_pocket/models/room_config.dart';

enum ExpiryDuration {
  min5(Duration(minutes: 5), '5 Minutes'),
  min15(Duration(minutes: 15), '15 Minutes'),
  min30(Duration(minutes: 30), '30 Minutes'),
  hour1(Duration(hours: 1), '1 Hour'),
  hour2(Duration(hours: 2), '2 Hours'),
  hour6(Duration(hours: 6), '6 Hours'),
  hour24(Duration(hours: 24), '24 Hours'),
  manual(null, 'Until Stopped');

  final Duration? duration;
  final String label;
  const ExpiryDuration(this.duration, this.label);

  RoomDuration toRoomDuration() {
    switch (this) {
      case ExpiryDuration.min5:
        return RoomDuration.min5;
      case ExpiryDuration.min15:
        return RoomDuration.min15;
      case ExpiryDuration.min30:
        return RoomDuration.min30;
      case ExpiryDuration.hour1:
        return RoomDuration.hour1;
      case ExpiryDuration.hour2:
      case ExpiryDuration.hour6:
      case ExpiryDuration.hour24:
      case ExpiryDuration.manual:
        return RoomDuration.hour2;
    }
  }
}

class SharedItem {
  final String path;
  final String name;
  final int sizeBytes;
  final bool isDirectory;
  final String mimeType;

  const SharedItem({
    required this.path,
    required this.name,
    required this.sizeBytes,
    required this.isDirectory,
    required this.mimeType,
  });

  Map<String, dynamic> toJson() => {
    'path': name, // Client sees relative name/subpath, not full device path
    'name': name,
    'size': sizeBytes,
    'isDirectory': isDirectory,
    'mimeType': mimeType,
  };
}

class ShareSession {
  final List<SharedItem> items;
  final bool requireGoogleAuth;
  final bool requirePassword;
  final String? password;
  final String? passwordHash;
  final List<String> allowedEmails;
  final ExpiryDuration expiryDuration;
  final bool allowUploads;
  final bool enableTunnel;
  final TunnelConfig tunnelConfig;
  final String? googleClientId;
  final bool isVaultMode;
  final int? maxDownloadsPerFile;
  final bool autoDeleteAfterExpiry;
  final String? sharedText;
  final bool isReceiveMode;
  final bool isDisposableRoom;
  final RoomConfig? roomConfig;
  final String? sessionToken;

  const ShareSession({
    this.items = const [],
    this.requireGoogleAuth = false,
    this.requirePassword = false,
    this.password,
    this.passwordHash,
    this.allowedEmails = const [],
    this.expiryDuration = ExpiryDuration.hour1,
    this.allowUploads = false,
    this.enableTunnel = true,
    this.tunnelConfig = const TunnelConfig(),
    this.googleClientId,
    this.isVaultMode = false,
    this.maxDownloadsPerFile,
    this.autoDeleteAfterExpiry = false,
    this.sharedText,
    this.isReceiveMode = false,
    this.isDisposableRoom = false,
    this.roomConfig,
    this.sessionToken,
  });

  static String generateSessionToken() {
    final rand = Random.secure();
    final bytes = List<int>.generate(16, (_) => rand.nextInt(256));
    return bytes.map((b) => b.toRadixString(16).padLeft(2, '0')).join();
  }

  bool get isProtected => requireGoogleAuth || requirePassword;

  String get securityDescription {
    if (isDisposableRoom) {
      return (roomConfig?.requirePin == true) ? 'PIN Protected Room' : 'Open Disposable Room';
    }
    if (requireGoogleAuth && requirePassword) {
      return 'Protected (2-Factor)';
    } else if (requireGoogleAuth) {
      return 'Sign-In Required';
    } else if (requirePassword) {
      return 'Password Protected';
    } else {
      return 'Open Access';
    }
  }

  static String hashPassword(String password) {
    return sha256.convert(utf8.encode(password)).toString();
  }

  ShareSession copyWith({
    List<SharedItem>? items,
    bool? requireGoogleAuth,
    bool? requirePassword,
    String? password,
    String? passwordHash,
    bool clearPassword = false,
    List<String>? allowedEmails,
    ExpiryDuration? expiryDuration,
    bool? allowUploads,
    bool? enableTunnel,
    TunnelConfig? tunnelConfig,
    String? googleClientId,
    bool clearGoogleClientId = false,
    bool? isVaultMode,
    int? maxDownloadsPerFile,
    bool clearMaxDownloads = false,
    bool? autoDeleteAfterExpiry,
    String? sharedText,
    bool clearSharedText = false,
    bool? isReceiveMode,
    bool? isDisposableRoom,
    RoomConfig? roomConfig,
    bool clearRoomConfig = false,
    String? sessionToken,
    bool clearSessionToken = false,
  }) {
    return ShareSession(
      items: items ?? this.items,
      requireGoogleAuth: requireGoogleAuth ?? this.requireGoogleAuth,
      requirePassword: requirePassword ?? this.requirePassword,
      password: clearPassword ? null : (password ?? this.password),
      passwordHash: clearPassword ? null : (passwordHash ?? this.passwordHash),
      allowedEmails: allowedEmails ?? this.allowedEmails,
      expiryDuration: expiryDuration ?? this.expiryDuration,
      allowUploads: allowUploads ?? (isReceiveMode == true || isDisposableRoom == true ? true : this.allowUploads),
      enableTunnel: enableTunnel ?? this.enableTunnel,
      tunnelConfig: tunnelConfig ?? this.tunnelConfig,
      googleClientId: clearGoogleClientId ? null : (googleClientId ?? this.googleClientId),
      isVaultMode: isVaultMode ?? this.isVaultMode,
      maxDownloadsPerFile: clearMaxDownloads ? null : (maxDownloadsPerFile ?? this.maxDownloadsPerFile),
      autoDeleteAfterExpiry: autoDeleteAfterExpiry ?? this.autoDeleteAfterExpiry,
      sharedText: clearSharedText ? null : (sharedText ?? this.sharedText),
      isReceiveMode: isReceiveMode ?? this.isReceiveMode,
      isDisposableRoom: isDisposableRoom ?? this.isDisposableRoom,
      roomConfig: clearRoomConfig ? null : (roomConfig ?? this.roomConfig),
      sessionToken: clearSessionToken ? null : (sessionToken ?? this.sessionToken),
    );
  }
}
