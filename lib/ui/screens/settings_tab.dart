import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:cloud_pocket/providers/server_provider.dart';
import 'package:cloud_pocket/providers/settings_provider.dart';
import 'package:cloud_pocket/services/foreground_service.dart';
import 'package:cloud_pocket/services/permission_service.dart';
import 'package:cloud_pocket/tunnel/tunnel_config.dart';
import 'package:cloud_pocket/ui/theme.dart';
import 'package:cloud_pocket/ui/widgets/apple_widgets.dart';
import 'package:cloud_pocket/ui/widgets/cloudflare_setup_dialog.dart';
import 'package:cloud_pocket/ui/widgets/custom_bore_dialog.dart';
import 'package:cloud_pocket/ui/widgets/log_viewer_dialog.dart';

final uploadDirectoryProvider = FutureProvider.autoDispose<String>((ref) async {
  final settings = ref.watch(settingsProvider);
  return ServerNotifier.resolveUploadDirectory(settings.customUploadDirectory);
});

class SettingsTab extends ConsumerStatefulWidget {
  const SettingsTab({super.key});

  @override
  ConsumerState<SettingsTab> createState() => _SettingsTabState();
}

class _SettingsTabState extends ConsumerState<SettingsTab> with WidgetsBindingObserver {
  bool _serviceRunning = false;
  bool _batteryUnrestricted = false;
  bool _notificationsAllowed = false;
  bool _watchdogActive = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _checkStatuses();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      _checkStatuses();
    }
  }

  Future<void> _checkStatuses() async {
    final srv = await PermissionService.isServiceRunning();
    final bat = await PermissionService.isBatteryOptimizationIgnored();
    final notif = await PermissionService.isNotificationPermissionGranted();
    final watch = await PermissionService.isWatchdogActive();
    if (mounted) {
      setState(() {
        _serviceRunning = srv;
        _batteryUnrestricted = bat;
        _notificationsAllowed = notif;
        _watchdogActive = watch;
      });
    }
  }

  Future<void> _onToggleKeepRunning(bool val) async {
    await ref.read(settingsProvider.notifier).setKeepRunning(val);
    await PermissionService.setWatchdogActive(val);
    if (!val) {
      await CloudPocketForegroundService.releaseLocksIfServiceIdle();
    } else {
      await CloudPocketForegroundService.acquireLocks();
    }
    await _checkStatuses();
  }

  Future<void> _fixService() async {
    if (!_serviceRunning) {
      final srvState = ref.read(serverProvider);
      if (srvState.isRunning) {
        await CloudPocketForegroundService.start(
          title: 'CloudPocket Background Service',
          text: 'Server is active on ${srvState.localUrl}',
        );
      } else {
        if (mounted) {
          AppleToast.show(context, 'Service starts automatically when sharing or receiving files.');
        }
      }
      await _checkStatuses();
    }
  }

  Future<void> _fixAllIssues() async {
    // 1. POST_NOTIFICATIONS
    if (!_notificationsAllowed) {
      await PermissionService.requestNotificationPermission();
    }

    // 2. ACTION_REQUEST_IGNORE_BATTERY_OPTIMIZATIONS
    final batIgnored = await PermissionService.isBatteryOptimizationIgnored();
    if (!batIgnored) {
      await PermissionService.requestIgnoreBatteryOptimization();
    }

    // 3. Only if the device is still restricted, prompt with one-line explanation and open OEM deep link
    final stillRestricted = !await PermissionService.isBatteryOptimizationIgnored();
    if (stillRestricted || !_watchdogActive) {
      final explanation = await PermissionService.getOemExplanation();
      if (mounted) {
        final colors = Theme.of(context).extension<CloudPocketColors>() ?? CloudPocketColors.light;
        final shouldOpen = await AppleDialog.show<bool>(
          context: context,
          title: const Text('Background Protection'),
          content: Text(explanation),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(false),
              child: Text('Cancel', style: TextStyle(color: colors.label2)),
            ),
            TextButton(
              onPressed: () => Navigator.of(context).pop(true),
              child: Text('Open Settings', style: TextStyle(color: colors.blue, fontWeight: FontWeight.bold)),
            ),
          ],
        );

        if (shouldOpen == true) {
          await PermissionService.openOemDeepLink();
        }
      }
    }

    await PermissionService.setWatchdogActive(true);
    await _checkStatuses();
  }

  void _editDeviceName(BuildContext context, String currentName) {
    final controller = TextEditingController(text: currentName);
    final colors = Theme.of(context).extension<CloudPocketColors>() ?? CloudPocketColors.light;

    AppleDialog.show(
      context: context,
      title: const Text('Edit Device Name'),
      content: TextField(
        controller: controller,
        autofocus: true,
        style: TextStyle(color: colors.label),
        decoration: InputDecoration(
          hintText: 'Device Name',
          hintStyle: TextStyle(color: colors.label2),
          filled: true,
          fillColor: colors.fill,
          border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide.none),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: Text('Cancel', style: TextStyle(color: colors.label2)),
        ),
        TextButton(
          onPressed: () {
            final val = controller.text.trim();
            if (val.isNotEmpty) {
              ref.read(settingsProvider.notifier).setDeviceName(val);
            }
            Navigator.of(context).pop();
          },
          child: Text('Save', style: TextStyle(color: colors.blue, fontWeight: FontWeight.bold)),
        ),
      ],
    );
  }

  void _pickUploadDirectory(BuildContext context) async {
    try {
      final selectedDirectory = await FilePicker.platform.getDirectoryPath();
      if (selectedDirectory != null) {
        await ref.read(settingsProvider.notifier).setCustomUploadDirectory(selectedDirectory);
        if (context.mounted) {
          AppleToast.show(context, 'Storage directory updated');
        }
      }
    } catch (_) {}
  }

  Widget _buildStatusTrailing(bool isOk, CloudPocketColors colors) {
    if (isOk) {
      return Icon(Icons.check_rounded, color: colors.green, size: 20);
    }
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(Icons.warning_amber_rounded, color: colors.orange, size: 18),
        const SizedBox(width: 4),
        Text(
          'Fix ›',
          style: TextStyle(
            fontSize: 14,
            fontWeight: FontWeight.w600,
            color: colors.orange,
            fontFamilyFallback: CloudPocketTheme.fontFallbacks,
          ),
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final settings = ref.watch(settingsProvider);
    final colors = Theme.of(context).extension<CloudPocketColors>() ?? CloudPocketColors.light;
    final uploadDirAsync = ref.watch(uploadDirectoryProvider);

    return Scaffold(
      backgroundColor: colors.bg,
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(20, 12, 20, 118),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Top Bar: Settings H1 (.top)
              Text(
                'Settings',
                style: TextStyle(
                  fontSize: 34,
                  fontWeight: FontWeight.w700,
                  letterSpacing: -0.8,
                  height: 1.1,
                  color: colors.label,
                  fontFamilyFallback: CloudPocketTheme.fontFallbacks,
                ),
              ),

              // Caption: Device (.cap)
              _buildCaption('Device', colors),
              AppleGroup(
                margin: EdgeInsets.zero,
                children: [
                  AppleRow(
                    showSeparator: false,
                    title: 'Name',
                    trailing: Text(
                      settings.deviceName,
                      style: TextStyle(
                        fontSize: 15,
                        color: colors.label2,
                        fontFamilyFallback: CloudPocketTheme.fontFallbacks,
                      ),
                    ),
                    onTap: () => _editDeviceName(context, settings.deviceName),
                  ),
                  AppleRow(
                    title: 'Port',
                    trailing: Text(
                      '8080',
                      style: TextStyle(
                        fontSize: 15,
                        color: colors.label2,
                        fontFamilyFallback: CloudPocketTheme.fontFallbacks,
                      ),
                    ),
                  ),
                  AppleRow(
                    title: 'Save Folder',
                    subtitle: uploadDirAsync.value ?? 'Downloads/CloudPocket',
                    trailing: Icon(Icons.folder_open_rounded, size: 18, color: colors.blue),
                    onTap: () => _pickUploadDirectory(context),
                  ),
                ],
              ),

              // Caption: Appearance (.cap)
              _buildCaption('Appearance', colors),
              AppleSegmentedControl<ThemeMode>(
                margin: EdgeInsets.zero,
                values: const [ThemeMode.system, ThemeMode.light, ThemeMode.dark],
                labels: const ['Auto', 'Light', 'Dark'],
                selectedValue: settings.themeMode,
                onValueChanged: (m) => ref.read(settingsProvider.notifier).setThemeMode(m),
              ),

              // Caption: Default reach (.cap)
              _buildCaption('Default reach', colors),
              AppleGroup(
                margin: EdgeInsets.zero,
                children: [
                  AppleRow(
                    showSeparator: false,
                    title: 'Local Wi‑Fi only',
                    trailing: (!settings.defaultEnableTunnel)
                        ? Icon(Icons.check_rounded, color: colors.blue, size: 20)
                        : const SizedBox.shrink(),
                    onTap: () {
                      ref.read(settingsProvider.notifier).setDefaultEnableTunnel(false);
                    },
                  ),
                  AppleRow(
                    title: 'Cloudflare tunnel',
                    trailing: (settings.defaultEnableTunnel && settings.defaultProvider == TunnelProvider.cloudflareQuick)
                        ? Icon(Icons.check_rounded, color: colors.blue, size: 20)
                        : const SizedBox.shrink(),
                    onTap: () {
                      ref.read(settingsProvider.notifier).setDefaultEnableTunnel(true);
                      ref.read(settingsProvider.notifier).setDefaultProvider(TunnelProvider.cloudflareQuick);
                    },
                  ),
                  AppleRow(
                    title: 'Bore relay',
                    trailing: (settings.defaultEnableTunnel && settings.defaultProvider == TunnelProvider.customBore)
                        ? Icon(Icons.check_rounded, color: colors.blue, size: 20)
                        : const SizedBox.shrink(),
                    onTap: () {
                      ref.read(settingsProvider.notifier).setDefaultEnableTunnel(true);
                      ref.read(settingsProvider.notifier).setDefaultProvider(TunnelProvider.customBore);
                      if (settings.customBoreHost == null || settings.customBoreHost!.isEmpty) {
                        CustomBoreDialog.show(context);
                      }
                    },
                  ),
                ],
              ),

              // Caption: Background protection (.cap)
              _buildCaption('Background protection', colors),
              AppleGroup(
                margin: EdgeInsets.zero,
                children: [
                  AppleRow(
                    showSeparator: false,
                    icon: AppleIconTile(
                      backgroundColor: colors.green,
                      icon: const Icon(Icons.bolt_rounded, color: Colors.white, size: 18),
                    ),
                    title: 'Keep running',
                    subtitle: 'Prevent background sleep and connection drops',
                    trailing: AppleToggle(
                      label: 'Keep running',
                      value: settings.keepRunning,
                      onChanged: _onToggleKeepRunning,
                    ),
                  ),
                  AppleRow(
                    icon: AppleIconTile(
                      backgroundColor: _serviceRunning ? colors.green : colors.orange,
                      icon: Icon(_serviceRunning ? Icons.check_circle_rounded : Icons.warning_amber_rounded, color: Colors.white, size: 18),
                    ),
                    title: 'Service running',
                    subtitle: _serviceRunning ? 'Active background service' : 'Idle or stopped',
                    trailing: _buildStatusTrailing(_serviceRunning, colors),
                    onTap: _fixService,
                  ),
                  AppleRow(
                    icon: AppleIconTile(
                      backgroundColor: _batteryUnrestricted ? colors.green : colors.orange,
                      icon: Icon(_batteryUnrestricted ? Icons.check_circle_rounded : Icons.warning_amber_rounded, color: Colors.white, size: 18),
                    ),
                    title: 'Battery unrestricted',
                    subtitle: _batteryUnrestricted ? 'Exempt from power saving' : 'Restricted by system',
                    trailing: _buildStatusTrailing(_batteryUnrestricted, colors),
                    onTap: () async {
                      await PermissionService.requestIgnoreBatteryOptimization();
                      await _checkStatuses();
                    },
                  ),
                  AppleRow(
                    icon: AppleIconTile(
                      backgroundColor: _notificationsAllowed ? colors.green : colors.orange,
                      icon: Icon(_notificationsAllowed ? Icons.check_circle_rounded : Icons.warning_amber_rounded, color: Colors.white, size: 18),
                    ),
                    title: 'Notifications allowed',
                    subtitle: _notificationsAllowed ? 'Notification channel granted' : 'Notifications blocked',
                    trailing: _buildStatusTrailing(_notificationsAllowed, colors),
                    onTap: () async {
                      await PermissionService.requestNotificationPermission();
                      await _checkStatuses();
                    },
                  ),
                  AppleRow(
                    icon: AppleIconTile(
                      backgroundColor: _watchdogActive ? colors.green : colors.orange,
                      icon: Icon(_watchdogActive ? Icons.check_circle_rounded : Icons.warning_amber_rounded, color: Colors.white, size: 18),
                    ),
                    title: 'Watchdog active',
                    subtitle: _watchdogActive ? '5-min keep-alive alarm active' : 'Watchdog inactive',
                    trailing: _buildStatusTrailing(_watchdogActive, colors),
                    onTap: () async {
                      await PermissionService.setWatchdogActive(!_watchdogActive);
                      await _checkStatuses();
                    },
                  ),
                ],
              ),
              Padding(
                padding: const EdgeInsets.only(top: 10),
                child: AppleButton.primary(
                  text: 'Fix all issues',
                  icon: const Icon(Icons.shield_rounded, size: 18, color: Colors.white),
                  onPressed: _fixAllIssues,
                ),
              ),

              // Caption: Diagnostics (.cap)
              _buildCaption('Diagnostics & Advanced', colors),
              AppleGroup(
                margin: EdgeInsets.zero,
                children: [
                  AppleRow(
                    showSeparator: false,
                    icon: AppleIconTile(
                      backgroundColor: colors.blue,
                      icon: const Icon(Icons.terminal_rounded, color: Colors.white, size: 18),
                    ),
                    title: 'System Logs',
                    subtitle: 'Tap to view live in-memory server logs',
                    trailing: Text('›', style: TextStyle(fontSize: 22, color: colors.label2, fontWeight: FontWeight.w300)),
                    onTap: () => LogViewerDialog.show(context),
                  ),
                  AppleRow(
                    icon: AppleIconTile(
                      backgroundColor: colors.orange,
                      icon: const Icon(Icons.cloud_sync_rounded, color: Colors.white, size: 18),
                    ),
                    title: 'Cloudflare Custom Domain',
                    subtitle: settings.isCloudflareConfigured ? settings.cloudflareDomain : 'Not configured',
                    trailing: Text('›', style: TextStyle(fontSize: 22, color: colors.label2, fontWeight: FontWeight.w300)),
                    onTap: () => CloudflareSetupDialog.show(context),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildCaption(String title, CloudPocketColors colors) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 24, 16, 6),
      child: Text(
        title,
        style: TextStyle(
          fontSize: 13,
          color: colors.label2,
          fontFamilyFallback: CloudPocketTheme.fontFallbacks,
        ),
      ),
    );
  }
}
