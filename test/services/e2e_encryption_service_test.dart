import 'dart:convert';
import 'dart:typed_data';
import 'package:flutter_test/flutter_test.dart';
import 'package:pointycastle/export.dart';
import 'package:cloud_pocket/services/e2e_encryption_service.dart';

void main() {
  group('E2eEncryptionService', () {
    test('derives 32-byte key from room secret', () {
      final key = E2eEncryptionService.deriveKey('my-secret-key-1234');
      expect(key.length, equals(32));
    });

    test('rejects empty secret during key derivation and initialization', () {
      expect(() => E2eEncryptionService.deriveKey(''), throwsArgumentError);
      expect(() => E2eEncryptionService.deriveKey('   '), throwsArgumentError);
      expect(() => E2eEncryptionService.fromSecret(''), throwsArgumentError);
      expect(() => E2eEncryptionService.fromSecret('   '), throwsArgumentError);
    });

    test('computes deterministic secret combining token and pin without fallback secret', () {
      final s1 = E2eEncryptionService.computeSecret(token: 'token123', pin: '4321');
      expect(s1, equals('token123:4321'));

      final s2 = E2eEncryptionService.computeSecret(token: 'token123', pin: null);
      expect(s2, equals('token123'));

      final s3 = E2eEncryptionService.computeSecret(token: null, pin: '4321');
      expect(s3, equals('4321'));

      // Never silently falls back to a predictable key
      final s4 = E2eEncryptionService.computeSecret(token: '', pin: '');
      expect(s4, isNull);

      final s5 = E2eEncryptionService.computeSecret(token: null, pin: null);
      expect(s5, isNull);
    });

    test('encrypts and decrypts text successfully with authenticated AES-256-GCM', () {
      final service = E2eEncryptionService.fromSecret('confidential-room-secret');
      const plainText = 'Hello! This message is end-to-end encrypted with AES-256-GCM.';

      final encrypted = service.encrypt(plainText);
      expect(encrypted.ciphertext.isNotEmpty, isTrue);
      expect(encrypted.iv.isNotEmpty, isTrue);
      expect(encrypted.algorithm, equals('AES-GCM'));

      // 12-byte standard GCM IV is 16 base64 chars
      final rawIv = base64.decode(encrypted.iv);
      expect(rawIv.length, equals(12));

      expect(encrypted.ciphertext, isNot(equals(plainText)));

      final decrypted = service.decrypt(ciphertext: encrypted.ciphertext, iv: encrypted.iv);
      expect(decrypted, equals(plainText));
    });

    test('different IVs result in different ciphertexts for the same plaintext', () {
      final service = E2eEncryptionService.fromSecret('secret-token');
      const text = 'Identical message';

      final enc1 = service.encrypt(text);
      final enc2 = service.encrypt(text);

      expect(enc1.iv, isNot(equals(enc2.iv)));
      expect(enc1.ciphertext, isNot(equals(enc2.ciphertext)));

      expect(service.decrypt(ciphertext: enc1.ciphertext, iv: enc1.iv), equals(text));
      expect(service.decrypt(ciphertext: enc2.ciphertext, iv: enc2.iv), equals(text));
    });

    test('authenticated encryption rejects ciphertext tampering and bit-flipping', () {
      final service = E2eEncryptionService.fromSecret('tamper-test-secret');
      final enc = service.encrypt('Sensitive unmodifiable data');

      final rawCipher = base64.decode(enc.ciphertext);
      // Flip a bit in the ciphertext
      rawCipher[0] = rawCipher[0] ^ 0x01;
      final tamperedCiphertext = base64.encode(rawCipher);

      // Decryption MUST fail and return null due to auth tag verification failure
      final decrypted = service.decrypt(ciphertext: tamperedCiphertext, iv: enc.iv);
      expect(decrypted, isNull);
    });

    test('authenticated encryption rejects IV tampering', () {
      final service = E2eEncryptionService.fromSecret('tamper-iv-secret');
      final enc = service.encrypt('Sensitive data');

      final rawIv = base64.decode(enc.iv);
      rawIv[0] = rawIv[0] ^ 0x01;
      final tamperedIv = base64.encode(rawIv);

      final decrypted = service.decrypt(ciphertext: enc.ciphertext, iv: tamperedIv);
      expect(decrypted, isNull);
    });

    test('fails gracefully when decrypting with wrong secret or malformed data', () {
      final service1 = E2eEncryptionService.fromSecret('secret-1');
      final service2 = E2eEncryptionService.fromSecret('secret-2');

      final enc = service1.encrypt('Secret payload');

      // Attempt decryption with wrong key
      final wrongDecrypt = service2.decrypt(ciphertext: enc.ciphertext, iv: enc.iv);
      expect(wrongDecrypt, isNull);

      // Attempt decryption with invalid ciphertext
      final tamperedDecrypt = service1.decrypt(ciphertext: 'invalid_base64!!!', iv: enc.iv);
      expect(tamperedDecrypt, isNull);
    });

    test('supports backward-compatible migration: decrypts legacy 16-byte IV AES-CBC payloads', () {
      const secret = 'migration-secret';
      final service = E2eEncryptionService.fromSecret(secret);
      final keyBytes = E2eEncryptionService.deriveKey(secret);

      // Manually produce a legacy AES-256-CBC payload with 16-byte IV
      final legacyIv = Uint8List(16);
      for (int i = 0; i < 16; i++) {
        legacyIv[i] = i;
      }
      final cbcCipher = PaddedBlockCipherImpl(
        PKCS7Padding(),
        CBCBlockCipher(AESEngine()),
      );
      final params = PaddedBlockCipherParameters<CipherParameters, CipherParameters>(
        ParametersWithIV<KeyParameter>(KeyParameter(keyBytes), legacyIv),
        null,
      );
      cbcCipher.init(true, params);
      const originalText = 'Legacy CBC message before GCM upgrade';
      final encryptedBytes = cbcCipher.process(Uint8List.fromList(utf8.encode(originalText)));

      final legacyPayload = base64.encode(encryptedBytes);
      final legacyIvB64 = base64.encode(legacyIv);

      // E2eEncryptionService.decrypt must recognize 16-byte IV and decrypt legacy CBC
      final decrypted = service.decrypt(ciphertext: legacyPayload, iv: legacyIvB64);
      expect(decrypted, equals(originalText));
    });
  });
}
