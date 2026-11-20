import 'package:material_ui/material_ui.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter/services.dart';
import 'package:cloud_pocket/models/share_session.dart';
import 'package:cloud_pocket/models/server_state.dart';
import 'package:cloud_pocket/providers/network_provider.dart';
import 'package:cloud_pocket/providers/server_provider.dart';
import 'package:cloud_pocket/providers/session_provider.dart';
import 'package:cloud_pocket/providers/settings_provider.dart';
import 'package:cloud_pocket/services/permission_service.dart';
import 'package:cloud_pocket/services/room_link_detector.dart';
import 'package:cloud_pocket/tunnel/tunnel_config.dart';
import 'package:cloud_pocket/ui/screens/file_selector_screen.dart';
import 'package:cloud_pocket/ui/screens/room_chat_screen.dart';
import 'package:cloud_pocket/ui/theme.dart';
import 'package:cloud_pocket/ui/widgets/apple_widgets.dart';
import 'package:cloud_pocket/ui/widgets/cloudflare_setup_dialog.dart';
import 'package:cloud_pocket/ui/widgets/custom_bore_dialog.dart';
import 'package:cloud_pocket/ui/widgets/hotspot_prompt_dialog.dart';
import 'package:cloud_pocket/ui/screens/disposable_room_live_view.dart';
import 'package:cloud_pocket/ui/screens/disposable_room_setup_screen.dart';
import 'package:cloud_pocket/ui/widgets/sharing_live_view.dart';

class HomeScreen extends ConsumerStatefulWidget {
  const HomeScreen({super.key, this.shareKey, this.reachKey, this.modeKeys, this.onPermissionsFinished});
  final Key? shareKey;
  final Key? reachKey;
  final Map<int, Key>? modeKeys;
  final VoidCallback? onPermissionsFinished;

  @override
  ConsumerState<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends ConsumerState<HomeScreen> with WidgetsBindingObserver {
  bool _isBatteryOptimizationIgnored = true;
  bool _dismissedBatteryBanner = false;
  String? _lastPromptedRoomUrl;
  int _activeMode = 0; // 0: Send Files, 1: Receive Mode, 2: Room
  static const _roomDurations = [ExpiryDuration.min5, ExpiryDuration.min15, ExpiryDuration.min30, ExpiryDuration.hour1, ExpiryDuration.hour2];

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      await PermissionService.requestInitialPermissions();
      if (!mounted) return;
      widget.onPermissionsFinished?.call();
      _checkBatteryOptimization();
      _checkClipboardForRoomLink();
    });
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      _checkClipboardForRoomLink();
    }
  }

  Future<void> _checkClipboardForRoomLink() async {
    final server = ref.read(serverProvider);
    if (server.isRunning) return;

    try {
      final data = await Clipboard.getData(Clipboard.kTextPlain);
      final text = data?.text;
      if (text == null || text.trim().isEmpty) return;

      final parsed = RoomLinkDetector.parse(text);
      if (parsed != null && parsed.roomUrl != _lastPromptedRoomUrl && mounted) {
        _lastPromptedRoomUrl = parsed.roomUrl;
        _showRoomDetectedPrompt(parsed);
      }
    } catch (_) {}
  }

  void _showRoomDetectedPrompt(ParsedRoomLink parsed) {
    final colors = Theme.of(context).extension<CloudPocketColors>() ?? CloudPocketColors.light;
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (ctx) {
        return Container(
          margin: const EdgeInsets.all(16),
          padding: const EdgeInsets.all(18),
          decoration: BoxDecoration(
            color: colors.card,
            borderRadius: BorderRadius.circular(22),
            boxShadow: colors.shadow,
            border: Border.all(color: colors.blue.withValues(alpha: 0.3)),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Row(
                children: [
                  AppleIconTile(
                    backgroundColor: colors.blue,
                    icon: const Icon(Icons.meeting_room_rounded, color: Colors.white, size: 20),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Room Link Detected',
                          style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16, color: colors.label),
                        ),
                        Text(
                          'Disposable room link copied to clipboard.',
                          style: TextStyle(fontSize: 13, color: colors.label2),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 16),
              Row(
                children: [
                  Expanded(
                    child: AppleButton.gray(
                      text: 'Ignore',
                      isSmall: true,
                      onPressed: () => Navigator.pop(ctx),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: AppleButton.primary(
                      text: 'Join Room',
                      isSmall: true,
                      onPressed: () {
                        Navigator.pop(ctx);
                        Navigator.of(context).push(
                          MaterialPageRoute(
                            builder: (_) => RoomChatScreen(
                              roomUrl: parsed.roomUrl,
                              initialPin: parsed.pin,
                              initialNickname: parsed.nickname ?? ref.read(settingsProvider).deviceName,
                            ),
                          ),
                        );
                      },
                    ),
                  ),
                ],
              ),
            ],
          ),
        );
      },
    );
  }

  Future<void> _checkBatteryOptimization() async {
    final ignored = await PermissionService.isBatteryOptimizationIgnored();
    if (mounted) {
      setState(() {
        _isBatteryOptimizationIgnored = ignored;
      });
    }
  }

  void _showBatteryOptimizationDialog() {
    final colors = Theme.of(context).extension<CloudPocketColors>() ?? CloudPocketColors.light;

    AppleDialog.show(
      context: context,
      title: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.battery_alert_rounded, size: 22, color: colors.orange),
          const SizedBox(width: 8),
          const Text('Prevent Transfer Drops'),
        ],
      ),
      content: const Text(
        'Android systems may pause the server when the screen is locked.\n\nAllow background execution for uninterrupted sharing.',
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: Text('Later', style: TextStyle(color: colors.label2)),
        ),
        TextButton(
          onPressed: () async {
            Navigator.of(context).pop();
            final granted = await PermissionService.requestIgnoreBatteryOptimization();
            if (mounted) {
              setState(() {
                _isBatteryOptimizationIgnored = granted;
                if (granted) _dismissedBatteryBanner = true;
              });
            }
          },
          child: Text('Allow Background', style: TextStyle(color: colors.blue, fontWeight: FontWeight.bold)),
        ),
      ],
    );
  }

  void _showSecurityDialog() {
    final session = ref.read(sessionProvider);
    final passwordController = TextEditingController(text: session.password ?? '');
    var isPasswordRequired = session.requirePassword;
    var obscurePassword = true;

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setModalState) {
          final colors = Theme.of(ctx).extension<CloudPocketColors>() ?? CloudPocketColors.light;
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
                  'Access Security',
                  style: TextStyle(fontSize: 20, fontWeight: FontWeight.w700, color: colors.label),
                ),
                const SizedBox(height: 8),
                Text(
                  'Require recipients to enter a password or PIN before accessing shared files.',
                  style: TextStyle(fontSize: 14, color: colors.label2),
                ),
                const SizedBox(height: 16),
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  title: Text('Require Password / PIN', style: TextStyle(color: colors.label, fontSize: 15)),
                  value: isPasswordRequired,
                  onChanged: (val) {
                    ref.read(sessionProvider.notifier).setRequirePassword(val);
                    setModalState(() {
                      isPasswordRequired = val;
                    });
                  },
                ),
                if (isPasswordRequired) ...[
                  const SizedBox(height: 10),
                  TextField(
                    controller: passwordController,
                    obscureText: obscurePassword,
                    decoration: InputDecoration(
                      hintText: 'Enter password or PIN',
                      suffixIcon: IconButton(
                        icon: Icon(
                          obscurePassword ? Icons.visibility_off_rounded : Icons.visibility_rounded,
                          size: 20,
                        ),
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
                AppleButton.primary(
                  text: 'Done',
                  onPressed: () => Navigator.of(ctx).pop(),
                ),
              ],
            ),
          );
        },
      ),
    );
  }

  void _showTunnelModeDialog(BuildContext context) {
    final currentProvider = ref.read(sessionProvider).tunnelConfig.provider;

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      builder: (ctx) {
        final colors = Theme.of(ctx).extension<CloudPocketColors>() ?? CloudPocketColors.light;
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
                    style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700, color: colors.label),
                  ),
                ),
                Flexible(
                  child: ListView(
                    shrinkWrap: true,
                    children: TunnelProvider.values
                        .where((p) => TunnelConfig.isProviderSupported(p))
                        .map((p) {
                      final isSelected = p == currentProvider;
                      return ListTile(
                        title: Text(p.displayName, style: TextStyle(color: colors.label, fontSize: 15)),
                        subtitle: Text(p.description, style: TextStyle(color: colors.label2, fontSize: 13)),
                        trailing: isSelected ? Icon(Icons.check_rounded, color: colors.blue) : null,
                        onTap: () {
                          ref.read(sessionProvider.notifier).setTunnelProvider(p);
                          ref.read(sessionProvider.notifier).setEnableTunnel(true);
                          Navigator.of(ctx).pop();
                          if (p == TunnelProvider.cloudflareQuick) {
                            HotspotPromptDialog.show(context);
                          } else if (p == TunnelProvider.cloudflareCustom) {
                            CloudflareSetupDialog.show(context);
                          } else if (p == TunnelProvider.customBore) {
                            CustomBoreDialog.show(context);
                          }
                        },
                      );
                    }).toList(),
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

  String _getReachLabel(ShareSession session) {
    if (!session.enableTunnel) return 'Local network';
    if (session.tunnelConfig.provider == TunnelProvider.auto) return 'Auto';
    if (session.tunnelConfig.provider == TunnelProvider.cloudflareQuick) return 'Cloudflare';
    return session.tunnelConfig.provider.displayName;
  }

  @override
  Widget build(BuildContext context) {
    final serverState = ref.watch(serverProvider);
    final session = ref.watch(sessionProvider);
    final colors = Theme.of(context).extension<CloudPocketColors>() ?? CloudPocketColors.light;

    // When server is running, show the dedicated Sharing Live screen
    if (serverState.isRunning) {
      if (session.isDisposableRoom) {
        return const Scaffold(
          body: SafeArea(child: DisposableRoomLiveView()),
        );
      }
      return const Scaffold(
        body: SafeArea(child: SharingLiveView()),
      );
    }

    final netInfo = ref.watch(networkStateProvider).value;
    final itemsCount = session.items.length;
    final activeIp = netInfo?.localIp;

    // Synchronize _activeMode with session.isReceiveMode
    if (session.isReceiveMode && _activeMode != 1) {
      _activeMode = 1;
    } else if (!session.isReceiveMode && _activeMode == 1) {
      _activeMode = 0;
    }

    return Scaffold(
      backgroundColor: colors.bg,
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(20, 12, 20, 118),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Top Bar: CloudPocket subtitle + Share H1 + IP Chip (.top)
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'CloudPocket',
                        style: TextStyle(
                          fontSize: 15,
                          fontWeight: FontWeight.w600,
                          color: colors.label2,
                          fontFamilyFallback: CloudPocketTheme.fontFallbacks,
                        ),
                      ),
                      Text(
                        'Share',
                        style: TextStyle(
                          fontSize: 34,
                          fontWeight: FontWeight.w700,
                          letterSpacing: -0.8,
                          height: 1.1,
                          color: colors.label,
                          fontFamilyFallback: CloudPocketTheme.fontFallbacks,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        netInfo?.isConnected == true
                            ? '${netInfo!.isWifi ? "Wi-Fi" : (netInfo.isHotspot ? "Hotspot" : "Network")} · ${netInfo.localIp ?? "Ready to share"}'
                            : 'Ready to share',
                        style: TextStyle(
                          fontSize: 13,
                          color: colors.label2,
                          fontFamilyFallback: CloudPocketTheme.fontFallbacks,
                        ),
                      ),
                    ],
                  ),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
                    decoration: BoxDecoration(
                      color: colors.card,
                      borderRadius: BorderRadius.circular(20),
                      boxShadow: colors.shadow,
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const PulsingDot(size: 8),
                        const SizedBox(width: 7),
                        Text(
                          activeIp ?? 'No local IP',
                          style: TextStyle(
                            fontSize: 13,
                            fontWeight: FontWeight.w500,
                            fontFeatures: const [FontFeature.tabularFigures()],
                            color: colors.label,
                            fontFamilyFallback: CloudPocketTheme.fontFallbacks,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),

              // Mode Switcher: Send Files / Receive Mode / Room (.seg)
              AppleSegmentedControl<int>(
                margin: const EdgeInsets.only(top: 16),
                segmentKeys: widget.modeKeys,
                values: const [0, 1, 2],
                labels: const ['Send Files', 'Receive Mode', 'Room'],
                selectedValue: _activeMode,
                onValueChanged: (val) {
                  setState(() => _activeMode = val);
                  if (val == 0) {
                    ref.read(sessionProvider.notifier).setIsDisposableRoom(false);
                    ref.read(sessionProvider.notifier).setIsReceiveMode(false);
                  } else if (val == 1) {
                    ref.read(sessionProvider.notifier).setIsReceiveMode(true);
                  } else {
                    ref.read(sessionProvider.notifier).setIsReceiveMode(false);
                    if (!_roomDurations.contains(session.expiryDuration)) {
                      ref.read(sessionProvider.notifier).setExpiryDuration(ExpiryDuration.min15);
                    }
                  }
                },
              ),

              const SizedBox(height: 16),

              // Hero Card per mode (.card .hero)
              _buildHeroCard(context, colors, itemsCount),

              // Background optimization warning (if active)
              if (itemsCount > 0 && !_isBatteryOptimizationIgnored && !_dismissedBatteryBanner) ...[
                const SizedBox(height: 14),
                AppleGroup(
                  children: [
                    AppleRow(
                      icon: const AppleIconTile(
                        backgroundColor: Color(0xFFFF9500),
                        icon: Icon(Icons.battery_alert_rounded, color: Colors.white, size: 18),
                      ),
                      title: 'Background Optimization',
                      subtitle: 'May pause transfers when screen sleeps',
                      trailing: const Text('Fix ›', style: TextStyle(color: Color(0xFF007AFF), fontWeight: FontWeight.w600)),
                      showSeparator: false,
                      onTap: _showBatteryOptimizationDialog,
                    ),
                  ],
                ),
              ],

              ExpansionTile(title: Text("Sharing options", key: widget.reachKey), subtitle: Text(_getReachLabel(session)), children: [
              AppleGroup(
                children: [
                  // Row 1: PIN protection
                  AppleRow(
                    icon: const AppleIconTile(
                      backgroundColor: Color(0xFFFF9500),
                      icon: Icon(Icons.lock_rounded, color: Colors.white, size: 16),
                    ),
                    title: 'PIN protection',

                    trailing: AppleToggle(
                      label: 'PIN protection',
                      value: session.requirePassword,
                      onChanged: (val) {
                        ref.read(sessionProvider.notifier).setRequirePassword(val);
                        if (val && (session.password == null || session.password!.isEmpty)) {
                          _showSecurityDialog();
                        }
                      },
                    ),
                    showSeparator: false,
                    onTap: _showSecurityDialog,
                  ),
                  if (_activeMode == 0) AppleRow(
                    icon: const AppleIconTile(
                      backgroundColor: Color(0xFFAF52DE),
                      icon: Icon(Icons.bolt_rounded, color: Colors.white, size: 18),
                    ),
                    title: 'One-time downloads',
                    subtitle: _activeMode != 0 ? 'Available in Send Files mode' : (session.isVaultMode ? 'First request uses access, even if interrupted' : null),
                    trailing: AppleToggle(
                      label: 'One-time downloads',
                      value: session.isVaultMode,
                      onChanged: _activeMode != 0 ? null : (val) {
                        ref.read(sessionProvider.notifier).setVaultMode(val, maxDownloads: val ? 1 : null);
                      },
                    ),
                  ),
                  // Row 3: Internet tunnel / Reach
                  AppleRow(
                    icon: AppleIconTile(
                      backgroundColor: colors.blue,
                      icon: const Icon(Icons.public_rounded, color: Colors.white, size: 18),
                    ),
                    title: 'Internet tunnel',
                    trailing: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          _getReachLabel(session),
                          style: TextStyle(
                            fontSize: 15,
                            color: colors.label2,
                            fontFamilyFallback: CloudPocketTheme.fontFallbacks,
                          ),
                        ),
                        const SizedBox(width: 4),
                        Icon(Icons.chevron_right_rounded, size: 18, color: colors.label2),
                      ],
                    ),
                    onTap: () => _showTunnelModeDialog(context),
                  ),
                ],
              ),

              ]),
              const SizedBox(height: 24),

              // Primary session action
              if (_activeMode != 0 || itemsCount > 0) AppleButton.primary(
                text: _activeMode == 1
                    ? 'Start Receiving'
                    : (_activeMode == 2 ? 'Create Room' : 'Start Sharing'),
                onPressed: serverState.status == ServerStatus.starting ? null : () {
                  if (_activeMode == 2) {
                    Navigator.of(context).push(
                      MaterialPageRoute(builder: (_) => const DisposableRoomSetupScreen()),
                    );
                    return;
                  }

                  if (session.requirePassword && (session.passwordHash == null || session.passwordHash!.isEmpty)) {
                    _showSecurityDialog();
                    return;
                  }

                  if (session.enableTunnel &&
                      session.tunnelConfig.provider == TunnelProvider.cloudflareQuick &&
                      netInfo?.isHotspot != true) {
                    HotspotPromptDialog.show(
                      context,
                      onContinue: () {
                        ref.read(serverProvider.notifier).startServer();
                      },
                    );
                  } else {
                    ref.read(serverProvider.notifier).startServer();
                  }
                },
              ),
              if (serverState.errorMessage != null) ...[
                const SizedBox(height: 12),
                Center(
                  child: Text(
                    serverState.errorMessage!,
                    style: TextStyle(color: colors.red, fontSize: 13),
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildHeroCard(BuildContext context, CloudPocketColors colors, int itemsCount) {
    if (_activeMode == 1) {
      // Receive Mode Hero
      return Container(
        width: double.infinity,
        padding: const EdgeInsets.all(22),
        decoration: BoxDecoration(
          color: colors.card,
          borderRadius: BorderRadius.circular(CloudPocketTheme.radiusCard),
          boxShadow: colors.shadow,
        ),
        child: Column(
          children: [
            RadarVisualizer(
              centerIcon: AppleIconTile(
                size: 60,
                radius: 19,
                backgroundColor: colors.green,
                icon: const Icon(Icons.download_rounded, color: Colors.white, size: 30),
              ),
            ),
            const SizedBox(height: 12),
            Text(
              'Ready to Receive Files',
              style: TextStyle(
                fontSize: 22,
                fontWeight: FontWeight.w700,
                letterSpacing: -0.4,
                color: colors.label,
                fontFamilyFallback: CloudPocketTheme.fontFallbacks,
              ),
            ),
            const SizedBox(height: 6),
            Text(
              'Receive files from a shared link.',
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 15,
                color: colors.label2,
                fontFamilyFallback: CloudPocketTheme.fontFallbacks,
              ),
            ),
            const SizedBox(height: 14),
            Text(
              ref.watch(settingsProvider).customUploadDirectory ?? 'Downloads/CloudPocket',
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 13,
                color: colors.label2,
                fontFamilyFallback: CloudPocketTheme.fontFallbacks,
              ),
            ),
          ],
        ),
      );
    }

    if (_activeMode == 2) {
      // Room Mode Hero
      return Container(
        width: double.infinity,
        padding: const EdgeInsets.all(22),
        decoration: BoxDecoration(
          color: colors.card,
          borderRadius: BorderRadius.circular(CloudPocketTheme.radiusCard),
          boxShadow: colors.shadow,
        ),
        child: Column(
          children: [
            Container(
              width: 60,
              height: 60,
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(19),
                gradient: const LinearGradient(
                  colors: [Color(0xFFFF9F0A), Color(0xFFFF375F)],
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                ),
              ),
              alignment: Alignment.center,
              child: const Icon(Icons.shield_outlined, color: Colors.white, size: 30),
            ),
            const SizedBox(height: 14),
            Text(
              'Disposable room',
              style: TextStyle(
                fontSize: 22,
                fontWeight: FontWeight.w700,
                letterSpacing: -0.4,
                color: colors.label,
                fontFamilyFallback: CloudPocketTheme.fontFallbacks,
              ),
            ),
            const SizedBox(height: 6),
            Text(
              'Choose when the room expires.',
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 15,
                color: colors.label2,
                fontFamilyFallback: CloudPocketTheme.fontFallbacks,
              ),
            ),
            const SizedBox(height: 14),
            AppleSegmentedControl<int>(
              margin: EdgeInsets.zero,
              values: const [0, 1, 2, 3, 4],
              labels: const ['5 min', '15 min', '30 min', '1 hr', '2 hr'],
              selectedValue: _roomDurations.indexOf(ref.watch(sessionProvider).expiryDuration),
              onValueChanged: (v) => ref.read(sessionProvider.notifier).setExpiryDuration(_roomDurations[v]),
            ),
          ],
        ),
      );
    }

    // Mode 0: Send Files Hero
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(22),
      decoration: BoxDecoration(
        color: colors.card,
        borderRadius: BorderRadius.circular(CloudPocketTheme.radiusCard),
        boxShadow: colors.shadow,
      ),
      child: Column(
        children: [
          AppleIconTile(
            size: 60,
            radius: 19,
            backgroundColor: colors.blue,
            icon: const Icon(Icons.cloud_upload_outlined, color: Colors.white, size: 30),
          ),
          const SizedBox(height: 14),
          Text(
            'Send files',
            style: TextStyle(
              fontSize: 22,
              fontWeight: FontWeight.w700,
              letterSpacing: -0.4,
              color: colors.label,
              fontFamilyFallback: CloudPocketTheme.fontFallbacks,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            'Choose files or folders to share.',
            textAlign: TextAlign.center,
            style: TextStyle(
              fontSize: 15,
              color: colors.label2,
              fontFamilyFallback: CloudPocketTheme.fontFallbacks,
            ),
          ),
          const SizedBox(height: 16),
          AppleButton(
            key: widget.shareKey,
            text: itemsCount > 0 ? '$itemsCount files ready · Edit' : 'Choose files',
            isSmall: true,
            onPressed: () {
              Navigator.of(context).push(
                MaterialPageRoute(builder: (_) => const FileSelectorScreen()),
              );
            },
          ),
        ],
      ),
    );
  }
}
