import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:cloud_pocket/models/share_session.dart';
import 'package:cloud_pocket/models/room_config.dart';
import 'package:cloud_pocket/tunnel/tunnel_config.dart';

import 'package:cloud_pocket/providers/settings_provider.dart';

class SessionNotifier extends Notifier<ShareSession> {
  @override
  ShareSession build() {
    final settings = ref.read(settingsProvider);

    ref.listen<SettingsState>(settingsProvider, (previous, next) {
      if (previous == null) return;
      if (previous.defaultExpiry != next.defaultExpiry) {
        state = state.copyWith(expiryDuration: next.defaultExpiry);
      }
      if (previous.defaultEnableTunnel != next.defaultEnableTunnel) {
        state = state.copyWith(enableTunnel: next.defaultEnableTunnel);
      }
      if (previous.defaultProvider != next.defaultProvider ||
          previous.customBoreHost != next.customBoreHost ||
          previous.customBorePort != next.customBorePort ||
          previous.customLocalTunnelSubdomain != next.customLocalTunnelSubdomain ||
          previous.cloudflareTunnelToken != next.cloudflareTunnelToken) {
        state = state.copyWith(
          tunnelConfig: _buildTunnelConfig(next.defaultProvider, next),
        );
      }
    });

    return ShareSession(
      expiryDuration: settings.defaultExpiry,
      enableTunnel: settings.defaultEnableTunnel,
      tunnelConfig: _buildTunnelConfig(settings.defaultProvider, settings),
    );
  }

  TunnelConfig _buildTunnelConfig(TunnelProvider provider, SettingsState settings) {
    switch (provider) {
      case TunnelProvider.cloudflareCustom:
        return TunnelConfig(
          provider: provider,
          cloudflareApiToken: settings.cloudflareApiToken,
          cloudflareAccountId: settings.cloudflareAccountId,
          cloudflareZoneId: settings.cloudflareZoneId,
          cloudflareDomain: settings.cloudflareDomain,
          cloudflareTunnelId: settings.cloudflareTunnelId,
          cloudflareTunnelToken: settings.cloudflareTunnelToken,
        );
      case TunnelProvider.customBore:
        return TunnelConfig(
          provider: provider,
          relayHost: settings.customBoreHost ?? 'bore.pub',
          relayPort: settings.customBorePort,
        );
      case TunnelProvider.localtunnel:
        return TunnelConfig(
          provider: provider,
          preferredSubdomain: settings.customLocalTunnelSubdomain,
        );
      default:
        return TunnelConfig(provider: provider);
    }
  }

  void addItems(List<SharedItem> newItems) {
    final updated = List<SharedItem>.from(state.items);
    for (final item in newItems) {
      if (!updated.any((existing) => existing.path == item.path)) {
        updated.add(item);
      }
    }
    state = state.copyWith(items: updated);
  }

  void removeItem(SharedItem item) {
    final updated = List<SharedItem>.from(state.items)..removeWhere((i) => i.path == item.path);
    state = state.copyWith(items: updated);
  }

  void clearItems() {
    state = state.copyWith(items: const []);
  }

  void setRequireGoogleAuth(bool require) {
    state = state.copyWith(
      requireGoogleAuth: require,
      enableTunnel: require ? true : state.enableTunnel,
    );
  }

  void setGoogleClientId(String? id) {
    state = state.copyWith(googleClientId: id);
  }

  void setRequirePassword(bool require) {
    final updatedConfig = state.roomConfig?.copyWith(
      requirePin: require,
      clearPin: !require,
    );
    state = state.copyWith(
      requirePassword: require,
      roomConfig: updatedConfig,
    );
  }

  void setPassword(String password) {
    if (password.isEmpty) {
      final updatedConfig = state.roomConfig?.copyWith(clearPin: true);
      state = state.copyWith(
        clearPassword: true,
        roomConfig: updatedConfig,
      );
    } else {
      final hash = ShareSession.hashPassword(password);
      final updatedConfig = state.roomConfig?.copyWith(
        pin: password,
        pinHash: hash,
        requirePin: true,
      );
      state = state.copyWith(
        password: password,
        passwordHash: hash,
        roomConfig: updatedConfig,
      );
    }
  }

  void setVaultMode(bool enabled, {int? maxDownloads, bool? autoDelete}) {
    state = state.copyWith(
      isVaultMode: enabled,
      maxDownloadsPerFile: maxDownloads,
      clearMaxDownloads: maxDownloads == null,
      autoDeleteAfterExpiry: autoDelete,
    );
  }

  void setAllowedEmails(List<String> emails) {
    state = state.copyWith(allowedEmails: emails);
  }

  void setExpiryDuration(ExpiryDuration duration) {
    final updatedConfig = state.roomConfig?.copyWith(
      duration: duration.toRoomDuration(),
    );
    state = state.copyWith(
      expiryDuration: duration,
      roomConfig: updatedConfig,
    );
  }

  void setAllowUploads(bool allow) {
    state = state.copyWith(allowUploads: allow);
  }

  void setIsReceiveMode(bool isReceive) {
    state = state.copyWith(
      isReceiveMode: isReceive,
      isDisposableRoom: isReceive ? false : state.isDisposableRoom,
      allowUploads: isReceive ? true : state.allowUploads,
      items: isReceive ? const [] : state.items,
    );
  }

  void setIsDisposableRoom(bool isRoom) {
    final effectiveExpiry = (isRoom && state.expiryDuration == ExpiryDuration.manual)
        ? ExpiryDuration.min15
        : state.expiryDuration;

    final config = isRoom
        ? (state.roomConfig?.copyWith(
            duration: effectiveExpiry.toRoomDuration(),
            requirePin: state.requirePassword,
            pin: state.password,
            pinHash: state.passwordHash,
            enableTunnel: state.enableTunnel,
            tunnelConfig: state.tunnelConfig,
            roomCode: state.roomConfig?.roomCode.isNotEmpty == true ? state.roomConfig!.roomCode : RoomConfig.generateRoomCode(),
            inviteToken: state.roomConfig?.inviteToken.isNotEmpty == true ? state.roomConfig!.inviteToken : RoomConfig.generateInviteToken(),
          ) ??
          RoomConfig(
            roomName: 'Disposable Room',
            roomCode: RoomConfig.generateRoomCode(),
            inviteToken: RoomConfig.generateInviteToken(),
            duration: effectiveExpiry.toRoomDuration(),
            requirePin: state.requirePassword,
            pin: state.password,
            pinHash: state.passwordHash,
            enableTunnel: state.enableTunnel,
            tunnelConfig: state.tunnelConfig,
          ))
        : state.roomConfig;

    state = state.copyWith(
      isDisposableRoom: isRoom,
      isReceiveMode: isRoom ? false : state.isReceiveMode,
      allowUploads: isRoom ? true : state.allowUploads,
      enableTunnel: state.enableTunnel,
      expiryDuration: effectiveExpiry,
      roomConfig: config,
    );
  }

  void setRoomName(String name) {
    final clean = name.trim().isEmpty ? 'Disposable Room' : name.trim();
    final updatedConfig = state.roomConfig?.copyWith(roomName: clean) ??
        RoomConfig(
          roomName: clean,
          roomCode: RoomConfig.generateRoomCode(),
          inviteToken: RoomConfig.generateInviteToken(),
        );
    state = state.copyWith(roomConfig: updatedConfig);
  }

  void setRoomConfig(RoomConfig config) {
    state = state.copyWith(roomConfig: config);
  }

  void setEnableTunnel(bool enable) {
    state = state.copyWith(enableTunnel: enable);
  }

  void setSharedText(String? text) {
    final clean = (text != null && text.trim().isNotEmpty) ? text.trim() : null;
    state = state.copyWith(
      sharedText: clean,
      clearSharedText: clean == null,
    );
  }

  void setTunnelProvider(TunnelProvider provider) {
    final settings = ref.read(settingsProvider);
    state = state.copyWith(
      tunnelConfig: _buildTunnelConfig(provider, settings),
    );
  }

  void updateTunnelConfig(TunnelConfig config) {
    state = state.copyWith(tunnelConfig: config);
  }

  void setSessionToken(String token) {
    state = state.copyWith(sessionToken: token);
  }

  void clearSessionToken() {
    state = state.copyWith(clearSessionToken: true);
  }

  void regenerateInviteToken() {
    if (state.roomConfig != null) {
      final newToken = RoomConfig.generateInviteToken();
      final updated = state.roomConfig!.copyWith(
        inviteToken: newToken,
        isTokenRevoked: false,
      );
      state = state.copyWith(roomConfig: updated);
    }
  }

  void resetSession() {
    final settings = ref.read(settingsProvider);
    state = ShareSession(
      expiryDuration: settings.defaultExpiry,
      enableTunnel: settings.defaultEnableTunnel,
      tunnelConfig: _buildTunnelConfig(settings.defaultProvider, settings),
    );
  }
}

final sessionProvider = NotifierProvider<SessionNotifier, ShareSession>(SessionNotifier.new);
