class ParsedRoomLink {
  final String roomUrl;
  final String? pin;
  final String? nickname;
  final String? token;

  const ParsedRoomLink({
    required this.roomUrl,
    this.pin,
    this.nickname,
    this.token,
  });

  @override
  String toString() => 'ParsedRoomLink(url: $roomUrl, pin: $pin, nick: $nickname, token: $token)';
}

class RoomLinkDetector {
  /// Regular expression to match URLs in arbitrary text (e.g. WhatsApp / Telegram messages)
  static final RegExp _urlRegex = RegExp(
    r'(?:https?:\/\/|cloudpocket:\/\/)[^\s"<>]+',
    caseSensitive: false,
  );

  /// Parse text or clipboard content and return a [ParsedRoomLink] if it contains a valid room link.
  static ParsedRoomLink? parse(String rawText) {
    final text = rawText.trim();
    if (text.isEmpty) return null;

    // 1. Direct cloudpocket://room deep link scheme
    if (text.toLowerCase().startsWith('cloudpocket://room')) {
      try {
        final uri = Uri.parse(text);
        final urlParam = uri.queryParameters['url'];
        if (urlParam != null && urlParam.isNotEmpty) {
          final decodedUrl = Uri.decodeComponent(urlParam);
          return ParsedRoomLink(
            roomUrl: normalizeRoomUrl(decodedUrl),
            pin: uri.queryParameters['pin'],
            nickname: uri.queryParameters['nick'] ?? uri.queryParameters['nickname'],
            token: uri.queryParameters['token'] ?? uri.queryParameters['k'],
          );
        }
      } catch (_) {}
    }

    // 2. Extract any embedded URL from text
    final match = _urlRegex.firstMatch(text);
    if (match != null) {
      final potentialUrl = match.group(0)!;
      return _parseHttpUrl(potentialUrl);
    }

    // 3. Fallback check on full string as URL
    return _parseHttpUrl(text);
  }

  static ParsedRoomLink? _parseHttpUrl(String rawUrl) {
    try {
      final clean = rawUrl.replaceAll(RegExp(r'[.,;!]+$'), ''); // trim trailing punctuation
      final uri = Uri.parse(clean);

      if (!uri.hasScheme || (uri.scheme != 'http' && uri.scheme != 'https' && uri.scheme != 'cloudpocket')) {
        return null;
      }

      String? token;
      String? pin;
      if (uri.hasFragment && uri.fragment.isNotEmpty) {
        final frag = uri.fragment;
        final fragParams = Uri.splitQueryString(frag);
        token = fragParams['k'] ?? fragParams['token'];
        pin = fragParams['pin'];
      }

      if (uri.scheme == 'cloudpocket' && uri.host == 'room') {
        final target = uri.queryParameters['url'];
        if (target != null && target.isNotEmpty) {
          return ParsedRoomLink(
            roomUrl: normalizeRoomUrl(Uri.decodeComponent(target)),
            pin: pin ?? uri.queryParameters['pin'],
            nickname: uri.queryParameters['nick'] ?? uri.queryParameters['nickname'],
            token: token ?? uri.queryParameters['token'] ?? uri.queryParameters['k'],
          );
        }
      }

      final host = uri.host.toLowerCase();
      // Recognized room hosts: trycloudflare.com, loca.lt, bore.pub, localhost, or IP addresses
      final isRecognizedHost = host.contains('trycloudflare.com') ||
          host.contains('loca.lt') ||
          host.contains('bore.pub') ||
          host == 'localhost' ||
          host == '127.0.0.1' ||
          RegExp(r'^\d{1,3}\.\d{1,3}\.\d{1,3}\.\d{1,3}$').hasMatch(host);

      final path = uri.path.toLowerCase();
      final hasRoomPath = path.contains('/room');

      // If it's a recognized tunnel provider or explicitly contains /room
      if (isRecognizedHost || hasRoomPath) {
        return ParsedRoomLink(
          roomUrl: normalizeRoomUrl(clean),
          pin: pin ?? uri.queryParameters['pin'],
          nickname: uri.queryParameters['nick'] ?? uri.queryParameters['nickname'],
          token: token ?? uri.queryParameters['token'] ?? uri.queryParameters['k'],
        );
      }
    } catch (_) {}
    return null;
  }

  /// Ensure roomUrl has proper scheme and is cleaned up
  static String normalizeRoomUrl(String url) {
    var trimmed = url.trim();
    if (!trimmed.startsWith('http://') && !trimmed.startsWith('https://')) {
      trimmed = 'https://$trimmed';
    }
    // Remove query params or hash fragments from the base endpoint
    try {
      final uri = Uri.parse(trimmed);
      final portStr = uri.hasPort ? ':${uri.port}' : '';
      return '${uri.scheme}://${uri.host}$portStr';
    } catch (_) {
      return trimmed;
    }
  }

  /// Build a deep link string that can be encoded in QR code or shared
  static String buildDeepLink({
    required String roomUrl,
    String? pin,
    String? nickname,
    String? token,
  }) {
    final params = <String, String>{
      'url': roomUrl,
    };
    if (pin != null && pin.isNotEmpty) {
      params['pin'] = pin;
    }
    if (nickname != null && nickname.isNotEmpty) {
      params['nick'] = nickname;
    }
    if (token != null && token.isNotEmpty) {
      params['token'] = token;
    }
    return Uri(
      scheme: 'cloudpocket',
      host: 'room',
      queryParameters: params,
    ).toString();
  }

  /// Build an encrypted invite link with the token in the URL fragment (#k=token).
  /// Fragments are never transmitted across HTTP requests, keeping the token invisible to proxies/CDNs.
  static String buildEncryptedInviteUrl({
    required String roomUrl,
    required String token,
  }) {
    final base = normalizeRoomUrl(roomUrl);
    return '$base/room#k=$token';
  }
}
