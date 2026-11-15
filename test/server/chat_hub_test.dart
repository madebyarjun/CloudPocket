import 'dart:async';
import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:web_socket_channel/web_socket_channel.dart';
import 'package:cloud_pocket/models/chat_message.dart';
import 'package:cloud_pocket/models/room_config.dart';
import 'package:cloud_pocket/server/chat_hub.dart';

class _MockWebSocketSink implements WebSocketSink {
  final StreamController<dynamic> _controller;
  _MockWebSocketSink(this._controller);

  @override
  void add(dynamic data) => _controller.add(data);

  @override
  Future<dynamic> close([int? closeCode, String? closeReason]) => _controller.close();

  @override
  Future<dynamic> get done => _controller.done;

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _MockWebSocketChannel implements WebSocketChannel {
  final StreamController<dynamic> _incoming;
  final StreamController<dynamic> _outgoing;
  late final _MockWebSocketSink _sink;

  _MockWebSocketChannel(this._incoming, this._outgoing) {
    _sink = _MockWebSocketSink(_outgoing);
  }

  @override
  Stream<dynamic> get stream => _incoming.stream;

  @override
  WebSocketSink get sink => _sink;

  @override
  String? get protocol => null;

  @override
  int? get closeCode => null;

  @override
  String? get closeReason => null;

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void main() {
  group('ChatHub Tests', () {
    test('addSystemMessage appends system message and increments sequence', () {
      final hub = ChatHub(config: const RoomConfig());

      expect(hub.messageCount, equals(0));
      hub.addSystemMessage('Room opened');
      expect(hub.messageCount, equals(1));

      final msg = hub.messages.first;
      expect(msg.type, equals(ChatMessageType.system));
      expect(msg.text, equals('Room opened'));
      expect(msg.seq, equals(1));
    });

    test('addFileMessage appends file message correctly', () {
      final hub = ChatHub(config: const RoomConfig());

      hub.addFileMessage(
        senderId: 'p_abc',
        nickname: 'Alice',
        filename: 'report.pdf',
        size: 1024,
        mimeType: 'application/pdf',
        downloadPath: '/api/room/files/report.pdf',
        isSecureClient: true,
        color: '#10B981',
      );

      expect(hub.messageCount, equals(1));
      final msg = hub.messages.first;
      expect(msg.type, equals(ChatMessageType.file));
      expect(msg.filename, equals('report.pdf'));
      expect(msg.fileSize, equals(1024));
      expect(msg.isSecureClient, isTrue);
    });

    test('clearAndCloseAll clears all in-memory messages', () {
      final hub = ChatHub(config: const RoomConfig());
      hub.addSystemMessage('Msg 1');
      hub.addSystemMessage('Msg 2');
      expect(hub.messageCount, equals(2));

      hub.clearAndCloseAll();
      expect(hub.messageCount, equals(0));
      expect(hub.participantCount, equals(0));
    });

    group('Credential Enforcement & PIN Bypass Prevention', () {
      late RoomConfig pinProtectedConfig;

      setUp(() {
        pinProtectedConfig = RoomConfig(
          inviteToken: 'secret_token_123',
          requirePin: true,
          pin: '1234',
          pinHash: RoomConfig.hashPin('1234'),
        );
      });

      test('valid invite token with missing PIN is strictly REJECTED (PIN bypass prevented)', () async {
        final hub = ChatHub(config: pinProtectedConfig);
        final incoming = StreamController<dynamic>();
        final outgoing = StreamController<dynamic>();
        final channel = _MockWebSocketChannel(incoming, outgoing);

        hub.handleWebSocket(channel);

        final outgoingMessages = <Map<String, dynamic>>[];
        outgoing.stream.listen((event) {
          outgoingMessages.add(jsonDecode(event.toString()) as Map<String, dynamic>);
        });

        // Client attempts join with token only (the former bypass attack)
        incoming.add(jsonEncode({
          'type': 'join',
          'nickname': 'Attacker',
          'token': 'secret_token_123',
        }));

        await Future.delayed(const Duration(milliseconds: 50));

        expect(outgoingMessages.length, equals(1));
        expect(outgoingMessages.first['type'], equals('error'));
        expect(outgoingMessages.first['code'], equals('PIN_REQUIRED'));
      });

      test('valid invite token with incorrect PIN is strictly REJECTED', () async {
        final hub = ChatHub(config: pinProtectedConfig);
        final incoming = StreamController<dynamic>();
        final outgoing = StreamController<dynamic>();
        final channel = _MockWebSocketChannel(incoming, outgoing);

        hub.handleWebSocket(channel);

        final outgoingMessages = <Map<String, dynamic>>[];
        outgoing.stream.listen((event) {
          outgoingMessages.add(jsonDecode(event.toString()) as Map<String, dynamic>);
        });

        incoming.add(jsonEncode({
          'type': 'join',
          'nickname': 'Attacker',
          'token': 'secret_token_123',
          'pin': '9999', // Incorrect PIN
        }));

        await Future.delayed(const Duration(milliseconds: 50));

        expect(outgoingMessages.length, equals(1));
        expect(outgoingMessages.first['type'], equals('error'));
        expect(outgoingMessages.first['code'], equals('INVALID_PIN'));
      });

      test('incorrect invite token with valid PIN is REJECTED', () async {
        final hub = ChatHub(config: pinProtectedConfig);
        final incoming = StreamController<dynamic>();
        final outgoing = StreamController<dynamic>();
        final channel = _MockWebSocketChannel(incoming, outgoing);

        hub.handleWebSocket(channel);

        final outgoingMessages = <Map<String, dynamic>>[];
        outgoing.stream.listen((event) {
          outgoingMessages.add(jsonDecode(event.toString()) as Map<String, dynamic>);
        });

        incoming.add(jsonEncode({
          'type': 'join',
          'nickname': 'Guest',
          'token': 'wrong_token',
          'pin': '1234',
        }));

        await Future.delayed(const Duration(milliseconds: 50));

        expect(outgoingMessages.length, equals(1));
        expect(outgoingMessages.first['type'], equals('error'));
        expect(outgoingMessages.first['code'], equals('INVALID_TOKEN'));
      });

      test('valid invite token AND valid PIN is accepted', () async {
        final hub = ChatHub(config: pinProtectedConfig);
        final incoming = StreamController<dynamic>();
        final outgoing = StreamController<dynamic>();
        final channel = _MockWebSocketChannel(incoming, outgoing);

        hub.handleWebSocket(channel);

        final outgoingMessages = <Map<String, dynamic>>[];
        outgoing.stream.listen((event) {
          outgoingMessages.add(jsonDecode(event.toString()) as Map<String, dynamic>);
        });

        incoming.add(jsonEncode({
          'type': 'join',
          'nickname': 'AuthorizedGuest',
          'token': 'secret_token_123',
          'pin': '1234',
        }));

        await Future.delayed(const Duration(milliseconds: 50));

        expect(outgoingMessages.any((m) => m['type'] == 'welcome'), isTrue);
        final welcomeMsg = outgoingMessages.firstWhere((m) => m['type'] == 'welcome');
        expect(welcomeMsg['nickname'], equals('AuthorizedGuest'));
      });

      test('token-only room allows valid token and rejects missing/invalid token', () async {
        const tokenOnlyConfig = RoomConfig(
          inviteToken: 'token_abc',
          requirePin: false,
        );
        final hub = ChatHub(config: tokenOnlyConfig);

        // 1. Missing token
        final incoming1 = StreamController<dynamic>();
        final outgoing1 = StreamController<dynamic>();
        final channel1 = _MockWebSocketChannel(incoming1, outgoing1);
        hub.handleWebSocket(channel1);
        final msgs1 = <Map<String, dynamic>>[];
        outgoing1.stream.listen((e) => msgs1.add(jsonDecode(e.toString()) as Map<String, dynamic>));

        incoming1.add(jsonEncode({'type': 'join', 'nickname': 'User'}));
        await Future.delayed(const Duration(milliseconds: 50));
        expect(msgs1.first['code'], equals('TOKEN_REQUIRED'));

        // 2. Valid token
        final incoming2 = StreamController<dynamic>();
        final outgoing2 = StreamController<dynamic>();
        final channel2 = _MockWebSocketChannel(incoming2, outgoing2);
        hub.handleWebSocket(channel2);
        final msgs2 = <Map<String, dynamic>>[];
        outgoing2.stream.listen((e) => msgs2.add(jsonDecode(e.toString()) as Map<String, dynamic>));

        incoming2.add(jsonEncode({'type': 'join', 'nickname': 'User', 'token': 'token_abc'}));
        await Future.delayed(const Duration(milliseconds: 50));
        expect(msgs2.any((m) => m['type'] == 'welcome'), isTrue);
      });
    });
  });
}
