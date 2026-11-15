import 'dart:io';
import 'package:shelf/shelf.dart';

/// In-memory rate limiter for PIN and token attempts (5 tries -> 60s lockout)
class RoomPinRateLimiter {
  // Forwarded headers are client-controlled on local and raw TCP connections.
  static String clientKey(Request request) =>
      (request.context['shelf.io.connection_info'] as HttpConnectionInfo?)
          ?.remoteAddress.address ?? 'unknown';
  static final RoomPinRateLimiter _instance = RoomPinRateLimiter._();
  factory RoomPinRateLimiter() => _instance;
  RoomPinRateLimiter._();

  static const int maxAttempts = 5;
  static const Duration lockoutDuration = Duration(seconds: 60);

  final Map<String, _AttemptEntry> _attempts = {};

  bool isLockedOut(String clientId) {
    _cleanupExpired();
    final entry = _attempts[clientId];
    if (entry == null) return false;
    if (entry.lockedUntil != null) {
      if (DateTime.now().isBefore(entry.lockedUntil!)) {
        return true;
      } else {
        _attempts.remove(clientId);
        return false;
      }
    }
    return false;
  }

  Duration? remainingLockout(String clientId) {
    final entry = _attempts[clientId];
    if (entry?.lockedUntil != null && DateTime.now().isBefore(entry!.lockedUntil!)) {
      return entry.lockedUntil!.difference(DateTime.now());
    }
    return null;
  }

  void recordFailure(String clientId) {
    _cleanupExpired();
    final entry = _attempts.putIfAbsent(clientId, () => _AttemptEntry());
    entry.count++;
    entry.lastAttempt = DateTime.now();
    if (entry.count >= maxAttempts) {
      entry.lockedUntil = DateTime.now().add(lockoutDuration);
    }
  }

  void recordSuccess(String clientId) {
    _attempts.remove(clientId);
  }

  void reset() {
    _attempts.clear();
  }

  void _cleanupExpired() {
    final now = DateTime.now();
    _attempts.removeWhere((_, entry) => entry.lockedUntil != null
        ? now.isAfter(entry.lockedUntil!)
        : now.difference(entry.lastAttempt) > const Duration(minutes: 5));
  }
}

class _AttemptEntry {
  DateTime lastAttempt = DateTime.now();
  int count = 0;
  DateTime? lockedUntil;
}

