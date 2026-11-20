import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;
import 'package:flutter/services.dart';
import 'package:shelf/shelf.dart';
import 'package:shelf/shelf_io.dart' as shelf_io;
import 'package:shelf_router/shelf_router.dart';
import 'package:shelf_web_socket/shelf_web_socket.dart';
import 'package:web_socket_channel/web_socket_channel.dart';
import 'package:cloud_pocket/models/chat_message.dart';
import 'package:cloud_pocket/models/server_stats.dart';
import 'package:cloud_pocket/models/share_session.dart';
import 'package:cloud_pocket/models/room_config.dart';
import 'package:cloud_pocket/server/auth_middleware.dart';
import 'package:cloud_pocket/server/file_handler.dart';
import 'package:cloud_pocket/server/upload_handler.dart';
import 'package:cloud_pocket/server/vault_tracker.dart';
import 'package:cloud_pocket/server/disposable_room.dart';
import 'package:cloud_pocket/server/room_pin_rate_limiter.dart';
import 'package:cloud_pocket/server/security_headers.dart';
import 'package:cloud_pocket/services/app_logger.dart';
import 'package:mime/mime.dart' as mime_resolver;
import 'package:path/path.dart' as p;

typedef StatsUpdateCallback = void Function(ServerStats stats);
typedef TransferProgressCallback = void Function({
  required String filename,
  required int bytesTransferred,
  required int totalBytes,
  required bool isUpload,
});

class ServerEngine {
  final ShareSession session;
  final String uploadDir;
  final String deviceName;
  String themeMode;
  String primaryColor;
  final StatsUpdateCallback? onStatsUpdated;
  final TransferProgressCallback? onTransferProgress;
  final void Function()? onExpired;
  final void Function(ChatMessage message)? onRoomMessage;
  final void Function(int total, int secure, int browser)? onRoomParticipantsChanged;

  HttpServer? _server;
  AuthManager? _authManager;
  VaultTracker? _vaultTracker;
  DisposableRoom? _disposableRoom;
  Timer? _metricsTimer;
  Timer? _expiryTimer;

  DisposableRoom? get disposableRoom => _disposableRoom;

  final Set<WebSocketChannel> _wsClients = {};
  final Set<String> _pausedTransferIds = {};
  final Set<String> _cancelledTransferIds = {};
  final Map<String, Completer<void>> _pauseCompleters = {};

  // Real-time tracking
  int _activeConnections = 0;
  int _totalBytesSent = 0;
  int _totalBytesReceived = 0;
  int _lastBytesSent = 0;
  int _lastBytesReceived = 0;
  double _bandwidthBytesPerSec = 0.0;
  final Set<String> _connectedIps = {};
  final Map<String, String> _visitorRegistry = {}; // vid / key -> visitor name
  final Map<WebSocketChannel, String> _wsClientNames = {};
  DateTime? _startTime;

  ServerEngine({
    required this.session,
    required this.uploadDir,
    this.deviceName = "My Phone",
    this.themeMode = "dark",
    this.primaryColor = "#1B8A6B",
    this.onStatsUpdated,
    this.onTransferProgress,
    this.onExpired,
    this.onRoomMessage,
    this.onRoomParticipantsChanged,
  });

  bool get isRunning => _server != null;
  int? get port => _server?.port;

  bool isTransferPaused(String id) => _pausedTransferIds.contains(id);
  bool isTransferCancelled(String id) => _cancelledTransferIds.contains(id);

  void cancelTransfer(String id) {
    _cancelledTransferIds.add(id);
    _pausedTransferIds.remove(id);
    _pauseCompleters.remove(id)?.complete();
    broadcastTransferEvent({'type': 'transfer_cancelled', 'id': id, 'filename': id});
  }

  void togglePauseTransfer(String id) {
    if (_pausedTransferIds.contains(id)) {
      _pausedTransferIds.remove(id);
      _pauseCompleters.remove(id)?.complete();
      broadcastTransferEvent({
        'type': 'transfer_resumed',
        'id': id,
        'filename': id,
      });
    } else {
      _pausedTransferIds.add(id);
      _pauseCompleters[id] = Completer<void>();
      broadcastTransferEvent({
        'type': 'transfer_paused',
        'id': id,
        'filename': id,
      });
    }
  }

  Future<void> waitIfPaused(String id) async {
    if (_cancelledTransferIds.contains(id)) throw StateError('Transfer cancelled');
    while (_pausedTransferIds.contains(id)) {
      final completer = _pauseCompleters[id];
      if (completer != null && !completer.isCompleted) {
        await completer.future;
      } else {
        await Future.delayed(const Duration(milliseconds: 200));
      }
    }
    if (_cancelledTransferIds.contains(id)) throw StateError('Transfer cancelled');
  }

  void broadcastTransferEvent(Map<String, dynamic> event) {
    final msg = jsonEncode(event);
    for (final client in _wsClients) {
      try {
        client.sink.add(msg);
      } catch (_) {}
    }
  }

  void updateTheme({required String themeMode, required String primaryColor}) {
    this.themeMode = themeMode;
    this.primaryColor = primaryColor;
    broadcastTransferEvent({
      'type': 'theme_changed',
      'themeMode': themeMode,
      'primaryColor': primaryColor,
    });
  }

  void _registerVisitor(String name, {String? vid, String? ip}) {
    final cleanName = name.trim();
    if (cleanName.isEmpty) return;
    final key = (vid != null && vid.trim().isNotEmpty)
        ? vid.trim()
        : (ip ?? 'client_${_visitorRegistry.length + 1}');
    _visitorRegistry[key] = cleanName;
    _broadcastCurrentStats();
  }

  void _broadcastCurrentStats() {
    final liveActiveCount = math.max(_wsClients.length, _activeConnections);
    final visitors = _visitorRegistry.values.toSet().toList();
    onStatsUpdated?.call(ServerStats(
      activeConnections: liveActiveCount,
      totalBytesSent: _totalBytesSent,
      totalBytesReceived: _totalBytesReceived,
      bandwidthBytesPerSec: _bandwidthBytesPerSec,
      connectedClients: visitors.isNotEmpty ? visitors : _connectedIps.toList(),
      sessionStartTime: _startTime,
    ));
  }

  Future<int> start({int preferredPort = 8080}) async {
    if (_server != null) return _server!.port;

    _authManager = AuthManager(session);
    _vaultTracker = VaultTracker(
      isVaultMode: session.isVaultMode,
      maxDownloadsPerFile: session.maxDownloadsPerFile,
    );

    if (session.isDisposableRoom) {
      final effectiveConfig = (session.roomConfig ?? const RoomConfig()).copyWith(
        duration: session.expiryDuration.toRoomDuration(),
        requirePin: session.requirePassword,
        pin: session.password,
        pinHash: session.passwordHash,
      );
      _disposableRoom = await DisposableRoom.create(
        config: effectiveConfig,
        baseCacheDir: Directory(uploadDir),
        onParticipantChanged: ({
          required int totalParticipants,
          required int secureParticipants,
          required int browserParticipants,
        }) {
          _activeConnections = totalParticipants;
          _broadcastCurrentStats();
          onRoomParticipantsChanged?.call(totalParticipants, secureParticipants, browserParticipants);
        },
        onNewMessage: (msg) {
          onRoomMessage?.call(msg);
        },
        onDestroyed: (reason) {
          stop();
          onExpired?.call();
        },
      );
      _disposableRoom!.start();
    }

    final fileHandler = FileHandler(
      session,
      vaultTracker: _vaultTracker,
      pauseChecker: waitIfPaused,
      onTransferStarted: _cancelledTransferIds.remove,
      onChunkSent: (bytesSent) {
        _totalBytesSent += bytesSent;
      },
      onProgress: (filename, bytesWritten, totalBytes) {
        onTransferProgress?.call(
          filename: filename,
          bytesTransferred: bytesWritten,
          totalBytes: totalBytes,
          isUpload: false,
        );
        broadcastTransferEvent({
          'type': 'transfer_progress',
          'filename': filename,
          'transferred': bytesWritten,
          'total': totalBytes,
          'direction': 'download',
        });
      },
    );

    final uploadHandler = UploadHandler(
      saveDirectoryPath: uploadDir,
      allowUploads: session.allowUploads && !session.isDisposableRoom,
      pauseChecker: waitIfPaused,
      onTransferStarted: _cancelledTransferIds.remove,
      onChunkReceived: (bytesReceived) {
        _totalBytesReceived += bytesReceived;
      },
      onProgress: (filename, bytesWritten, totalBytes) {
        onTransferProgress?.call(
          filename: filename,
          bytesTransferred: bytesWritten,
          totalBytes: totalBytes,
          isUpload: true,
        );
        broadcastTransferEvent({
          'type': 'transfer_progress',
          'filename': filename,
          'transferred': bytesWritten,
          'total': totalBytes,
          'direction': 'upload',
        });
      },
    );

    final router = Router();

    // WebSocket endpoint for real-time transfer tracking
    final wsHandler = webSocketHandler((WebSocketChannel webSocket, String? _) {
      _wsClients.add(webSocket);
      _broadcastCurrentStats();
      webSocket.stream.listen(
        (data) {
          try {
            final json = jsonDecode(data.toString());
            if (json['type'] == 'register_name') {
              final name = (json['name'] as String?)?.trim();
              final vid = (json['visitorId'] as String?)?.trim();
              if (name != null && name.isNotEmpty) {
                _wsClientNames[webSocket] = name;
                _registerVisitor(name, vid: vid);
              }
            } else if (json['type'] == 'ping') {
              try {
                webSocket.sink.add(jsonEncode({'type': 'pong'}));
              } catch (_) {}
            }
          } catch (_) {}
        },
        onDone: () {
          _wsClients.remove(webSocket);
          _wsClientNames.remove(webSocket);
          _broadcastCurrentStats();
        },
        onError: (_) {
          _wsClients.remove(webSocket);
          _wsClientNames.remove(webSocket);
          _broadcastCurrentStats();
        },
      );
    });
    router.get('/ws/transfers', wsHandler);

    // Register Visitor Endpoint
    router.post('/api/register-visitor', (Request req) async {
      try {
        final body = await req.readAsString();
        final json = jsonDecode(body) as Map<String, dynamic>;
        final name = (json['name'] as String?)?.trim() ?? 'Visitor';
        final vid = (json['visitorId'] as String?)?.trim();
        final clientIp = (req.context['shelf.io.connection_info'] as HttpConnectionInfo?)
            ?.remoteAddress
            .address;
        _registerVisitor(name, vid: vid, ip: clientIp);
        return Response.ok(
          jsonEncode({'success': true, 'name': name}),
          headers: {'content-type': 'application/json'},
        );
      } catch (e) {
        return Response(400, body: jsonEncode({'error': 'Bad Request'}));
      }
    });

    // Static Web Portal Routes (Embedded Flutter Assets or Disk Fallback)
    router.get('/', (Request req) {
      if (session.isDisposableRoom) {
        return _serveAsset('assets/web/room.html', 'text/html');
      }
      return _serveAsset('assets/web/index.html', 'text/html');
    });
    router.get('/styles.css', (Request req) => _serveAsset('assets/web/styles.css', 'text/css'));
    router.get('/theme.css', (Request req) => _serveAsset('assets/web/theme.css', 'text/css'));
    router.get('/theme.js', (Request req) => _serveAsset('assets/web/theme.js', 'application/javascript'));
    router.get('/app.js', (Request req) => _serveAsset('assets/web/app.js', 'application/javascript'));
    router.get('/favicon.png', (Request req) => _serveAsset('assets/web/favicon.png', 'image/png'));
    router.get('/logo.png', (Request req) => _serveAsset('assets/web/logo.png', 'image/png'));

    // Disposable Room Web Client & APIs
    router.get('/room', (Request req) => _serveAsset('assets/web/room.html', 'text/html'));
    router.get('/room.js', (Request req) => _serveAsset('assets/web/room.js', 'application/javascript'));
    router.get('/room.css', (Request req) => _serveAsset('assets/web/room.css', 'text/css'));

    Future<Response> roomWsHandler(Request request) async {
      return webSocketHandler((WebSocketChannel webSocket, String? _) {
      if (_disposableRoom != null) {
        _disposableRoom!.chatHub.handleWebSocket(
          webSocket,
          remainingSeconds: _disposableRoom!.remainingSeconds,
          clientId: RoomPinRateLimiter.clientKey(request),
        );
      } else {
        webSocket.sink.close();
      }
      })(request);
    }
    router.get('/ws/room', roomWsHandler);
    router.get('/api/room/ws', roomWsHandler);

    // Room Info Endpoint
    router.get('/api/room/info', (Request req) {
      if (_disposableRoom == null) {
        return Response(404, body: jsonEncode({'error': 'No active room'}), headers: {'content-type': 'application/json'});
      }
      return Response.ok(
        jsonEncode({
          'roomId': _disposableRoom!.roomId,
          'roomName': session.roomConfig?.roomName ?? 'Disposable Room',
          'roomCode': session.roomConfig?.roomCode ?? '',
          'remainingSeconds': _disposableRoom!.remainingSeconds,
          'isCountdownActive': _disposableRoom!.isCountdownActive,
          'requirePin': session.roomConfig?.requirePin ?? false,
          'maxParticipants': session.roomConfig?.maxParticipants ?? 10,
          'allowFileSharing': session.roomConfig?.allowFileSharing ?? true,
          'participantCount': _disposableRoom!.chatHub.participantCount,
          'secureParticipants': _disposableRoom!.chatHub.secureParticipantCount,
          'browserParticipants': _disposableRoom!.chatHub.browserParticipantCount,
          'messageCount': _disposableRoom!.chatHub.messageCount,
          'themeMode': themeMode,
        }),
        headers: {'content-type': 'application/json'},
      );
    });

    // Room PIN & Token Validation
    router.post('/api/room/auth', (Request req) async {
      if (_disposableRoom == null || _disposableRoom!.isDestroyed) {
        return Response(404, body: jsonEncode({'error': 'No active room'}));
      }
      try {
        final body = await req.readAsString();
        final json = jsonDecode(body) as Map<String, dynamic>;
        final inputPin = json['pin'] as String?;
        final inputToken = json['token'] as String?;
        final roomCfg = session.roomConfig;

        final clientIp = RoomPinRateLimiter.clientKey(req);

        if (roomCfg != null) {
          final roomRateLimiter = RoomPinRateLimiter();
          if (roomRateLimiter.isLockedOut(clientIp)) return Response(429, body: 'Too many failed room authentication attempts');
          if (roomCfg.isTokenRevoked) return Response(401, body: 'Room invite has been revoked');
          // If PIN is required, a valid PIN is mandatory and cannot be bypassed by an invite token
          if (roomCfg.requirePin) {
            final rateLimiter = RoomPinRateLimiter();
            if (rateLimiter.isLockedOut(clientIp)) {
              return Response(
                429,
                body: jsonEncode({
                  'error': 'Too many failed PIN attempts. Locked out for 60 seconds.',
                  'code': 'LOCKED_OUT',
                }),
                headers: {'content-type': 'application/json'},
              );
            }

            final isPinValid = inputPin != null && inputPin.isNotEmpty && roomCfg.verifyPin(inputPin);
            if (!isPinValid) {
              rateLimiter.recordFailure(clientIp);
              final isLocked = rateLimiter.isLockedOut(clientIp);
              return Response(
                isLocked ? 429 : 401,
                body: jsonEncode({
                  'error': isLocked
                      ? 'Too many failed PIN attempts. Locked out for 60 seconds.'
                      : ((inputPin == null || inputPin.isEmpty) ? 'PIN required' : 'Invalid PIN'),
                  'code': isLocked ? 'LOCKED_OUT' : ((inputPin == null || inputPin.isEmpty) ? 'PIN_REQUIRED' : 'INVALID_PIN'),
                }),
                headers: {'content-type': 'application/json'},
              );
            }
          }

          // If token is configured and provided, validate it
          if (roomCfg.inviteToken.isNotEmpty && inputToken != null && inputToken.isNotEmpty) {
            if (inputToken != roomCfg.inviteToken) {
              roomRateLimiter.recordFailure(clientIp);
              return Response(
                401,
                body: jsonEncode({'error': 'Invalid invite token', 'code': 'INVALID_TOKEN'}),
                headers: {'content-type': 'application/json'},
              );
            }
          } else if (!roomCfg.requirePin && roomCfg.inviteToken.isNotEmpty) {
            // Token-only room requires valid invite token
            if (inputToken == null || inputToken != roomCfg.inviteToken) {
              roomRateLimiter.recordFailure(clientIp);
              return Response(
                401,
                body: jsonEncode({'error': 'Invite token required', 'code': 'TOKEN_REQUIRED'}),
                headers: {'content-type': 'application/json'},
              );
            }
          }
        }

        final existingToken = _authManager!.extractTokenFromRequest(req);
        final entry = _authManager!.getOrCreateSession(existingToken);
        entry.isPasswordVerified = true;
        entry.isRoomVerified = true;
        RoomPinRateLimiter().recordSuccess(clientIp);
        return Response.ok(
          jsonEncode({'success': true}),
          headers: {
            'content-type': 'application/json',
            'set-cookie': 'cp_session=${entry.token}; Path=/; HttpOnly; SameSite=Lax',
          },
        );
      } catch (_) {
        return Response(400, body: jsonEncode({'error': 'Bad Request'}));
      }
    });

    // Room File Upload Endpoint (App-Only View-Once Media)
    router.post('/api/room/upload', (Request req) async {
      if (_disposableRoom == null) {
        return Response(404, body: jsonEncode({'error': 'Room not active'}));
      }
      if (session.roomConfig?.allowFileSharing != true) {
        return Response(403, body: jsonEncode({'error': 'File sharing disabled in this room'}));
      }
      final isSecure = req.headers['x-secure-client'] == 'true';
      if (!isSecure) {
        return Response(403, body: jsonEncode({'error': 'Room media sharing is an App-only feature'}));
      }

      final rawFilename = req.headers['x-filename'] ?? req.url.queryParameters['name'];
      if (rawFilename == null || rawFilename.isEmpty) {
        return Response(400, body: jsonEncode({'error': 'Missing X-Filename header'}));
      }
      final sanitizedName = p.basename(Uri.decodeComponent(rawFilename));
      final senderNick = req.headers['x-nickname'] ?? 'Guest';
      final senderId = req.headers['x-sender-id'] ?? 'unknown';
      final senderColor = req.headers['x-color'] ?? '#38BDF8';

      final maxBytes = (session.roomConfig?.maxFileSizeMb ?? 100) * 1024 * 1024;
      String finalName = sanitizedName;
      File targetFile = File('${_disposableRoom!.tempDirectory.path}${Platform.pathSeparator}$finalName');
      if (await targetFile.exists()) {
        final ext = p.extension(sanitizedName);
        final base = p.basenameWithoutExtension(sanitizedName);
        finalName = '${base}_${DateTime.now().millisecondsSinceEpoch}$ext';
        targetFile = File('${_disposableRoom!.tempDirectory.path}${Platform.pathSeparator}$finalName');
      }
      final sink = targetFile.openWrite();
      int bytesReceived = 0;

      try {
        await for (final chunk in req.read()) {
          bytesReceived += chunk.length;
          if (bytesReceived > maxBytes) {
            await sink.close();
            if (await targetFile.exists()) {
              try { await targetFile.delete(); } catch (_) {}
            }
            return Response(413, body: jsonEncode({'error': 'File exceeds maximum room limit of ${session.roomConfig?.maxFileSizeMb} MB'}));
          }
          sink.add(chunk);
          // Await storage to prevent an unbounded IOSink queue.
          await sink.flush();
          _totalBytesReceived += chunk.length;
        }
        await sink.flush();
        await sink.close();

        final mimeType = mime_resolver.lookupMimeType(finalName) ?? 'application/octet-stream';
        final encodedName = Uri.encodeComponent(finalName);

        _disposableRoom!.chatHub.addFileMessage(
          senderId: senderId,
          nickname: senderNick,
          filename: finalName,
          size: bytesReceived,
          mimeType: mimeType,
          downloadPath: '/api/room/files/$encodedName',
          isSecureClient: true,
          color: senderColor,
        );

        return Response.ok(
          jsonEncode({
            'success': true,
            'filename': finalName,
            'size': bytesReceived,
            'downloadPath': '/api/room/files/$encodedName',
          }),
          headers: {'content-type': 'application/json'},
        );
      } catch (e) {
        await sink.close();
        if (await targetFile.exists()) {
          try { await targetFile.delete(); } catch (_) {}
        }
        return Response(500, body: jsonEncode({'error': 'Upload failed: $e'}));
      }
    });

    // Room File Inline Streaming Endpoint (View/Play-Only in App)
    router.get('/api/room/files/<filename|.*>', (Request req, String filename) async {
      if (_disposableRoom == null) {
        return Response(404, body: 'Room not active');
      }
      if (!_disposableRoom!.chatHub.mayViewAttachment(req.headers['x-room-view-key'])) {
        return Response.forbidden('Open the attachment from the app chat');
      }
      final safeName = p.basename(Uri.decodeComponent(filename));
      final file = File('${_disposableRoom!.tempDirectory.path}${Platform.pathSeparator}$safeName');
      if (!await file.exists()) {
        return Response(404, body: 'File not found or expired');
      }

      final mimeType = mime_resolver.lookupMimeType(safeName) ?? 'application/octet-stream';
      final length = await file.length();

      final rangeHeader = req.headers['range'];
      if (length > 0 && rangeHeader != null && rangeHeader.startsWith('bytes=')) {
        try {
          final rangeSpec = rangeHeader.substring(6).trim();
          final parts = rangeSpec.split('-');
          int start;
          int end;
          if (parts[0].isEmpty) {
            final suffix = int.parse(parts[1]);
            start = (length - suffix).clamp(0, length - 1);
            end = length - 1;
          } else {
            start = int.parse(parts[0]);
            end = (parts.length > 1 && parts[1].isNotEmpty) ? int.parse(parts[1]) : length - 1;
          }
          end = math.min(end, length - 1);
          if (start < 0 || start >= length || start > end) {
            return Response(416, headers: {'content-range': 'bytes */$length'});
          }
          final contentLength = end - start + 1;
          _totalBytesSent += contentLength;
          return Response(
            206,
            body: file.openRead(start, end + 1),
            headers: {
              'content-type': mimeType,
              'content-length': contentLength.toString(),
              'content-range': 'bytes $start-$end/$length',
              'accept-ranges': 'bytes',
              'content-disposition': 'inline; filename="$safeName"',
              'cache-control': 'no-store, no-cache, must-revalidate',
            },
          );
        } catch (_) {}
      }

      _totalBytesSent += length;

      return Response.ok(
        file.openRead(),
        headers: {
          'content-type': mimeType,
          'content-length': length.toString(),
          'accept-ranges': 'bytes',
          'content-disposition': 'inline; filename="$safeName"',
          'cache-control': 'no-store, no-cache, must-revalidate',
        },
      );
    });

    // Device Identity Endpoint
    router.get('/api/device-info', (Request req) {
      return Response.ok(
        jsonEncode({
          'deviceName': deviceName,
          'appVersion': '1.5.0',
          'themeMode': themeMode,
          'primaryColor': primaryColor,
        }),
        headers: {'content-type': 'application/json'},
      );
    });

    // Vault Status Endpoint
    router.get('/api/vault-status', (Request req) {
      final sanitizedCounts = <String, int>{};
      if (_vaultTracker != null) {
        for (final entry in _vaultTracker!.downloadCounts.entries) {
          sanitizedCounts[entry.key.split(RegExp(r'[\\/]')).last] = entry.value;
        }
      }
      return Response.ok(
        jsonEncode({
          'isVaultMode': session.isVaultMode,
          'maxDownloadsPerFile': session.maxDownloadsPerFile,
          'downloadCounts': sanitizedCounts,
        }),
        headers: {'content-type': 'application/json'},
      );
    });

    // Security & Auth Endpoints
    router.get('/api/security-mode', (Request req) {
      return Response.ok(
        jsonEncode({
          'requireGoogleAuth': session.requireGoogleAuth,
          'requirePassword': session.requirePassword,
          'securityDescription': session.securityDescription,
          'allowUploads': session.allowUploads,
          'googleClientId': session.googleClientId,
          'isVaultMode': session.isVaultMode,
          'sharedText': session.sharedText,
        }),
        headers: {'content-type': 'application/json'},
      );
    });

    router.post('/api/auth/exchange', (Request req) async {
      try {
        final clientIp = RoomPinRateLimiter.clientKey(req);

        final rateLimiter = RoomPinRateLimiter();
        if (rateLimiter.isLockedOut(clientIp)) {
          return Response(
            429,
            body: jsonEncode({
              'error': 'Too many failed attempts. Locked out for 60 seconds.',
              'code': 'LOCKED_OUT',
            }),
            headers: {'content-type': 'application/json'},
          );
        }

        final body = await req.readAsString();
        final json = jsonDecode(body) as Map<String, dynamic>;
        final inputToken = json['token'] as String? ?? '';
        final inputName = (json['name'] as String?)?.trim();
        final vid = (json['visitorId'] as String?)?.trim();

        final validToken = session.sessionToken;
        if (validToken == null || validToken.isEmpty || inputToken.isEmpty || inputToken != validToken) {
          rateLimiter.recordFailure(clientIp);
          final isLocked = rateLimiter.isLockedOut(clientIp);
          return Response(
            isLocked ? 429 : 401,
            body: jsonEncode({
              'error': isLocked ? 'Too many failed attempts. Locked out for 60 seconds.' : 'Invalid or expired session token',
              'code': isLocked ? 'LOCKED_OUT' : 'INVALID_TOKEN',
            }),
            headers: {'content-type': 'application/json'},
          );
        }

        rateLimiter.recordSuccess(clientIp);

        if (inputName != null && inputName.isNotEmpty) {
          _registerVisitor(inputName, vid: vid, ip: clientIp);
        }

        final existingToken = _authManager!.extractTokenFromRequest(req);
        final entry = _authManager!.getOrCreateSession(existingToken);
        entry.isPasswordVerified = true;
        if (inputName != null && inputName.isNotEmpty) {
          entry.userIdentifier = inputName;
        }

        final isComplete = entry.isFullyAuthenticated(session);

        return Response.ok(
          jsonEncode({
            'success': true,
            'fullyAuthenticated': isComplete,
            'needsGoogle': session.requireGoogleAuth && !entry.isGoogleVerified,
          }),
          headers: {
            'content-type': 'application/json',
            'set-cookie': 'cp_session=${entry.token}; Path=/; HttpOnly; SameSite=Lax',
          },
        );
      } catch (e) {
        return Response(400, body: jsonEncode({'error': 'Bad Request'}));
      }
    });

    router.post('/api/auth/password', (Request req) async {
      try {
        final clientIp = RoomPinRateLimiter.clientKey(req);

        final rateLimiter = RoomPinRateLimiter();
        if (rateLimiter.isLockedOut(clientIp)) {
          return Response(
            429,
            body: jsonEncode({
              'error': 'Too many failed attempts. Locked out for 60 seconds.',
              'code': 'LOCKED_OUT',
            }),
            headers: {'content-type': 'application/json'},
          );
        }

        final body = await req.readAsString();
        final json = jsonDecode(body) as Map<String, dynamic>;
        final inputPassword = json['password'] as String? ?? '';
        final inputName = (json['name'] as String?)?.trim();
        final vid = (json['visitorId'] as String?)?.trim();

        if (_authManager!.verifyPassword(inputPassword)) {
          rateLimiter.recordSuccess(clientIp);
          if (inputName != null && inputName.isNotEmpty) {
            _registerVisitor(inputName, vid: vid, ip: clientIp);
          }
          final existingToken = _authManager!.extractTokenFromRequest(req);
          final entry = _authManager!.getOrCreateSession(existingToken);
          entry.isPasswordVerified = true;
          if (inputName != null && inputName.isNotEmpty) {
            entry.userIdentifier = inputName;
          }

          final isComplete = entry.isFullyAuthenticated(session);

          return Response.ok(
            jsonEncode({
              'success': true,
              'fullyAuthenticated': isComplete,
              'needsGoogle': session.requireGoogleAuth && !entry.isGoogleVerified,
            }),
            headers: {
              'content-type': 'application/json',
              'set-cookie': 'cp_session=${entry.token}; Path=/; HttpOnly; SameSite=Lax',
            },
          );
        }
        rateLimiter.recordFailure(clientIp);
        final isLocked = rateLimiter.isLockedOut(clientIp);
        return Response(
          isLocked ? 429 : 401,
          body: jsonEncode({
            'error': isLocked ? 'Too many failed attempts. Locked out for 60 seconds.' : 'Incorrect password',
            'code': isLocked ? 'LOCKED_OUT' : 'InvalidPassword',
            'message': isLocked ? 'Too many failed attempts. Locked out for 60 seconds.' : 'Incorrect password',
          }),
          headers: {'content-type': 'application/json'},
        );
      } catch (e) {
        return Response(400, body: jsonEncode({'error': 'Bad Request'}));
      }
    });

    router.post('/api/auth/google', (Request req) async {
      try {
        final body = await req.readAsString();
        final json = jsonDecode(body) as Map<String, dynamic>;
        final idToken = json['id_token'] as String? ?? '';

        final tokenInfo = await _authManager!.verifyGoogleIdToken(idToken);
        if (tokenInfo != null) {
          final email = tokenInfo['email'] as String?;
          final existingToken = _authManager!.extractTokenFromRequest(req);
          final entry = _authManager!.getOrCreateSession(existingToken);
          entry.isGoogleVerified = true;
          entry.userIdentifier = email;

          final isComplete = entry.isFullyAuthenticated(session);

          return Response.ok(
            jsonEncode({
              'success': true,
              'email': email,
              'fullyAuthenticated': isComplete,
              'needsPassword': session.requirePassword && !entry.isPasswordVerified,
            }),
            headers: {
              'content-type': 'application/json',
              'set-cookie': 'cp_session=${entry.token}; Path=/; HttpOnly; SameSite=Lax',
            },
          );
        }
        return Response(401, body: jsonEncode({'error': 'Unauthorized', 'message': 'Google authentication failed or account not whitelisted'}), headers: {'content-type': 'application/json'});
      } catch (e) {
        return Response(400, body: jsonEncode({'error': 'Bad Request'}));
      }
    });

    router.post('/api/auth/logout', (Request req) {
      final token = _authManager?.extractTokenFromRequest(req);
      _authManager?.revokeToken(token);
      return Response.ok(
        jsonEncode({'success': true}),
        headers: {
          'content-type': 'application/json',
          'set-cookie': 'cp_session=; Path=/; Max-Age=0',
        },
      );
    });

    // File Management Endpoints
    router.get('/api/files', (Request req) => fileHandler.listFiles(req));
    router.get('/api/files/<path|.*>', (Request req, String path) => fileHandler.serveFile(req, path));
    router.get('/api/thumbnail', (Request req) => fileHandler.serveThumbnail(req));
    router.get('/api/download-zip', (Request req) => fileHandler.downloadZip(req));
    router.post('/api/download-zip', (Request req) => fileHandler.downloadZip(req));
    router.post('/api/upload', (Request req) => uploadHandler.handleUpload(req));

    // Pipeline: CORS -> Connection/Traffic Metric Tracker -> Auth Middleware -> Router
    final handler = const Pipeline()
        .addMiddleware(securityHeaders())
        .addMiddleware(_corsMiddleware())
        .addMiddleware(_trafficTrackerMiddleware())
        .addMiddleware(_authManager!.middleware)
        .addHandler(router.call);

    // Bind to all IPv4 interfaces on phone
    var bindPort = preferredPort;
    HttpServer? boundServer;
    for (var attempt = 0; attempt < 5; attempt++) {
      try {
        boundServer = await shelf_io.serve(handler, InternetAddress.anyIPv4, bindPort);
        boundServer.autoCompress = false;
        boundServer.idleTimeout = const Duration(minutes: 30);
        break;
      } catch (_) {
        bindPort++;
      }
    }

    if (boundServer == null) {
      throw Exception('Could not bind HTTP server on ports $preferredPort-${preferredPort + 5}');
    }

    _server = boundServer;
    _startTime = DateTime.now();
    AppLogger().info('SERVER', 'Shelf server bound on port $bindPort (PID: $pid)');

    // Start 1-second metrics calculation timer & 10-second WebSocket keepalive
    var tickCount = 0;
    _metricsTimer = Timer.periodic(const Duration(seconds: 1), (_) {
      tickCount++;
      final deltaSent = _totalBytesSent - _lastBytesSent;
      final deltaRecv = _totalBytesReceived - _lastBytesReceived;
      _lastBytesSent = _totalBytesSent;
      _lastBytesReceived = _totalBytesReceived;
      _bandwidthBytesPerSec = (deltaSent + deltaRecv).toDouble();

      _broadcastCurrentStats();

      if (tickCount % 10 == 0 && _wsClients.isNotEmpty) {
        broadcastTransferEvent({'type': 'ping', 'ts': DateTime.now().millisecondsSinceEpoch});
      }
    });

    // Schedule expiry timer if configured (DisposableRoom manages its own timer on first join)
    final duration = session.expiryDuration.duration;
    if (duration != null && !session.isDisposableRoom) {
      _expiryTimer = Timer(duration, () {
        stop();
        onExpired?.call();
      });
    }

    return boundServer.port;
  }

  Future<void> stop() async {
    for (final completer in _pauseCompleters.values) {
      if (!completer.isCompleted) completer.complete();
    }
    _pauseCompleters.clear();
    _cancelledTransferIds.addAll(_pausedTransferIds);
    _pausedTransferIds.clear();
    _metricsTimer?.cancel();
    _metricsTimer = null;
    _expiryTimer?.cancel();
    _expiryTimer = null;

    if (_disposableRoom != null) {
      await _disposableRoom!.destroy('server_stopped');
      _disposableRoom = null;
    }

    for (final client in _wsClients) {
      try {
        client.sink.close();
      } catch (_) {}
    }
    _wsClients.clear();

    await _server?.close(force: true);
    _server = null;
    AppLogger().info('SERVER', 'Shelf server stopped');
  }

  Middleware _corsMiddleware() {
    return (Handler innerHandler) {
      return (Request request) async {
        final origin = request.headers['origin'];
        final originUri = origin == null ? null : Uri.tryParse(origin);
        if (origin != null && (originUri == null ||
            !const {'http', 'https'}.contains(originUri.scheme) ||
            originUri.authority != request.headers['host'])) {
          return Response(403, body: 'Cross-origin requests are not allowed');
        }
        final corsHeaders = {
          'Access-Control-Allow-Origin': ?origin,
          'Vary': 'Origin',
          'Access-Control-Allow-Methods': 'GET, POST, OPTIONS',
          'Access-Control-Allow-Headers': 'Origin, Content-Type, X-Filename, X-Subpath, X-Filesize, X-Nickname, X-Sender-Id, X-Secure-Client, X-Color, X-Room-Pin, X-Room-Token, Range, Authorization',
          'Access-Control-Expose-Headers': 'Content-Length, Content-Range, Accept-Ranges, Content-Disposition',
          if (origin != null) 'Access-Control-Allow-Credentials': 'true',
        };

        if (request.method == 'OPTIONS') {
          return Response.ok('', headers: corsHeaders);
        }

        final response = await innerHandler(request);
        return response.change(headers: corsHeaders);
      };
    };
  }

  Middleware _trafficTrackerMiddleware() {
    return (Handler innerHandler) {
      return (Request request) async {
        _activeConnections++;
        final forwardedFor = request.headers['x-forwarded-for'];
        final cfIp = request.headers['cf-connecting-ip'];
        final clientIp = cfIp ??
            forwardedFor?.split(',').first.trim() ??
            (request.context['shelf.io.connection_info'] as HttpConnectionInfo?)
                ?.remoteAddress
                .address;
        if (clientIp != null) {
          _connectedIps.add(clientIp);
        }

        try {
          final response = await innerHandler(request);

          final isStreamedFile = request.url.path.startsWith('api/files');
          final responseContentLength = response.contentLength;
          if (responseContentLength != null && !isStreamedFile) {
            _totalBytesSent += responseContentLength;
          }

          return response;
        } finally {
          _activeConnections = (_activeConnections > 0) ? _activeConnections - 1 : 0;
        }
      };
    };
  }

  Future<Response> _serveAsset(String assetPath, String contentType) async {
    try {
      final data = await rootBundle.load(assetPath);
      final bytes = data.buffer.asUint8List();
      return Response.ok(bytes, headers: {'content-type': contentType, 'cache-control': 'no-cache'});
    } catch (_) {
      final directFile = File(assetPath);
      if (await directFile.exists()) {
        return Response.ok(directFile.openRead(), headers: {'content-type': contentType, 'cache-control': 'no-cache'});
      }
      return Response.notFound('Asset not found: $assetPath');
    }
  }
}
