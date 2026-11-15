import 'dart:convert';
import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:cloud_pocket/models/room_config.dart';
import 'package:cloud_pocket/models/share_session.dart';
import 'package:cloud_pocket/server/room_pin_rate_limiter.dart';
import 'package:cloud_pocket/server/server_engine.dart';

void main() {
  setUp(() => RoomPinRateLimiter().reset());

  Future<ServerEngine> start(ShareSession session) async {
    final directory = await Directory.systemTemp.createTemp('cp_security_');
    final engine = ServerEngine(session: session, uploadDir: directory.path);
    await engine.start(preferredPort: 0);
    addTearDown(() async {
      await engine.stop();
      await directory.delete(recursive: true);
    });
    return engine;
  }

  test('Room auth cannot unlock password-protected file sharing', () async {
    final engine = await start(ShareSession(
      requirePassword: true, passwordHash: ShareSession.hashPassword('test-password'),
    ));
    final base = 'http://127.0.0.1:${engine.port}';
    final response = await http.post(Uri.parse('$base/api/room/auth'), body: '{}');
    expect(response.statusCode, 404);
    expect(response.headers['set-cookie'], isNull);
    final files = await http.get(Uri.parse('$base/api/files'));
    expect(files.statusCode, 401);
  });

  test('Token-only room protects media and accepts authenticated room cookie', () async {
    final engine = await start(const ShareSession(
      isDisposableRoom: true,
      roomConfig: RoomConfig(inviteToken: 'test-invite'),
    ));
    await File('${engine.disposableRoom!.tempDirectory.path}/sample.txt').writeAsString('fixture');
    final base = 'http://127.0.0.1:${engine.port}';
    expect((await http.get(Uri.parse('$base/api/room/files/sample.txt'))).statusCode, 401);
    final login = await http.post(Uri.parse('$base/api/room/auth'), body: jsonEncode({'token': 'test-invite'}));
    expect(login.statusCode, 200);
    final cookie = login.headers['set-cookie']!.split(';').first;
    expect((await http.get(Uri.parse('$base/api/room/files/sample.txt'), headers: {'cookie': cookie})).statusCode, 200);
    expect((await http.get(Uri.parse('$base/api/room/files/sample.txt'), headers: {'x-room-token': 'test-invite'})).statusCode, 200);
  });

  test('Pending and rejected sockets cannot receive broadcasts or inject messages', () async {
    final engine = await start(const ShareSession(
      isDisposableRoom: true, roomConfig: RoomConfig(inviteToken: 'test-invite'),
    ));
    final socket = await WebSocket.connect('ws://127.0.0.1:${engine.port}/api/room/ws');
    final events = <Map<String, dynamic>>[];
    socket.listen((data) => events.add(jsonDecode(data as String) as Map<String, dynamic>));
    addTearDown(socket.close);
    socket.add(jsonEncode({'type': 'join', 'token': 'wrong'}));
    await Future<void>.delayed(const Duration(milliseconds: 30));
    socket.add(jsonEncode({'type': 'message', 'text': 'must not be accepted'}));
    engine.disposableRoom!.chatHub.sendHostMessage('host fixture');
    await Future<void>.delayed(const Duration(milliseconds: 30));
    expect(engine.disposableRoom!.chatHub.participantCount, 0);
    expect(engine.disposableRoom!.chatHub.messages.any((m) => m.text == 'must not be accepted'), isFalse);
    expect(events.where((e) => e['type'] == 'chat_message'), isEmpty);
    socket.add(jsonEncode({'type': 'join', 'token': 'test-invite', 'nickname': 'Test'}));
    await Future<void>.delayed(const Duration(milliseconds: 30));
    expect(events.any((e) => e['type'] == 'welcome'), isTrue);
    expect(engine.disposableRoom!.chatHub.participantCount, 1);
  });

  test('Direct PIN media authentication is rate limited across spoofed headers', () async {
    final engine = await start(ShareSession(
      isDisposableRoom: true, requirePassword: true, password: '1234',
      passwordHash: ShareSession.hashPassword('1234'),
      roomConfig: RoomConfig(requirePin: true, pinHash: RoomConfig.hashPin('1234')),
    ));
    final url = Uri.parse('http://127.0.0.1:${engine.port}/api/room/files/missing.txt');
    for (var i = 0; i < 5; i++) {
      final response = await http.get(url, headers: {'x-room-pin': 'wrong', 'x-forwarded-for': '192.0.2.$i'});
      expect(response.statusCode, i == 4 ? 429 : 401);
    }
    expect((await http.get(url, headers: {'x-room-pin': '1234'})).statusCode, 429);
  });

  test('Host encrypted messages never include the plaintext in broadcast JSON', () async {
    final engine = await start(const ShareSession(isDisposableRoom: true, roomConfig: RoomConfig()));
    engine.disposableRoom!.chatHub.sendHostMessage('private fixture', isE2e: true, ciphertext: 'cipher', iv: 'nonce');
    expect(engine.disposableRoom!.chatHub.messages.last.toJson()['text'], '[Encrypted Message]');
  });
}
