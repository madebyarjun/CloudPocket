import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:cloud_pocket/models/server_state.dart';
import 'package:cloud_pocket/models/share_session.dart';
import 'package:cloud_pocket/providers/network_provider.dart';
import 'package:cloud_pocket/providers/server_provider.dart';
import 'package:cloud_pocket/providers/session_provider.dart';
import 'package:cloud_pocket/providers/settings_provider.dart';
import 'package:cloud_pocket/services/room_discovery_service.dart';
import 'package:cloud_pocket/services/room_link_detector.dart';
import 'package:cloud_pocket/tunnel/tunnel_config.dart';
import 'package:cloud_pocket/ui/screens/room_chat_screen.dart';
import 'package:cloud_pocket/ui/theme.dart';
import 'package:cloud_pocket/ui/widgets/apple_widgets.dart';
import 'package:cloud_pocket/ui/widgets/cloudflare_setup_dialog.dart';
import 'package:cloud_pocket/ui/widgets/custom_bore_dialog.dart';
import 'package:cloud_pocket/ui/widgets/hotspot_prompt_dialog.dart';
import 'package:cloud_pocket/ui/widgets/qr_scanner_sheet.dart';

class DisposableRoomSetupScreen extends ConsumerStatefulWidget {
  const DisposableRoomSetupScreen({super.key});

  @override
  ConsumerState<DisposableRoomSetupScreen> createState() => _DisposableRoomSetupScreenState();
}

class _DisposableRoomSetupScreenState extends ConsumerState<DisposableRoomSetupScreen> {
  int _roomTab = 0; // 0: Host Room, 1: Join Room
  final TextEditingController _joinUrlController = TextEditingController();
  final TextEditingController _joinPinController = TextEditingController();
  final TextEditingController _joinNickController = TextEditingController();
  final TextEditingController _roomNameController = TextEditingController();
  bool _obscureJoinPin = true;
  bool _isResolvingChatId = false;
  String? _detectedToken;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      ref.read(sessionProvider.notifier).setIsDisposableRoom(true);
      final expiry = ref.read(sessionProvider).expiryDuration;
      if (expiry.duration == null || expiry.duration! > const Duration(hours: 2)) {
        ref.read(sessionProvider.notifier).setExpiryDuration(ExpiryDuration.min15);
      }
      final devName = ref.read(settingsProvider).deviceName;
      final currentConfigName = ref.read(sessionProvider).roomConfig?.roomName;
      _roomNameController.text = (currentConfigName != null &&
              currentConfigName.isNotEmpty &&
              currentConfigName != 'Disposable Room')
          ? currentConfigName
          : (devName.isNotEmpty ? "$devName's Room" : 'Disposable Room');
      _joinNickController.text = devName;
      _checkClipboardForRoomLink();
    });
  }

  @override
  void dispose() {
    _joinUrlController.dispose();
    _joinPinController.dispose();
    _joinNickController.dispose();
    _roomNameController.dispose();
    super.dispose();
  }

  Future<void> _checkClipboardForRoomLink() async {
    try {
      final data = await Clipboard.getData(Clipboard.kTextPlain);
      if (data?.text != null && mounted) {
        final parsed = RoomLinkDetector.parse(data!.text!);
        if (parsed != null) {
          _joinUrlController.text = parsed.roomUrl;
          if (parsed.pin != null) _joinPinController.text = parsed.pin!;
          if (parsed.nickname != null) _joinNickController.text = parsed.nickname!;
          _detectedToken = parsed.token;
        }
      }
    } catch (_) {}
  }

  Future<void> _scanQrCode() async {
    final result = await QrScannerSheet.show(context);
    if (result != null && mounted) {
      _joinUrlController.text = result.roomUrl;
      if (result.pin != null) _joinPinController.text = result.pin!;
      if (result.nickname != null) _joinNickController.text = result.nickname!;
      _detectedToken = result.token;
      await _joinRoom();
    }
  }

  Future<void> _pasteFromClipboard() async {
    final data = await Clipboard.getData(Clipboard.kTextPlain);
    if (data?.text != null && mounted) {
      final parsed = RoomLinkDetector.parse(data!.text!);
      if (parsed != null) {
        _joinUrlController.text = parsed.roomUrl;
        if (parsed.pin != null) _joinPinController.text = parsed.pin!;
        if (parsed.nickname != null) _joinNickController.text = parsed.nickname!;
        _detectedToken = parsed.token;
        AppleToast.show(context, 'Room link detected and pasted!');
      } else {
        _joinUrlController.text = data.text!.trim();
      }
    }
  }

  Future<void> _joinRoom() async {
    final raw = _joinUrlController.text.trim();
    if (raw.isEmpty) {
      AppleToast.show(context, 'Please enter a Chat ID or room link');
      return;
    }

    String targetUrl = '';
    String? token = _detectedToken;
    String? pin = _joinPinController.text.trim().isNotEmpty ? _joinPinController.text.trim() : null;
    String? discoveredRoomName;

    final isUrl = raw.startsWith('http://') || raw.startsWith('https://') || raw.startsWith('cloudpocket://');

    if (isUrl) {
      final parsed = RoomLinkDetector.parse(raw);
      targetUrl = parsed?.roomUrl ?? RoomLinkDetector.normalizeRoomUrl(raw);
      pin = pin ?? parsed?.pin;
      token = token ?? parsed?.token;
    } else {
      if (pin == null || pin.isEmpty) {
        AppleToast.show(context, 'Enter the room PIN to join using a Chat ID. Token-only rooms require a full invite link.');
        return;
      }
      // Input is a Chat ID (e.g. "AB-4829" or "ab4829")
      setState(() => _isResolvingChatId = true);
      final discovered = await RoomDiscoveryService.resolveRoom(raw);
      if (!mounted) return;
      setState(() => _isResolvingChatId = false);

      if (discovered == null) {
        AppleToast.show(context, 'Room "$raw" not found or expired. Please check the Chat ID.');
        return;
      }
      targetUrl = discovered.roomUrl;
      token = token ?? discovered.inviteToken;
      discoveredRoomName = discovered.roomName;
    }

    final nick = _joinNickController.text.trim().isNotEmpty
        ? _joinNickController.text.trim()
        : ref.read(settingsProvider).deviceName;

    if (!mounted) return;

    Navigator.of(context).pushReplacement(
      MaterialPageRoute(
        builder: (_) => RoomChatScreen(
          roomUrl: targetUrl,
          initialPin: pin,
          initialToken: token,
          initialNickname: nick,
          initialRoomName: discoveredRoomName,
        ),
      ),
    );
  }

  void _showTunnelModeDialog(BuildContext context) {
    final currentProvider = ref.read(sessionProvider).tunnelConfig.provider;

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (ctx) {
        final cs = Theme.of(ctx).colorScheme;
        final cpColors = Theme.of(ctx).extension<CloudPocketColors>()!;
        return SafeArea(
          child: ConstrainedBox(
            constraints: BoxConstraints(
              maxHeight: MediaQuery.of(ctx).size.height * 0.75,
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(20.0, 16.0, 20.0, 8.0),
                  child: Text(
                    'Select Tunnel Provider',
                    style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600, color: cs.onSurface),
                  ),
                ),
                Flexible(
                  child: ListView(
                    shrinkWrap: true,
                    children: TunnelProvider.values
                        .where((p) => TunnelConfig.isProviderSupported(p))
                        .map(
                      (p) {
                        final settings = ref.read(settingsProvider);
                        Widget? trailingWidget;

                        if (p == TunnelProvider.cloudflareCustom) {
                          trailingWidget = IconButton(
                            icon: Icon(Icons.tune_rounded, size: 18, color: cpColors.warning),
                            tooltip: 'Configure Cloudflare',
                            onPressed: () {
                              Navigator.of(ctx).pop();
                              CloudflareSetupDialog.show(context);
                            },
                          );
                        } else if (p == TunnelProvider.customBore) {
                          trailingWidget = IconButton(
                            icon: Icon(Icons.tune_rounded, size: 18, color: cpColors.success),
                            tooltip: 'Configure VPS',
                            onPressed: () {
                              Navigator.of(ctx).pop();
                              CustomBoreDialog.show(context);
                            },
                          );
                        } else if (p == currentProvider) {
                          trailingWidget = Icon(Icons.check_rounded, color: cs.primary);
                        }

                        return ListTile(
                          title: Text(p.displayName, style: TextStyle(color: cs.onSurface, fontSize: 14)),
                          subtitle: Text(
                            p == TunnelProvider.cloudflareCustom && settings.isCloudflareConfigured
                                ? '${settings.cloudflareDomain} · Connected'
                                : (p == TunnelProvider.customBore && settings.customBoreHost != null && settings.customBoreHost!.isNotEmpty
                                    ? '${settings.customBoreHost}:${settings.customBorePort}'
                                    : (p == TunnelProvider.cloudflareQuick
                                        ? '${p.description} · Turn on Mobile Hotspot'
                                        : p.description)),
                            style: TextStyle(color: cs.onSurfaceVariant, fontSize: 12),
                          ),
                          trailing: trailingWidget,
                          onTap: () {
                            ref.read(sessionProvider.notifier).setTunnelProvider(p);
                            ref.read(sessionProvider.notifier).setEnableTunnel(true);
                            Navigator.of(ctx).pop();

                            if (p == TunnelProvider.cloudflareQuick) {
                              HotspotPromptDialog.show(context);
                            } else if (p == TunnelProvider.cloudflareCustom && !settings.isCloudflareConfigured) {
                              CloudflareSetupDialog.show(context);
                            } else if (p == TunnelProvider.customBore &&
                                (settings.customBoreHost == null || settings.customBoreHost!.isEmpty)) {
                              CustomBoreDialog.show(context);
                            }
                          },
                        );
                      },
                    ).toList(),
                  ),
                ),
                const SizedBox(height: 12),
              ],
            ),
          ),
        );
      },
    );
  }

  void _showDurationDialog(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final current = ref.read(sessionProvider).expiryDuration;
    final durations = ExpiryDuration.values.where((e) => e.duration != null && e.duration! <= const Duration(hours: 2)).toList();

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (ctx) => SafeArea(
        child: SingleChildScrollView(child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 16.0),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 20.0, vertical: 8.0),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Room Self-Destruct Timer',
                      style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: colorScheme.onSurface),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      'Strict countdown timer. Once launched, this timer cannot be extended.',
                      style: TextStyle(fontSize: 12, color: colorScheme.onSurfaceVariant),
                    ),
                  ],
                ),
              ),
              ...durations.map(
                (e) => ListTile(
                  title: Text(e.label, style: TextStyle(color: colorScheme.onSurface, fontSize: 14)),
                  trailing: e == current ? Icon(Icons.check_rounded, color: colorScheme.primary) : null,
                  onTap: () {
                    ref.read(sessionProvider.notifier).setExpiryDuration(e);
                    Navigator.of(ctx).pop();
                  },
                ),
              ),
            ],
          ),
        )),
      ),
    );
  }

  void _showSecurityDialog(BuildContext context) {
    final session = ref.read(sessionProvider);
    final passwordController = TextEditingController(text: session.password ?? '');
    var isPasswordRequired = session.requirePassword;
    var obscurePassword = true;

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setModalState) {
          final cs = Theme.of(ctx).colorScheme;
          return Padding(
            padding: EdgeInsets.only(
              left: 20,
              right: 20,
              top: 24,
              bottom: MediaQuery.of(ctx).viewInsets.bottom + 24,
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Room Security PIN / Password',
                  style: TextStyle(fontSize: 18, fontWeight: FontWeight.w600, color: cs.onSurface),
                ),
                const SizedBox(height: 8),
                Text(
                  'Require participants to enter a PIN or password before entering the disposable room.',
                  style: TextStyle(fontSize: 13, color: cs.onSurfaceVariant),
                ),
                const SizedBox(height: 16),
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  title: Text('Require PIN / Password', style: TextStyle(color: cs.onSurface, fontSize: 14)),
                  value: isPasswordRequired,
                  onChanged: (val) {
                    ref.read(sessionProvider.notifier).setRequirePassword(val);
                    setModalState(() {
                      isPasswordRequired = val;
                    });
                  },
                ),
                if (isPasswordRequired) ...[
                  const SizedBox(height: 8),
                  TextField(
                    controller: passwordController,
                    obscureText: obscurePassword,
                    decoration: InputDecoration(
                      hintText: 'Enter 4-6 digit PIN or password',
                      suffixIcon: IconButton(
                        icon: Icon(
                          obscurePassword ? Icons.visibility_off_rounded : Icons.visibility_rounded,
                          size: 20,
                        ),
                        tooltip: obscurePassword ? 'Show password' : 'Hide password',
                        onPressed: () {
                          setModalState(() {
                            obscurePassword = !obscurePassword;
                          });
                        },
                      ),
                    ),
                    onChanged: (val) {
                      ref.read(sessionProvider.notifier).setPassword(val);
                    },
                  ),
                ],
                const SizedBox(height: 20),
                SizedBox(
                  width: double.infinity,
                  child: FilledButton(
                    onPressed: () => Navigator.of(ctx).pop(),
                    child: const Text('Done'),
                  ),
                ),
              ],
            ),
          );
        },
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final session = ref.watch(sessionProvider);
    final serverState = ref.watch(serverProvider);
    final netInfo = ref.watch(networkStateProvider).value;
    final colors = Theme.of(context).extension<CloudPocketColors>() ?? CloudPocketColors.light;

    return WillPopScope(
      onWillPop: () async {
        ref.read(sessionProvider.notifier).setIsDisposableRoom(false);
        return true;
      },
      child: Scaffold(
      backgroundColor: colors.bg,
      appBar: AppBar(
        backgroundColor: colors.bg,
        elevation: 0,
        leading: IconButton(
          icon: Icon(Icons.close_rounded, color: colors.label),
          onPressed: () {
            ref.read(sessionProvider.notifier).setIsDisposableRoom(false);
            Navigator.of(context).pop();
          },
        ),
        title: Text(
          'Disposable Room',
          style: TextStyle(
            fontSize: 17,
            fontWeight: FontWeight.w600,
            color: colors.label,
            fontFamilyFallback: CloudPocketTheme.fontFallbacks,
          ),
        ),
      ),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.symmetric(horizontal: 20.0, vertical: 12.0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Mode Switcher: [Host Room | Join Room]
              AppleSegmentedControl<int>(
                values: const [0, 1],
                labels: const ['Host Room', 'Join Room'],
                selectedValue: _roomTab,
                onValueChanged: (val) => setState(() => _roomTab = val),
              ),
              const SizedBox(height: 18),

              if (_roomTab == 0) ...[
                // Hero Overview Card (.card)
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(20),
                  decoration: BoxDecoration(
                    color: colors.card,
                    borderRadius: BorderRadius.circular(CloudPocketTheme.radiusCard),
                    boxShadow: colors.shadow,
                  ),
                  child: Row(
                    children: [
                      Container(
                        width: 48,
                        height: 48,
                        decoration: BoxDecoration(
                          gradient: const LinearGradient(
                            colors: [Color(0xFFFF9F0A), Color(0xFFFF375F)],
                            begin: Alignment.topLeft,
                            end: Alignment.bottomRight,
                          ),
                          borderRadius: BorderRadius.circular(14),
                        ),
                        alignment: Alignment.center,
                        child: const Icon(Icons.shield_rounded, color: Colors.white, size: 26),
                      ),
                      const SizedBox(width: 14),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'Temporary Burner Room',
                              style: TextStyle(
                                fontSize: 16,
                                fontWeight: FontWeight.w700,
                                color: colors.label,
                                fontFamilyFallback: CloudPocketTheme.fontFallbacks,
                              ),
                            ),
                            const SizedBox(height: 3),
                            Text(
                              'Messages in memory · Temporary media',
                              style: TextStyle(
                                fontSize: 13,
                                color: colors.label2,
                                fontFamilyFallback: CloudPocketTheme.fontFallbacks,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),

                const SizedBox(height: 18),

                // Room Name Input Field (.grp)
                AppleGroup(
                  margin: EdgeInsets.zero,
                  children: [
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
                      child: TextField(
                        controller: _roomNameController,
                        style: TextStyle(
                          color: colors.label,
                          fontSize: 15,
                          fontFamilyFallback: CloudPocketTheme.fontFallbacks,
                        ),
                        decoration: InputDecoration(
                          border: InputBorder.none,
                          labelText: 'Room Name',
                          labelStyle: TextStyle(color: colors.label2, fontSize: 13),
                          hintText: 'e.g. Project Chat, Secret Room',
                          hintStyle: TextStyle(color: colors.label2.withOpacity(0.5), fontSize: 15),
                        ),
                        onChanged: (val) {
                          ref.read(sessionProvider.notifier).setRoomName(val);
                        },
                      ),
                    ),
                  ],
                ),

                const SizedBox(height: 18),

                // Configuration Options Group (.grp)
                AppleGroup(
                  margin: EdgeInsets.zero,
                  children: [
                    // Public Tunnel
                    AppleRow(
                      showSeparator: false,
                      icon: AppleIconTile(
                        backgroundColor: colors.blue,
                        icon: const Icon(Icons.public_rounded, color: Colors.white, size: 18),
                      ),
                      title: 'Reach',
                      subtitle: session.enableTunnel ? '${session.tunnelConfig.provider.displayName} · Remote access' : 'Local network only',
                      trailing: Text('›', style: TextStyle(fontSize: 22, color: colors.label2, fontWeight: FontWeight.w300)),
                      onTap: () => _showTunnelModeDialog(context),
                    ),
                    // Self-Destruct Timer
                    AppleRow(
                      icon: AppleIconTile(
                        backgroundColor: colors.orange,
                        icon: const Icon(Icons.timer_rounded, color: Colors.white, size: 18),
                      ),
                      title: 'Self-Destruct Timer',
                      subtitle: '${session.expiryDuration.label} · Strict countdown',
                      trailing: Text('›', style: TextStyle(fontSize: 22, color: colors.label2, fontWeight: FontWeight.w300)),
                      onTap: () => _showDurationDialog(context),
                    ),
                    // Room Security PIN
                    AppleRow(
                      icon: const AppleIconTile(
                        backgroundColor: Color(0xFFFF375F),
                        icon: Icon(Icons.lock_rounded, color: Colors.white, size: 18),
                      ),
                      title: 'PIN Protection',
                      subtitle: session.requirePassword ? 'PIN / Password active' : 'Optional PIN or password',
                      trailing: Text('›', style: TextStyle(fontSize: 22, color: colors.label2, fontWeight: FontWeight.w300)),
                      onTap: () => _showSecurityDialog(context),
                    ),
                  ],
                ),

                // Hotspot Notice Banner
                if (session.enableTunnel && session.tunnelConfig.provider == TunnelProvider.cloudflareQuick &&
                    netInfo?.isHotspot != true) ...[
                  const SizedBox(height: 14),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                    decoration: BoxDecoration(
                      color: colors.card,
                      borderRadius: BorderRadius.circular(16),
                      boxShadow: colors.shadow,
                    ),
                    child: Row(
                      children: [
                        Icon(Icons.wifi_tethering_rounded, size: 20, color: colors.orange),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Text(
                            'Turn on Mobile Hotspot for Cloudflare Quick to route reliably.',
                            style: TextStyle(
                              color: colors.label,
                              fontSize: 13,
                              fontFamilyFallback: CloudPocketTheme.fontFallbacks,
                            ),
                          ),
                        ),
                        TextButton(
                          onPressed: () => HotspotPromptDialog.openHotspotSettings(),
                          child: Text('Settings', style: TextStyle(color: colors.blue)),
                        ),
                      ],
                    ),
                  ),
                ],

                const SizedBox(height: 28),

                // Launch Button (.btn)
                AppleButton.primary(
                  text: serverState.status == ServerStatus.starting
                      ? 'Launching Room...'
                      : 'Launch Disposable Room',
                  onPressed: serverState.status == ServerStatus.starting
                      ? null
                      : () async {
                          final name = _roomNameController.text.trim();
                          if (session.requirePassword && (session.passwordHash == null || session.passwordHash!.isEmpty)) {
                            _showSecurityDialog(context);
                            return;
                          }
                          ref.read(sessionProvider.notifier).setRoomName(name);
                          ref.read(sessionProvider.notifier).setIsDisposableRoom(true);

                          if (session.enableTunnel && session.tunnelConfig.provider == TunnelProvider.cloudflareQuick &&
                              netInfo?.isHotspot != true) {
                            HotspotPromptDialog.show(
                              context,
                              onContinue: () async {
                                Navigator.of(context).pop();
                                await ref.read(serverProvider.notifier).startServer();
                              },
                            );
                          } else {
                            Navigator.of(context).pop();
                            await ref.read(serverProvider.notifier).startServer();
                          }
                        },
                ),
              ] else ...[
                _buildJoinTab(context, colors),
              ],
            ],
          ),
        ),
      ),
    ));
  }

  Widget _buildJoinTab(BuildContext context, CloudPocketColors colors) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Camera QR Scanner Card (.card)
        GestureDetector(
          onTap: _scanQrCode,
          child: Container(
            width: double.infinity,
            padding: const EdgeInsets.all(20),
            decoration: BoxDecoration(
              color: colors.card,
              borderRadius: BorderRadius.circular(CloudPocketTheme.radiusCard),
              boxShadow: colors.shadow,
            ),
            child: Row(
              children: [
                AppleIconTile(
                  size: 48,
                  radius: 14,
                  backgroundColor: colors.blue,
                  icon: const Icon(Icons.qr_code_scanner_rounded, size: 26, color: Colors.white),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Scan Host QR Code',
                        style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.w700,
                          color: colors.label,
                          fontFamilyFallback: CloudPocketTheme.fontFallbacks,
                        ),
                      ),
                      const SizedBox(height: 3),
                      Text(
                        'Instant zero-typing join with screenshot guard',
                        style: TextStyle(
                          fontSize: 13,
                          color: colors.label2,
                          fontFamilyFallback: CloudPocketTheme.fontFallbacks,
                        ),
                      ),
                    ],
                  ),
                ),
                Text('›', style: TextStyle(fontSize: 22, color: colors.label2, fontWeight: FontWeight.w300)),
              ],
            ),
          ),
        ),

        const SizedBox(height: 22),

        // Manual Input Section Caption (.cap)
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
          child: Text(
            'OR JOIN VIA CHAT ID OR LINK',
            style: TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w600,
              color: colors.label2,
              letterSpacing: 0.2,
              fontFamilyFallback: CloudPocketTheme.fontFallbacks,
            ),
          ),
        ),
        const SizedBox(height: 4),

        // Input Fields Group (.grp)
        AppleGroup(
          margin: EdgeInsets.zero,
          children: [
            // Chat ID or Room Link
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
              child: TextField(
                controller: _joinUrlController,
                style: TextStyle(color: colors.label, fontSize: 15, fontFamilyFallback: CloudPocketTheme.fontFallbacks),
                decoration: InputDecoration(
                  border: InputBorder.none,
                  labelText: 'Chat ID or Room Link',
                  labelStyle: TextStyle(color: colors.label2, fontSize: 13),
                  hintText: 'e.g. AB-4829 or https://...',
                  hintStyle: TextStyle(color: colors.label2.withOpacity(0.5), fontSize: 15),
                  suffixIcon: IconButton(
                    icon: Icon(Icons.content_paste_rounded, size: 19, color: colors.blue),
                    tooltip: 'Paste from clipboard',
                    onPressed: _pasteFromClipboard,
                  ),
                ),
              ),
            ),
            // Room PIN
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
              child: TextField(
                controller: _joinPinController,
                obscureText: _obscureJoinPin,
                style: TextStyle(color: colors.label, fontSize: 15, fontFamilyFallback: CloudPocketTheme.fontFallbacks),
                decoration: InputDecoration(
                  border: InputBorder.none,
                  labelText: 'Room PIN (if required)',
                  labelStyle: TextStyle(color: colors.label2, fontSize: 13),
                  hintText: 'Enter secret room PIN',
                  hintStyle: TextStyle(color: colors.label2.withOpacity(0.5), fontSize: 15),
                  suffixIcon: IconButton(
                    icon: Icon(_obscureJoinPin ? Icons.visibility_off_rounded : Icons.visibility_rounded, size: 19, color: colors.label2),
                    onPressed: () => setState(() => _obscureJoinPin = !_obscureJoinPin),
                  ),
                ),
              ),
            ),
            // Nickname
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
              child: TextField(
                controller: _joinNickController,
                style: TextStyle(color: colors.label, fontSize: 15, fontFamilyFallback: CloudPocketTheme.fontFallbacks),
                decoration: InputDecoration(
                  border: InputBorder.none,
                  labelText: 'Your Nickname',
                  labelStyle: TextStyle(color: colors.label2, fontSize: 13),
                  hintText: 'Host or guest name',
                  hintStyle: TextStyle(color: colors.label2.withOpacity(0.5), fontSize: 15),
                ),
              ),
            ),
          ],
        ),

        const SizedBox(height: 28),

        // Join Room Action Button (.btn)
        AppleButton.primary(
          text: _isResolvingChatId ? 'Finding Room...' : 'Join Room (Secure Mode)',
          onPressed: _isResolvingChatId ? null : _joinRoom,
        ),
      ],
    );
  }
}
