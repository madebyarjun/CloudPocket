import 'dart:convert';
import 'dart:math';
import 'dart:typed_data';
import 'package:crypto/crypto.dart';
import 'package:pointycastle/export.dart';

class E2eEncryptedPayload {
  final String ciphertext;
  final String iv;
  final String algorithm;

  const E2eEncryptedPayload({
    required this.ciphertext,
    required this.iv,
    this.algorithm = 'AES-GCM',
  });
}

class E2eEncryptionService {
  final Uint8List _keyBytes;

  E2eEncryptionService._(this._keyBytes);

  /// Derives an AES-256 key from room secret credentials (inviteToken or PIN or both).
  /// Throws [ArgumentError] if the secret is empty.
  factory E2eEncryptionService.fromSecret(String secret) {
    if (secret.trim().isEmpty) {
      throw ArgumentError('Room secret must not be empty');
    }
    final keyBytes = deriveKey(secret);
    return E2eEncryptionService._(keyBytes);
  }

  /// Derives a 32-byte AES key via SHA-256.
  static Uint8List deriveKey(String secret) {
    if (secret.trim().isEmpty) {
      throw ArgumentError('Secret must not be empty');
    }
    return Uint8List.fromList(sha256.convert(utf8.encode(secret)).bytes);
  }

  /// Computes the shared secret string from available room tokens.
  /// Returns null if neither token nor PIN is provided.
  /// Never falls back to a predictable default key.
  static String? computeSecret({String? token, String? pin}) {
    final cleanToken = token?.trim() ?? '';
    final cleanPin = pin?.trim() ?? '';
    if (cleanToken.isNotEmpty && cleanPin.isNotEmpty) {
      return '$cleanToken:$cleanPin';
    } else if (cleanToken.isNotEmpty) {
      return cleanToken;
    } else if (cleanPin.isNotEmpty) {
      return cleanPin;
    }
    return null;
  }

  /// Encrypts plaintext message into base64 ciphertext and base64 IV
  /// using authenticated AES-256-GCM with a 12-byte random nonce and 128-bit auth tag.
  E2eEncryptedPayload encrypt(String plaintext, {Uint8List? associatedData}) {
    final random = Random.secure();
    final iv = Uint8List(12); // Standard 96-bit nonce for GCM
    for (int i = 0; i < 12; i++) {
      iv[i] = random.nextInt(256);
    }

    final cipher = GCMBlockCipher(AESEngine());
    final aad = associatedData ?? Uint8List(0);
    final params = AEADParameters(
      KeyParameter(_keyBytes),
      128, // 128-bit authentication tag
      iv,
      aad,
    );
    cipher.init(true, params);

    final input = Uint8List.fromList(utf8.encode(plaintext));
    final encrypted = cipher.process(input);

    return E2eEncryptedPayload(
      ciphertext: base64.encode(encrypted),
      iv: base64.encode(iv),
      algorithm: 'AES-GCM',
    );
  }

  /// Decrypts base64 ciphertext using base64 IV.
  /// Uses authenticated AES-256-GCM if IV is 12 bytes (96-bit).
  /// Falls back to legacy AES-256-CBC if IV is 16 bytes (128-bit) for backward compatibility.
  /// Rejects tampered, malformed, or unauthenticated ciphertexts by returning null.
  String? decrypt({
    required String ciphertext,
    required String iv,
    Uint8List? associatedData,
  }) {
    try {
      final ivBytes = base64.decode(iv);
      final cipherBytes = base64.decode(ciphertext);
      final aad = associatedData ?? Uint8List(0);

      if (ivBytes.length == 12) {
        // Authenticated AES-GCM decryption with 128-bit MAC check
        final cipher = GCMBlockCipher(AESEngine());
        final params = AEADParameters(
          KeyParameter(_keyBytes),
          128,
          ivBytes,
          aad,
        );
        cipher.init(false, params);
        final decrypted = cipher.process(cipherBytes);
        return utf8.decode(decrypted);
      } else if (ivBytes.length == 16) {
        // Legacy fallback AES-CBC (for backward compatibility during migration)
        final cipher = PaddedBlockCipherImpl(
          PKCS7Padding(),
          CBCBlockCipher(AESEngine()),
        );
        final params = PaddedBlockCipherParameters<CipherParameters, CipherParameters>(
          ParametersWithIV<KeyParameter>(KeyParameter(_keyBytes), ivBytes),
          null,
        );
        cipher.init(false, params);
        final decrypted = cipher.process(cipherBytes);
        return utf8.decode(decrypted);
      }
      return null;
    } catch (_) {
      return null;
    }
  }
}
