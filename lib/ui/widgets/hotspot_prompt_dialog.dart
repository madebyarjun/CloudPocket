import 'package:material_ui/material_ui.dart';
import 'package:flutter/services.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:cloud_pocket/ui/theme.dart';
import 'package:cloud_pocket/ui/widgets/apple_widgets.dart';

class HotspotPromptDialog {
  HotspotPromptDialog._();

  static const _platform = MethodChannel('com.cloudpocket.app/wifi_lock');

  static Future<void> openHotspotSettings() async {
    try {
      await _platform.invokeMethod('openHotspotSettings');
    } catch (_) {
      openAppSettings();
    }
  }

  static Future<void> show(
    BuildContext context, {
    VoidCallback? onContinue,
  }) {
    final colors = Theme.of(context).extension<CloudPocketColors>() ?? CloudPocketColors.light;

    return AppleDialog.show(
      context: context,
      title: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.wifi_tethering_rounded, size: 22, color: colors.orange),
          const SizedBox(width: 8),
          const Text('Turn On Mobile Hotspot'),
        ],
      ),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Cloudflare Quick Tunnel operates most reliably on Android when your Mobile Hotspot is turned ON.\n\n'
            'You can simply toggle Hotspot from your phone\'s top pull-down control center / quick settings, or tap below to open Hotspot Settings.',
            style: TextStyle(color: colors.label, fontSize: 14, height: 1.4),
          ),
          const SizedBox(height: 12),
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: colors.fill,
              borderRadius: BorderRadius.circular(10),
            ),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(Icons.info_outline_rounded, size: 18, color: colors.blue),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    'No other device needs to connect to your hotspot. Just having it turned on prevents mobile carrier port 53 blocking.',
                    style: TextStyle(color: colors.label2, fontSize: 12, height: 1.3),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
      actions: [
        TextButton.icon(
          icon: Icon(Icons.wifi_tethering_rounded, size: 16, color: colors.blue),
          label: Text('Hotspot Settings', style: TextStyle(color: colors.blue)),
          onPressed: openHotspotSettings,
        ),
        TextButton(
          onPressed: () {
            Navigator.of(context).pop();
            onContinue?.call();
          },
          child: Text('Got It', style: TextStyle(color: colors.blue, fontWeight: FontWeight.bold)),
        ),
      ],
    );
  }
}
