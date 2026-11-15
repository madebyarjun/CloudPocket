abstract class TunnelClient {
  /// Starts the tunnel and returns the publicly accessible URL.
  Future<String> start();

  /// Gracefully stops the tunnel and cleans up all resources.
  Future<void> stop();

  /// Returns the current public URL if active, or null if stopped.
  String? get publicUrl;

  /// Returns whether the tunnel is actively running and ready to handle traffic.
  bool get isRunning;
}
