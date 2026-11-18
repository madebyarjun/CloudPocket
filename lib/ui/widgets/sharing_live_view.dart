import 'dart:async';
import 'dart:io';
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path_provider/path_provider.dart';
import 'package:pretty_qr_code/pretty_qr_code.dart';
import 'package:share_plus/share_plus.dart';
import 'package:cloud_pocket/services/external_link_service.dart';
import 'package:cloud_pocket/models/server_state.dart';
import 'package:cloud_pocket/providers/server_provider.dart';
import 'package:cloud_pocket/providers/session_provider.dart';
import 'package:cloud_pocket/providers/stats_provider.dart';
import 'package:cloud_pocket/services/cloudpocket_link_builder.dart';
import 'package:cloud_pocket/services/permission_service.dart';
import 'package:cloud_pocket/ui/theme.dart';
import 'package:cloud_pocket/ui/widgets/apple_widgets.dart';

enum SharingInterfaceChip { wifi, hotspot, tunnel }

/// Live Sharing bottom sheet panel matching /design/cloudpocket.html
class SharingLiveView extends ConsumerStatefulWidget {
  const SharingLiveView({super.key});

  @override
  ConsumerState<SharingLiveView> createState() => _SharingLiveViewState();
}

class _SharingLiveViewState extends ConsumerState<SharingLiveView> with SingleTickerProviderStateMixin {
  late AnimationController _slideController;
  late Animation<double> _slideAnimation;
  final GlobalKey _qrKey = GlobalKey();
  SharingInterfaceChip _selectedChip = SharingInterfaceChip.wifi;

  @override
  void initState() {
    super.initState();
    if (ref.read(sessionProvider).enableTunnel) _selectedChip = SharingInterfaceChip.tunnel;
    _slideController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 600),
    );
    _slideAnimation = CurvedAnimation(
      parent: _slideController,
      curve: appleCurve,
    );
    _slideController.forward();
  }

  @override
  void dispose() {
    _slideController.dispose();
    super.dispose();
  }

  String _getActiveUrl() {
    final serverState = ref.watch(serverProvider);
    final session = ref.watch(sessionProvider);
    final allIps = serverState.allLocalUrls;
    final categorized = CloudPocketLinkBuilder.filterAndSortIps(allIps);

    String rawTarget = '';
    switch (_selectedChip) {
      case SharingInterfaceChip.tunnel:
        if (serverState.tunnelUrl != null && serverState.tunnelUrl!.isNotEmpty) {
          rawTarget = serverState.tunnelUrl!;
        }
        break;
      case SharingInterfaceChip.hotspot:
        if (categorized.hotspotIps.isNotEmpty) {
          rawTarget = categorized.hotspotIps.first;
        }
        break;
      case SharingInterfaceChip.wifi:
        if (serverState.localUrl != null && serverState.localUrl!.isNotEmpty) {
          rawTarget = serverState.localUrl!;
        } else if (categorized.wifiIps.isNotEmpty) {
          rawTarget = categorized.wifiIps.first;
        }
        break;
    }

    if (rawTarget.isEmpty && _selectedChip != SharingInterfaceChip.tunnel) {
      if (serverState.localUrl != null && serverState.localUrl!.isNotEmpty) {
        rawTarget = serverState.localUrl!;
      } else if (allIps.isNotEmpty) {
        rawTarget = allIps.first;
      }
    }

    if (rawTarget.isEmpty) return '';

    return CloudPocketLinkBuilder.buildUrl(
      interfaceAddress: rawTarget,
      mode: session.isDisposableRoom ? SharingLinkMode.roomInvite : SharingLinkMode.fileSharing,
      session: session,
    );
  }

  Future<void> _shareQrCode(String url) async {
    if (url.isEmpty) return;
    File? tempFile;
    try {
      final qrCode = QrCode.fromData(
        data: url,
        errorCorrectLevel: QrErrorCorrectLevel.M,
      );
      final qrImage = QrImage(qrCode);
      final byteData = await qrImage.toImageAsBytes(
        size: 1024,
        format: ui.ImageByteFormat.png,
        decoration: const PrettyQrDecoration(
          background: Colors.white,
          quietZone: PrettyQrQuietZone.modules(4),
          shape: PrettyQrSmoothSymbol(
            color: Colors.black,
            roundFactor: 0.15,
          ),
        ),
      );

      Uint8List bytes;
      if (byteData != null) {
        bytes = byteData.buffer.asUint8List();
      } else {
        final boundary = _qrKey.currentContext?.findRenderObject() as RenderRepaintBoundary?;
        if (boundary == null) return;
        final image = await boundary.toImage(pixelRatio: 3.0);
        final fallbackData = await image.toByteData(format: ui.ImageByteFormat.png);
        if (fallbackData == null) return;
        bytes = fallbackData.buffer.asUint8List();
      }

      final tempDir = await getTemporaryDirectory();
      tempFile = File('${tempDir.path}/cloudpocket_qr_${DateTime.now().millisecondsSinceEpoch}.png');
      await tempFile.writeAsBytes(bytes);

      await Share.shareXFiles(
        [XFile(tempFile.path)],
        text: 'Connect to CloudPocket: $url',
        subject: 'CloudPocket Share Link',
      );
    } catch (_) {
      if (mounted) {
        AppleToast.show(context, 'Could not share QR code');
      }
    } finally {
      if (tempFile != null && await tempFile.exists()) {
        try {
          await tempFile.delete();
        } catch (_) {}
      }
    }
  }

  void _openFullscreenQr(String url) async {
    if (url.isEmpty) return;
    await PermissionService.setScreenBrightness(1.0);
    if (!mounted) return;
    await showDialog(
      context: context,
      barrierColor: Colors.black.withOpacity(0.92),
      builder: (ctx) {
        return Dialog(
          backgroundColor: Colors.transparent,
          insetPadding: const EdgeInsets.all(20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 320,
                height: 320,
                padding: const EdgeInsets.all(24),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(28),
                ),
                child: PrettyQrView.data(
                  data: url,
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
              const SizedBox(height: 16),
              SelectableText(
                url,
                textAlign: TextAlign.center,
                style: const TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                  color: Colors.white,
                  fontFeatures: [ui.FontFeature.tabularFigures()],
                ),
              ),
              const SizedBox(height: 20),
              AppleButton.gray(
                text: 'Close',
                isSmall: true,
                onPressed: () => Navigator.of(ctx).pop(),
              ),
            ],
          ),
        );
      },
    );
    await PermissionService.setScreenBrightness(-1.0);
  }

  Future<void> _confirmStopSharing() async {
    final session = ref.read(sessionProvider);
    final isReceive = session.isReceiveMode;

    await _slideController.reverse();
    ref.read(serverProvider.notifier).stopServer();
    if (mounted) {
      AppleToast.show(context, isReceive ? 'Receiving stopped' : 'Sharing stopped');
    }
  }

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).extension<CloudPocketColors>() ?? CloudPocketColors.light;
    final serverState = ref.watch(serverProvider);
    final session = ref.watch(sessionProvider);
    final stats = ref.watch(statsProvider);
    final isReceive = session.isReceiveMode;

    final currentUrl = _getActiveUrl();
    final allIps = serverState.allLocalUrls;
    final categorized = CloudPocketLinkBuilder.filterAndSortIps(allIps);
    final hasWifi = categorized.wifiIps.isNotEmpty;
    final hasHotspot = categorized.hotspotIps.isNotEmpty;
    final showTunnel = session.enableTunnel ||
        serverState.tunnelUrl != null ||
        serverState.isTunnelConnecting ||
        serverState.tunnelError != null;

    final hasUsableNetwork = hasWifi || hasHotspot || (serverState.tunnelUrl != null && serverState.tunnelUrl!.isNotEmpty);

    final isTunnelSelected = _selectedChip == SharingInterfaceChip.tunnel;
    final isTunnelConnecting = isTunnelSelected && currentUrl.isEmpty && serverState.tunnelError == null;
    final isTunnelFailed = isTunnelSelected && serverState.tunnelError != null;

    final activeSpeedMb = (stats.bandwidthBytesPerSec / (1024 * 1024)).toStringAsFixed(1);
    final totalMb = isReceive
        ? (stats.totalBytesReceived / (1024 * 1024)).toStringAsFixed(0)
        : (stats.totalBytesSent / (1024 * 1024)).toStringAsFixed(0);

    return Scaffold(
      backgroundColor: Colors.transparent,
      body: Stack(
        children: [
          // Dim backdrop (purely decorative; tapping it never stops server by accident)
          AnimatedBuilder(
            animation: _slideAnimation,
            builder: (context, child) {
              return Container(
                color: Colors.black.withOpacity(0.4 * _slideAnimation.value),
              );
            },
          ),
          // Bottom sheet panel (.sheet .pn)
          AnimatedBuilder(
            animation: _slideAnimation,
            builder: (context, child) {
              return Transform.translate(
                offset: Offset(0, (1.0 - _slideAnimation.value) * MediaQuery.of(context).size.height),
                child: child,
              );
            },
            child: Align(
              alignment: Alignment.bottomCenter,
              child: Container(
                constraints: BoxConstraints(
                  maxHeight: MediaQuery.of(context).size.height * 0.92,
                ),
                decoration: BoxDecoration(
                  color: colors.bg,
                  borderRadius: const BorderRadius.vertical(top: Radius.circular(30)),
                  boxShadow: const [
                    BoxShadow(
                      color: Color.fromRGBO(0, 0, 0, 0.25),
                      blurRadius: 40,
                      offset: Offset(0, -10),
                    ),
                  ],
                ),
                child: SafeArea(
                  top: false,
                  child: SingleChildScrollView(
                    padding: const EdgeInsets.fromLTRB(20, 10, 20, 26),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        // Grabber (.grab)
                        Container(
                          width: 38,
                          height: 5,
                          margin: const EdgeInsets.only(bottom: 14),
                          decoration: BoxDecoration(
                            color: colors.sep,
                            borderRadius: BorderRadius.circular(3),
                          ),
                        ),
                        // Top header row
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          crossAxisAlignment: CrossAxisAlignment.center,
                          children: [
                            Text(
                              isReceive ? 'Receiving' : 'Sharing',
                              style: TextStyle(
                                fontSize: 22,
                                fontWeight: FontWeight.w700,
                                letterSpacing: -0.4,
                                color: colors.label,
                                fontFamilyFallback: CloudPocketTheme.fontFallbacks,
                              ),
                            ),
                            const ApplePill(
                              text: 'Online',
                              leading: PulsingDot(size: 8),
                            ),
                          ],
                        ),
                        const SizedBox(height: 16),

                        // QR Card / Network State / Tunnel Connecting
                        if (!hasUsableNetwork && !isTunnelSelected) ...[
                          Container(
                            width: 236,
                            height: 236,
                            padding: const EdgeInsets.all(20),
                            decoration: BoxDecoration(
                              color: colors.card,
                              borderRadius: BorderRadius.circular(CloudPocketTheme.radiusCard),
                              border: Border.all(color: colors.sep),
                              boxShadow: colors.shadow,
                            ),
                            child: Column(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                Icon(Icons.wifi_off_rounded, size: 48, color: colors.orange),
                                const SizedBox(height: 12),
                                Text(
                                  'No Network Available',
                                  textAlign: TextAlign.center,
                                  style: TextStyle(
                                    fontSize: 15,
                                    fontWeight: FontWeight.w600,
                                    color: colors.label,
                                  ),
                                ),
                                const SizedBox(height: 6),
                                Text(
                                  'Connect to Wi-Fi or turn on hotspot to share',
                                  textAlign: TextAlign.center,
                                  style: TextStyle(
                                    fontSize: 12,
                                    color: colors.label2,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ] else if (isTunnelConnecting) ...[
                          Container(
                            width: 236,
                            height: 236,
                            padding: const EdgeInsets.all(20),
                            decoration: BoxDecoration(
                              color: colors.card,
                              borderRadius: BorderRadius.circular(CloudPocketTheme.radiusCard),
                              border: Border.all(color: colors.blue.withOpacity(0.3)),
                              boxShadow: colors.shadow,
                            ),
                            child: Column(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                SizedBox(
                                  width: 36,
                                  height: 36,
                                  child: CircularProgressIndicator(
                                    strokeWidth: 3,
                                    color: colors.blue,
                                  ),
                                ),
                                const SizedBox(height: 16),
                                Text(
                                  'Allocating Tunnel...',
                                  textAlign: TextAlign.center,
                                  style: TextStyle(
                                    fontSize: 15,
                                    fontWeight: FontWeight.w600,
                                    color: colors.label,
                                  ),
                                ),
                                const SizedBox(height: 6),
                                Text(
                                  'Connecting to public edge relay',
                                  textAlign: TextAlign.center,
                                  style: TextStyle(
                                    fontSize: 12,
                                    color: colors.label2,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ] else if (isTunnelFailed) ...[
                          Container(
                            width: 236,
                            height: 236,
                            padding: const EdgeInsets.all(20),
                            decoration: BoxDecoration(
                              color: colors.card,
                              borderRadius: BorderRadius.circular(CloudPocketTheme.radiusCard),
                              border: Border.all(color: colors.red.withOpacity(0.4)),
                              boxShadow: colors.shadow,
                            ),
                            child: Column(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                Icon(Icons.error_outline_rounded, size: 42, color: colors.red),
                                const SizedBox(height: 10),
                                Text(
                                  'Tunnel Allocation Failed',
                                  textAlign: TextAlign.center,
                                  style: TextStyle(
                                    fontSize: 14,
                                    fontWeight: FontWeight.w600,
                                    color: colors.label,
                                  ),
                                ),
                                const SizedBox(height: 12),
                                AppleButton.primary(
                                  text: 'Retry Tunnel',
                                  isSmall: true,
                                  onPressed: () {
                                    ref.read(serverProvider.notifier).toggleTunnel(true);
                                    AppleToast.show(context, 'Retrying tunnel...');
                                  },
                                ),
                              ],
                            ),
                          ),
                        ] else ...[
                          GestureDetector(
                            onTap: () => _openFullscreenQr(currentUrl),
                            child: Semantics(
                              label: 'CloudPocket connection QR code. Tap to expand fullscreen.',
                              child: Container(
                                width: 236,
                                padding: const EdgeInsets.all(20),
                                decoration: BoxDecoration(
                                  color: Colors.white,
                                  borderRadius: BorderRadius.circular(CloudPocketTheme.radiusCard),
                                  boxShadow: colors.shadow,
                                ),
                                child: RepaintBoundary(
                                  key: _qrKey,
                                  child: PrettyQrView.data(
                                    data: currentUrl,
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
                          ),
                        ],
                        const SizedBox(height: 12),

                        // URL text (.sub)
                        SelectableText(
                          currentUrl.isNotEmpty ? currentUrl : 'No active address',
                          textAlign: TextAlign.center,
                          style: TextStyle(
                            fontSize: 14.5,
                            fontWeight: FontWeight.w500,
                            color: colors.label2,
                            fontFeatures: const [ui.FontFeature.tabularFigures()],
                            fontFamilyFallback: CloudPocketTheme.fontFallbacks,
                          ),
                        ),
                        const SizedBox(height: 16),

                        // Address chips (.chips)
                        SingleChildScrollView(
                          scrollDirection: Axis.horizontal,
                          child: Row(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              if (hasWifi) ...[
                                _buildChip(SharingInterfaceChip.wifi, 'Wi‑Fi', colors),
                              ],
                              if (hasHotspot) ...[
                                if (hasWifi) const SizedBox(width: 8),
                                _buildChip(SharingInterfaceChip.hotspot, 'Hotspot', colors),
                              ],
                              if (showTunnel) ...[
                                if (hasWifi || hasHotspot) const SizedBox(width: 8),
                                _buildTunnelChip(colors, serverState),
                              ],
                            ],
                          ),
                        ),

                        ExpansionTile(title: const Text('Connection details'), children: [
                        if (allIps.length > 1) ...[
                          const SizedBox(height: 12),
                          Text(
                            'Available addresses',
                            style: TextStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.w600,
                              color: colors.label2,
                              fontFamilyFallback: CloudPocketTheme.fontFallbacks,
                            ),
                          ),
                          const SizedBox(height: 8),
                          Wrap(
                            spacing: 8,
                            runSpacing: 6,
                            alignment: WrapAlignment.center,
                            children: allIps.map((ipUrl) {
                              final cleanText = ipUrl.replaceFirst('http://', '').replaceFirst('https://', '');
                              final isSelected = (serverState.localUrl == ipUrl && _selectedChip == SharingInterfaceChip.wifi);
                              return GestureDetector(
                                onTap: () {
                                  ref.read(serverProvider.notifier).setLocalUrl(ipUrl);
                                  setState(() => _selectedChip = SharingInterfaceChip.wifi);
                                },
                                child: Container(
                                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                                  decoration: BoxDecoration(
                                    color: isSelected ? colors.blue.withOpacity(0.15) : colors.card,
                                    borderRadius: BorderRadius.circular(12),
                                    border: Border.all(
                                      color: isSelected ? colors.blue : colors.sep,
                                      width: 1,
                                    ),
                                  ),
                                  child: Text(
                                    cleanText,
                                    style: TextStyle(
                                      fontSize: 12,
                                      fontWeight: isSelected ? FontWeight.w600 : FontWeight.w400,
                                      color: isSelected ? colors.blue : colors.label,
                                    ),
                                  ),
                                ),
                              );
                            }).toList(),
                          ),
                        ],

                        const SizedBox(height: 12),
                        Container(
                          padding: const EdgeInsets.all(12),
                          decoration: BoxDecoration(
                            color: colors.card,
                            borderRadius: BorderRadius.circular(14),
                            boxShadow: colors.shadow,
                          ),
                          child: Row(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Icon(Icons.laptop_chromebook_rounded, size: 20, color: colors.blue),
                              const SizedBox(width: 10),
                              Expanded(
                                child: Text(
                                  'Connecting from laptop? Type http:// in the address bar. Globe icon is normal for offline sharing.',
                                  style: TextStyle(
                                    fontSize: 12,
                                    color: colors.label2,
                                    fontFamilyFallback: CloudPocketTheme.fontFallbacks,
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(height: 16),

                        ]),
                        // Actions row (Copy, Share, Open)
                        Row(
                          children: [
                            Expanded(
                              child: AppleButton.gray(
                                text: 'Copy',
                                isSmall: true,
                                onPressed: currentUrl.isNotEmpty
                                    ? () {
                                        PermissionService.copySensitiveClipboard(currentUrl, label: 'CloudPocket Share URL', autoClear: false);
                                        HapticFeedback.selectionClick();
                                        AppleToast.show(context, 'Link copied');
                                      }
                                    : null,
                              ),
                            ),
                            const SizedBox(width: 8),
                            Expanded(
                              child: AppleButton.primary(
                                text: 'Share link',
                                isSmall: true,
                                onPressed: currentUrl.isNotEmpty
                                    ? () {
                                        _shareQrCode(currentUrl);
                                      }
                                    : null,
                              ),
                            ),
                            const SizedBox(width: 8),
                            Expanded(
                              child: AppleButton.gray(
                                text: 'Open',
                                isSmall: true,
                                onPressed: currentUrl.isNotEmpty
                                    ? () async {
                                        try {
                                          final opened = await ExternalLinkService.open(currentUrl);
                                          if (!opened && mounted) {
                                            AppleToast.show(context, 'Could not open browser');
                                          }
                                        } catch (_) {
                                          if (mounted) {
                                            AppleToast.show(context, 'Could not open browser');
                                          }
                                        }
                                      }
                                    : null,
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 16),

                        // Stats card (.stats)
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 16),
                          decoration: BoxDecoration(
                            color: colors.card,
                            borderRadius: BorderRadius.circular(20),
                            boxShadow: colors.shadow,
                          ),
                          child: Row(
                            children: [
                              Expanded(
                                child: Column(
                                  children: [
                                    Text(
                                      '${stats.activeConnections}',
                                      style: TextStyle(
                                        fontSize: 22,
                                        fontWeight: FontWeight.w700,
                                        color: colors.label,
                                        fontFamilyFallback: CloudPocketTheme.fontFallbacks,
                                      ),
                                    ),
                                    Text(
                                      'People',
                                      style: TextStyle(
                                        fontSize: 12,
                                        color: colors.label2,
                                        fontFamilyFallback: CloudPocketTheme.fontFallbacks,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                              Expanded(
                                child: Column(
                                  children: [
                                    Text(
                                      activeSpeedMb,
                                      style: TextStyle(
                                        fontSize: 22,
                                        fontWeight: FontWeight.w700,
                                        color: colors.label,
                                        fontFamilyFallback: CloudPocketTheme.fontFallbacks,
                                      ),
                                    ),
                                    Text(
                                      'MB/s',
                                      style: TextStyle(
                                        fontSize: 12,
                                        color: colors.label2,
                                        fontFamilyFallback: CloudPocketTheme.fontFallbacks,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                              Expanded(
                                child: Column(
                                  children: [
                                    Text(
                                      totalMb,
                                      style: TextStyle(
                                        fontSize: 22,
                                        fontWeight: FontWeight.w700,
                                        color: colors.label,
                                        fontFamilyFallback: CloudPocketTheme.fontFallbacks,
                                      ),
                                    ),
                                    Text(
                                      isReceive ? 'MB recv' : 'MB sent',
                                      style: TextStyle(
                                        fontSize: 12,
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
                        const SizedBox(height: 16),

                        // Red Stop button (.btn .red)
                        AppleButton.red(
                          text: isReceive ? 'Stop Receiving' : 'Stop Sharing',
                          onPressed: _confirmStopSharing,
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildChip(SharingInterfaceChip chip, String label, CloudPocketColors colors) {
    final isSelected = _selectedChip == chip;

    return GestureDetector(
      onTap: () {
        HapticFeedback.selectionClick();
        setState(() => _selectedChip = chip);
      },
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 300),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
        decoration: BoxDecoration(
          color: isSelected ? colors.blue : colors.fill,
          borderRadius: BorderRadius.circular(18),
        ),
        child: Text(
          label,
          style: TextStyle(
            fontSize: 13,
            fontWeight: FontWeight.w600,
            color: isSelected ? Colors.white : colors.label,
            fontFamilyFallback: CloudPocketTheme.fontFallbacks,
          ),
        ),
      ),
    );
  }

  Widget _buildTunnelChip(CloudPocketColors colors, ServerState serverState) {
    final isSelected = _selectedChip == SharingInterfaceChip.tunnel;
    final isConnecting = serverState.isTunnelConnecting;
    final hasError = serverState.tunnelError != null;

    return GestureDetector(
      onTap: () {
        HapticFeedback.selectionClick();
        if (hasError) {
          ref.read(serverProvider.notifier).toggleTunnel(true);
          AppleToast.show(context, 'Retrying tunnel...');
        } else {
          setState(() => _selectedChip = SharingInterfaceChip.tunnel);
        }
      },
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 300),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
        decoration: BoxDecoration(
          color: hasError
              ? colors.red.withOpacity(0.15)
              : (isSelected ? colors.blue : colors.fill),
          borderRadius: BorderRadius.circular(18),
          border: hasError ? Border.all(color: colors.red.withOpacity(0.5)) : null,
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (isConnecting) ...[
              SizedBox(
                width: 12,
                height: 12,
                child: CircularProgressIndicator(
                  strokeWidth: 2,
                  color: isSelected ? Colors.white : colors.blue,
                ),
              ),
              const SizedBox(width: 6),
              Text(
                'Tunnel (Connecting...)',
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                  color: isSelected ? Colors.white : colors.label,
                  fontFamilyFallback: CloudPocketTheme.fontFallbacks,
                ),
              ),
            ] else if (hasError) ...[
              Icon(Icons.warning_amber_rounded, size: 14, color: colors.red),
              const SizedBox(width: 6),
              Text(
                'Tunnel (Failed) · Retry',
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                  color: colors.red,
                  fontFamilyFallback: CloudPocketTheme.fontFallbacks,
                ),
              ),
            ] else ...[
              Text(
                'Tunnel',
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                  color: isSelected ? Colors.white : colors.label,
                  fontFamilyFallback: CloudPocketTheme.fontFallbacks,
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
