import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:cloud_pocket/services/app_logger.dart';

class DiscoveredRoom {
  final String roomUrl;
  final String? roomName;
  final String? inviteToken;

  const DiscoveredRoom({
    required this.roomUrl,
    this.roomName,
    this.inviteToken,
  });
}

class RoomDiscoveryService {
  static const String _ntfyBase = 'https://ntfy.sh';
  static const discoveryLifetime = Duration(minutes: 10);

  static String _cleanTopic(String roomCode) {
    final clean = roomCode.trim().toLowerCase().replaceAll(RegExp(r'[^a-z0-9]'), '');
    return 'cp-room-$clean';
  }

  /// Register or publish an active room so other clients can discover it via Chat ID
  static Future<bool> registerRoom({
    required String roomCode,
    required String tunnelUrl,
    String? roomName,
    bool requirePin = false,
    http.Client? httpClient,
  }) async {
    if (roomCode.isEmpty || tunnelUrl.isEmpty || !requirePin) return false;
    final topic = _cleanTopic(roomCode);
    final url = Uri.parse('$_ntfyBase/$topic');
    final client = httpClient ?? http.Client();

    try {
      final payload = jsonEncode({
        'url': tunnelUrl,
        if (roomName != null && roomName.isNotEmpty) 'roomName': roomName,
        'timestamp': DateTime.now().millisecondsSinceEpoch,
        'expiresAt': DateTime.now().add(discoveryLifetime).millisecondsSinceEpoch,
        'requirePin': true,
      });

      final response = await client.post(
        url,
        headers: {
          'Title': 'CloudPocket Room',
          'Content-Type': 'application/json',
        },
        body: payload,
      ).timeout(const Duration(seconds: 6));

      if (response.statusCode >= 200 && response.statusCode < 300) {
        AppLogger().info('DISCOVERY', 'Registered Chat ID $roomCode -> $tunnelUrl');
        return true;
      }
    } catch (e) {
      AppLogger().warn('DISCOVERY', 'Failed to register Chat ID $roomCode: $e');
    } finally {
      if (httpClient == null) client.close();
    }
    return false;
  }

  /// Resolve a Chat ID (e.g. "AB-4829" or "ab4829") to its active tunnel URL
  static Future<DiscoveredRoom?> resolveRoom(String roomCode, {http.Client? httpClient}) async {
    final clean = roomCode.trim().toLowerCase().replaceAll(RegExp(r'[^a-z0-9]'), '');
    if (clean.length < 4) return null;
    final topic = 'cp-room-$clean';
    final url = Uri.parse('$_ntfyBase/$topic/json?poll=1');
    final client = httpClient ?? http.Client();

    try {
      final response = await client.get(url).timeout(const Duration(seconds: 6));
      if (response.statusCode == 200) {
        // ntfy /json?poll=1 returns JSON lines
        final lines = response.body.split('\n');
        for (final line in lines.reversed) {
          final trimmed = line.trim();
          if (trimmed.isEmpty) continue;
          try {
            final json = jsonDecode(trimmed) as Map<String, dynamic>;
            final messageRaw = json['message'];
            if (messageRaw is String && messageRaw.isNotEmpty) {
              final parsedMsg = jsonDecode(messageRaw) as Map<String, dynamic>;
              if (parsedMsg['burned'] == true) {
                return null;
              }
              final expiresAt = parsedMsg['expiresAt'];
              if (parsedMsg['requirePin'] != true || expiresAt is! int ||
                  DateTime.now().millisecondsSinceEpoch >= expiresAt) {
                return null;
              }
              final targetUrl = parsedMsg['url'] as String?;
              if (targetUrl != null && targetUrl.isNotEmpty) {
                return DiscoveredRoom(
                  roomUrl: targetUrl,
                  roomName: parsedMsg['roomName'] as String?,
                );
              }
            }
          } catch (_) {}
        }
      }
    } catch (e) {
      AppLogger().warn('DISCOVERY', 'Failed to resolve Chat ID $roomCode: $e');
    } finally {
      if (httpClient == null) client.close();
    }
    return null;
  }

  /// Clean up the registered topic when room is burned
  static Future<void> unregisterRoom(String roomCode, {http.Client? httpClient}) async {
    if (roomCode.isEmpty) return;
    final topic = _cleanTopic(roomCode);
    final url = Uri.parse('$_ntfyBase/$topic');
    final client = httpClient ?? http.Client();
    try {
      await client.post(
        url,
        headers: {'Title': 'CloudPocket Room Burned'},
        body: jsonEncode({'burned': true}),
      ).timeout(const Duration(seconds: 3));
    } catch (_) {} finally {
      if (httpClient == null) client.close();
    }
  }
}
