import 'package:flutter_test/flutter_test.dart';
import 'package:cloud_pocket/tunnel/tunnel_config.dart';

void main() {
  group('TunnelConfig Tests', () {
    test('default configuration is Cloudflare Quick', () {
      const config = TunnelConfig();
      expect(config.provider, equals(TunnelProvider.cloudflareQuick));
      expect(config.isCloudflare, isTrue);
    });

    test('Cloudflare Quick provider identification', () {
      const config = TunnelConfig(provider: TunnelProvider.cloudflareQuick);
      expect(config.isCloudflare, isTrue);
      expect(config.provider.displayName, contains('Cloudflare Quick'));
    });

    test('Cloudflare Custom provider copyWith and JSON roundtrip', () {
      final config = const TunnelConfig().copyWith(
        provider: TunnelProvider.cloudflareCustom,
        cloudflareApiToken: 'test_token_123',
        cloudflareAccountId: 'acc_456',
        cloudflareZoneId: 'zone_789',
        cloudflareDomain: 'pocket.example.com',
        cloudflareTunnelId: 'tun_abc',
        cloudflareTunnelToken: 'token_xyz',
      );

      expect(config.isCloudflare, isTrue);
      expect(config.cloudflareDomain, equals('pocket.example.com'));

      final json = config.toJson();
      expect(json['provider'], equals('cloudflareCustom'));
      expect(json['cloudflareApiToken'], equals('test_token_123'));
      expect(json['cloudflareDomain'], equals('pocket.example.com'));

      final restored = TunnelConfig.fromJson(json);
      expect(restored.provider, equals(TunnelProvider.cloudflareCustom));
      expect(restored.cloudflareApiToken, equals('test_token_123'));
      expect(restored.cloudflareDomain, equals('pocket.example.com'));
      expect(restored.cloudflareTunnelToken, equals('token_xyz'));
    });

    test('TunnelProvider displayNames do not contain emojis', () {
      for (final provider in TunnelProvider.values) {
        expect(provider.displayName, isNot(contains('⚡')));
        expect(provider.displayName, isNot(contains('🔒')));
        expect(provider.displayName, isNot(contains('🌐')));
        expect(provider.displayName, isNot(contains('🚀')));
        expect(provider.displayName, isNot(contains('🔗')));
      }
    });

    test('defaultProviderForPlatform returns cloudflareQuick and is supported', () {
      final provider = TunnelConfig.defaultProviderForPlatform;
      expect(provider, equals(TunnelProvider.cloudflareQuick));
      expect(TunnelConfig.isProviderSupported(provider), isTrue);
    });
  });
}
