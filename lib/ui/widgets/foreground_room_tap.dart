import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../main.dart';
import '../../providers/server_provider.dart';
import '../../providers/session_provider.dart';
import '../../providers/settings_provider.dart';
import '../../services/cloudpocket_link_builder.dart';
import '../../services/external_link_service.dart';
import '../../services/room_link_detector.dart';
import '../screens/room_chat_screen.dart';

final manualRoomTap = ValueNotifier(false);
const _channel = MethodChannel('cloudpocket/room_tap');

class ForegroundRoomTap extends ConsumerStatefulWidget {
  final Widget child;
  const ForegroundRoomTap({super.key, required this.child});
  @override
  ConsumerState<ForegroundRoomTap> createState() => _ForegroundRoomTapState();
}

class _ForegroundRoomTapState extends ConsumerState<ForegroundRoomTap>
    with WidgetsBindingObserver {
  String? target;
  bool resumed = true, prompted = false, joining = false;
  int generation = 0;
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    manualRoomTap.addListener(refresh);
  }

  @override
  void dispose() {
    generation++;
    manualRoomTap.removeListener(refresh);
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    resumed = state == AppLifecycleState.resumed;
    refresh();
  }

  void refresh() {
    final id = ++generation;
    if (!resumed || manualRoomTap.value || joining) return;
    WidgetsBinding.instance.addPostFrameCallback((_) => arm(id));
    WidgetsBinding.instance.ensureVisualUpdate();
  }

  Future<void> arm(int id) async {
    bool current() => mounted && generation == id;
    if (!current()) return;
    try {
      await _channel.invokeMethod<void>('stop');
      if (!current()) return;
      final url = target;
      if (await _channel
                  .invokeMethod<bool>(url == null ? 'canRead' : 'canHost') !=
              true ||
          !current()) return;
      final enabled = await _channel.invokeMethod<bool>('enabled');
      if (!current()) return;
      final nav = rootNavigatorKey.currentState;
      if (nav == null) return;
      if (enabled != true) {
        if (!mounted || !nav.mounted || prompted) return;
        prompted = true;
        final enable = await promptForNfc(nav);
        if (enable == true && mounted) {
          await _channel.invokeMethod<void>('settings');
        }
        return;
      }
      if (!current() || url == '') return;
      final value = await _channel.invokeMethod<String>(
          url == null ? 'read' : 'host', url);
      if (!current() || value == null) return;
      if (url != null) {
        refresh();
        return;
      }
      final uri = Uri.tryParse(value);
      if (uri == null || !ExternalLinkService.isWebUrl(value)) {
        refresh();
        return;
      }
      joining = true;
      try {
        if (uri.path == '/room') {
          final parsed = RoomLinkDetector.parse(value);
          if (parsed != null) {
            HapticFeedback.lightImpact();
            await nav.push(MaterialPageRoute(
                builder: (_) => RoomChatScreen(
                    roomUrl: parsed.roomUrl,
                    initialToken: parsed.token,
                    initialPin: parsed.pin,
                    initialNickname: ref.read(settingsProvider).deviceName)));
          }
        } else if (uri.path.isEmpty || uri.path == '/') {
          await ExternalLinkService.open(value);
        }
      } finally {
        joining = false;
        if (mounted) refresh();
      }
    } on MissingPluginException {
      return;
    } on PlatformException {
      return;
    }
  }

  Future<bool?> promptForNfc(NavigatorState nav) => showDialog<bool>(
      context: nav.overlay!.context,
      builder: (ctx) => AlertDialog(
            title: const Text('Enable tap to connect?'),
            content: const Text(
                'Turn on NFC to join a nearby CloudPocket host by touching phones.'),
            actions: [
              TextButton(
                  onPressed: () => Navigator.pop(ctx),
                  child: const Text('Later')),
              TextButton(
                  onPressed: () => Navigator.pop(ctx, true),
                  child: const Text('Open settings')),
            ],
          ));

  bool initialized = false;
  @override
  Widget build(BuildContext context) {
    final server = ref.watch(serverProvider);
    final session = ref.watch(sessionProvider);
    final address = session.enableTunnel ? server.tunnelUrl : server.localUrl;
    final next = !server.isRunning
        ? null
        : address == null
            ? ''
            : CloudPocketLinkBuilder.buildUrl(
                interfaceAddress: address,
                session: session,
                mode: session.isDisposableRoom
                    ? SharingLinkMode.roomQr
                    : SharingLinkMode.fileSharing);
    if (!initialized || target != next) {
      initialized = true;
      target = next;
      refresh();
    }
    return widget.child;
  }
}
