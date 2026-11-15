import 'dart:async';
import 'dart:io';
import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter/services.dart';

class NetworkInfoState {
  final String? localIp;
  final bool isWifi;
  final bool isHotspot;
  final bool isConnected;
  final List<String> allIps;

  const NetworkInfoState({
    this.localIp,
    this.isWifi = false,
    this.isHotspot = false,
    this.isConnected = false,
    this.allIps = const [],
  });
}

class NetworkMonitor {
  final Connectivity _connectivity = Connectivity();
  StreamSubscription<ConnectivityResult>? _subscription;
  final _stateController = StreamController<NetworkInfoState>.broadcast();

  Stream<NetworkInfoState> get onNetworkChanged => _stateController.stream;

  void startListening() {
    _subscription = _connectivity.onConnectivityChanged.listen((_) async {
      final state = await getNetworkState();
      _stateController.add(state);
    });
    // Fire initial state
    getNetworkState().then((state) => _stateController.add(state));
  }

  void stopListening() {
    _subscription?.cancel();
    _subscription = null;
  }

  static Future<NetworkInfoState> getNetworkState() async {
    String? resolvedIp;
    var isWifi = false;
    var isHotspot = false;

    String? hotspotIp;
    String? wifiIp;
    String? fallbackIp;
    final allIps = <String>[];

    try {
      final interfaces = await NetworkInterface.list(
        type: InternetAddressType.IPv4,
        includeLinkLocal: false,
        includeLoopback: false,
      );

      for (final iface in interfaces) {
        final name = iface.name.toLowerCase();
        for (final addr in iface.addresses) {
          if (!addr.isLoopback && !addr.address.startsWith('127.')) {
            allIps.add(addr.address);

            // Detect hotspot interface:
            // - ap0, softap0, swlan0 (Samsung One UI), wlan1 (dual-band chips)
            // - rndis0 (USB tethering)
            // - IP subnets: 192.168.43.x (legacy AOSP), 192.168.x.1 ending in .1
            //   (Samsung randomizes: 192.168.227.1, 192.168.58.1, etc.)
            final isHotspotIface = name.contains('ap') ||
                name.contains('softap') ||
                name.contains('swlan') ||
                name == 'wlan1' ||
                name.contains('rndis') ||
                name.contains('ncm') ||
                name.contains('bridge') ||
                name.contains('teth') ||
                addr.address.startsWith('192.168.43.') ||
                addr.address.startsWith('192.168.49.'); // Wi-Fi Direct

            // Heuristic: Any private IP ending in .1 on a non-standard wlan
            // interface is very likely a tethering gateway
            final isGatewayAddress = addr.address.endsWith('.1') &&
                !addr.address.startsWith('127.') &&
                _isPrivateIp(addr.address);

            if (isHotspotIface) {
              isHotspot = true;
              hotspotIp ??= addr.address;
            } else if (isGatewayAddress && name.contains('wlan')) {
              // Samsung often re-uses wlan0 for hotspot with a .1 gateway address
              // while connected Wi-Fi gets .x (non-.1) addresses
              isHotspot = true;
              hotspotIp ??= addr.address;
            } else if (name.contains('wlan') || name.contains('wi-fi') ||
                name.contains('eth') || name.contains('en')) {
              isWifi = true;
              wifiIp ??= addr.address;
            } else {
              fallbackIp ??= addr.address;
            }
          }
        }
      }

      resolvedIp = hotspotIp ?? wifiIp ?? fallbackIp;

      // Native fallback: ask Android for the real tethering IP
      if (resolvedIp == null || (!isHotspot && !isWifi)) {
        try {
          final nativeIp = await _getNativeTetheringIp();
          if (nativeIp != null && nativeIp.isNotEmpty) {
            resolvedIp ??= nativeIp;
            if (!allIps.contains(nativeIp)) allIps.add(nativeIp);
            isHotspot = true;
          }
        } catch (_) {}
      }
    } catch (_) {}

    return NetworkInfoState(
      localIp: resolvedIp,
      isWifi: isWifi,
      isHotspot: isHotspot,
      isConnected: resolvedIp != null,
      allIps: allIps,
    );
  }

  static bool _isPrivateIp(String ip) {
    final parts = ip.split('.');
    if (parts.length != 4) return false;
    final a = int.tryParse(parts[0]) ?? 0;
    final b = int.tryParse(parts[1]) ?? 0;
    if (a == 10) return true; // 10.0.0.0/8
    if (a == 172 && b >= 16 && b <= 31) return true; // 172.16.0.0/12
    if (a == 192 && b == 168) return true; // 192.168.0.0/16
    return false;
  }

  static const _wifiChannel = MethodChannel('com.cloudpocket.app/wifi_lock');

  static Future<String?> _getNativeTetheringIp() async {
    try {
      final result = await _wifiChannel.invokeMethod<String>('getTetheringAddress');
      return result;
    } catch (_) {
      return null;
    }
  }

  /// Probes the local server to verify it is reachable from this IP.
  /// Returns true if a successful HTTP response is received.
  static Future<bool> probeServer(String ip, int port, {Duration timeout = const Duration(seconds: 3)}) async {
    try {
      final socket = await Socket.connect(ip, port, timeout: timeout);
      socket.destroy();
      return true;
    } catch (_) {
      return false;
    }
  }
}
