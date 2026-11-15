import 'dart:async';
import 'dart:io';
import 'dart:typed_data';
import 'package:flutter_test/flutter_test.dart';
import 'package:cloud_pocket/tunnel/micro_dns_server.dart';

void main() {
  group('MicroDnsServer Tests', () {
    late MicroDnsServer server;

    setUp(() async {
      server = MicroDnsServer();
      await server.start();
    });

    tearDown(() async {
      await server.stop();
    });

    test('starts and binds to an unprivileged loopback port', () {
      expect(server.isRunning, isTrue);
      expect(server.port, greaterThan(1024));
    });

    test('resolves SRV query for _v2-origintunneld._tcp.argotunnel.com', () async {
      final client = await RawDatagramSocket.bind(InternetAddress.loopbackIPv4, 0);
      final completer = Completer<Uint8List>();

      client.listen((event) {
        if (event == RawSocketEvent.read) {
          final dg = client.receive();
          if (dg != null && !completer.isCompleted) {
            completer.complete(dg.data);
          }
        }
      });

      // Construct standard DNS SRV query
      final query = BytesBuilder();
      query.add([0x12, 0x34]); // TxID
      query.add([0x01, 0x00]); // Standard query, RD=1
      query.add([0x00, 0x01]); // QDCOUNT = 1
      query.add([0x00, 0x00, 0x00, 0x00, 0x00, 0x00]); // AN/NS/AR count = 0

      // QNAME: _v2-origintunneld._tcp.argotunnel.com
      for (final label in '_v2-origintunneld._tcp.argotunnel.com'.split('.')) {
        query.addByte(label.length);
        query.add(label.codeUnits);
      }
      query.addByte(0x00);
      query.add([0x00, 0x21]); // QTYPE: SRV (33)
      query.add([0x00, 0x01]); // QCLASS: IN (1)

      client.send(query.toBytes(), InternetAddress.loopbackIPv4, server.port);

      final resp = await completer.future.timeout(const Duration(seconds: 3));
      client.close();

      // Verify response
      expect(resp.length, greaterThan(12));
      expect(resp[0], equals(0x12)); // TxID matched
      expect(resp[1], equals(0x34));
      expect(resp[2] & 0x80, equals(0x80)); // QR bit is 1 (Response)
      final ancount = (resp[6] << 8) | resp[7];
      expect(ancount, equals(2)); // 2 SRV records (region1 and region2)
    });

    test('resolves A query for region1.v2.argotunnel.com', () async {
      final client = await RawDatagramSocket.bind(InternetAddress.loopbackIPv4, 0);
      final completer = Completer<Uint8List>();

      client.listen((event) {
        if (event == RawSocketEvent.read) {
          final dg = client.receive();
          if (dg != null && !completer.isCompleted) {
            completer.complete(dg.data);
          }
        }
      });

      // Construct standard DNS A query
      final query = BytesBuilder();
      query.add([0xAB, 0xCD]); // TxID
      query.add([0x01, 0x00]); // Standard query
      query.add([0x00, 0x01]); // QDCOUNT = 1
      query.add([0x00, 0x00, 0x00, 0x00, 0x00, 0x00]);

      // QNAME: region1.v2.argotunnel.com
      for (final label in 'region1.v2.argotunnel.com'.split('.')) {
        query.addByte(label.length);
        query.add(label.codeUnits);
      }
      query.addByte(0x00);
      query.add([0x00, 0x01]); // QTYPE: A (1)
      query.add([0x00, 0x01]); // QCLASS: IN (1)

      client.send(query.toBytes(), InternetAddress.loopbackIPv4, server.port);

      final resp = await completer.future.timeout(const Duration(seconds: 3));
      client.close();

      expect(resp[0], equals(0xAB));
      expect(resp[1], equals(0xCD));
      final ancount = (resp[6] << 8) | resp[7];
      expect(ancount, equals(4)); // 4 Anycast A records
    });

    test('resolves A query for region2.v2.argotunnel.com', () async {
      final client = await RawDatagramSocket.bind(InternetAddress.loopbackIPv4, 0);
      final completer = Completer<Uint8List>();

      client.listen((event) {
        if (event == RawSocketEvent.read) {
          final dg = client.receive();
          if (dg != null && !completer.isCompleted) {
            completer.complete(dg.data);
          }
        }
      });

      final query = BytesBuilder();
      query.add([0xDE, 0xAD]);
      query.add([0x01, 0x00]);
      query.add([0x00, 0x01]);
      query.add([0x00, 0x00, 0x00, 0x00, 0x00, 0x00]);

      for (final label in 'region2.v2.argotunnel.com'.split('.')) {
        query.addByte(label.length);
        query.add(label.codeUnits);
      }
      query.addByte(0x00);
      query.add([0x00, 0x01]);
      query.add([0x00, 0x01]);

      client.send(query.toBytes(), InternetAddress.loopbackIPv4, server.port);

      final resp = await completer.future.timeout(const Duration(seconds: 3));
      client.close();

      expect(resp[0], equals(0xDE));
      expect(resp[1], equals(0xAD));
      final ancount = (resp[6] << 8) | resp[7];
      expect(ancount, equals(4)); // 4 Anycast A records
    });

    test('stops cleanly and resets state', () async {
      expect(server.isRunning, isTrue);
      await server.stop();
      expect(server.isRunning, isFalse);
      expect(server.port, equals(0));
    });
  });
}
