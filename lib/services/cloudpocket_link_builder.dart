import 'package:cloud_pocket/models/share_session.dart';

enum SharingLinkMode {
  fileSharing, // Send or Receive Mode (AirDrop style)
  roomInvite,  // Disposable Room remote invite (Token only in fragment, NO PIN)
  roomQr,      // Disposable Room in-person QR (Token + PIN in fragment while active)
}

class CloudPocketLinkBuilder {
  CloudPocketLinkBuilder._();

  static const List<String> knownTunnelDomains = [
    'trycloudflare.com',
    'loca.lt',
    'bore.pub',
  ];

  /// Builds a canonical, single-source-of-truth URL for CloudPocket sharing
  static String buildUrl({
    required String interfaceAddress,
    required SharingLinkMode mode,
    required ShareSession session,
    String? sessionToken,
    bool isRoomActive = true,
    int defaultPort = 8080,
  }) {
    final cleanAddr = interfaceAddress.trim();
    if (cleanAddr.isEmpty) return '';

    String scheme;
    String host;
    int? port;

    if (cleanAddr.startsWith('http://') || cleanAddr.startsWith('https://')) {
      final uri = Uri.parse(cleanAddr);
      scheme = uri.scheme;
      host = uri.host;
      port = uri.hasPort ? uri.port : null;
    } else {
      // Determine if address has an explicit port (e.g. 192.168.1.50:8080)
      if (cleanAddr.contains(':')) {
        final parts = cleanAddr.split(':');
        host = parts[0];
        port = int.tryParse(parts[1]) ?? defaultPort;
      } else {
        host = cleanAddr;
        port = defaultPort;
      }

      // Determine scheme: https for known/custom tunnels, http for LAN/Hotspot
      final isTunnel = isKnownTunnelHost(host) || (session.tunnelConfig.cloudflareDomain != null && host == session.tunnelConfig.cloudflareDomain);
      scheme = (isTunnel && !host.contains('bore.pub')) ? 'https' : 'http';
    }

    final portPart = (port != null && !((scheme == 'http' && port == 80) || (scheme == 'https' && port == 443)))
        ? ':$port'
        : '';

    final baseUrl = '$scheme://$host$portPart';

    switch (mode) {
      case SharingLinkMode.fileSharing:
        final token = sessionToken ?? session.sessionToken;
        if (session.isProtected && token != null && token.isNotEmpty) {
          return '$baseUrl/#t=${Uri.encodeComponent(token)}';
        }
        return baseUrl;

      case SharingLinkMode.roomInvite:
        final token = session.roomConfig?.inviteToken ?? '';
        final frag = token.isNotEmpty ? '#token=${Uri.encodeComponent(token)}' : '';
        return '$baseUrl/room$frag';

      case SharingLinkMode.roomQr:
        final token = session.roomConfig?.inviteToken ?? '';
        final pin = session.password ?? session.roomConfig?.pin;
        final hasPin = pin != null && pin.isNotEmpty && isRoomActive;

        if (token.isNotEmpty && hasPin) {
          return '$baseUrl/room#token=${Uri.encodeComponent(token)}&pin=${Uri.encodeComponent(pin)}';
        } else if (token.isNotEmpty) {
          return '$baseUrl/room#token=${Uri.encodeComponent(token)}';
        }
        return '$baseUrl/room';
    }
  }

  /// Verifies if a host is a recognized tunnel provider
  static bool isKnownTunnelHost(String host) {
    final lower = host.toLowerCase();
    return knownTunnelDomains.any((domain) => lower == domain || lower.endsWith('.$domain'));
  }

  /// Validates if an IP is a usable, non-loopback, non-link-local IPv4 address
  static bool isUsableIpv4(String ip) {
    final trimmed = ip.trim();
    if (trimmed.isEmpty || trimmed == '0.0.0.0') return false;

    final parts = trimmed.split('.');
    if (parts.length != 4) return false;

    for (final part in parts) {
      final val = int.tryParse(part);
      if (val == null || val < 0 || val > 255) return false;
    }

    // Exclude loopback (127.0.0.0/8)
    if (parts[0] == '127') return false;

    // Exclude link-local / APIPA (169.254.0.0/16)
    if (parts[0] == '169' && parts[1] == '254') return false;

    return true;
  }

  /// Validates whether an IP address belongs to RFC 1918 private subnets
  static bool isPrivateIpv4(String ip) {
    if (!isUsableIpv4(ip)) return false;
    final parts = ip.split('.').map(int.parse).toList();

    // 10.0.0.0/8
    if (parts[0] == 10) return true;
    // 172.16.0.0/12 (172.16.0.0 - 172.31.255.255)
    if (parts[0] == 172 && parts[1] >= 16 && parts[1] <= 31) return true;
    // 192.168.0.0/16
    if (parts[0] == 192 && parts[1] == 168) return true;

    return false;
  }

  /// Validates if a hostname or IP is a legitimate CloudPocket host
  static bool isValidCloudPocketHost(
    String host, {
    List<String> allowedCustomDomains = const [],
  }) {
    final cleanHost = host.trim().toLowerCase();
    if (cleanHost.isEmpty) return false;

    if (cleanHost == 'localhost' || cleanHost == '127.0.0.1') return true;

    if (isUsableIpv4(cleanHost)) {
      return isPrivateIpv4(cleanHost);
    }

    if (isKnownTunnelHost(cleanHost)) return true;

    for (final custom in allowedCustomDomains) {
      final cClean = custom.trim().toLowerCase();
      if (cClean.isNotEmpty && (cleanHost == cClean || cleanHost.endsWith('.$cClean'))) {
        return true;
      }
    }

    return false;
  }

  /// Categorizes already constructed local URLs (e.g. from ServerState.allLocalUrls)
  static CategorizedInterfaces categorizeUrls(List<String> rawUrls) {
    final wifiList = <String>[];
    final hotspotList = <String>[];
    final otherList = <String>[];

    for (final raw in rawUrls) {
      final clean = raw.trim();
      if (clean.isEmpty) continue;
      final uri = Uri.tryParse(clean);
      final host = uri?.host ?? clean.split(':').first;
      if (!isUsableIpv4(host)) continue;

      if (host.startsWith('192.168.43.') || host.startsWith('192.168.49.')) {
        if (!hotspotList.contains(clean)) hotspotList.add(clean);
      } else if (isPrivateIpv4(host)) {
        if (!wifiList.contains(clean)) wifiList.add(clean);
      } else {
        if (!otherList.contains(clean)) otherList.add(clean);
      }
    }

    return CategorizedInterfaces(
      wifiIps: wifiList,
      hotspotIps: hotspotList,
      otherLanIps: otherList,
    );
  }

  /// Filters and sorts raw network interface URLs:
  /// Wi-Fi first, then Hotspot, then other live LAN IPs.
  static CategorizedInterfaces filterAndSortIps(List<String> rawUrls) {
    return categorizeUrls(rawUrls);
  }

  /// Filters and sorts raw network interface candidates:
  /// Wi-Fi first, then Hotspot, then other live LAN IPs.
  /// VPN, tun, tap, loopback, link-local, and IPv6 are strictly discarded.
  static List<String> filterAndSortCandidates(List<NetworkInterfaceCandidate> candidates) {
    final wifiList = <String>[];
    final hotspotList = <String>[];
    final otherList = <String>[];

    for (final cand in candidates) {
      final name = cand.interfaceName.toLowerCase();
      final ip = cand.ip.trim();

      // Discard VPN and tunnel adapters
      if (name.contains('tun') ||
          name.contains('tap') ||
          name.contains('vpn') ||
          name.contains('ppp') ||
          name.contains('p2p') ||
          name.contains('ipsec') ||
          name.contains('wireguard')) {
        continue;
      }

      if (!isUsableIpv4(ip)) continue;

      // Classify hotspot vs Wi-Fi vs other
      final isHotspot = name.contains('ap') ||
          name.contains('softap') ||
          name.contains('swlan') ||
          name == 'wlan1' ||
          name.contains('rndis') ||
          name.contains('ncm') ||
          name.contains('bridge') ||
          name.contains('teth') ||
          ip.startsWith('192.168.43.') ||
          ip.startsWith('192.168.49.');

      if (isHotspot) {
        if (!hotspotList.contains(ip)) hotspotList.add(ip);
      } else if (name.contains('wlan') ||
          name.contains('wi-fi') ||
          name.contains('eth') ||
          name.contains('en')) {
        if (!wifiList.contains(ip)) wifiList.add(ip);
      } else {
        if (!otherList.contains(ip) && !wifiList.contains(ip) && !hotspotList.contains(ip)) {
          otherList.add(ip);
        }
      }
    }

    return [...wifiList, ...hotspotList, ...otherList];
  }
}

class CategorizedInterfaces {
  final List<String> wifiIps;
  final List<String> hotspotIps;
  final List<String> otherLanIps;

  const CategorizedInterfaces({
    this.wifiIps = const [],
    this.hotspotIps = const [],
    this.otherLanIps = const [],
  });

  List<String> get all => [...wifiIps, ...hotspotIps, ...otherLanIps];
}

class NetworkInterfaceCandidate {
  final String interfaceName;
  final String ip;

  const NetworkInterfaceCandidate({
    required this.interfaceName,
    required this.ip,
  });
}
