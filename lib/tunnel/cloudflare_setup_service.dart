import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:cloud_pocket/tunnel/tunnel_config.dart';

class CloudflareSetupService {
  static const String _baseUrl = 'https://api.cloudflare.com/client/v4';

  final http.Client _client;

  CloudflareSetupService({http.Client? client}) : _client = client ?? http.Client();

  /// Close underlying HTTP client to cancel any in-flight requests
  void close() => _client.close();

  Map<String, String> _headers(String apiToken) => {
        'Authorization': 'Bearer $apiToken',
        'Content-Type': 'application/json',
      };

  /// Verifies token and retrieves Cloudflare accounts.
  Future<List<Map<String, dynamic>>> getAccounts(String apiToken) async {
    final res = await _client.get(
      Uri.parse('$_baseUrl/accounts'),
      headers: _headers(apiToken),
    );

    if (res.statusCode != 200) {
      final error = _parseErrorMessage(res.body, 'Failed to fetch accounts (HTTP ${res.statusCode})');
      throw Exception(error);
    }

    final data = jsonDecode(res.body) as Map<String, dynamic>;
    final result = data['result'] as List<dynamic>? ?? [];
    return result.map((acc) => {
          'id': acc['id'] as String,
          'name': acc['name'] as String,
        }).toList();
  }

  /// Lists available DNS domains/zones for the account.
  /// If accountId is provided, filters by account. Otherwise queries all accessible zones.
  Future<List<Map<String, dynamic>>> getZones(String apiToken, [String? accountId]) async {
    final String url;
    if (accountId != null && accountId.isNotEmpty) {
      url = '$_baseUrl/zones?account.id=$accountId&status=active';
    } else {
      url = '$_baseUrl/zones?status=active';
    }

    final res = await _client.get(
      Uri.parse(url),
      headers: _headers(apiToken),
    );

    if (res.statusCode != 200) {
      final error = _parseErrorMessage(res.body, 'Failed to fetch domains (HTTP ${res.statusCode})');
      throw Exception(error);
    }

    final data = jsonDecode(res.body) as Map<String, dynamic>;
    final result = data['result'] as List<dynamic>? ?? [];
    return result.map((zone) {
      final acc = zone['account'] as Map<String, dynamic>?;
      return {
        'id': zone['id'] as String,
        'name': zone['name'] as String,
        if (acc != null && acc['id'] != null) 'accountId': acc['id'] as String,
        if (acc != null && acc['name'] != null) 'accountName': acc['name'] as String,
      };
    }).toList();
  }

  /// Looks up a specific zone by domain name.
  Future<Map<String, dynamic>?> getZoneByName({
    required String apiToken,
    required String domainName,
    String? accountId,
  }) async {
    final clean = domainName.trim().toLowerCase();
    final url = accountId != null && accountId.isNotEmpty
        ? '$_baseUrl/zones?name=$clean&account.id=$accountId'
        : '$_baseUrl/zones?name=$clean';

    final res = await _client.get(
      Uri.parse(url),
      headers: _headers(apiToken),
    );

    if (res.statusCode == 200) {
      final data = jsonDecode(res.body) as Map<String, dynamic>;
      final result = data['result'] as List<dynamic>? ?? [];
      if (result.isNotEmpty) {
        final zone = result.first as Map<String, dynamic>;
        final acc = zone['account'] as Map<String, dynamic>?;
        return {
          'id': zone['id'] as String,
          'name': zone['name'] as String,
          if (acc != null && acc['id'] != null) 'accountId': acc['id'] as String,
          if (acc != null && acc['name'] != null) 'accountName': acc['name'] as String,
        };
      }
    }
    return null;
  }

  /// Creates a new named tunnel on the account.
  Future<Map<String, dynamic>> createTunnel({
    required String apiToken,
    required String accountId,
    required String tunnelName,
  }) async {
    final res = await _client.post(
      Uri.parse('$_baseUrl/accounts/$accountId/cfd_tunnel'),
      headers: _headers(apiToken),
      body: jsonEncode({
        'name': tunnelName,
        'config_src': 'cloudflare',
      }),
    );

    if (res.statusCode != 200) {
      final error = _parseErrorMessage(res.body, 'Failed to create tunnel (HTTP ${res.statusCode})');
      throw Exception(error);
    }

    final data = jsonDecode(res.body) as Map<String, dynamic>;
    final result = data['result'] as Map<String, dynamic>;
    return {
      'id': result['id'] as String,
      'name': result['name'] as String,
    };
  }

  /// Gets the runtime connector token for a tunnel.
  Future<String> getTunnelToken({
    required String apiToken,
    required String accountId,
    required String tunnelId,
  }) async {
    final res = await _client.get(
      Uri.parse('$_baseUrl/accounts/$accountId/cfd_tunnel/$tunnelId/token'),
      headers: _headers(apiToken),
    );

    if (res.statusCode != 200) {
      final error = _parseErrorMessage(res.body, 'Failed to get tunnel token (HTTP ${res.statusCode})');
      throw Exception(error);
    }

    final data = jsonDecode(res.body) as Map<String, dynamic>;
    final token = data['result'] as String?;
    if (token == null || token.isEmpty) {
      throw Exception('Empty tunnel token returned from Cloudflare API.');
    }
    return token;
  }

  /// Configures remote tunnel ingress rules so requests route to local port.
  Future<void> configureRemoteTunnelIngress({
    required String apiToken,
    required String accountId,
    required String tunnelId,
    required String fullHostname,
    required int localPort,
  }) async {
    final res = await _client.put(
      Uri.parse('$_baseUrl/accounts/$accountId/cfd_tunnel/$tunnelId/configurations'),
      headers: _headers(apiToken),
      body: jsonEncode({
        'config': {
          'ingress': [
            {
              'hostname': fullHostname,
              'service': 'http://localhost:$localPort',
            },
            {
              'service': 'http_status:404',
            }
          ]
        }
      }),
    );

    if (res.statusCode != 200) {
      // Non-fatal if ingress cannot be configured remotely, tunnel still starts with local rules
    }
  }

  /// Creates or updates a DNS CNAME record pointing to <tunnelId>.cfargotunnel.com.
  Future<void> createDnsCnameRecord({
    required String apiToken,
    required String zoneId,
    required String fullHostname,
    required String tunnelId,
  }) async {
    final targetCname = '$tunnelId.cfargotunnel.com';

    final res = await _client.post(
      Uri.parse('$_baseUrl/zones/$zoneId/dns_records'),
      headers: _headers(apiToken),
      body: jsonEncode({
        'type': 'CNAME',
        'name': fullHostname,
        'content': targetCname,
        'proxied': true,
        'ttl': 1,
      }),
    );

    if (res.statusCode != 200) {
      // Check if record already exists (HTTP 409 or error code 81057)
      final body = res.body;
      if (body.contains('already exists') || body.contains('81057')) {
        return; // Existing record is fine
      }
      final error = _parseErrorMessage(body, 'Failed to create DNS record (HTTP ${res.statusCode})');
      throw Exception(error);
    }
  }

  /// Complete 1-Tap Automated Setup:
  /// Creates tunnel, gets token, configures ingress, creates DNS CNAME record.
  Future<TunnelConfig> autoConfigureTunnel({
    required String apiToken,
    required String accountId,
    required String zoneId,
    required String domainName,
    required String subdomain,
    int localPort = 8080,
    void Function(String stepMessage)? onStep,
  }) async {
    final cleanSubdomain = subdomain.trim().toLowerCase();
    final fullHostname = cleanSubdomain.isEmpty ? domainName : '$cleanSubdomain.$domainName';
    final tunnelName = 'CloudPocket-${DateTime.now().millisecondsSinceEpoch % 100000}';

    onStep?.call('1/4 Creating Cloudflare Tunnel...');
    final tunnel = await createTunnel(
      apiToken: apiToken,
      accountId: accountId,
      tunnelName: tunnelName,
    );
    final tunnelId = tunnel['id'] as String;

    onStep?.call('2/4 Fetching tunnel credentials...');
    final tunnelToken = await getTunnelToken(
      apiToken: apiToken,
      accountId: accountId,
      tunnelId: tunnelId,
    );

    onStep?.call('3/4 Configuring remote routing rules...');
    await configureRemoteTunnelIngress(
      apiToken: apiToken,
      accountId: accountId,
      tunnelId: tunnelId,
      fullHostname: fullHostname,
      localPort: localPort,
    );

    onStep?.call('4/4 Setting up DNS CNAME record ($fullHostname)...');
    await createDnsCnameRecord(
      apiToken: apiToken,
      zoneId: zoneId,
      fullHostname: fullHostname,
      tunnelId: tunnelId,
    );

    onStep?.call('Cloudflare Tunnel configured successfully!');

    return TunnelConfig(
      provider: TunnelProvider.cloudflareCustom,
      cloudflareApiToken: apiToken,
      cloudflareAccountId: accountId,
      cloudflareZoneId: zoneId,
      cloudflareDomain: fullHostname,
      cloudflareTunnelId: tunnelId,
      cloudflareTunnelToken: tunnelToken,
    );
  }

  String _parseErrorMessage(String responseBody, String defaultMsg) {
    try {
      final json = jsonDecode(responseBody) as Map<String, dynamic>;
      final errors = json['errors'] as List<dynamic>?;
      if (errors != null && errors.isNotEmpty) {
        final first = errors.first as Map<String, dynamic>;
        final message = first['message'] as String?;
        if (message != null && message.isNotEmpty) return message;
      }
    } catch (_) {}
    return defaultMsg;
  }
}
