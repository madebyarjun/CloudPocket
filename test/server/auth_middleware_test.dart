import 'package:flutter_test/flutter_test.dart';
import 'package:shelf/shelf.dart';
import 'package:cloud_pocket/models/share_session.dart';
import 'package:cloud_pocket/server/auth_middleware.dart';

void main() {
  group('AuthManager & Middleware Multi-Combination Tests', () {
    test('Open mode passes requests directly through', () async {
      const session = ShareSession(requireGoogleAuth: false, requirePassword: false);
      final manager = AuthManager(session);

      final handler = const Pipeline().addMiddleware(manager.middleware).addHandler((req) => Response.ok('unlocked'));
      final response = await handler(Request('GET', Uri.parse('http://localhost:8080/api/files')));

      expect(response.statusCode, 200);
      expect(await response.readAsString(), 'unlocked');
    });

    test('Password only mode blocks requests without valid token', () async {
      final session = ShareSession(
        requireGoogleAuth: false,
        requirePassword: true,
        passwordHash: ShareSession.hashPassword('secret123'),
      );
      final manager = AuthManager(session);

      final handler = const Pipeline().addMiddleware(manager.middleware).addHandler((req) => Response.ok('unlocked'));
      final response = await handler(Request('GET', Uri.parse('http://localhost:8080/api/files')));

      expect(response.statusCode, 401);
    });

    test('Password only mode allows requests after password verified', () async {
      final session = ShareSession(
        requireGoogleAuth: false,
        requirePassword: true,
        passwordHash: ShareSession.hashPassword('secret123'),
      );
      final manager = AuthManager(session);

      expect(manager.verifyPassword('wrong'), false);
      expect(manager.verifyPassword('secret123'), true);

      final entry = manager.getOrCreateSession(null);
      entry.isPasswordVerified = true;
      expect(manager.validateToken(entry.token), true);

      final handler = const Pipeline().addMiddleware(manager.middleware).addHandler((req) => Response.ok('unlocked'));
      final response = await handler(
        Request(
          'GET',
          Uri.parse('http://localhost:8080/api/files'),
          headers: {'cookie': 'cp_session=${entry.token}'},
        ),
      );

      expect(response.statusCode, 200);
      expect(await response.readAsString(), 'unlocked');
    });

    test('Google only mode (Google Auth, No Password) requires Google verification', () async {
      const session = ShareSession(
        requireGoogleAuth: true,
        requirePassword: false,
      );
      final manager = AuthManager(session);

      final entry = manager.getOrCreateSession(null);
      // Not yet Google verified
      expect(manager.validateToken(entry.token), false);

      // Verify Google
      entry.isGoogleVerified = true;
      entry.userIdentifier = 'test@gmail.com';
      expect(manager.validateToken(entry.token), true);
    });

    test('Dual mode (Google Auth AND Password) requires both to be verified', () async {
      final session = ShareSession(
        requireGoogleAuth: true,
        requirePassword: true,
        passwordHash: ShareSession.hashPassword('pass456'),
      );
      final manager = AuthManager(session);

      final entry = manager.getOrCreateSession(null);
      expect(manager.validateToken(entry.token), false);

      // Verify Google only
      entry.isGoogleVerified = true;
      expect(manager.validateToken(entry.token), false); // Still needs password

      // Verify password
      entry.isPasswordVerified = true;
      expect(manager.validateToken(entry.token), true); // Both verified!
    });

    test('Expired tokens are rejected', () async {
      final session = ShareSession(
        requireGoogleAuth: false,
        requirePassword: true,
        passwordHash: ShareSession.hashPassword('secret123'),
      );
      final manager = AuthManager(session);

      final entry = manager.getOrCreateSession(null, lifetime: const Duration(milliseconds: -10));
      entry.isPasswordVerified = true;
      expect(manager.validateToken(entry.token), false);
    });
  });
}
