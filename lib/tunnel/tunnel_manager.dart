import 'dart:async';
import 'package:cloud_pocket/services/app_logger.dart';
import 'package:cloud_pocket/tunnel/bore_client.dart';
import 'package:cloud_pocket/tunnel/cloudflare_client.dart';
import 'package:cloud_pocket/tunnel/localtunnel_client.dart';
import 'package:cloud_pocket/tunnel/smart_tunnel_engine.dart';
import 'package:cloud_pocket/tunnel/tunnel_client.dart';
import 'package:cloud_pocket/tunnel/tunnel_config.dart';
import 'package:cloud_pocket/tunnel/tunnel_health_monitor.dart';

class TunnelException implements Exception {
  final String message;
  final Map<TunnelProvider, String> failureDetails;

  TunnelException(this.message, [this.failureDetails = const {}]);

  @override
  String toString() => message;
}

class TunnelManager {
  final int localPort;
  final TunnelConfig config;
  final void Function(double progress, String status)? onStatusUpdate;
  final void Function(String newUrl, TunnelProvider provider, int latencyMs)? onTunnelChanged;

  TunnelClient? _activeClient;
  TunnelHealthMonitor? _healthMonitor;
  String? _currentPublicUrl;
  bool _isRunning = false;
  TunnelProvider? _activeProvider;
  int? _latencyMs;

  TunnelManager({
    required this.localPort,
    this.config = const TunnelConfig(),
    this.onStatusUpdate,
    this.onTunnelChanged,
  });

  String? get publicUrl => _currentPublicUrl ?? _activeClient?.publicUrl;
  bool get isRunning => _isRunning && (_activeClient?.isRunning ?? false);
  TunnelProvider? get activeProvider => _activeProvider ?? config.provider;
  int? get latencyMs => _latencyMs;

  Future<String?> startTunnel() async {
    _isRunning = true;
    try {
      if (config.provider == TunnelProvider.auto) {
        AppLogger().info('TUNNEL', 'Probing fastest tunnel providers...');
        onStatusUpdate?.call(0.1, 'Probing fastest tunnel providers...');
        final probes = await SmartTunnelEngine.probeAll();
        for (final p in probes) {
          AppLogger().debug('TUNNEL', 'Probe ${p.provider.displayName}: reachable=${p.reachable}, latency=${p.latencyMs}ms ${p.errorMessage ?? ""}');
        }
        final candidates = probes.where((p) => p.reachable).toList();
        if (candidates.isEmpty) {
          candidates.addAll(probes);
        }

        final failureDetails = <TunnelProvider, String>{};
        for (final candidate in candidates) {
          try {
            _activeProvider = candidate.provider;
            _latencyMs = candidate.latencyMs;
            AppLogger().info('TUNNEL', 'Auto mode connecting to ${_activeProvider!.displayName} (${candidate.latencyMs}ms)...');
            onStatusUpdate?.call(0.3, 'Connecting to ${_activeProvider!.displayName} (${candidate.latencyMs}ms)...');
            final client = _createClient(_activeProvider!);
            final url = await client.start().timeout(const Duration(seconds: 15));
            if (url.isNotEmpty) {
              _activeClient = client;
              _currentPublicUrl = url;
              AppLogger().info('TUNNEL', 'Auto mode established tunnel via ${_activeProvider!.displayName}: $url');
              break;
            } else {
              await client.stop();
            }
          } catch (e) {
            AppLogger().warn('TUNNEL', 'Candidate ${candidate.provider.displayName} failed: $e');
            failureDetails[candidate.provider] = e.toString();
          }
        }

        if (_currentPublicUrl == null) {
          AppLogger().error('TUNNEL', 'All tested auto providers failed: $failureDetails');
          throw TunnelException(
            'Unable to establish public tunnel. All tested providers failed.',
            failureDetails,
          );
        }
      } else {
        _activeProvider = config.provider;
        AppLogger().info('TUNNEL', 'Starting manual tunnel ${_activeProvider!.displayName} on local port $localPort');
        onStatusUpdate?.call(0.2, 'Starting ${config.provider.displayName}...');
        _activeClient = _createClient(_activeProvider!);
        try {
          _currentPublicUrl = await _activeClient!.start().timeout(const Duration(seconds: 20));
          AppLogger().info('TUNNEL', '${_activeProvider!.displayName} connected successfully: $_currentPublicUrl');
        } catch (initialErr) {
          AppLogger().error('TUNNEL', '${_activeProvider!.displayName} failed: $initialErr');
          rethrow;
        }
      }

      if (_currentPublicUrl != null && _currentPublicUrl!.isNotEmpty) {
        // Start health monitor for active tunnel
        _healthMonitor = TunnelHealthMonitor(
          tunnelUrl: _currentPublicUrl!,
          onUnhealthy: () async {
            AppLogger().warn('TUNNEL', 'Tunnel health check failed for $_currentPublicUrl');
            // Auto failover if running in Auto mode
            if (config.provider == TunnelProvider.auto && _isRunning) {
              await _handleAutoFailover();
            }
          },
        )..start();

        return _currentPublicUrl;
      }

      throw TunnelException('${_activeProvider!.displayName} returned no public URL', {
        _activeProvider!: 'Returned no public URL',
      });
    } catch (e) {
      _isRunning = false;
      await _activeClient?.stop();
      _activeClient = null;
      _currentPublicUrl = null;
      AppLogger().error('TUNNEL', 'startTunnel failed: $e');
      if (e is TunnelException) rethrow;
      throw TunnelException('${(_activeProvider ?? config.provider).displayName} failed:\n$e', {
        (_activeProvider ?? config.provider): e.toString(),
      });
    }
  }

  Future<void> _handleAutoFailover() async {
    if (!_isRunning) return;
    try {
      final oldClient = _activeClient;
      final oldProvider = _activeProvider;
      AppLogger().warn('TUNNEL', 'Auto failover triggered from ${oldProvider?.displayName ?? "unknown"}');
      _activeClient = null;
      _currentPublicUrl = null;
      await oldClient?.stop();
      if (!_isRunning) return;

      final probes = await SmartTunnelEngine.probeAll();
      final alternateCandidates = probes.where((p) => p.provider != oldProvider && p.reachable).toList();
      if (alternateCandidates.isEmpty) {
        alternateCandidates.addAll(probes.where((p) => p.provider != oldProvider));
      }

      for (final candidate in alternateCandidates) {
        if (!_isRunning) return;
        try {
          AppLogger().info('TUNNEL', 'Auto failover attempting ${candidate.provider.displayName}...');
          final client = _createClient(candidate.provider);
          final url = await client.start().timeout(const Duration(seconds: 15));
          if (url.isNotEmpty) {
            if (!_isRunning) {
              await client.stop();
              return;
            }
            _activeClient = client;
            _activeProvider = candidate.provider;
            _latencyMs = candidate.latencyMs;
            _currentPublicUrl = url;

            AppLogger().info('TUNNEL', 'Auto failover successfully switched to ${_activeProvider!.displayName}: $url');
            onTunnelChanged?.call(_currentPublicUrl!, _activeProvider!, _latencyMs ?? 0);

            _healthMonitor?.stop();
            _healthMonitor = TunnelHealthMonitor(
              tunnelUrl: _currentPublicUrl!,
              onUnhealthy: () async {
                if (config.provider == TunnelProvider.auto && _isRunning) {
                  await _handleAutoFailover();
                }
              },
            )..start();
            break;
          } else {
            await client.stop();
          }
        } catch (_) {}
      }

      if (_activeClient == null && _isRunning) {
        onTunnelChanged?.call('', oldProvider ?? config.provider, 0);
      }
    } catch (_) {}
  }

  TunnelClient _createClient(TunnelProvider provider) {
    switch (provider) {
      case TunnelProvider.auto:
      case TunnelProvider.cloudflareQuick:
      case TunnelProvider.cloudflareCustom:
        return CloudflareClient(
          localPort: localPort,
          config: config,
          onStatusUpdate: onStatusUpdate,
          onDisconnect: () {
            if (config.provider == TunnelProvider.auto && _isRunning) {
              _handleAutoFailover();
            }
          },
        );
      case TunnelProvider.bore:
      case TunnelProvider.customBore:
        return BoreClient(
          localPort: localPort,
          boreHost: config.relayHost,
          boreControlPort: config.relayPort,
          onStatusUpdate: onStatusUpdate,
          onDisconnect: () {
            if (config.provider == TunnelProvider.auto && _isRunning) {
              _handleAutoFailover();
            }
          },
        );
      case TunnelProvider.localtunnel:
        final bool isCustomLt = config.provider == TunnelProvider.localtunnel &&
            config.relayHost != 'bore.pub' &&
            config.relayHost.isNotEmpty;
        return LocaltunnelClient(
          localPort: localPort,
          relayHost: isCustomLt ? config.relayHost : 'loca.lt',
          preferredSubdomain: config.preferredSubdomain,
        );
    }
  }

  Future<void> stopTunnel() async {
    _isRunning = false;
    _healthMonitor?.stop();
    _healthMonitor = null;
    await _activeClient?.stop();
    _activeClient = null;
    _currentPublicUrl = null;
  }
}
