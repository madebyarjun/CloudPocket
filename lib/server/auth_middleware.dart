import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:shelf/shelf.dart';
import 'package:uuid/uuid.dart';
import 'package:cloud_pocket/models/share_session.dart';
import 'package:cloud_pocket/server/room_pin_rate_limiter.dart';

class SessionEntry {
  final String token;
  String? userIdentifier;
  final DateTime expiresAt;
  bool isGoogleVerified;
  bool isPasswordVerified;
  bool isRoomVerified;

  SessionEntry({
    required this.token,
    this.userIdentifier,
    required this.expiresAt,
    this.isGoogleVerified = false,
    this.isPasswordVerified = false,
    this.isRoomVerified = false,
  });

  bool get isExpired => DateTime.now().isAfter(expiresAt);

  bool isFullyAuthenticated(ShareSession config) {
    if (isExpired) return false;
    if (config.requireGoogleAuth && !isGoogleVerified) return false;
    if (config.requirePassword && !isPasswordVerified) return false;
    if (config.roomConfig?.requirePin == true && !isPasswordVerified) return false;
    if (config.isDisposableRoom && config.roomConfig != null &&
        (config.roomConfig!.inviteToken.isNotEmpty || config.roomConfig!.requirePin) && !isRoomVerified) return false;
    if (config.isDisposableRoom && config.roomConfig?.isTokenRevoked == true) return false;
    return true;
  }
}

class AuthManager {
  bool get _isProtected => sessionConfig.isProtected ||
      (sessionConfig.isDisposableRoom && sessionConfig.roomConfig != null &&
          (sessionConfig.roomConfig!.requirePin || sessionConfig.roomConfig!.inviteToken.isNotEmpty || sessionConfig.roomConfig!.isTokenRevoked));
  final ShareSession sessionConfig;
  final Map<String, SessionEntry> _activeSessions = {};
  static const String cookieName = 'cp_session';
  static const Uuid _uuid = Uuid();

  AuthManager(this.sessionConfig);

  SessionEntry getOrCreateSession(String? existingToken, {Duration lifetime = const Duration(hours: 24)}) {
    _cleanupExpired();
    if (existingToken != null && _activeSessions.containsKey(existingToken)) {
      final existing = _activeSessions[existingToken]!;
      if (!existing.isExpired) return existing;
    }

    final token = _uuid.v4();
    final entry = SessionEntry(
      token: token,
      expiresAt: DateTime.now().add(lifetime),
      isGoogleVerified: !sessionConfig.requireGoogleAuth,
      isPasswordVerified: !sessionConfig.requirePassword && (sessionConfig.roomConfig?.requirePin != true),
    );
    _activeSessions[token] = entry;
    return entry;
  }

  bool validateToken(String? token) {
    final isProtected = _isProtected;
    if (!isProtected) return true;
    if (token == null) return false;
    _cleanupExpired();
    final entry = _activeSessions[token];
    return entry != null && entry.isFullyAuthenticated(sessionConfig);
  }

  void revokeToken(String? token) {
    if (token != null) _activeSessions.remove(token);
  }

  void _cleanupExpired() {
    _activeSessions.removeWhere((_, entry) => entry.isExpired);
  }

  bool verifyPassword(String inputPassword) {
    if (!sessionConfig.requirePassword) return true;
    final inputHash = ShareSession.hashPassword(inputPassword);
    return inputHash == sessionConfig.passwordHash;
  }

  Future<Map<String, dynamic>?> verifyGoogleIdToken(String idToken) async {
    if (!sessionConfig.requireGoogleAuth) return {'verified': true};

    try {
      final uri = Uri.https('oauth2.googleapis.com', '/tokeninfo', {'id_token': idToken});
      final res = await http.get(uri).timeout(const Duration(seconds: 8));
      if (res.statusCode != 200) return null;

      final data = jsonDecode(res.body) as Map<String, dynamic>;
      final email = data['email'] as String?;
      final emailVerified = data['email_verified'] == 'true' || data['email_verified'] == true;

      if (email == null || !emailVerified) return null;

      // If allowed emails whitelist is specified, verify membership
      if (sessionConfig.allowedEmails.isNotEmpty) {
        final matches = sessionConfig.allowedEmails.any(
          (allowed) => allowed.trim().toLowerCase() == email.trim().toLowerCase(),
        );
        if (!matches) return null;
      }

      // Verify audience matches configured Google Client ID to prevent Confused Deputy attacks
      if (sessionConfig.googleClientId != null && sessionConfig.googleClientId!.trim().isNotEmpty) {
        final aud = data['aud'] as String?;
        if (aud != sessionConfig.googleClientId!.trim()) {
          return null;
        }
      }

      return data;
    } catch (_) {
      return null;
    }
  }

  String? extractTokenFromRequest(Request request) {
    // 1. Check Authorization header: Bearer <token>
    final authHeader = request.headers['authorization'];
    if (authHeader != null && authHeader.toLowerCase().startsWith('bearer ')) {
      return authHeader.substring(7).trim();
    }

    // 2. Check Cookie header: cp_session=<token>
    final cookieHeader = request.headers['cookie'];
    if (cookieHeader != null) {
      final cookies = cookieHeader.split(';');
      for (final cookie in cookies) {
        final parts = cookie.split('=');
        if (parts.length == 2 && parts[0].trim() == cookieName) {
          return parts[1].trim();
        }
      }
    }

    // 3. Query parameter fallback for streaming/websockets: ?token=<token>
    return request.url.queryParameters['token'];
  }

  Middleware get middleware => (Handler innerHandler) {
    return (Request request) async {
      // If no authentication is required, pass through
      final isProtected = _isProtected;
      if (!isProtected) {
        return innerHandler(request);
      }

      final path = request.url.path;
      // Room sockets authenticate their join frame in ChatHub before admission.
      if (sessionConfig.isDisposableRoom && (path == 'ws/room' || path == 'api/room/ws')) {
        return innerHandler(request);
      }

      // Allow static assets, auth endpoints, and public status without auth
      final isPublicApi = path.startsWith('api/auth/') ||
          path.startsWith('api/room/auth') ||
          path == 'api/room/info' ||
          path == 'api/status' ||
          path == 'api/security-mode' ||
          path == 'api/register-visitor';
      final isStaticAsset = !path.startsWith('api/') && !path.startsWith('ws/');

      if (isPublicApi || isStaticAsset) {
        return innerHandler(request);
      }

      // Check session token
      final token = extractTokenFromRequest(request);
      if (validateToken(token)) {
        return innerHandler(request);
      }

      // Native media requests carry room credentials rather than browser cookies.
      if (path.startsWith('api/room/') && sessionConfig.isDisposableRoom && sessionConfig.roomConfig != null) {
        final config = sessionConfig.roomConfig!;
        final roomPin = request.headers['x-room-pin'] ?? request.url.queryParameters['pin'];
        final roomToken = request.headers['x-room-token'];
        if (roomPin != null || roomToken != null) {
          final limiter = RoomPinRateLimiter();
          final key = RoomPinRateLimiter.clientKey(request);
          if (limiter.isLockedOut(key)) return Response(429, body: 'Too many failed room authentication attempts');
          final pinValid = !config.requirePin || (roomPin != null && roomPin.isNotEmpty && config.verifyPin(roomPin));
          final tokenValid = config.inviteToken.isEmpty ||
              (roomToken != null ? roomToken == config.inviteToken : config.requirePin);
          if (!config.isTokenRevoked && pinValid && tokenValid) {
            limiter.recordSuccess(key);
            return innerHandler(request);
          }
          limiter.recordFailure(key);
          if (limiter.isLockedOut(key)) return Response(429, body: 'Too many failed room authentication attempts');
        }
      }

      return Response(
        401,
        body: jsonEncode({
          'error': 'Unauthorized',
          'message': 'Authentication required',
          'requireGoogleAuth': sessionConfig.requireGoogleAuth,
          'requirePassword': sessionConfig.requirePassword,
        }),
        headers: {'content-type': 'application/json'},
      );
    };
  };
}
