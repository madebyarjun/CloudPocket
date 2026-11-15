import 'dart:io';

enum TunnelProvider {
  auto,
  cloudflareQuick,
  cloudflareCustom,
  bore,
  customBore,
  localtunnel;

  String get displayName {
    switch (this) {
      case TunnelProvider.auto:
        return 'Auto (Recommended)';
      case TunnelProvider.cloudflareQuick:
        return 'Cloudflare Quick (trycloudflare.com)';
      case TunnelProvider.cloudflareCustom:
        return 'Cloudflare Custom Domain';
      case TunnelProvider.bore:
        return 'Bore (Public bore.pub)';
      case TunnelProvider.customBore:
        return 'Custom Self-Hosted Relay (Your VPS)';
      case TunnelProvider.localtunnel:
        return 'LocalTunnel (loca.lt)';
    }
  }

  String get description {
    switch (this) {
      case TunnelProvider.auto:
        return 'Automatically tests and selects the fastest available tunnel';
      case TunnelProvider.cloudflareQuick:
        return 'Fastest: Instant HTTPS via Cloudflare edge with zero account needed';
      case TunnelProvider.cloudflareCustom:
        return 'Persistent custom domain on your Cloudflare account';
      case TunnelProvider.bore:
        return 'Zero-setup TCP reverse proxy over public bore.pub (Plaintext HTTP - Unencrypted)';
      case TunnelProvider.customBore:
        return 'Full unmetered gigabit speed through your own private Bore VPS (Plaintext HTTP - Unencrypted)';
      case TunnelProvider.localtunnel:
        return 'HTTP reverse proxy over loca.lt';
    }
  }

  /// Whether the tunnel provider provides TLS/HTTPS transport encryption
  bool get isEncryptedTransport {
    switch (this) {
      case TunnelProvider.auto:
      case TunnelProvider.cloudflareQuick:
      case TunnelProvider.cloudflareCustom:
      case TunnelProvider.localtunnel:
        return true;
      case TunnelProvider.bore:
      case TunnelProvider.customBore:
        return false;
    }
  }

  bool get requiresDesktopBinary => false;
}

class TunnelConfig {
  static TunnelProvider get defaultProviderForPlatform =>
      Platform.isIOS ? TunnelProvider.localtunnel : TunnelProvider.cloudflareQuick;

  static bool isProviderSupported(TunnelProvider provider) {
    if (Platform.isIOS) {
      // iOS strictly forbids running external subprocesses (App Store Review Guideline 2.5.2)
      return provider == TunnelProvider.localtunnel ||
          provider == TunnelProvider.bore ||
          provider == TunnelProvider.customBore;
    }
    return true;
  }
  final TunnelProvider provider;
  final String relayHost;
  final int relayPort;
  final String? preferredSubdomain;

  // Cloudflare-specific settings
  final String? cloudflareApiToken;
  final String? cloudflareAccountId;
  final String? cloudflareZoneId;
  final String? cloudflareDomain;
  final String? cloudflareTunnelId;
  final String? cloudflareTunnelToken;

  const TunnelConfig({
    this.provider = TunnelProvider.cloudflareQuick,
    this.relayHost = 'bore.pub',
    this.relayPort = 7835,
    this.preferredSubdomain,
    this.cloudflareApiToken,
    this.cloudflareAccountId,
    this.cloudflareZoneId,
    this.cloudflareDomain,
    this.cloudflareTunnelId,
    this.cloudflareTunnelToken,
  });

  bool get isCloudflare =>
      provider == TunnelProvider.cloudflareQuick || provider == TunnelProvider.cloudflareCustom;

  TunnelConfig copyWith({
    TunnelProvider? provider,
    String? relayHost,
    int? relayPort,
    String? preferredSubdomain,
    String? cloudflareApiToken,
    String? cloudflareAccountId,
    String? cloudflareZoneId,
    String? cloudflareDomain,
    String? cloudflareTunnelId,
    String? cloudflareTunnelToken,
  }) {
    return TunnelConfig(
      provider: provider ?? this.provider,
      relayHost: relayHost ?? this.relayHost,
      relayPort: relayPort ?? this.relayPort,
      preferredSubdomain: preferredSubdomain ?? this.preferredSubdomain,
      cloudflareApiToken: cloudflareApiToken ?? this.cloudflareApiToken,
      cloudflareAccountId: cloudflareAccountId ?? this.cloudflareAccountId,
      cloudflareZoneId: cloudflareZoneId ?? this.cloudflareZoneId,
      cloudflareDomain: cloudflareDomain ?? this.cloudflareDomain,
      cloudflareTunnelId: cloudflareTunnelId ?? this.cloudflareTunnelId,
      cloudflareTunnelToken: cloudflareTunnelToken ?? this.cloudflareTunnelToken,
    );
  }

  Map<String, dynamic> toJson() => {
        'provider': provider.name,
        'relayHost': relayHost,
        'relayPort': relayPort,
        if (preferredSubdomain != null) 'preferredSubdomain': preferredSubdomain,
        if (cloudflareApiToken != null) 'cloudflareApiToken': cloudflareApiToken,
        if (cloudflareAccountId != null) 'cloudflareAccountId': cloudflareAccountId,
        if (cloudflareZoneId != null) 'cloudflareZoneId': cloudflareZoneId,
        if (cloudflareDomain != null) 'cloudflareDomain': cloudflareDomain,
        if (cloudflareTunnelId != null) 'cloudflareTunnelId': cloudflareTunnelId,
        if (cloudflareTunnelToken != null) 'cloudflareTunnelToken': cloudflareTunnelToken,
      };

  factory TunnelConfig.fromJson(Map<String, dynamic> json) {
    return TunnelConfig(
      provider: TunnelProvider.values.firstWhere(
        (p) => p.name == json['provider'],
        orElse: () => TunnelProvider.cloudflareQuick,
      ),
      relayHost: json['relayHost'] as String? ?? 'bore.pub',
      relayPort: json['relayPort'] as int? ?? 7835,
      preferredSubdomain: json['preferredSubdomain'] as String?,
      cloudflareApiToken: json['cloudflareApiToken'] as String?,
      cloudflareAccountId: json['cloudflareAccountId'] as String?,
      cloudflareZoneId: json['cloudflareZoneId'] as String?,
      cloudflareDomain: json['cloudflareDomain'] as String?,
      cloudflareTunnelId: json['cloudflareTunnelId'] as String?,
      cloudflareTunnelToken: json['cloudflareTunnelToken'] as String?,
    );
  }
}
