import 'package:material_ui/material_ui.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:cloud_pocket/providers/settings_provider.dart';
import 'package:cloud_pocket/providers/session_provider.dart';
import 'package:cloud_pocket/tunnel/tunnel_config.dart';
import 'package:cloud_pocket/ui/theme.dart';
import 'package:cloud_pocket/ui/widgets/cp_sheet.dart';
import 'package:cloud_pocket/ui/widgets/tunnel_guide_dialog.dart';

class CustomBoreDialog extends ConsumerStatefulWidget {
  const CustomBoreDialog({super.key});

  static Future<void> show(BuildContext context) {
    return CpSheet.show(
      context: context,
      builder: (context) => const CustomBoreDialog(),
    );
  }

  @override
  ConsumerState<CustomBoreDialog> createState() => _CustomBoreDialogState();
}

class _CustomBoreDialogState extends ConsumerState<CustomBoreDialog> {
  final _hostController = TextEditingController();
  final _portController = TextEditingController(text: '7835');
  String? _errorMessage;

  @override
  void initState() {
    super.initState();
    final settings = ref.read(settingsProvider);
    if (settings.customBoreHost != null) {
      _hostController.text = settings.customBoreHost!;
    }
    _portController.text = settings.customBorePort.toString();
  }

  @override
  void dispose() {
    _hostController.dispose();
    _portController.dispose();
    super.dispose();
  }

  void _save() {
    final host = _hostController.text.trim();
    final portStr = _portController.text.trim();
    final port = int.tryParse(portStr);

    if (host.isEmpty) {
      setState(() => _errorMessage = 'Please enter a VPS Host or IP address.');
      return;
    }
    if (port == null || port <= 0 || port > 65535) {
      setState(() => _errorMessage = 'Please enter a valid port number (1-65535).');
      return;
    }

    setState(() => _errorMessage = null);
    ref.read(settingsProvider.notifier).saveCustomBoreConfig(host: host, port: port);
    ref.read(sessionProvider.notifier).setTunnelProvider(TunnelProvider.customBore);
    Navigator.pop(context);
  }

  void _reset() {
    setState(() => _errorMessage = null);
    ref.read(settingsProvider.notifier).saveCustomBoreConfig(host: null, port: 7835);
    Navigator.pop(context);
  }

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).extension<CloudPocketColors>() ?? CloudPocketColors.light;

    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        CpHeader(
          icon: Icons.dns_rounded,
          iconColor: Colors.white,
          iconBg: colors.blue,
          title: 'Bore relay',
          description: 'Route transfers through your own private cloud VPS for unmetered gigabit speeds.',
          helpLinkText: 'VPS setup guide',
          onHelpTap: () => TunnelGuideDialog.show(context, initialTab: 1),
        ),
        CpFieldGroup(
          errorMessage: _errorMessage,
          fields: [
            CpFieldItem(
              controller: _hostController,
              hint: 'Hostname or IP',
              icon: Icons.computer_rounded,
              iconColor: colors.blue,
              iconBg: colors.card,
              onChanged: (_) {
                if (_errorMessage != null) setState(() => _errorMessage = null);
              },
            ),
            CpFieldItem(
              controller: _portController,
              hint: 'Control port',
              helperText: 'Default Bore relay port is 7835',
              icon: Icons.tag_rounded,
              iconColor: colors.blue,
              iconBg: colors.card,
              keyboardType: TextInputType.number,
              onChanged: (_) {
                if (_errorMessage != null) setState(() => _errorMessage = null);
              },
            ),
          ],
        ),
        const SizedBox(height: 20),
        CpButton(
          text: 'Save relay',
          onPressed: _save,
        ),
        const SizedBox(height: 10),
        CpButton(
          text: 'Reset to bore.pub',
          isSecondary: true,
          onPressed: _reset,
        ),
      ],
    );
  }
}
