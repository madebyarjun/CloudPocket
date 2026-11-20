import 'foreground_room_tap.dart';
import 'package:material_ui/material_ui.dart';
import 'package:flutter/services.dart';

const _nfc = MethodChannel('cloudpocket/room_tap');

class RoomTapButton extends StatefulWidget {
  final String? invite;
  final ValueChanged<String>? onInvite;
  const RoomTapButton({super.key, this.invite, this.onInvite});

  @override
  State<RoomTapButton> createState() => _RoomTapButtonState();
}

class _RoomTapButtonState extends State<RoomTapButton> {
  late final Future<bool> supported = _available();

  Future<bool> _available() async {
    try {
      return await _nfc.invokeMethod<bool>(
              widget.invite == null ? 'canRead' : 'canHost') ??
          false;
    } on MissingPluginException {
      return false;
    } on PlatformException {
      return false;
    }
  }

  @override
  Widget build(BuildContext context) => FutureBuilder<bool>(
        future: supported,
        builder: (context, snapshot) => snapshot.data != true
            ? const SizedBox.shrink()
            : TextButton.icon(
                icon: const Icon(Icons.nfc_rounded),
                label: Text(widget.invite == null
                    ? 'Join with NFC'
                    : 'Invite with NFC'),
                onPressed: () async {
                  manualRoomTap.value = true;
                  final value = await showModalBottomSheet<String>(
                      context: context,
                      builder: (_) => _RoomTapSheet(invite: widget.invite));
                  if (mounted && value != null && value.isNotEmpty) {
                    widget.onInvite?.call(value);
                  }
                },
              ),
      );
}

class _RoomTapSheet extends StatefulWidget {
  final String? invite;
  const _RoomTapSheet({this.invite});
  @override
  State<_RoomTapSheet> createState() => _RoomTapSheetState();
}

class _RoomTapSheetState extends State<_RoomTapSheet>
    with SingleTickerProviderStateMixin {
  late final pulse = AnimationController(
      vsync: this, duration: const Duration(milliseconds: 1500));
  String? error;
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      if (!mounted) return;
      try {
        final value = await _nfc.invokeMethod<String>(
            widget.invite == null ? 'read' : 'host', widget.invite);
        if (!mounted) return;
        if (ModalRoute.of(context)?.isCurrent != true) return;
        if (value != null) HapticFeedback.lightImpact();
        Navigator.pop(context, value);
      } on PlatformException catch (e) {
        if (mounted) {
          setState(() => error = e.message ?? 'Use the room QR code.');
        }
      }
    });
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (MediaQuery.of(context).disableAnimations) {
      pulse.stop();
    } else if (!pulse.isAnimating) {
      pulse.repeat(reverse: true);
    }
  }

  @override
  void dispose() {
    _nfc
        .invokeMethod<void>('stop')
        .whenComplete(() => manualRoomTap.value = false);
    pulse.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => SafeArea(
          child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          ScaleTransition(
              scale: Tween(begin: 1.0, end: 1.12).animate(pulse),
              child: Icon(Icons.contactless_outlined,
                  size: 52, color: Theme.of(context).colorScheme.primary)),
          const SizedBox(height: 12),
          Text('Hold phones back to back',
              style: Theme.of(context).textTheme.titleLarge),
          const SizedBox(height: 8),
          Text(
              error ??
                  (widget.invite == null
                      ? 'Ask the host to open Invite with NFC.'
                      : 'Ask the other person to open Join with NFC.'),
              textAlign: TextAlign.center),
          TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Close')),
        ]),
      ));
}
