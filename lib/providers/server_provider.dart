import 'dart:async';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path_provider/path_provider.dart';
import 'package:uuid/uuid.dart';
import 'package:cloud_pocket/models/server_state.dart';
import 'package:cloud_pocket/models/share_history.dart';
import 'package:cloud_pocket/models/share_session.dart';
import 'package:cloud_pocket/models/transfer_record.dart';
import 'package:cloud_pocket/providers/history_provider.dart';
import 'package:cloud_pocket/providers/session_provider.dart';
import 'package:cloud_pocket/providers/settings_provider.dart';
import 'package:cloud_pocket/providers/stats_provider.dart';
import 'package:cloud_pocket/providers/transfers_provider.dart';
import 'package:cloud_pocket/server/server_engine.dart';
import 'package:cloud_pocket/services/app_logger.dart';
import 'package:cloud_pocket/services/foreground_service.dart';
import 'package:cloud_pocket/services/network_monitor.dart';
import 'package:cloud_pocket/services/permission_service.dart';
import 'package:cloud_pocket/services/pocket_link_generator.dart';
import 'package:cloud_pocket/tunnel/tunnel_config.dart';
import 'package:cloud_pocket/tunnel/tunnel_manager.dart';
import 'package:cloud_pocket/providers/network_provider.dart';
import 'package:cloud_pocket/providers/received_files_provider.dart';
import 'package:cloud_pocket/providers/room_provider.dart';
import 'package:cloud_pocket/server/disposable_room.dart';
import 'package:cloud_pocket/services/room_discovery_service.dart';

class ServerNotifier extends Notifier<ServerState> {
  ServerEngine? _engine;
  TunnelManager? _tunnelManager;
  Timer? _heartbeatTimer;
  int _heartbeatBackoffSec = 5;
  DateTime? _lastDiscoveryRefresh;
  Future<void>? _orphanSweep;

  ServerEngine? get engine => _engine;

  static String _getThemeModeString(ThemeMode mode) {
    switch (mode) {
      case ThemeMode.light:
        return 'light';
      case ThemeMode.dark:
        return 'dark';
      case ThemeMode.system:
        return 'system';
    }
  }

  static String _getHexColor(int colorValue) {
    return '#${(colorValue & 0xFFFFFF).toRadixString(16).padLeft(6, '0')}';
  }

  @override
  ServerState build() {
    _orphanSweep = getTemporaryDirectory().then((tempDir) {
      return DisposableRoom.sweepOrphanedRoomDirectories(tempDir);
    }).catchError((_) {});

    ref.listen<SettingsState>(settingsProvider, (previous, next) {
      if (previous == null) return;
      if (_engine != null && _engine!.isRunning) {
        if (previous.themeMode != next.themeMode || previous.primaryColorValue != next.primaryColorValue) {
          _engine!.updateTheme(
            themeMode: _getThemeModeString(next.themeMode),
            primaryColor: _getHexColor(next.primaryColorValue),
          );
        }
      }
    });

    ref.listen<AsyncValue<NetworkInfoState>>(networkStateProvider, (previous, next) {
      final prevIp = previous?.value?.localIp;
      final nextIp = next.value?.localIp;
      if (prevIp != null && nextIp != null && prevIp != nextIp && state.isRunning) {
        _handleNetworkChange();
      }
    });

    return const ServerState();
  }

  void _startHeartbeat() {
    _heartbeatTimer?.cancel();
    _heartbeatBackoffSec = 5;
    _lastDiscoveryRefresh = DateTime.now();
    _heartbeatTimer = Timer.periodic(const Duration(seconds: 30), (_) async {
      if (!state.isRunning || _engine == null) return;
      try {
        final port = _engine?.port ?? 8080;
        final socket = await Socket.connect('127.0.0.1', port, timeout: const Duration(seconds: 4));
        socket.destroy();
        _heartbeatBackoffSec = 5;
        final roomConfig = ref.read(sessionProvider).roomConfig;
        if (ref.read(sessionProvider).isDisposableRoom && roomConfig?.requirePin == true &&
            state.tunnelUrl != null && DateTime.now().difference(_lastDiscoveryRefresh!) >= const Duration(minutes: 5)) {
          _lastDiscoveryRefresh = DateTime.now();
          await RoomDiscoveryService.registerRoom(
            roomCode: roomConfig!.roomCode,
            tunnelUrl: state.tunnelUrl!,
            roomName: roomConfig.roomName,
            requirePin: true,
          );
        }
      } catch (e) {
        AppLogger().warn('HEARTBEAT', 'Local server unreachable on port ${_engine?.port}. Backoff: ${_heartbeatBackoffSec}s');
        await Future.delayed(Duration(seconds: _heartbeatBackoffSec));
        _heartbeatBackoffSec = (_heartbeatBackoffSec * 2).clamp(5, 60);
        if (state.isRunning && _engine != null && !_engine!.isRunning) {
          try {
            await _engine!.start(preferredPort: _engine?.port ?? 8080);
          } catch (_) {}
        }
      }
    });
  }

  Future<void> _handleNetworkChange() async {
    if (!state.isRunning) return;
    final netInfo = await NetworkMonitor.getNetworkState();
    final boundPort = _engine?.port ?? 8080;
    final localIp = netInfo.localIp ?? '127.0.0.1';
    final localUrl = 'http://$localIp:$boundPort';
    final allLocalUrls = netInfo.allIps.isNotEmpty
        ? netInfo.allIps.map((ip) => 'http://$ip:$boundPort').toList()
        : [localUrl];
    state = state.copyWith(localUrl: localUrl, allLocalUrls: allLocalUrls);

    final session = ref.read(sessionProvider);
    if ((session.enableTunnel || session.requireGoogleAuth) && _tunnelManager != null) {
      AppLogger().info('TUNNEL', 'Network interface change detected. Reconnecting tunnel...');
      await _tunnelManager?.stopTunnel();
      _tunnelManager = null;
      _startTunnelBackground(boundPort);
    }
  }

  /// Resolves the upload directory to customPath if configured, otherwise Downloads/CloudPocket
  static Future<String> resolveUploadDirectory([String? customPath]) async {
    if (customPath != null && customPath.trim().isNotEmpty) {
      final customDir = Directory(customPath.trim());
      try {
        if (!await customDir.exists()) {
          await customDir.create(recursive: true);
        }
        return customDir.path;
      } catch (_) {
        // Fall back to default directories if custom directory cannot be accessed
      }
    }

    // 1. Android public Download/CloudPocket directory
    if (Platform.isAndroid) {
      final downloadDirs = [
        Directory('/storage/emulated/0/Download'),
        Directory('/storage/emulated/0/Downloads'),
        Directory('/sdcard/Download'),
      ];
      for (final dir in downloadDirs) {
        if (await dir.exists()) {
          final target = Directory('${dir.path}/CloudPocket');
          try {
            if (!await target.exists()) {
              await target.create(recursive: true);
            }
            final probe = File('${target.path}/.write_probe_${DateTime.now().microsecondsSinceEpoch}.tmp');
            await probe.writeAsString('ok', flush: true);
            await probe.delete();
            return target.path;
          } catch (_) {}
        }
      }
    }

    // 2. Multi-platform getDownloadsDirectory() from path_provider
    try {
      final downloads = await getDownloadsDirectory();
      if (downloads != null) {
        final target = Directory('${downloads.path}/CloudPocket');
        try {
          if (!await target.exists()) {
            await target.create(recursive: true);
          }
          final probe = File('${target.path}/.write_probe_${DateTime.now().microsecondsSinceEpoch}.tmp');
          await probe.writeAsString('ok', flush: true);
          await probe.delete();
          return target.path;
        } catch (_) {}
      }
    } catch (_) {}

    // 3. Fallback to external storage Downloads/CloudPocket
    try {
      final extDir = await getExternalStorageDirectory();
      if (extDir != null) {
        final target = Directory('${extDir.path}/Downloads/CloudPocket');
        if (!await target.exists()) {
          await target.create(recursive: true);
        }
        return target.path;
      }
    } catch (_) {}

    // 4. Last resort fallback to app documents
    final docsDir = await getApplicationDocumentsDirectory();
    final target = Directory('${docsDir.path}/Downloads/CloudPocket');
    if (!await target.exists()) {
      await target.create(recursive: true);
    }
    return target.path;
  }

  Future<void> startServer() async {
    if (state.isRunning || state.status == ServerStatus.starting) return;

    final session = ref.read(sessionProvider);
    if (!session.isReceiveMode && !session.isDisposableRoom && session.items.isEmpty) {
      state = state.copyWith(
        status: ServerStatus.error,
        errorMessage: 'Please select at least one file or folder to share, or switch to Receive or Room Mode.',
      );
      return;
    }

    state = state.copyWith(status: ServerStatus.starting, errorMessage: null);

    try {
      final settings = ref.read(settingsProvider);
      if (session.isDisposableRoom) await _orphanSweep;

      var activeSession = session;
      if (activeSession.sessionToken == null || activeSession.sessionToken!.isEmpty) {
        final token = ShareSession.generateSessionToken();
        activeSession = activeSession.copyWith(sessionToken: token);
        ref.read(sessionProvider.notifier).setSessionToken(token);
      }

      // 1. Resolve upload directory (custom if set, temp cache if room, otherwise Downloads/CloudPocket)
      final uploadDir = activeSession.isDisposableRoom
          ? (await getTemporaryDirectory()).path
          : await resolveUploadDirectory(settings.customUploadDirectory);

      final Map<String, int> lastProgressReport = {};

      // 2. Start Shelf Server Engine
      _engine = ServerEngine(
        session: activeSession,
        uploadDir: uploadDir,
        deviceName: settings.deviceName,
        themeMode: _getThemeModeString(settings.themeMode),
        primaryColor: _getHexColor(settings.primaryColorValue),
        onExpired: () {
          AppLogger().info('SERVER', 'Share session duration expired. Automatically stopping server.');
          stopServer();
        },
        onRoomMessage: (msg) {
          ref.read(roomProvider.notifier).onNewMessage(msg);
        },
        onRoomParticipantsChanged: (total, secure, browser) {
          ref.read(roomProvider.notifier).onParticipantsChanged(total, secure, browser);
        },
        onStatsUpdated: (stats) {
          ref.read(statsProvider.notifier).updateStats(stats);
          CloudPocketForegroundService.updateNotification(
            title: session.isDisposableRoom ? 'CloudPocket Disposable Room' : 'CloudPocket Sharing Active',
            text: session.isDisposableRoom
                ? '${stats.activeConnections} participants connected'
                : '${stats.activeConnections} clients · ${stats.formattedSentBytes} sent',
          );
        },
        onTransferProgress: ({
          required String filename,
          required int bytesTransferred,
          required int totalBytes,
          required bool isUpload,
        }) {
          if (_engine?.isTransferCancelled(filename) == true) return;
          final now = DateTime.now().millisecondsSinceEpoch;
          final lastReport = lastProgressReport[filename] ?? 0;
          final isComplete = totalBytes > 0 && bytesTransferred >= totalBytes;
          if (!isComplete && (now - lastReport) < 100) {
            return;
          }
          lastProgressReport[filename] = now;
          if (isComplete) {
            lastProgressReport.remove(filename);
            if (isUpload) {
              // Refresh received files list immediately upon upload completion
              ref.read(receivedFilesProvider.notifier).refresh();
            }
          }

          final id = filename;
          final speed = ref.read(statsProvider).bandwidthBytesPerSec;
          final transfers = ref.read(transfersProvider);
          final existing = transfers.any((t) => t.id == id);
          if (!existing) {
            ref.read(transfersProvider.notifier).addTransfer(TransferRecord(
              id: id,
              filename: filename,
              totalBytes: totalBytes,
              transferredBytes: bytesTransferred,
              direction: isUpload ? TransferDirection.upload : TransferDirection.download,
              status: isComplete ? TransferStatus.completed : TransferStatus.active,
              speedBytesPerSec: speed,
              startTime: DateTime.now(),
            ));
          } else {
            ref.read(transfersProvider.notifier).updateProgress(
              id: id,
              transferredBytes: bytesTransferred,
              speedBytesPerSec: speed,
            );
          }
        },
      );

      final boundPort = await _engine!.start(preferredPort: 8080);

      // 3. Resolve Local Network IP
      final netInfo = await NetworkMonitor.getNetworkState();
      final localIp = netInfo.localIp ?? '127.0.0.1';
      final localUrl = 'http://$localIp:$boundPort';
      final allLocalUrls = netInfo.allIps.isNotEmpty
          ? netInfo.allIps.map((ip) => 'http://$ip:$boundPort').toList()
          : [localUrl];

      // 4. Ensure Android Background Execution & Notification Permissions, then start Foreground Service
      await PermissionService.ensureBackgroundExecutionPermissions();
      if (session.isReceiveMode || session.allowUploads) {
        await PermissionService.ensureManageExternalStorage();
      }
      await CloudPocketForegroundService.start(
        title: session.isDisposableRoom ? 'CloudPocket Disposable Room' : 'CloudPocket is Sharing Files',
        text: 'Local URL: $localUrl',
      );

      final shouldTunnel = session.enableTunnel || session.requireGoogleAuth;
      final pocketSlug = PocketLinkGenerator.generateSlug(prefix: settings.deviceName);

      state = ServerState(
        status: ServerStatus.running,
        localUrl: localUrl,
        tunnelUrl: null,
        pocketLinkSlug: pocketSlug,
        isTunnelConnecting: shouldTunnel,
        startTime: DateTime.now(),
        allLocalUrls: allLocalUrls,
      );

      _startHeartbeat();

      if (session.isDisposableRoom) {
        ref.read(roomProvider.notifier).startRoomSession();
      }

      // 5. Start Public Internet Tunnel asynchronously if requested
      if (shouldTunnel) {
        _startTunnelBackground(boundPort);
      }
    } catch (e) {
      await stopServer();
      state = ServerState(
        status: ServerStatus.error,
        errorMessage: 'Failed to start server: $e',
      );
    }
  }

  Future<void> _startTunnelBackground(int port) async {
    state = state.copyWith(isTunnelConnecting: true, clearTunnelError: true);
    try {
      final session = ref.read(sessionProvider);
      _tunnelManager = TunnelManager(
        localPort: port,
        config: session.tunnelConfig,
        onTunnelChanged: (newUrl, provider, latency) {
          if (!state.isRunning) return;
          state = state.copyWith(
            tunnelUrl: newUrl,
            activeTunnelProvider: provider,
            tunnelLatencyMs: latency,
          );
          if (session.isDisposableRoom && session.roomConfig != null) {
            RoomDiscoveryService.registerRoom(
              roomCode: session.roomConfig!.roomCode,
              tunnelUrl: newUrl,
              roomName: session.roomConfig!.roomName,
              requirePin: session.roomConfig!.requirePin,
            );
          }
        },
      );
      final publicUrl = await _tunnelManager!.startTunnel();
      if (!state.isRunning) {
        await _tunnelManager?.stopTunnel();
        _tunnelManager = null;
        return;
      }
      if (publicUrl != null) {
        state = state.copyWith(
          tunnelUrl: publicUrl,
          activeTunnelProvider: _tunnelManager?.activeProvider,
          tunnelLatencyMs: _tunnelManager?.latencyMs,
          clearTunnelError: true,
          isTunnelConnecting: false,
        );
        if (session.isDisposableRoom && session.roomConfig != null) {
          RoomDiscoveryService.registerRoom(
            roomCode: session.roomConfig!.roomCode,
            tunnelUrl: publicUrl,
            roomName: session.roomConfig!.roomName,
            requirePin: session.roomConfig!.requirePin,
          );
        }
      } else {
        state = state.copyWith(
          clearTunnelUrl: true,
          tunnelError: 'Could not obtain a public tunnel address.',
          isTunnelConnecting: false,
        );
      }
    } on TunnelException catch (e) {
      if (!state.isRunning) return;
      state = state.copyWith(
        clearTunnelUrl: true,
        tunnelError: e.message,
        isTunnelConnecting: false,
      );
    } catch (e) {
      if (!state.isRunning) return;
      state = state.copyWith(
        clearTunnelUrl: true,
        tunnelError: 'Tunnel error: $e',
        isTunnelConnecting: false,
      );
    }
  }

  Future<void> fallbackToLocalTunnel() async {
    if (!state.isRunning) return;
    AppLogger().info('SERVER', 'User requested manual fallback to LocalTunnel (loca.lt)');
    await _tunnelManager?.stopTunnel();
    _tunnelManager = null;
    state = state.copyWith(
      isTunnelConnecting: true,
      clearTunnelError: true,
      clearTunnelUrl: true,
      activeTunnelProvider: TunnelProvider.localtunnel,
    );

    try {
      final port = _engine?.port ?? 8080;
      final session = ref.read(sessionProvider);
      final config = const TunnelConfig().copyWith(provider: TunnelProvider.localtunnel);
      _tunnelManager = TunnelManager(
        localPort: port,
        config: config,
        onTunnelChanged: (newUrl, provider, latency) {
          if (!state.isRunning) return;
          state = state.copyWith(
            tunnelUrl: newUrl,
            activeTunnelProvider: provider,
            tunnelLatencyMs: latency,
          );
          if (session.isDisposableRoom && session.roomConfig != null) {
            RoomDiscoveryService.registerRoom(
              roomCode: session.roomConfig!.roomCode,
              tunnelUrl: newUrl,
              roomName: session.roomConfig!.roomName,
              requirePin: session.roomConfig!.requirePin,
            );
          }
        },
      );
      final publicUrl = await _tunnelManager!.startTunnel();
      if (!state.isRunning) {
        await _tunnelManager?.stopTunnel();
        _tunnelManager = null;
        return;
      }
      if (publicUrl != null) {
        state = state.copyWith(
          tunnelUrl: publicUrl,
          activeTunnelProvider: TunnelProvider.localtunnel,
          tunnelLatencyMs: _tunnelManager?.latencyMs,
          clearTunnelError: true,
          isTunnelConnecting: false,
        );
        if (session.isDisposableRoom && session.roomConfig != null) {
          RoomDiscoveryService.registerRoom(
            roomCode: session.roomConfig!.roomCode,
            tunnelUrl: publicUrl,
            roomName: session.roomConfig!.roomName,
            requirePin: session.roomConfig!.requirePin,
          );
        }
      } else {
        state = state.copyWith(
          clearTunnelUrl: true,
          tunnelError: 'LocalTunnel did not return a public address.',
          isTunnelConnecting: false,
        );
      }
    } catch (e) {
      if (!state.isRunning) return;
      state = state.copyWith(
        clearTunnelUrl: true,
        tunnelError: 'LocalTunnel failed: $e',
        isTunnelConnecting: false,
      );
    }
  }

  Future<void> toggleTunnel(bool enable) async {
    if (!state.isRunning) return;

    if (enable) {
      if (_tunnelManager != null && _tunnelManager!.isRunning) return;
      final port = _engine?.port ?? 8080;
      await _startTunnelBackground(port);
    } else {
      await _tunnelManager?.stopTunnel();
      _tunnelManager = null;
      state = state.copyWith(
        clearTunnelUrl: true,
        clearActiveTunnelProvider: true,
        clearTunnelLatency: true,
        clearTunnelError: true,
        isTunnelConnecting: false,
      );
    }
  }

  void updatePocketLinkSlug(String slug) {
    state = state.copyWith(pocketLinkSlug: slug);
  }

  void setLocalUrl(String url) {
    if (state.localUrl == url) return;
    state = state.copyWith(localUrl: url);
    final session = ref.read(sessionProvider);
    CloudPocketForegroundService.updateNotification(
      title: session.isDisposableRoom ? 'CloudPocket Disposable Room' : 'CloudPocket Sharing Active',
      text: 'Local URL: $url',
      force: true,
    );
  }

  void togglePauseTransfer(String id) {
    _engine?.togglePauseTransfer(id);
    ref.read(transfersProvider.notifier).togglePause(id);
  }

  void cancelTransfer(String id) {
    _engine?.cancelTransfer(id);
    ref.read(transfersProvider.notifier).failTransfer(id, 'Cancelled');
  }

  Future<void> stopServer() async {
    final stats = ref.read(statsProvider);
    final session = ref.read(sessionProvider);
    final startTime = state.startTime;

    state = state.copyWith(status: ServerStatus.stopping);

    _heartbeatTimer?.cancel();
    _heartbeatTimer = null;

    try {
      await _engine?.stop();
      _engine = null;
      await _tunnelManager?.stopTunnel();
      _tunnelManager = null;
      await CloudPocketForegroundService.stop();

      // Clear any active transfers on server stop
      ref.read(transfersProvider.notifier).clearTransfers();

      // Invalidate session token on stop
      ref.read(sessionProvider.notifier).clearSessionToken();

      if (session.isDisposableRoom) {
        if (session.roomConfig != null) {
          RoomDiscoveryService.unregisterRoom(session.roomConfig!.roomCode);
        }
        ref.read(roomProvider.notifier).stopRoomSession();
      }

      // Record to history if sharing was active
      if (!session.isDisposableRoom && startTime != null && session.items.isNotEmpty) {
        final duration = DateTime.now().difference(startTime).inSeconds;
        final record = ShareHistoryRecord(
          id: const Uuid().v4(),
          timestamp: startTime,
          itemCount: session.items.length,
          totalBytes: stats.totalBytesSent + stats.totalBytesReceived,
          durationSeconds: duration,
          securityLabel: session.securityDescription,
        );
        ref.read(historyProvider.notifier).addRecord(record);
      }

      ref.read(statsProvider.notifier).reset();
    } catch (_) {}

    state = const ServerState(status: ServerStatus.idle);
  }
}

final serverProvider = NotifierProvider<ServerNotifier, ServerState>(ServerNotifier.new);
