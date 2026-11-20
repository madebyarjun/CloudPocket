import 'package:material_ui/material_ui.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:cloud_pocket/providers/session_provider.dart';
import 'package:cloud_pocket/providers/settings_provider.dart';
import 'package:cloud_pocket/tunnel/cloudflare_setup_service.dart';
import 'package:cloud_pocket/tunnel/tunnel_config.dart';
import 'package:cloud_pocket/ui/theme.dart';
import 'package:cloud_pocket/ui/widgets/cp_sheet.dart';
import 'package:cloud_pocket/ui/widgets/tunnel_guide_dialog.dart';

class CloudflareSetupDialog extends ConsumerStatefulWidget {
  const CloudflareSetupDialog({super.key});

  static Future<void> show(BuildContext context) {
    return CpSheet.show(
      context: context,
      builder: (context) => const CloudflareSetupDialog(),
    );
  }

  @override
  ConsumerState<CloudflareSetupDialog> createState() => _CloudflareSetupDialogState();
}

class _CloudflareSetupDialogState extends ConsumerState<CloudflareSetupDialog> {
  final _tokenController = TextEditingController();
  final _accountIdController = TextEditingController();
  final _subdomainController = TextEditingController(text: 'pocket');
  final _setupService = CloudflareSetupService();

  bool _obscureToken = true;
  bool _isLoading = false;
  String? _statusMessage;
  String? _errorMessage;

  String? _selectedAccountId;
  List<Map<String, dynamic>> _zones = [];
  String? _selectedZoneId;
  String? _selectedZoneName;

  @override
  void initState() {
    super.initState();
    final settings = ref.read(settingsProvider);
    final sessionConfig = ref.read(sessionProvider).tunnelConfig;
    final token = settings.cloudflareApiToken ?? sessionConfig.cloudflareApiToken;
    final accountId = settings.cloudflareAccountId ?? sessionConfig.cloudflareAccountId;
    final zoneId = settings.cloudflareZoneId ?? sessionConfig.cloudflareZoneId;

    if (token != null) {
      _tokenController.text = token;
    }
    if (accountId != null) {
      _selectedAccountId = accountId;
      _accountIdController.text = accountId;
    }
    if (zoneId != null) {
      _selectedZoneId = zoneId;
    }
  }

  @override
  void dispose() {
    _setupService.close();
    _tokenController.dispose();
    _accountIdController.dispose();
    _subdomainController.dispose();
    super.dispose();
  }

  Future<void> _fetchAccountsAndZones() async {
    final token = _tokenController.text.trim();
    final manualAccountId = _accountIdController.text.trim().isNotEmpty
        ? _accountIdController.text.trim()
        : null;

    if (token.isEmpty) {
      if (mounted) setState(() => _errorMessage = 'Please enter your Cloudflare API Token.');
      return;
    }

    if (mounted) {
      setState(() {
        _isLoading = true;
        _errorMessage = null;
        _statusMessage = 'Connecting to Cloudflare...';
      });
    }

    try {
      List<Map<String, dynamic>> zones = [];
      String? accountId = manualAccountId ?? _selectedAccountId;

      try {
        zones = await _setupService.getZones(token, accountId);
      } catch (_) {}

      if (zones.isNotEmpty) {
        final zoneAccountId = zones.first['accountId'] as String?;
        if ((accountId == null || accountId.isEmpty) && zoneAccountId != null && zoneAccountId.isNotEmpty) {
          accountId = zoneAccountId;
          _accountIdController.text = zoneAccountId;
        }
      } else {
        try {
          final accounts = await _setupService.getAccounts(token);
          if (accounts.isNotEmpty) {
            accountId = accounts.first['id'] as String;
            _accountIdController.text = accountId;
            zones = await _setupService.getZones(token, accountId);
          }
        } catch (_) {}
      }

      if (zones.isEmpty) {
        throw Exception(
          'No active domains found. Ensure token permissions include Zone Read, DNS Edit, and Cloudflare Tunnel Edit.',
        );
      }

      if (mounted) {
        setState(() {
          _selectedAccountId = accountId;
          _zones = zones;
          _selectedZoneId = zones.first['id'] as String;
          _selectedZoneName = zones.first['name'] as String;
          _isLoading = false;
          _statusMessage = null;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _isLoading = false;
          _errorMessage = e.toString().replaceAll('Exception: ', '');
          _statusMessage = null;
        });
      }
    }
  }

  Future<void> _autoConfigureTunnel() async {
    final token = _tokenController.text.trim();
    final manualAccountId = _accountIdController.text.trim().isNotEmpty
        ? _accountIdController.text.trim()
        : null;
    final accountId = manualAccountId ?? _selectedAccountId;
    final zoneId = _selectedZoneId;
    final domainName = _selectedZoneName;
    final subdomain = _subdomainController.text.trim();

    if (token.isEmpty) {
      setState(() => _errorMessage = 'Please enter your Cloudflare API Token.');
      return;
    }
    if (accountId == null || accountId.isEmpty) {
      setState(() => _errorMessage = 'Account ID is required. Please enter your Account ID.');
      return;
    }
    if (zoneId == null || domainName == null) {
      setState(() => _errorMessage = 'Please select a domain first.');
      return;
    }

    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    try {
      final newConfig = await _setupService.autoConfigureTunnel(
        apiToken: token,
        accountId: accountId,
        zoneId: zoneId,
        domainName: domainName,
        subdomain: subdomain,
        localPort: 8080,
        onStep: (msg) {
          if (mounted) setState(() => _statusMessage = msg);
        },
      );

      await ref.read(settingsProvider.notifier).saveCloudflareConfig(newConfig);
      ref.read(sessionProvider.notifier).updateTunnelConfig(newConfig);
      ref.read(sessionProvider.notifier).setTunnelProvider(TunnelProvider.cloudflareCustom);

      if (mounted) {
        Navigator.pop(context);
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _isLoading = false;
          _errorMessage = e.toString().replaceAll('Exception: ', '');
          _statusMessage = null;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).extension<CloudPocketColors>() ?? CloudPocketColors.light;
    final hasToken = _tokenController.text.trim().isNotEmpty;

    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        CpHeader(
          icon: Icons.cloud_outlined,
          iconColor: Colors.white,
          iconBg: colors.orange,
          title: 'Cloudflare domain',
          description: 'Automate tunnel and DNS creation with your Cloudflare API token. No manual dashboard DNS setup needed.',
          helpLinkText: 'API token guide',
          onHelpTap: () => TunnelGuideDialog.show(context, initialTab: 0),
        ),
        CpFieldGroup(
          errorMessage: _errorMessage,
          fields: [
            CpFieldItem(
              controller: _tokenController,
              hint: 'API token',
              icon: Icons.vpn_key_outlined,
              iconColor: colors.orange,
              iconBg: colors.card,
              obscureText: _obscureToken,
              suffixWidth: 96,
              onChanged: (_) => setState(() {}),
              suffixIcon: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  IconButton(
                    iconSize: 18,
                    padding: EdgeInsets.zero,
                    constraints: const BoxConstraints(minWidth: 22, minHeight: 44),
                    icon: Icon(_obscureToken ? Icons.visibility_off : Icons.visibility, color: colors.label2),
                    onPressed: () => setState(() => _obscureToken = !_obscureToken),
                  ),
                  IconButton(
                    iconSize: 18,
                    padding: EdgeInsets.zero,
                    constraints: const BoxConstraints(minWidth: 22, minHeight: 44),
                    icon: Icon(Icons.paste_rounded, color: colors.label2),
                    onPressed: () async {
                      final data = await Clipboard.getData('text/plain');
                      final text = data?.text?.trim();
                      if (text != null && text.isNotEmpty) {
                        setState(() {
                          _tokenController.text = text;
                          _errorMessage = null;
                        });
                      }
                    },
                  ),
                ],
              ),
            ),
            CpFieldItem(
              controller: _accountIdController,
              hint: 'Account ID (optional)',
              helperText: 'Found on Cloudflare dashboard overview or URL',
              icon: Icons.badge_outlined,
              iconColor: colors.orange,
              iconBg: colors.card,
              onChanged: (val) {
                _selectedAccountId = val.trim().isNotEmpty ? val.trim() : null;
              },
              suffixIcon: IconButton(
                iconSize: 18,
                padding: EdgeInsets.zero,
                icon: Icon(Icons.paste_rounded, color: colors.label2),
                onPressed: () async {
                  final data = await Clipboard.getData('text/plain');
                  final text = data?.text?.trim();
                  if (text != null && text.isNotEmpty) {
                    setState(() {
                      _accountIdController.text = text;
                      _selectedAccountId = text;
                    });
                  }
                },
              ),
            ),
          ],
        ),

        // Animated domain selection and subdomain field
        AnimatedSize(
          duration: const Duration(milliseconds: 500),
          curve: cpMotionCurve,
          child: _zones.isNotEmpty
              ? Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    const SizedBox(height: 16),
                    Text(
                      'Domains',
                      style: TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w500,
                        color: colors.label2,
                        fontFamilyFallback: CloudPocketTheme.fontFallbacks,
                      ),
                    ),
                    const SizedBox(height: 6),
                    Container(
                      decoration: BoxDecoration(
                        color: colors.fill,
                        borderRadius: BorderRadius.circular(16),
                      ),
                      clipBehavior: Clip.antiAlias,
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          for (var i = 0; i < _zones.length; i++) ...[
                            if (i > 0)
                              Divider(
                                height: 0.5,
                                thickness: 0.5,
                                color: colors.sep,
                                indent: 44,
                              ),
                            _buildDomainRow(_zones[i], colors),
                          ],
                        ],
                      ),
                    ),
                    const SizedBox(height: 12),
                    CpFieldGroup(
                      fields: [
                        CpFieldItem(
                          controller: _subdomainController,
                          hint: 'Subdomain (e.g. pocket)',
                          helperText: _selectedZoneName != null
                              ? 'Result: ${_subdomainController.text.trim()}.${_selectedZoneName!}'
                              : null,
                          icon: Icons.link_rounded,
                          iconColor: colors.orange,
                          iconBg: colors.card,
                          onChanged: (_) => setState(() {}),
                        ),
                      ],
                    ),
                  ],
                )
              : const SizedBox.shrink(),
        ),

        if (_statusMessage != null) ...[
          const SizedBox(height: 12),
          Row(
            children: [
              if (_isLoading) ...[
                SizedBox(
                  width: 14,
                  height: 14,
                  child: CircularProgressIndicator(strokeWidth: 2, valueColor: AlwaysStoppedAnimation(colors.blue)),
                ),
                const SizedBox(width: 8),
              ],
              Expanded(
                child: Text(
                  _statusMessage!,
                  style: TextStyle(
                    fontSize: 13,
                    color: _isLoading ? colors.blue : colors.green,
                    fontWeight: FontWeight.w500,
                    fontFamilyFallback: CloudPocketTheme.fontFallbacks,
                  ),
                ),
              ),
            ],
          ),
        ],

        const SizedBox(height: 20),

        if (_zones.isEmpty)
          CpButton(
            text: 'Fetch domains',
            isLoading: _isLoading,
            onPressed: (hasToken && !_isLoading) ? _fetchAccountsAndZones : null,
          )
        else
          CpButton(
            text: 'Save domain',
            isLoading: _isLoading,
            onPressed: (!_isLoading && _selectedZoneId != null) ? _autoConfigureTunnel : null,
          ),
      ],
    );
  }

  Widget _buildDomainRow(Map<String, dynamic> zone, CloudPocketColors colors) {
    final id = zone['id'] as String;
    final name = zone['name'] as String;
    final isSelected = _selectedZoneId == id;

    return InkWell(
      onTap: () {
        setState(() {
          _selectedZoneId = id;
          _selectedZoneName = name;
        });
      },
      child: Container(
        height: 52,
        padding: const EdgeInsets.symmetric(horizontal: 14),
        child: Row(
          children: [
            Icon(Icons.language_rounded, size: 20, color: isSelected ? colors.orange : colors.label2),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                name,
                style: TextStyle(
                  fontSize: 15,
                  fontWeight: isSelected ? FontWeight.w600 : FontWeight.w400,
                  color: colors.label,
                  fontFamilyFallback: CloudPocketTheme.fontFallbacks,
                ),
              ),
            ),
            if (isSelected)
              Icon(Icons.check_rounded, color: colors.blue, size: 20),
          ],
        ),
      ),
    );
  }
}
