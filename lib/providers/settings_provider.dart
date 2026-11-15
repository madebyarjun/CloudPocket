import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:cloud_pocket/models/share_session.dart';
import 'package:cloud_pocket/tunnel/tunnel_config.dart';

class SettingsState {
  final String deviceName;
  final TunnelProvider defaultProvider;
  final ExpiryDuration defaultExpiry;
  final ThemeMode themeMode;
  final int primaryColorValue;
  final bool isFirstLaunch;
  final bool defaultEnableTunnel;
  final bool keepRunning;
  final String? customUploadDirectory;

  // Cloudflare Custom Domain settings
  final String? cloudflareApiToken;
  final String? cloudflareAccountId;
  final String? cloudflareZoneId;
  final String? cloudflareDomain;
  final String? cloudflareTunnelId;
  final String? cloudflareTunnelToken;

  // Custom Bore VPS settings
  final String? customBoreHost;
  final int customBorePort;

  // LocalTunnel custom subdomain
  final String? customLocalTunnelSubdomain;

  const SettingsState({
    this.deviceName = "My Phone",
    this.defaultProvider = TunnelProvider.cloudflareQuick,
    this.defaultExpiry = ExpiryDuration.hour6,
    this.themeMode = ThemeMode.dark,
    this.primaryColorValue = 0xFF475569,
    this.isFirstLaunch = false,
    this.defaultEnableTunnel = true,
    this.keepRunning = true,
    this.customUploadDirectory,
    this.cloudflareApiToken,
    this.cloudflareAccountId,
    this.cloudflareZoneId,
    this.cloudflareDomain,
    this.cloudflareTunnelId,
    this.cloudflareTunnelToken,
    this.customBoreHost,
    this.customBorePort = 7835,
    this.customLocalTunnelSubdomain,
  });

  bool get isCloudflareConfigured =>
      cloudflareTunnelToken != null &&
      cloudflareTunnelToken!.isNotEmpty &&
      cloudflareDomain != null &&
      cloudflareDomain!.isNotEmpty;

  SettingsState copyWith({
    String? deviceName,
    TunnelProvider? defaultProvider,
    ExpiryDuration? defaultExpiry,
    ThemeMode? themeMode,
    int? primaryColorValue,
    bool? isFirstLaunch,
    bool? defaultEnableTunnel,
    bool? keepRunning,
    String? customUploadDirectory,
    bool clearCustomUploadDirectory = false,
    String? cloudflareApiToken,
    String? cloudflareAccountId,
    String? cloudflareZoneId,
    String? cloudflareDomain,
    String? cloudflareTunnelId,
    String? cloudflareTunnelToken,
    bool clearCloudflare = false,
    bool clearCustomBoreHost = false,
    bool clearCustomLocalTunnelSubdomain = false,
    String? customBoreHost,
    int? customBorePort,
    String? customLocalTunnelSubdomain,
  }) {
    return SettingsState(
      deviceName: deviceName ?? this.deviceName,
      defaultProvider: defaultProvider ?? this.defaultProvider,
      defaultExpiry: defaultExpiry ?? this.defaultExpiry,
      themeMode: themeMode ?? this.themeMode,
      primaryColorValue: primaryColorValue ?? this.primaryColorValue,
      isFirstLaunch: isFirstLaunch ?? this.isFirstLaunch,
      defaultEnableTunnel: defaultEnableTunnel ?? this.defaultEnableTunnel,
      keepRunning: keepRunning ?? this.keepRunning,
      customUploadDirectory: clearCustomUploadDirectory
          ? null
          : (customUploadDirectory ?? this.customUploadDirectory),
      cloudflareApiToken: clearCloudflare ? null : (cloudflareApiToken ?? this.cloudflareApiToken),
      cloudflareAccountId: clearCloudflare ? null : (cloudflareAccountId ?? this.cloudflareAccountId),
      cloudflareZoneId: clearCloudflare ? null : (cloudflareZoneId ?? this.cloudflareZoneId),
      cloudflareDomain: clearCloudflare ? null : (cloudflareDomain ?? this.cloudflareDomain),
      cloudflareTunnelId: clearCloudflare ? null : (cloudflareTunnelId ?? this.cloudflareTunnelId),
      cloudflareTunnelToken: clearCloudflare ? null : (cloudflareTunnelToken ?? this.cloudflareTunnelToken),
      customBoreHost: clearCustomBoreHost ? null : (customBoreHost ?? this.customBoreHost),
      customBorePort: customBorePort ?? this.customBorePort,
      customLocalTunnelSubdomain: clearCustomLocalTunnelSubdomain
          ? null
          : (customLocalTunnelSubdomain ?? this.customLocalTunnelSubdomain),
    );
  }
}

class SettingsNotifier extends Notifier<SettingsState> {
  static const _kDeviceNameKey = 'cp_setting_device_name';
  static const _kDefaultProviderKey = 'cp_setting_default_provider';
  static const _kDefaultExpiryKey = 'cp_setting_default_expiry';
  static const _kFirstLaunchKey = 'cp_setting_is_first_launch';
  static const _kDefaultEnableTunnelKey = 'cp_setting_default_enable_tunnel';
  static const _kKeepRunningKey = 'cp_setting_keep_running';
  static const _kCustomUploadDirKey = 'cp_setting_custom_upload_dir';

  // Cloudflare Keys
  static const _kCfTokenKey = 'cp_setting_cf_token';
  static const _kCfAccountIdKey = 'cp_setting_cf_account_id';
  static const _kCfZoneIdKey = 'cp_setting_cf_zone_id';
  static const _kCfDomainKey = 'cp_setting_cf_domain';
  static const _kCfTunnelIdKey = 'cp_setting_cf_tunnel_id';
  static const _kCfTunnelTokenKey = 'cp_setting_cf_tunnel_token';

  // Bore Keys
  static const _kBoreHostKey = 'cp_setting_bore_host';
  static const _kBorePortKey = 'cp_setting_bore_port';

  // LocalTunnel Key
  static const _kLtSubdomainKey = 'cp_setting_lt_subdomain';

  // Theme Keys
  static const _kThemeModeKey = 'cp_setting_theme_mode';
  static const _kPrimaryColorKey = 'cp_setting_primary_color';

  static const _secureStorage = FlutterSecureStorage(
    aOptions: AndroidOptions(encryptedSharedPreferences: true),
  );

  @override
  SettingsState build() {
    _loadSettings();
    return const SettingsState();
  }

  Future<void> _loadSettings() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final deviceName = prefs.getString(_kDeviceNameKey) ?? "My Phone";
      final providerStr = prefs.getString(_kDefaultProviderKey);
      final expiryStr = prefs.getString(_kDefaultExpiryKey);
      final hasLaunched = prefs.getBool(_kFirstLaunchKey) ?? false;
      final defaultEnableTunnel = prefs.getBool(_kDefaultEnableTunnelKey) ?? true;
      final keepRunning = prefs.getBool(_kKeepRunningKey) ?? true;
      final customUploadDir = prefs.getString(_kCustomUploadDirKey);

      final provider = providerStr != null
          ? TunnelProvider.values.firstWhere(
              (p) => p.name == providerStr,
              orElse: () => TunnelProvider.cloudflareQuick,
            )
          : TunnelProvider.cloudflareQuick;

      final expiry = expiryStr != null
          ? ExpiryDuration.values.firstWhere(
              (e) => e.name == expiryStr,
              orElse: () => ExpiryDuration.hour6,
            )
          : ExpiryDuration.hour6;

      // Load tunnel configs: secrets from secure storage with migration fallback
      String? cfToken;
      String? cfTunnelToken;
      try {
        cfToken = await _secureStorage.read(key: _kCfTokenKey);
        cfTunnelToken = await _secureStorage.read(key: _kCfTunnelTokenKey);
      } catch (_) {}

      if (cfToken == null || cfToken.isEmpty) {
        cfToken = prefs.getString(_kCfTokenKey);
        if (cfToken != null && cfToken.isNotEmpty) {
          try {
            await _secureStorage.write(key: _kCfTokenKey, value: cfToken);
            await prefs.remove(_kCfTokenKey);
          } catch (_) {}
        }
      }

      if (cfTunnelToken == null || cfTunnelToken.isEmpty) {
        cfTunnelToken = prefs.getString(_kCfTunnelTokenKey);
        if (cfTunnelToken != null && cfTunnelToken.isNotEmpty) {
          try {
            await _secureStorage.write(key: _kCfTunnelTokenKey, value: cfTunnelToken);
            await prefs.remove(_kCfTunnelTokenKey);
          } catch (_) {}
        }
      }

      final cfAccountId = prefs.getString(_kCfAccountIdKey);
      final cfZoneId = prefs.getString(_kCfZoneIdKey);
      final cfDomain = prefs.getString(_kCfDomainKey);
      final cfTunnelId = prefs.getString(_kCfTunnelIdKey);

      final boreHost = prefs.getString(_kBoreHostKey);
      final borePort = prefs.getInt(_kBorePortKey) ?? 7835;

      final ltSubdomain = prefs.getString(_kLtSubdomainKey);

      final themeModeStr = prefs.getString(_kThemeModeKey);
      final themeMode = themeModeStr != null
          ? ThemeMode.values.firstWhere(
              (m) => m.name == themeModeStr,
              orElse: () => ThemeMode.system,
            )
          : ThemeMode.system;

      final primaryColor = prefs.getInt(_kPrimaryColorKey) ?? 0xFF475569;

      state = state.copyWith(
        deviceName: deviceName,
        defaultProvider: provider,
        defaultExpiry: expiry,
        themeMode: themeMode,
        primaryColorValue: primaryColor,
        isFirstLaunch: !hasLaunched,
        defaultEnableTunnel: defaultEnableTunnel,
        keepRunning: keepRunning,
        customUploadDirectory: customUploadDir,
        cloudflareApiToken: cfToken,
        cloudflareAccountId: cfAccountId,
        cloudflareZoneId: cfZoneId,
        cloudflareDomain: cfDomain,
        cloudflareTunnelId: cfTunnelId,
        cloudflareTunnelToken: cfTunnelToken,
        customBoreHost: boreHost,
        customBorePort: borePort,
        customLocalTunnelSubdomain: ltSubdomain,
      );
    } catch (_) {}
  }

  Future<void> setDeviceName(String name) async {
    state = state.copyWith(deviceName: name);
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_kDeviceNameKey, name);
  }

  Future<void> setDefaultProvider(TunnelProvider provider) async {
    state = state.copyWith(defaultProvider: provider);
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_kDefaultProviderKey, provider.name);
  }

  Future<void> setDefaultExpiry(ExpiryDuration expiry) async {
    state = state.copyWith(defaultExpiry: expiry);
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_kDefaultExpiryKey, expiry.name);
  }

  Future<void> setDefaultEnableTunnel(bool enable) async {
    state = state.copyWith(defaultEnableTunnel: enable);
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_kDefaultEnableTunnelKey, enable);
  }

  Future<void> setKeepRunning(bool value) async {
    state = state.copyWith(keepRunning: value);
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_kKeepRunningKey, value);
  }

  Future<void> setCustomUploadDirectory(String? path) async {
    final prefs = await SharedPreferences.getInstance();
    if (path == null || path.trim().isEmpty) {
      state = state.copyWith(clearCustomUploadDirectory: true);
      await prefs.remove(_kCustomUploadDirKey);
    } else {
      state = state.copyWith(customUploadDirectory: path.trim());
      await prefs.setString(_kCustomUploadDirKey, path.trim());
    }
  }

  Future<void> completeOnboarding() async {
    state = state.copyWith(isFirstLaunch: false);
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_kFirstLaunchKey, true);
  }

  Future<void> setThemeMode(ThemeMode mode) async {
    state = state.copyWith(themeMode: mode);
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_kThemeModeKey, mode.name);
  }

  Future<void> setPrimaryColorValue(int colorValue) async {
    state = state.copyWith(primaryColorValue: colorValue);
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt(_kPrimaryColorKey, colorValue);
  }

  Future<void> saveCloudflareConfig(TunnelConfig config) async {
    state = state.copyWith(
      cloudflareApiToken: config.cloudflareApiToken,
      cloudflareAccountId: config.cloudflareAccountId,
      cloudflareZoneId: config.cloudflareZoneId,
      cloudflareDomain: config.cloudflareDomain,
      cloudflareTunnelId: config.cloudflareTunnelId,
      cloudflareTunnelToken: config.cloudflareTunnelToken,
    );

    // Save sensitive tokens to secure storage
    try {
      if (config.cloudflareApiToken != null) {
        await _secureStorage.write(key: _kCfTokenKey, value: config.cloudflareApiToken!);
      } else {
        await _secureStorage.delete(key: _kCfTokenKey);
      }
      if (config.cloudflareTunnelToken != null) {
        await _secureStorage.write(key: _kCfTunnelTokenKey, value: config.cloudflareTunnelToken!);
      } else {
        await _secureStorage.delete(key: _kCfTunnelTokenKey);
      }
    } catch (_) {}

    final prefs = await SharedPreferences.getInstance();
    // Non-sensitive IDs and domain to SharedPreferences
    if (config.cloudflareAccountId != null) {
      await prefs.setString(_kCfAccountIdKey, config.cloudflareAccountId!);
    }
    if (config.cloudflareZoneId != null) {
      await prefs.setString(_kCfZoneIdKey, config.cloudflareZoneId!);
    }
    if (config.cloudflareDomain != null) {
      await prefs.setString(_kCfDomainKey, config.cloudflareDomain!);
    }
    if (config.cloudflareTunnelId != null) {
      await prefs.setString(_kCfTunnelIdKey, config.cloudflareTunnelId!);
    }
    // Remove plain text copies from SharedPreferences
    await prefs.remove(_kCfTokenKey);
    await prefs.remove(_kCfTunnelTokenKey);
  }

  Future<void> clearCloudflareConfig() async {
    state = state.copyWith(clearCloudflare: true);
    try {
      await _secureStorage.delete(key: _kCfTokenKey);
      await _secureStorage.delete(key: _kCfTunnelTokenKey);
    } catch (_) {}

    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_kCfTokenKey);
    await prefs.remove(_kCfAccountIdKey);
    await prefs.remove(_kCfZoneIdKey);
    await prefs.remove(_kCfDomainKey);
    await prefs.remove(_kCfTunnelIdKey);
    await prefs.remove(_kCfTunnelTokenKey);
  }

  Future<void> saveCustomBoreConfig({required String? host, required int port}) async {
    final cleanHost = (host != null && host.trim().isNotEmpty) ? host.trim() : null;
    state = state.copyWith(
      customBoreHost: cleanHost,
      clearCustomBoreHost: cleanHost == null,
      customBorePort: port,
    );

    final prefs = await SharedPreferences.getInstance();
    if (cleanHost != null) {
      await prefs.setString(_kBoreHostKey, cleanHost);
    } else {
      await prefs.remove(_kBoreHostKey);
    }
    await prefs.setInt(_kBorePortKey, port);
  }

  Future<void> saveLocalTunnelSubdomain(String? subdomain) async {
    final clean = (subdomain != null && subdomain.trim().isNotEmpty)
        ? subdomain.trim().toLowerCase()
        : null;
    state = state.copyWith(
      customLocalTunnelSubdomain: clean,
      clearCustomLocalTunnelSubdomain: clean == null,
    );

    final prefs = await SharedPreferences.getInstance();
    if (clean != null) {
      await prefs.setString(_kLtSubdomainKey, clean);
    } else {
      await prefs.remove(_kLtSubdomainKey);
    }
  }
}

final settingsProvider = NotifierProvider<SettingsNotifier, SettingsState>(
  SettingsNotifier.new,
);
