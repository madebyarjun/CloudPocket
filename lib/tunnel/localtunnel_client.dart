import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
import 'package:http/http.dart' as http;
import 'package:cloud_pocket/services/app_logger.dart';
import 'package:cloud_pocket/tunnel/tunnel_client.dart';

class LocaltunnelClient implements TunnelClient {
  final int localPort;
  final String relayHost;
  final String? preferredSubdomain;

  bool _isStopping = false;
  String? _assignedUrl;
  int? _remotePort;
  int _maxConn = 10;
  final List<Socket> _openSockets = [];

  LocaltunnelClient({
    required this.localPort,
    this.relayHost = 'loca.lt',
    this.preferredSubdomain,
  });

  @override
  String? get publicUrl => _assignedUrl;

  @override
  bool get isRunning => !_isStopping && _assignedUrl != null;

  @override
  Future<String> start() async {
    _isStopping = false;
    AppLogger().info('LOCALTUNNEL', 'Requesting tunnel allocation from $relayHost...');

    // 1. Request new tunnel from relay
    final queryParams = <String, String>{'new': ''};
    if (preferredSubdomain != null && preferredSubdomain!.isNotEmpty) {
      queryParams['subdomain'] = preferredSubdomain!;
    }

    final uri = Uri.https(relayHost, '/', queryParams);
    final response = await http.get(uri).timeout(const Duration(seconds: 10));

    if (response.statusCode != 200) {
      AppLogger().error('LOCALTUNNEL', 'Failed allocation from $relayHost: HTTP ${response.statusCode}');
      throw Exception('Failed to initialize tunnel from $relayHost: ${response.statusCode}');
    }

    final data = jsonDecode(response.body) as Map<String, dynamic>;
    _assignedUrl = data['url'] as String;
    _remotePort = data['port'] as int;
    _maxConn = (data['max_conn_count'] as int?) ?? (data['max_conn'] as int?) ?? 2;

    AppLogger().info('LOCALTUNNEL', 'Tunnel allocated: $_assignedUrl (remote port: $_remotePort, max sockets: $_maxConn)');

    // 2. Open TCP connection pool to remote server
    for (var i = 0; i < _maxConn; i++) {
      _createTunnelSocket();
    }

    return _assignedUrl!;
  }

  void _createTunnelSocket() {
    if (_isStopping || _remotePort == null) return;

    Socket.connect(relayHost, _remotePort!).then((remoteSocket) {
      remoteSocket.setOption(SocketOption.tcpNoDelay, true);
      _openSockets.add(remoteSocket);

      Socket? localSocket;
      var isConnectingLocal = false;
      var hasConnectedLocal = false;
      final pendingChunks = <Uint8List>[];
      StreamSubscription<Uint8List>? remoteSub;

      remoteSub = remoteSocket.listen(
        (data) async {
          if (!hasConnectedLocal) {
            pendingChunks.add(data);

            if (!isConnectingLocal) {
              isConnectingLocal = true;
              remoteSub?.pause();

              try {
                final socket = await Socket.connect(
                  '127.0.0.1',
                  localPort,
                  timeout: const Duration(seconds: 5),
                );
                socket.setOption(SocketOption.tcpNoDelay, true);
                localSocket = socket;
                _openSockets.add(socket);
                hasConnectedLocal = true;

                void safeClose(Socket? s) {
                  if (s == null) return;
                  _openSockets.remove(s);
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

                socket.listen(
                  (localData) {
                    try {
                      remoteSocket.add(localData);
                    } catch (_) {}
                  },
                  onDone: () {
                    safeClose(socket);
                    safeClose(remoteSocket);
                  },
                  onError: (_) {
                    safeClose(socket);
                    safeClose(remoteSocket);
                  },
                );

                // Drain buffered chunks safely by snapshotting the list
                final toDrain = List<Uint8List>.from(pendingChunks);
                pendingChunks.clear();
                for (final chunk in toDrain) {
                  socket.add(chunk);
                }

                remoteSub?.resume();
              } catch (_) {
                _openSockets.remove(remoteSocket);
                try { remoteSocket.destroy(); } catch (_) {}
              }
            }
          } else {
            localSocket?.add(data);
          }
        },
        onDone: () {
          _openSockets.remove(remoteSocket);
          if (localSocket != null) {
            _openSockets.remove(localSocket);
            try { localSocket?.close(); } catch (_) {}
          }
          if (!_isStopping) {
            _createTunnelSocket(); // Replenish pool
          }
        },
        onError: (_) {
          _openSockets.remove(remoteSocket);
          if (localSocket != null) {
            _openSockets.remove(localSocket);
            try { localSocket?.destroy(); } catch (_) {}
          }
          if (!_isStopping) {
            _createTunnelSocket();
          }
        },
        cancelOnError: true,
      );
    }).catchError((_) {
      // Re-attempt after delay
      if (!_isStopping) {
        Future.delayed(const Duration(seconds: 2), _createTunnelSocket);
      }
    });
  }

  @override
  Future<void> stop() async {
    _isStopping = true;
    for (final s in List<Socket>.from(_openSockets)) {
      try {
        s.destroy();
      } catch (_) {}
    }
    _openSockets.clear();
    _assignedUrl = null;
    _remotePort = null;
  }
}
