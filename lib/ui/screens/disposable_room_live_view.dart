import 'package:cloud_pocket/ui/widgets/room_tap_button.dart';
import 'dart:async';
import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:pretty_qr_code/pretty_qr_code.dart';
import 'package:share_plus/share_plus.dart';
import 'package:cloud_pocket/providers/room_provider.dart';
import 'package:cloud_pocket/providers/server_provider.dart';
import 'package:cloud_pocket/providers/session_provider.dart';
import 'package:cloud_pocket/services/cloudpocket_link_builder.dart';
import 'package:cloud_pocket/services/permission_service.dart';
import 'package:cloud_pocket/ui/screens/room_chat_screen.dart';
import 'package:cloud_pocket/ui/theme.dart';
import 'package:cloud_pocket/ui/widgets/apple_widgets.dart';
import 'package:cloud_pocket/ui/widgets/cp_sheet.dart';

class DisposableRoomLiveView extends ConsumerStatefulWidget {
  const DisposableRoomLiveView({super.key});

  @override
  ConsumerState<DisposableRoomLiveView> createState() => _DisposableRoomLiveViewState();
}

class _DisposableRoomLiveViewState extends ConsumerState<DisposableRoomLiveView> with WidgetsBindingObserver {
  static const MethodChannel _securityChannel = MethodChannel('com.cloudpocket.app/security');

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _enableSecureMode();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      _enableSecureMode();
    }
  }

  Future<void> _enableSecureMode() async {
    try {
      await _securityChannel.invokeMethod('enableSecureMode', identityHashCode(this).toString());
    } catch (_) {}
  }

  Future<void> _disableSecureMode() async {
    try {
      await _securityChannel.invokeMethod('disableSecureMode', identityHashCode(this).toString());
    } catch (_) {}
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _disableSecureMode();
    super.dispose();
  }

  Future<void> _confirmBurnRoom() async {
    final colors = Theme.of(context).extension<CloudPocketColors>() ?? CloudPocketColors.light;

    final shouldBurn = await AppleDialog.show<bool>(
      context: context,
      title: const Text('End and Erase Room?'),
      content: const Text(
        'This will immediately disconnect all participants and wipe all messages from memory.\n\nThis action cannot be undone.',
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(false),
          child: Text('Cancel', style: TextStyle(color: colors.label2)),
        ),
        TextButton(
          onPressed: () => Navigator.of(context).pop(true),
          child: Text('Erase Room', style: TextStyle(color: colors.red, fontWeight: FontWeight.bold)),
        ),
      ],
    );

    if (shouldBurn == true && mounted) {
      await ref.read(roomProvider.notifier).burnRoomNow();
      if (!mounted) return;
      AppleToast.show(context, 'Room ended. A new one is ready.');
    }
  }

  String _formatCountdown(int seconds) {
    final m = seconds ~/ 60;
    final s = seconds % 60;
    return '${m.toString().padLeft(2, '0')}:${s.toString().padLeft(2, '0')}';
  }

  void _showRoomQrSheet({
    required BuildContext context,
    required String inviteUrl,
    required String inPersonQrUrl,
    required String roomCode,
    required String roomPin,
    required String? rawPin,
  }) {
    CpSheet.show(
      context: context,
      builder: (ctx) {
        final colors = Theme.of(ctx).extension<CloudPocketColors>() ?? CloudPocketColors.light;
        return Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            CpHeader(
              icon: Icons.qr_code_2_rounded,
              iconColor: Colors.white,
              iconBg: colors.blue,
              title: 'Room invite',
              description: 'In-person guests can scan the QR code to join directly. Remote guests need the invite link.',
            ),
            GestureDetector(
              onTap: () async {
                await PermissionService.setScreenBrightness(1.0);
                if (!context.mounted) return;
                await showDialog(
                  context: context,
                  barrierColor: Colors.black.withOpacity(0.92),
                  builder: (diagCtx) => Dialog(
                    backgroundColor: Colors.transparent,
                    insetPadding: const EdgeInsets.all(20),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Container(
                          width: 300,
                          height: 300,
                          padding: const EdgeInsets.all(20),
                          decoration: BoxDecoration(
                            color: Colors.white,
                            borderRadius: BorderRadius.circular(28),
                          ),
                          child: PrettyQrView.data(
                            data: inPersonQrUrl,
                            errorCorrectLevel: QrErrorCorrectLevel.M,
                            decoration: const PrettyQrDecoration(
                              quietZone: PrettyQrQuietZone.modules(4),
                              shape: PrettyQrSmoothSymbol(
                                color: Colors.black,
                                roundFactor: 0.15,
                              ),
                            ),
                          ),
                        ),
                        const SizedBox(height: 20),
                        AppleButton.gray(
                          text: 'Close',
                          isSmall: true,
                          onPressed: () => Navigator.of(diagCtx).pop(),
                        ),
                      ],
                    ),
                  ),
                );
                await PermissionService.setScreenBrightness(-1.0);
              },
              child: Center(
                child: Container(
                  width: 220,
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(CloudPocketTheme.radiusCard),
                    boxShadow: colors.shadow,
                  ),
                  child: PrettyQrView.data(
                    data: inPersonQrUrl,
                    errorCorrectLevel: QrErrorCorrectLevel.M,
                    decoration: const PrettyQrDecoration(
                      quietZone: PrettyQrQuietZone.modules(4),
                      shape: PrettyQrSmoothSymbol(
                        color: Colors.black,
                        roundFactor: 0.15,
                      ),
                    ),
                  ),
                ),
              ),
            ),
            const SizedBox(height: 14),
            SelectableText(
              inviteUrl,
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w500,
                color: colors.label2,
                fontFeatures: const [FontFeature.tabularFigures()],
                fontFamilyFallback: CloudPocketTheme.fontFallbacks,
              ),
            ),
            const SizedBox(height: 18),
            CpButton(
              text: 'Share invite link',
              onPressed: () {
                Share.share(
                  'Connect to CloudPocket Room:\n$inviteUrl',
                  subject: 'CloudPocket Ephemeral Room Invite',
                );
              },
            ),
            RoomTapButton(invite: inPersonQrUrl),
            if (rawPin != null && rawPin.isNotEmpty) ...[
              const SizedBox(height: 10),
              CpButton(
                text: 'Share PIN separately',
                isSecondary: true,
                onPressed: () {
                  Share.share(
                    'CloudPocket Room PIN: $rawPin\n(Send the PIN in a different message)',
                    subject: 'CloudPocket Room PIN',
                  );
                },
              ),
              const SizedBox(height: 4),
              Center(
                child: Text(
                  'Send the PIN in a different message for extra security',
                  style: TextStyle(fontSize: 11, color: colors.label2),
                ),
              ),
            ],
            const SizedBox(height: 10),
            CpButton(
              text: 'Copy invite link',
              isSecondary: true,
              onPressed: () {
                PermissionService.copySensitiveClipboard(inviteUrl, label: 'Room Invite Link', autoClear: true);
                Navigator.pop(ctx);
                AppleToast.show(context, 'Invite link copied! Auto-clears in 60s.');
              },
            ),
            const SizedBox(height: 10),
            CpButton(
              text: 'Regenerate invite link',
              isSecondary: true,
              onPressed: () {
                ref.read(sessionProvider.notifier).regenerateInviteToken();
                Navigator.pop(ctx);
                AppleToast.show(context, 'New 128-bit invite link generated');
              },
            ),
          ],
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).extension<CloudPocketColors>() ?? CloudPocketColors.light;
    final roomState = ref.watch(roomProvider);
    final session = ref.watch(sessionProvider);
    final serverState = ref.watch(serverProvider);

    final remainingSec = roomState.remainingSeconds;
    final totalDurationSec = session.expiryDuration.duration?.inSeconds ?? 900;
    final progress = totalDurationSec > 0 ? (remainingSec / totalDurationSec) : 1.0;
    final timeStr = _formatCountdown(remainingSec);

    final roomCode = session.roomConfig?.roomCode.isNotEmpty == true ? session.roomConfig!.roomCode : 'NX-7204';
    final roomPin = session.password ?? (session.roomConfig?.pinHash != null ? '****' : 'None');
    final rawPin = session.password;
    final peerCount = roomState.participantCount;
    final peopleCount = peerCount + 1; // including host

    final currentUrl = serverState.localUrl ?? 'http://127.0.0.1:8080';
    final baseUrl = session.enableTunnel ? serverState.tunnelUrl : serverState.localUrl;
    final inviteReady = baseUrl != null && baseUrl.isNotEmpty;
    final inviteStatus = serverState.tunnelError ?? 'Waiting for share address…';
    final inviteUrl = !inviteReady ? '' : CloudPocketLinkBuilder.buildUrl(
      interfaceAddress: baseUrl,
      mode: SharingLinkMode.roomInvite,
      session: session,
    );
    final inPersonQrUrl = !inviteReady ? '' : CloudPocketLinkBuilder.buildUrl(
      interfaceAddress: baseUrl,
      mode: SharingLinkMode.roomQr,
      session: session,
      isRoomActive: roomState.status == RoomStatus.live,
    );

    return Scaffold(
      backgroundColor: colors.bg,
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(20, 12, 20, 118),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Top Bar: Disposable sub + Room H1 + Encrypted Pill (.top)
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Disposable',
                        style: TextStyle(
                          fontSize: 15,
                          fontWeight: FontWeight.w600,
                          color: colors.label2,
                          fontFamilyFallback: CloudPocketTheme.fontFallbacks,
                        ),
                      ),
                      Text(
                        'Room',
                        style: TextStyle(
                          fontSize: 34,
                          fontWeight: FontWeight.w700,
                          letterSpacing: -0.8,
                          height: 1.1,
                          color: colors.label,
                          fontFamilyFallback: CloudPocketTheme.fontFallbacks,
                        ),
                      ),
                    ],
                  ),
                  const ApplePill(
                    text: 'Temporary',
                    leading: PulsingDot(size: 8),
                  ),
                ],
              ),
              const SizedBox(height: 16),

              // Countdown Ring Card (.card)
              Container(
                width: double.infinity,
                padding: const EdgeInsets.symmetric(vertical: 22, horizontal: 16),
                decoration: BoxDecoration(
                  color: colors.card,
                  borderRadius: BorderRadius.circular(CloudPocketTheme.radiusCard),
                  boxShadow: colors.shadow,
                ),
                alignment: Alignment.center,
                child: CountdownRing(
                  timeString: timeStr,
                  progress: progress,
                ),
              ),
              const SizedBox(height: 14),

              // Room code and PIN Group (.grp)
              AppleGroup(
                margin: EdgeInsets.zero,
                children: [
                  AppleRow(
                    title: 'Room code',
                    subtitle: session.roomConfig?.requirePin == true
                        ? 'Join with this code and the room PIN'
                        : 'Enable a PIN for Chat ID joins; otherwise use the invite link',
                    trailing: Text(
                      roomCode,
                      style: TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.w700,
                        fontFeatures: const [FontFeature.tabularFigures()],
                        letterSpacing: 0.5,
                        color: colors.label,
                        fontFamilyFallback: CloudPocketTheme.fontFallbacks,
                      ),
                    ),
                    showSeparator: false,
                    onTap: () {
                      PermissionService.copySensitiveClipboard(roomCode, label: 'Room Code', autoClear: true);
                      HapticFeedback.selectionClick();
                      AppleToast.show(context, 'Room code copied (auto-clears in 60s)');
                    },
                  ),
                  AppleRow(
                    title: 'PIN',
                    trailing: Text(
                      roomPin,
                      style: TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.w700,
                        fontFeatures: const [FontFeature.tabularFigures()],
                        letterSpacing: 2.0,
                        color: colors.label,
                        fontFamilyFallback: CloudPocketTheme.fontFallbacks,
                      ),
                    ),
                    onTap: () {
                      PermissionService.copySensitiveClipboard(roomPin, label: 'Room PIN', autoClear: true);
                      HapticFeedback.selectionClick();
                      AppleToast.show(context, 'PIN copied (auto-clears in 60s)');
                    },
                  ),
                ],
              ),

              // People caption (.cap)
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 24, 16, 6),
                child: Text(
                  '$peopleCount ${peopleCount == 1 ? "person" : "people"} here',
                  style: TextStyle(
                    fontSize: 13,
                    color: colors.label2,
                    fontFamilyFallback: CloudPocketTheme.fontFallbacks,
                  ),
                ),
              ),

              // Peers Group (.grp)
              AppleGroup(
                margin: EdgeInsets.zero,
                children: [
                  // Host Row
                  AppleRow(
                    showSeparator: false,
                    icon: AppleIconTile(
                      backgroundColor: colors.blue,
                      text: 'You',
                    ),
                    title: 'Host',
                    trailing: const PulsingDot(size: 8),
                  ),
                  // Connected peers
                  ...List.generate(peerCount, (index) {
                    final peerColors = [
                      const Color(0xFF5856D6),
                      colors.orange,
                      const Color(0xFFFF375F),
                      colors.green,
                    ];
                    final tileColor = peerColors[index % peerColors.length];
                    final isSecure = index < roomState.secureParticipants;
                    final label = isSecure ? 'CloudPocket App' : 'Web Browser';

                    return AppleRow(
                      icon: AppleIconTile(
                        backgroundColor: tileColor,
                        text: 'P${index + 1}',
                      ),
                      title: 'Guest ${index + 1}',
                      subtitle: label,
                      trailing: const PulsingDot(size: 8),
                    );
                  }),
                ],
              ),
              const SizedBox(height: 22),

              // Share Invite Link & QR button
              AppleButton.gray(
                text: inviteReady ? 'Invite' : inviteStatus,
                icon: const Icon(Icons.qr_code_2_rounded, size: 18),
                onPressed: !inviteReady ? null : () => _showRoomQrSheet(
                  context: context,
                  inviteUrl: inviteUrl,
                  inPersonQrUrl: inPersonQrUrl,
                  roomCode: roomCode,
                  roomPin: roomPin,
                  rawPin: rawPin,
                ),
              ),
              const SizedBox(height: 10),

              // Open Chat button (.btn)
              AppleButton.primary(
                text: 'Open Chat',
                onPressed: () {
                  Navigator.of(context).push(
                    MaterialPageRoute(
                      builder: (_) => RoomChatScreen(
                        roomUrl: currentUrl,
                        initialPin: session.password,
                        initialToken: session.roomConfig?.inviteToken,
                        initialNickname: 'Host',
                      ),
                    ),
                  ).then((_) { if (mounted) _enableSecureMode(); });
                },
              ),
              const SizedBox(height: 10),

              // End and Erase Room button (.btn .gray red)
              AppleButton.gray(
                text: 'End and Erase Room',
                textColor: colors.red,
                onPressed: _confirmBurnRoom,
              ),
            ],
          ),
        ),
      ),
    );
  }
}
