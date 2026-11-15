import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:cloud_pocket/services/network_monitor.dart';

final networkMonitorProvider = Provider<NetworkMonitor>((ref) {
  final monitor = NetworkMonitor();
  monitor.startListening();
  ref.onDispose(() => monitor.stopListening());
  return monitor;
});

final networkStateProvider = StreamProvider<NetworkInfoState>((ref) {
  final monitor = ref.watch(networkMonitorProvider);
  return monitor.onNetworkChanged;
});
