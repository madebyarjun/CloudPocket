import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import '../services/app_logger.dart';

/// A lightweight, embedded RFC 1035 UDP DNS server running on localhost (127.0.0.1)
/// on an unprivileged ephemeral port.
///
/// Solves the Android DNS limitation for cloudflared:
/// - Android does not have `/etc/resolv.conf`, causing Go's resolver to query `[::1]:53`.
/// - Public DNS resolvers (1.1.1.1:53) over cellular (Jio, Airtel, Vi) can be dropped or blocked.
/// - Traffic to 127.0.0.1 never leaves the device and is 100% reliable with 0ms latency.
///
/// MicroDnsServer provides:
/// 1. Instant resolution of Cloudflare Argo Tunnel SRV records (`_v2-origintunneld._tcp.argotunnel.com`)
///    pointing to region1 and region2 edge targets.
/// 2. Instant resolution of region1 and region2 Anycast IPv4 addresses (`198.41.192.x` and `198.41.200.x`).
/// 3. Native OS fallback resolution via [InternetAddress.lookup] for any other domain.
class MicroDnsServer {
  RawDatagramSocket? _socket;
  StreamSubscription<RawSocketEvent>? _subscription;
  int _port = 0;

  int get port => _port;
  bool get isRunning => _socket != null;

  static const List<String> region1Ips = [
    '198.41.192.7',
    '198.41.192.27',
    '198.41.192.37',
    '198.41.192.47',
    '198.41.192.57',
    '198.41.192.67',
    '198.41.192.77',
    '198.41.192.107',
  ];

  static const List<String> region2Ips = [
    '198.41.200.13',
    '198.41.200.23',
    '198.41.200.33',
    '198.41.200.43',
    '198.41.200.53',
    '198.41.200.63',
    '198.41.200.73',
    '198.41.200.113',
  ];

  /// Starts the DNS server on loopback IPv4 with an ephemeral port.
  Future<int> start() async {
    if (_socket != null) return _port;

    _socket = await RawDatagramSocket.bind(InternetAddress.loopbackIPv4, 0);
    _port = _socket!.port;
    AppLogger().info('TUNNEL', 'Micro DNS Server listening on 127.0.0.1:$_port');

    _subscription = _socket!.listen((event) {
      if (event == RawSocketEvent.read && _socket != null) {
        try {
          final datagram = _socket!.receive();
          if (datagram != null) {
            _handleQuery(datagram.data, datagram.address, datagram.port);
          }
        } catch (e) {
          AppLogger().debug('TUNNEL', 'MicroDNS socket read error: $e');
        }
      }
    });

    return _port;
  }

  void _handleQuery(Uint8List data, InternetAddress clientAddr, int clientPort) async {
    if (data.length < 12) return;

    final txId = (data[0] << 8) | data[1];

    // Parse Question QNAME
    var pos = 12;
    final labels = <String>[];
    while (pos < data.length && data[pos] != 0) {
      final len = data[pos];
      pos++;
      if (pos + len > data.length) return;
      labels.add(String.fromCharCodes(data.sublist(pos, pos + len)));
      pos += len;
    }
    if (pos >= data.length || data[pos] != 0) return;
    pos++; // consume 0x00 root terminator

    if (pos + 4 > data.length) return;
    final qtype = (data[pos] << 8) | data[pos + 1];
    pos += 4;

    final qname = labels.join('.').toLowerCase();

    // Prepare response header
    final builder = BytesBuilder();
    builder.add([(txId >> 8) & 0xFF, txId & 0xFF]);
    // Flags: 0x8180 = QR=1 (response), Opcode=0, AA=0, TC=0, RD=1, RA=1, RCODE=0 (No error)
    builder.add([0x81, 0x80]);
    // QDCOUNT = 1
    builder.add([0x00, 0x01]);

    final answers = <Uint8List>[];

    // Match SRV query (QTYPE 33) or ANY (255)
    if (qname.contains('argotunnel.com') && (qtype == 33 || qtype == 255)) {
      answers.add(_buildSrvRecord(qname, 1, 1, 7844, 'region1.v2.argotunnel.com'));
      answers.add(_buildSrvRecord(qname, 2, 1, 7844, 'region2.v2.argotunnel.com'));
    } else if (qname.contains('region1') && (qtype == 1 || qtype == 255)) {
      for (final ip in region1Ips.take(4)) {
        answers.add(_buildARecord(qname, ip));
      }
    } else if (qname.contains('region2') && (qtype == 1 || qtype == 255)) {
      for (final ip in region2Ips.take(4)) {
        answers.add(_buildARecord(qname, ip));
      }
    } else if (qname.contains('argotunnel.com') && (qtype == 1 || qtype == 255)) {
      for (final ip in region1Ips.take(2)) {
        answers.add(_buildARecord(qname, ip));
      }
      for (final ip in region2Ips.take(2)) {
        answers.add(_buildARecord(qname, ip));
      }
    } else if (qtype == 1) {
      // General A query: fallback to Android OS native resolver
      try {
        final addrs = await InternetAddress.lookup(qname).timeout(
          const Duration(seconds: 2),
        );
        for (final a in addrs.where((x) => x.type == InternetAddressType.IPv4).take(4)) {
          answers.add(_buildARecord(qname, a.address));
        }
      } catch (_) {
        // Domain not resolved or timed out; return empty answer with NoError
      }
    }

    // ANCOUNT
    builder.add([(answers.length >> 8) & 0xFF, answers.length & 0xFF]);
    // NSCOUNT = 0
    builder.add([0x00, 0x00]);
    // ARCOUNT = 0
    builder.add([0x00, 0x00]);

    // Question section echoed back
    builder.add(data.sublist(12, pos));

    // Answers section
    for (final ans in answers) {
      builder.add(ans);
    }

    final responseBytes = builder.toBytes();
    try {
      _socket?.send(responseBytes, clientAddr, clientPort);
    } catch (_) {}
  }

  static Uint8List _encodeDomain(String domain) {
    final b = BytesBuilder();
    for (final part in domain.split('.')) {
      if (part.isNotEmpty) {
        b.addByte(part.length);
        b.add(part.codeUnits);
      }
    }
    b.addByte(0);
    return b.toBytes();
  }

  static Uint8List _buildARecord(String name, String ip) {
    final b = BytesBuilder();
    b.add(_encodeDomain(name));
    b.add([0x00, 0x01]); // Type A (1)
    b.add([0x00, 0x01]); // Class IN (1)
    b.add([0x00, 0x00, 0x01, 0x2c]); // TTL = 300s
    b.add([0x00, 0x04]); // RDLENGTH = 4 bytes
    final parts = ip.split('.').map(int.parse).toList();
    b.add(parts);
    return b.toBytes();
  }

  static Uint8List _buildSrvRecord(String name, int priority, int weight, int port, String target) {
    final b = BytesBuilder();
    b.add(_encodeDomain(name));
    b.add([0x00, 0x21]); // Type SRV (33)
    b.add([0x00, 0x01]); // Class IN (1)
    b.add([0x00, 0x00, 0x01, 0x2c]); // TTL = 300s

    final targetBytes = _encodeDomain(target);
    final rdlength = 6 + targetBytes.length; // priority(2) + weight(2) + port(2) + target
    b.add([(rdlength >> 8) & 0xFF, rdlength & 0xFF]);
    b.add([(priority >> 8) & 0xFF, priority & 0xFF]);
    b.add([(weight >> 8) & 0xFF, weight & 0xFF]);
    b.add([(port >> 8) & 0xFF, port & 0xFF]);
    b.add(targetBytes);
    return b.toBytes();
  }

  /// Stops the DNS server and frees the local socket.
  Future<void> stop() async {
    try {
      await _subscription?.cancel();
    } catch (_) {}
    _subscription = null;
    try {
      _socket?.close();
    } catch (_) {}
    _socket = null;
    _port = 0;
  }
}
