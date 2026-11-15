import 'dart:convert';
import 'dart:io';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:cloud_pocket/models/share_session.dart';
import 'package:cloud_pocket/providers/session_provider.dart';
import 'package:cloud_pocket/providers/settings_provider.dart';
import 'package:cloud_pocket/server/server_engine.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    HttpOverrides.global = null;
    SharedPreferences.setMockInitialValues({});
  });

  group('Sharing Defaults & Session Reactivity Tests', () {
    test('SessionNotifier initializes with SettingsState defaults', () async {
      final container = ProviderContainer();
      addTearDown(container.dispose);

      // Verify defaults
      final session = container.read(sessionProvider);
      final settings = container.read(settingsProvider);

      expect(session.expiryDuration, equals(settings.defaultExpiry));
      expect(session.enableTunnel, equals(settings.defaultEnableTunnel));
      expect(session.allowUploads, isFalse);
    });

    test('SessionNotifier reacts when SettingsState defaultExpiry or defaultEnableTunnel changes', () async {
      final container = ProviderContainer();
      addTearDown(container.dispose);

      // Update settings default expiry
      await container.read(settingsProvider.notifier).setDefaultExpiry(ExpiryDuration.hour24);
      expect(container.read(sessionProvider).expiryDuration, equals(ExpiryDuration.hour24));

      // Update settings default tunnel enable
      await container.read(settingsProvider.notifier).setDefaultEnableTunnel(false);
      expect(container.read(sessionProvider).enableTunnel, isFalse);
    });

    test('SessionNotifier preserves allowUploads in Send Mode when switching Receive Mode off', () {
      final container = ProviderContainer();
      addTearDown(container.dispose);

      final notifier = container.read(sessionProvider.notifier);

      // In Send Mode, set allowUploads to true
      notifier.setAllowUploads(true);
      expect(container.read(sessionProvider).allowUploads, isTrue);

      // Switch to Receive Mode
      notifier.setIsReceiveMode(true);
      expect(container.read(sessionProvider).isReceiveMode, isTrue);
      expect(container.read(sessionProvider).allowUploads, isTrue);

      // Switch back to Send Mode: allowUploads remains true
      notifier.setIsReceiveMode(false);
      expect(container.read(sessionProvider).isReceiveMode, isFalse);
      expect(container.read(sessionProvider).allowUploads, isTrue);
    });
  });

  group('ServerEngine Theme Sync & /api/device-info Tests', () {
    late Directory tempDir;

    setUp(() async {
      tempDir = await Directory.systemTemp.createTemp('cp_theme_test_');
    });

    tearDown(() async {
      if (await tempDir.exists()) {
        await tempDir.delete(recursive: true);
      }
    });

    test('ServerEngine initializes with themeMode and primaryColor in /api/device-info', () async {
      const session = ShareSession(
        items: [],
      );

      final engine = ServerEngine(
        session: session,
        uploadDir: tempDir.path,
        deviceName: 'Test Phone',
        themeMode: 'dark',
        primaryColor: '#6366F1',
      );

      final port = await engine.start(preferredPort: 0);
      addTearDown(() => engine.stop());

      final client = HttpClient();
      final req = await client.getUrl(Uri.parse('http://127.0.0.1:$port/api/device-info'));
      final res = await req.close();
      final body = await res.transform(utf8.decoder).join();
      final json = jsonDecode(body) as Map<String, dynamic>;

      expect(res.statusCode, equals(200));
      expect(json['deviceName'], equals('Test Phone'));
      expect(json['themeMode'], equals('dark'));
      expect(json['primaryColor'], equals('#6366F1'));
    });

    test('ServerEngine updateTheme changes values and broadcasts theme_changed', () async {
      const session = ShareSession(
        items: [],
      );

      final engine = ServerEngine(
        session: session,
        uploadDir: tempDir.path,
        deviceName: 'Test Phone',
        themeMode: 'dark',
        primaryColor: '#1B8A6B',
      );

      final port = await engine.start(preferredPort: 0);
      addTearDown(() => engine.stop());

      // Update theme
      engine.updateTheme(themeMode: 'light', primaryColor: '#DC2626');
      expect(engine.themeMode, equals('light'));
      expect(engine.primaryColor, equals('#DC2626'));

      // Check /api/device-info reflects new theme
      final client = HttpClient();
      final req = await client.getUrl(Uri.parse('http://127.0.0.1:$port/api/device-info'));
      final res = await req.close();
      final body = await res.transform(utf8.decoder).join();
      final json = jsonDecode(body) as Map<String, dynamic>;

      expect(json['themeMode'], equals('light'));
      expect(json['primaryColor'], equals('#DC2626'));
    });
  });
}
