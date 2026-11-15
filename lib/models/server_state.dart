import 'package:flutter/foundation.dart';
import 'package:cloud_pocket/tunnel/tunnel_config.dart';

enum ServerStatus {
  idle,
  starting,
  running,
  stopping,
  error,
}

class ServerState {
  final ServerStatus status;
  final String? localUrl;
  final String? tunnelUrl;
  final String? pocketLinkSlug;
  final bool isTunnelConnecting;
  final String? errorMessage;
  final String? tunnelError;
  final DateTime? startTime;
  final TunnelProvider? activeTunnelProvider;
  final int? tunnelLatencyMs;
  final List<String> allLocalUrls;

  const ServerState({
    this.status = ServerStatus.idle,
    this.localUrl,
    this.tunnelUrl,
    this.pocketLinkSlug,
    this.isTunnelConnecting = false,
    this.errorMessage,
    this.tunnelError,
    this.startTime,
    this.activeTunnelProvider,
    this.tunnelLatencyMs,
    this.allLocalUrls = const [],
  });

  bool get isRunning => status == ServerStatus.running;
  bool get isIdle => status == ServerStatus.idle;

  ServerState copyWith({
    ServerStatus? status,
    String? localUrl,
    bool clearLocalUrl = false,
    String? tunnelUrl,
    bool clearTunnelUrl = false,
    String? pocketLinkSlug,
    bool clearPocketLinkSlug = false,
    bool? isTunnelConnecting,
    String? errorMessage,
    bool clearErrorMessage = false,
    String? tunnelError,
    bool clearTunnelError = false,
    DateTime? startTime,
    TunnelProvider? activeTunnelProvider,
    bool clearActiveTunnelProvider = false,
    int? tunnelLatencyMs,
    bool clearTunnelLatency = false,
    List<String>? allLocalUrls,
  }) {
    return ServerState(
      status: status ?? this.status,
      localUrl: clearLocalUrl ? null : (localUrl ?? this.localUrl),
      tunnelUrl: clearTunnelUrl ? null : (tunnelUrl ?? this.tunnelUrl),
      pocketLinkSlug: clearPocketLinkSlug ? null : (pocketLinkSlug ?? this.pocketLinkSlug),
      isTunnelConnecting: isTunnelConnecting ?? this.isTunnelConnecting,
      errorMessage: clearErrorMessage ? null : (errorMessage ?? this.errorMessage),
      tunnelError: clearTunnelError ? null : (tunnelError ?? this.tunnelError),
      startTime: startTime ?? this.startTime,
      activeTunnelProvider: clearActiveTunnelProvider ? null : (activeTunnelProvider ?? this.activeTunnelProvider),
      tunnelLatencyMs: clearTunnelLatency ? null : (tunnelLatencyMs ?? this.tunnelLatencyMs),
      allLocalUrls: allLocalUrls ?? this.allLocalUrls,
    );
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is ServerState &&
          runtimeType == other.runtimeType &&
          status == other.status &&
          localUrl == other.localUrl &&
          tunnelUrl == other.tunnelUrl &&
          pocketLinkSlug == other.pocketLinkSlug &&
          isTunnelConnecting == other.isTunnelConnecting &&
          errorMessage == other.errorMessage &&
          tunnelError == other.tunnelError &&
          startTime == other.startTime &&
          activeTunnelProvider == other.activeTunnelProvider &&
          tunnelLatencyMs == other.tunnelLatencyMs &&
          listEquals(allLocalUrls, other.allLocalUrls);

  @override
  int get hashCode => Object.hash(
        status,
        localUrl,
        tunnelUrl,
        pocketLinkSlug,
        isTunnelConnecting,
        errorMessage,
        tunnelError,
        startTime,
        activeTunnelProvider,
        tunnelLatencyMs,
        Object.hashAll(allLocalUrls),
      );
}
