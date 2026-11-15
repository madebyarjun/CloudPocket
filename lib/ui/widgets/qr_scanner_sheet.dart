import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:mobile_scanner/mobile_scanner.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:open_filex/open_filex.dart';
import 'package:cloud_pocket/services/cloudpocket_link_builder.dart';
import 'package:cloud_pocket/services/room_link_detector.dart';
import 'package:cloud_pocket/ui/widgets/apple_widgets.dart';

class QrScannerSheet extends StatefulWidget {
  const QrScannerSheet({super.key});

  static Future<ParsedRoomLink?> show(BuildContext context) {
    return Navigator.of(context).push<ParsedRoomLink>(
      MaterialPageRoute(
        builder: (_) => const QrScannerSheet(),
        fullscreenDialog: true,
      ),
    );
  }

  @override
  State<QrScannerSheet> createState() => _QrScannerSheetState();
}

class _QrScannerSheetState extends State<QrScannerSheet> {
  final MobileScannerController _controller = MobileScannerController(
    detectionSpeed: DetectionSpeed.noDuplicates,
    facing: CameraFacing.back,
  );
  bool _hasDetected = false;
  bool _torchOn = false;
  String? _errorMessage;
  Timer? _errorClearTimer;

  @override
  void dispose() {
    _errorClearTimer?.cancel();
    _controller.dispose();
    super.dispose();
  }

  void _showError(String message) {
    _errorClearTimer?.cancel();
    setState(() {
      _errorMessage = message;
    });
    HapticFeedback.vibrate();
    _errorClearTimer = Timer(const Duration(seconds: 4), () {
      if (mounted) setState(() => _errorMessage = null);
    });
  }

  Future<void> _handleScannedText(String raw) async {
    final clean = raw.trim();
    if (clean.isEmpty) return;

    // Check scheme and parse URI
    Uri? uri;
    try {
      uri = Uri.parse(clean);
    } catch (_) {
      _showError('Invalid QR code format');
      return;
    }

    if (uri.scheme != 'http' && uri.scheme != 'https' && uri.scheme != 'cloudpocket') {
      _showError('Invalid scheme: ${uri.scheme}. Expected http or https.');
      return;
    }

    final host = uri.scheme == 'cloudpocket'
        ? (Uri.tryParse(uri.queryParameters['url'] ?? '')?.host ?? '')
        : uri.host;

    if (!CloudPocketLinkBuilder.isValidCloudPocketHost(host)) {
      _showError('Untrusted host: $host. Not a recognized CloudPocket server.');
      return;
    }

    final isRoomLink = clean.contains('/room') || uri.scheme == 'cloudpocket';
    if (isRoomLink) {
      final parsed = RoomLinkDetector.parse(clean);
      if (parsed != null) {
        _hasDetected = true;
        HapticFeedback.mediumImpact();
        Navigator.of(context).pop(parsed);
        return;
      }
    } else {
      // File sharing link: launch in external browser
      _hasDetected = true;
      HapticFeedback.mediumImpact();
      Navigator.of(context).pop();
      try {
        await OpenFilex.open(clean);
      } catch (_) {
        if (mounted) {
          AppleToast.show(context, 'Could not launch file portal in browser');
        }
      }
    }
  }

  void _onDetect(BarcodeCapture capture) {
    if (_hasDetected) return;
    for (final barcode in capture.barcodes) {
      final raw = barcode.rawValue;
      if (raw != null && raw.isNotEmpty) {
        _handleScannedText(raw);
        return;
      }
    }
  }

  Future<void> _pasteLinkFallback() async {
    final data = await Clipboard.getData(Clipboard.kTextPlain);
    final text = data?.text?.trim();
    if (text == null || text.isEmpty) {
      _showError('Clipboard is empty');
      return;
    }
    await _handleScannedText(text);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      body: Stack(
        children: [
          // Camera stream
          MobileScanner(
            controller: _controller,
            onDetect: _onDetect,
            errorBuilder: (context, error, child) {
              return Center(
                child: Padding(
                  padding: const EdgeInsets.all(24.0),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Icon(Icons.videocam_off_rounded, size: 54, color: Color(0xFFEF4444)),
                      const SizedBox(height: 16),
                      const Text(
                        'Camera Permission Required',
                        style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: Colors.white),
                      ),
                      const SizedBox(height: 8),
                      const Text(
                        'CloudPocket needs camera access to scan room QR codes. Please allow permission in system settings.',
                        textAlign: TextAlign.center,
                        style: TextStyle(fontSize: 13, color: Colors.white70),
                      ),
                      const SizedBox(height: 20),
                      FilledButton(
                        onPressed: () => openAppSettings(),
                        child: const Text('Open App Settings'),
                      ),
                      const SizedBox(height: 12),
                      TextButton.icon(
                        icon: const Icon(Icons.content_paste_rounded, color: Colors.white70, size: 18),
                        label: const Text('Paste link from clipboard', style: TextStyle(color: Colors.white70)),
                        onPressed: _pasteLinkFallback,
                      ),
                    ],
                  ),
                ),
              );
            },
          ),

          // Dark vignette overlay with square scan cutout
          Positioned.fill(
            child: IgnorePointer(
              child: Container(
                decoration: BoxDecoration(
                  color: Colors.black.withOpacity(0.4),
                ),
              ),
            ),
          ),

          // Centered Scan Reticle Target
          Center(
            child: Container(
              width: 260,
              height: 260,
              decoration: BoxDecoration(
                border: Border.all(color: const Color(0xFF38BDF8), width: 2.5),
                borderRadius: BorderRadius.circular(20),
                boxShadow: [
                  BoxShadow(
                    color: const Color(0xFF38BDF8).withOpacity(0.2),
                    blurRadius: 16,
                    spreadRadius: 2,
                  ),
                ],
              ),
              child: Stack(
                children: [
                  Positioned(
                    top: 10,
                    left: 10,
                    child: Container(width: 20, height: 2, color: Colors.white),
                  ),
                  Positioned(
                    top: 10,
                    left: 10,
                    child: Container(width: 2, height: 20, color: Colors.white),
                  ),
                  Positioned(
                    top: 10,
                    right: 10,
                    child: Container(width: 20, height: 2, color: Colors.white),
                  ),
                  Positioned(
                    top: 10,
                    right: 10,
                    child: Container(width: 2, height: 20, color: Colors.white),
                  ),
                  Positioned(
                    bottom: 10,
                    left: 10,
                    child: Container(width: 20, height: 2, color: Colors.white),
                  ),
                  Positioned(
                    bottom: 10,
                    left: 10,
                    child: Container(width: 2, height: 20, color: Colors.white),
                  ),
                  Positioned(
                    bottom: 10,
                    right: 10,
                    child: Container(width: 20, height: 2, color: Colors.white),
                  ),
                  Positioned(
                    bottom: 10,
                    right: 10,
                    child: Container(width: 2, height: 20, color: Colors.white),
                  ),
                ],
              ),
            ),
          ),

          // Inline Error Banner
          if (_errorMessage != null)
            Positioned(
              top: 100,
              left: 20,
              right: 20,
              child: SafeArea(
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                  decoration: BoxDecoration(
                    color: const Color(0xFFDC2626).withOpacity(0.92),
                    borderRadius: BorderRadius.circular(14),
                    boxShadow: const [
                      BoxShadow(color: Colors.black45, blurRadius: 10, offset: Offset(0, 4)),
                    ],
                  ),
                  child: Row(
                    children: [
                      const Icon(Icons.warning_amber_rounded, color: Colors.white, size: 20),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Text(
                          _errorMessage!,
                          style: const TextStyle(fontSize: 13, color: Colors.white, fontWeight: FontWeight.w600),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),

          // Top Header Bar
          Positioned(
            top: 0,
            left: 0,
            right: 0,
            child: SafeArea(
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    IconButton(
                      icon: const Icon(Icons.close_rounded, color: Colors.white, size: 28),
                      onPressed: () => Navigator.of(context).pop(),
                    ),
                    const Text(
                      'Scan CloudPocket QR',
                      style: TextStyle(
                        fontSize: 17,
                        fontWeight: FontWeight.bold,
                        color: Colors.white,
                      ),
                    ),
                    Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        IconButton(
                          icon: const Icon(Icons.content_paste_rounded, color: Colors.white, size: 22),
                          tooltip: 'Paste link',
                          onPressed: _pasteLinkFallback,
                        ),
                        IconButton(
                          icon: Icon(
                            _torchOn ? Icons.flash_on_rounded : Icons.flash_off_rounded,
                            color: _torchOn ? const Color(0xFFF59E0B) : Colors.white,
                            size: 24,
                          ),
                          onPressed: () async {
                            HapticFeedback.selectionClick();
                            await _controller.toggleTorch();
                            setState(() {
                              _torchOn = !_torchOn;
                            });
                          },
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
          ),

          // Bottom Prompt
          Positioned(
            bottom: 40,
            left: 24,
            right: 24,
            child: SafeArea(
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                decoration: BoxDecoration(
                  color: const Color(0xFF1C1C1E).withOpacity(0.85),
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(color: Colors.white12),
                ),
                child: const Row(
                  children: [
                    Icon(Icons.qr_code_scanner_rounded, color: Color(0xFF0A84FF), size: 22),
                    SizedBox(width: 12),
                    Expanded(
                      child: Text(
                        'Point camera at CloudPocket QR code or tap paste to connect',
                        style: TextStyle(fontSize: 12.5, color: Colors.white70),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
