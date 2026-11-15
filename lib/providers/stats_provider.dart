import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:cloud_pocket/models/server_stats.dart';

class StatsNotifier extends Notifier<ServerStats> {
  @override
  ServerStats build() {
    return const ServerStats();
  }

  void updateStats(ServerStats newStats) {
    state = newStats;
  }

  void reset() {
    state = const ServerStats();
  }
}

final statsProvider = NotifierProvider<StatsNotifier, ServerStats>(StatsNotifier.new);
