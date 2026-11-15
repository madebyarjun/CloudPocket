import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
import 'package:cloud_pocket/services/app_logger.dart';
import 'package:cloud_pocket/tunnel/tunnel_client.dart';

class BoreClient implements TunnelClient {
  final int localPort;
  final String boreHost;
  final int boreControlPort;
  final void Function(double progress, String status)? onStatusUpdate;
  final void Function()? onDisconnect;

  Socket? _controlSocket;
  int? _assignedPort;
  bool _isStopping = false;
  final List<Socket> _activePipes = [];

  BoreClient({
    required this.localPort,
    this.boreHost = 'bore.pub',
    this.boreControlPort = 7835,
    this.onStatusUpdate,
    this.onDisconnect,
  });

  @override
  String? get publicUrl => _assignedPort != null ? 'http://$boreHost:$_assignedPort' : null;

  @override
  bool get isRunning => !_isStopping && _controlSocket != null && _assignedPort != null;

  /// Resolves the target host preferring IPv4 since public Bore relays bind to IPv4 only
  Future<dynamic> _resolveHost() async {
    try {
      final addrs = await InternetAddress.lookup(boreHost, type: InternetAddressType.IPv4);
      if (addrs.isNotEmpty) return addrs.first;
    } catch (_) {}
    return boreHost;
  }

  @override
  Future<String> start() async {
    _isStopping = false;
    final completer = Completer<String>();

    Timer? timeoutTimer;
    try {
      final target = await _resolveHost();
      onStatusUpdate?.call(0.3, 'Connecting to Bore relay ($boreHost)...');
      AppLogger().info('BORE', 'Connecting to Bore relay at $boreHost:$boreControlPort');
      _controlSocket = await Socket.connect(target, boreControlPort, timeout: const Duration(seconds: 8));
      _controlSocket!.setOption(SocketOption.tcpNoDelay, true);
      AppLogger().info('BORE', 'Connected to Bore control socket');

      // Buffer incoming null-delimited or newline-delimited JSON frames
      final buffer = BytesBuilder();

      _controlSocket!.listen(
        (chunk) {
          for (final byte in chunk) {
            if (byte == 0 || byte == 10) {
              if (buffer.isNotEmpty) {
                final frameStr = utf8.decode(buffer.toBytes());
                buffer.clear();
                _handleServerMessage(frameStr, completer);
              }
            } else {
              buffer.addByte(byte);
            }
          }
        },
        onDone: () {
          AppLogger().warn('BORE', 'Bore control socket closed by server');
          final wasRunning = isRunning;
          stop();
          if (wasRunning) {
            onDisconnect?.call();
          }
        },
        onError: (err) {
          AppLogger().error('BORE', 'Bore control socket error: $err');
          timeoutTimer?.cancel();
          if (!completer.isCompleted) completer.completeError(err);
          final wasRunning = isRunning;
          stop();
          if (wasRunning) {
            onDisconnect?.call();
          }
        },
        cancelOnError: true,
      );

      // Send Hello(0) to request a random free port on bore.pub
      final helloMsg = '${jsonEncode({'Hello': 0})}\x00';
      _controlSocket!.write(helloMsg);
      await _controlSocket!.flush();

      // Timeout after 10s if no ack
      timeoutTimer = Timer(const Duration(seconds: 10), () {
        if (!completer.isCompleted) {
          completer.completeError(TimeoutException('Bore server did not respond within 10 seconds'));
        }
      });

      final url = await completer.future;
      timeoutTimer.cancel();
      AppLogger().info('BORE', 'Bore tunnel active: $url');
      return url;
    } catch (e) {
      AppLogger().error('BORE', 'Bore start failed: $e');
      timeoutTimer?.cancel();
      if (!completer.isCompleted) completer.completeError(e);
      rethrow;
    }
  }

  void _handleServerMessage(String rawFrame, Completer<String> completer) {
    try {
      final trimmed = rawFrame.trim();
      if (trimmed.isEmpty || trimmed == '"Heartbeat"' || trimmed == 'Heartbeat') {
        return;
      }
      AppLogger().debug('BORE', 'Received server frame: $trimmed');
      final json = jsonDecode(trimmed);
      if (json is Map<String, dynamic>) {
        if (json.containsKey('Hello')) {
          _assignedPort = json['Hello'] as int;
          AppLogger().info('BORE', 'Allocated port $_assignedPort on $boreHost');
          if (!completer.isCompleted) {
            completer.complete(publicUrl!);
          }
        } else if (json.containsKey('Connection')) {
          final uuid = json['Connection'] as String;
          AppLogger().debug('BORE', 'Proxying incoming connection $uuid');
          _proxyConnection(uuid);
        } else if (json.containsKey('Error')) {
          final err = json['Error'] as String;
          AppLogger().error('BORE', 'Bore server returned error: $err');
          if (!completer.isCompleted) {
            completer.completeError(Exception('Bore error: $err'));
          }
        }
      }
    } catch (_) {}
  }

  Future<void> _proxyConnection(String uuid) async {
    if (_isStopping) return;

    Socket? remoteSocket;
    Socket? localSocket;
    try {
      final host = await _resolveHost();
      // 1. Connect to Bore server control port to accept proxy stream
      remoteSocket = await Socket.connect(host, boreControlPort, timeout: const Duration(seconds: 5));
      remoteSocket.setOption(SocketOption.tcpNoDelay, true);
      _activePipes.add(remoteSocket);

      // 2. Connect to local phone server
      localSocket = await Socket.connect('127.0.0.1', localPort, timeout: const Duration(seconds: 5));
      localSocket.setOption(SocketOption.tcpNoDelay, true);
      _activePipes.add(localSocket);

      // 3. Send Accept(uuid) frame
      final acceptMsg = '${jsonEncode({'Accept': uuid})}\x00';
      remoteSocket.write(acceptMsg);
      await remoteSocket.flush();

      void safeClose(Socket? s) {
        if (s == null) return;
        _activePipes.remove(s);
        try {
          s.flush().then((_) {
            try { s.close(); } catch (_) {}
          }).catchError((_) {
            try { s.destroy(); } catch (_) {}
          });
        } catch (_) {
          try { s.destroy(); } catch (_) {}
        }
      }

      void closePair() {
        safeClose(remoteSocket);
        safeClose(localSocket);
      }

      // 4. Bidirectional stream pipe
      remoteSocket.listen(
        (data) => localSocket?.add(data),
        onDone: closePair,
        onError: (_) => closePair(),
        cancelOnError: true,
      );

      localSocket.listen(
        (data) => remoteSocket?.add(data),
        onDone: closePair,
        onError: (_) => closePair(),
        cancelOnError: true,
      );
    } catch (_) {
      _activePipes.remove(remoteSocket);
      _activePipes.remove(localSocket);
      try { remoteSocket?.destroy(); } catch (_) {}
      try { localSocket?.destroy(); } catch (_) {}
    }
  }

  @override
  Future<void> stop() async {
    if (_isStopping) return;
    _isStopping = true;

    final sock = _controlSocket;
    _controlSocket = null;
    try {
      sock?.destroy();
    } catch (_) {}

    final pipes = List<Socket>.from(_activePipes);
    _activePipes.clear();
    for (final s in pipes) {
      try {
        s.destroy();
      } catch (_) {}
    }
    _assignedPort = null;
  }
}
