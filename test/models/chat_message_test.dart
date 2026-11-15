import 'package:flutter_test/flutter_test.dart';
import 'package:cloud_pocket/models/chat_message.dart';

void main() {
  test('WebSocket envelopes preserve the underlying file message type', () {
    final message = ChatMessage.fromJson({'type': 'chat_message', 'messageType': 'file', 'filename': 'fixture.txt'});
    expect(message.type, ChatMessageType.file);
  });
  group('ChatMessage Tests', () {
    test('serializes and deserializes text message correctly', () {
      final now = DateTime.now();
      final msg = ChatMessage(
        seq: 1,
        type: ChatMessageType.text,
        senderId: 'p_1234',
        senderNickname: 'Alice',
        text: 'Hello world',
        timestamp: now,
        isSecureClient: true,
        color: '#10B981',
      );

      final json = msg.toJson();
      expect(json['seq'], equals(1));
      expect(json['type'], equals('text'));
      expect(json['senderNickname'], equals('Alice'));
      expect(json['text'], equals('Hello world'));
      expect(json['isSecureClient'], isTrue);

      final revived = ChatMessage.fromJson(json);
      expect(revived.seq, equals(1));
      expect(revived.type, equals(ChatMessageType.text));
      expect(revived.senderNickname, equals('Alice'));
      expect(revived.text, equals('Hello world'));
      expect(revived.isSecureClient, isTrue);
    });

    test('serializes and deserializes file message correctly', () {
      final now = DateTime.now();
      final msg = ChatMessage(
        seq: 2,
        type: ChatMessageType.file,
        senderId: 'p_5678',
        senderNickname: 'Bob',
        filename: 'secret.pdf',
        fileSize: 204800,
        fileMimeType: 'application/pdf',
        fileDownloadPath: '/api/room/files/secret.pdf',
        timestamp: now,
        isSecureClient: false,
      );

      final json = msg.toJson();
      expect(json['type'], equals('file'));
      expect(json['filename'], equals('secret.pdf'));
      expect(json['fileSize'], equals(204800));

      final revived = ChatMessage.fromJson(json);
      expect(revived.type, equals(ChatMessageType.file));
      expect(revived.filename, equals('secret.pdf'));
      expect(revived.fileDownloadPath, equals('/api/room/files/secret.pdf'));
    });

    test('serializes, deserializes, and copies E2E encrypted message', () {
      final now = DateTime.now();
      final msg = ChatMessage(
        seq: 3,
        type: ChatMessageType.text,
        senderId: 'p_9999',
        senderNickname: 'Charlie',
        timestamp: now,
        isSecureClient: true,
        color: '#38BDF8',
        isE2e: true,
        ciphertext: 'k8d+encrypted=',
        iv: '16byteIvBase64==',
      );

      final json = msg.toJson();
      expect(json['isE2e'], isTrue);
      expect(json['ciphertext'], equals('k8d+encrypted='));
      expect(json['iv'], equals('16byteIvBase64=='));
      expect(json['text'], isNull);

      final revived = ChatMessage.fromJson(json);
      expect(revived.isE2e, isTrue);
      expect(revived.ciphertext, equals('k8d+encrypted='));
      expect(revived.iv, equals('16byteIvBase64=='));

      final decryptedCopy = revived.copyWith(text: 'Decrypted message text');
      expect(decryptedCopy.text, equals('Decrypted message text'));
      expect(decryptedCopy.isE2e, isTrue);
    });
  });
}
