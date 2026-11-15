import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:cloud_pocket/tunnel/cloudflare_setup_service.dart';
import 'package:cloud_pocket/tunnel/tunnel_config.dart';

void main() {
  group('CloudflareSetupService Tests', () {
    test('getAccounts returns list of account mappings', () async {
      final mockClient = MockClient((request) async {
        expect(request.url.path, equals('/client/v4/accounts'));
        expect(request.headers['Authorization'], equals('Bearer valid_token'));
        return http.Response(
          jsonEncode({
            'success': true,
            'result': [
              {'id': 'acc_123', 'name': 'My Main Account'}
            ]
          }),
          200,
        );
      });

      final service = CloudflareSetupService(client: mockClient);
      final accounts = await service.getAccounts('valid_token');

      expect(accounts.length, equals(1));
      expect(accounts.first['id'], equals('acc_123'));
      expect(accounts.first['name'], equals('My Main Account'));
    });

    test('getZones returns active domains', () async {
      final mockClient = MockClient((request) async {
        expect(request.url.path, equals('/client/v4/zones'));
        return http.Response(
          jsonEncode({
            'success': true,
            'result': [
              {'id': 'zone_999', 'name': 'example.com'}
            ]
          }),
          200,
        );
      });

      final service = CloudflareSetupService(client: mockClient);
      final zones = await service.getZones('valid_token', 'acc_123');

      expect(zones.length, equals(1));
      expect(zones.first['id'], equals('zone_999'));
      expect(zones.first['name'], equals('example.com'));
    });

    test('autoConfigureTunnel performs all 4 steps and returns valid TunnelConfig', () async {
      final mockClient = MockClient((request) async {
        final path = request.url.path;
        if (path == '/client/v4/accounts/acc_1/cfd_tunnel') {
          return http.Response(
            jsonEncode({
              'success': true,
              'result': {'id': 'tunnel_abc', 'name': 'CloudPocket-123'}
            }),
            200,
          );
        } else if (path == '/client/v4/accounts/acc_1/cfd_tunnel/tunnel_abc/token') {
          return http.Response(
            jsonEncode({
              'success': true,
              'result': 'eyJhIjoiYWNjXzEiLCJ0IjoidHVubmVsX2FiYyJ9'
            }),
            200,
          );
        } else if (path == '/client/v4/accounts/acc_1/cfd_tunnel/tunnel_abc/configurations') {
          return http.Response(jsonEncode({'success': true}), 200);
        } else if (path == '/client/v4/zones/zone_1/dns_records') {
          return http.Response(jsonEncode({'success': true}), 200);
        }
        return http.Response('Not Found', 404);
      });

      final service = CloudflareSetupService(client: mockClient);
      final steps = <String>[];

      final config = await service.autoConfigureTunnel(
        apiToken: 'test_token',
        accountId: 'acc_1',
        zoneId: 'zone_1',
        domainName: 'example.com',
        subdomain: 'pocket',
        onStep: (step) => steps.add(step),
      );

      expect(steps.length, greaterThanOrEqualTo(4));
      expect(config.provider, equals(TunnelProvider.cloudflareCustom));
      expect(config.cloudflareDomain, equals('pocket.example.com'));
      expect(config.cloudflareTunnelId, equals('tunnel_abc'));
      expect(config.cloudflareTunnelToken, equals('eyJhIjoiYWNjXzEiLCJ0IjoidHVubmVsX2FiYyJ9'));
    });
  });
}
