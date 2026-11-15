import 'dart:io';
import 'package:flutter/services.dart';
import 'package:permission_handler/permission_handler.dart';

class PermissionService {
  static Future<bool> requestInitialPermissions() async {
    if (!Platform.isAndroid) return true;

    try {
      // 1. Android 13+ Notification Permission (Needed for Foreground Service)
      if (await Permission.notification.isDenied) {
        await Permission.notification.request();
      }

      // 2. Storage Permission: Try Manage External Storage first
      if (!await Permission.manageExternalStorage.isGranted) {
        final status = await Permission.manageExternalStorage.request();
        if (!status.isGranted) {
          // Fallback to media permissions
          await [
            Permission.photos,
            Permission.videos,
            Permission.audio,
            Permission.storage,
          ].request();
        }
      }

      // 3. Ignore Battery Optimizations (To avoid Doze mode dropping sockets)
      if (await Permission.ignoreBatteryOptimizations.isDenied) {
        await Permission.ignoreBatteryOptimizations.request();
      }
    } catch (_) {}

    return true;
  }

  /// Ensures notification permission and battery optimization exemption are requested
  /// so Android does not suspend network sockets when the screen turns off.
  static Future<void> ensureBackgroundExecutionPermissions() async {
    if (!Platform.isAndroid) return;
    try {
      if (await Permission.notification.isDenied) {
        await Permission.notification.request();
      }
      if (await Permission.ignoreBatteryOptimizations.isDenied) {
        await Permission.ignoreBatteryOptimizations.request();
      }
    } catch (_) {}
  }

  static const _wifiLockChannel = MethodChannel('com.cloudpocket.app/wifi_lock');

  static Future<bool> hasStoragePermission() async {
    if (!Platform.isAndroid) return true;
    if (await Permission.manageExternalStorage.isGranted) return true;
    if (await Permission.storage.isGranted) return true;
    // Android 13+ granular media permissions fallback
    final photos = await Permission.photos.isGranted;
    final videos = await Permission.videos.isGranted;
    final audio = await Permission.audio.isGranted;
    return photos || videos || audio;
  }

  static Future<bool> ensureManageExternalStorage() async {
    if (!Platform.isAndroid) return true;
    if (await Permission.manageExternalStorage.isGranted) return true;
    try {
      final status = await Permission.manageExternalStorage.request();
      if (status.isGranted) return true;
      if (status.isPermanentlyDenied) {
        final mediaStatuses = await [
          Permission.photos,
          Permission.videos,
          Permission.audio,
          Permission.storage,
        ].request();
        if (mediaStatuses.values.any((s) => s.isGranted)) {
          return true;
        }
      }
      return status.isGranted;
    } catch (_) {
      return false;
    }
  }

  /// Check if the system has exempted the app from battery optimizations
  static Future<bool> isBatteryOptimizationIgnored() async {
    if (!Platform.isAndroid) return true;
    try {
      final res = await _wifiLockChannel.invokeMethod<bool>('isBatteryOptimizationIgnored');
      if (res != null) return res;
      return await Permission.ignoreBatteryOptimizations.isGranted;
    } catch (_) {
      try {
        return await Permission.ignoreBatteryOptimizations.isGranted;
      } catch (_) {
        return true;
      }
    }
  }

  /// Check if the foreground service is currently running
  static Future<bool> isServiceRunning() async {
    if (!Platform.isAndroid) return false;
    try {
      final res = await _wifiLockChannel.invokeMethod<bool>('isServiceRunning');
      return res ?? false;
    } catch (_) {
      return false;
    }
  }

  /// Check if notifications are enabled
  static Future<bool> isNotificationPermissionGranted() async {
    if (!Platform.isAndroid) return true;
    try {
      final res = await _wifiLockChannel.invokeMethod<bool>('isNotificationPermissionGranted');
      if (res != null) return res;
      return await Permission.notification.isGranted;
    } catch (_) {
      try {
        return await Permission.notification.isGranted;
      } catch (_) {
        return true;
      }
    }
  }

  /// Request notification permission
  static Future<bool> requestNotificationPermission() async {
    if (!Platform.isAndroid) return true;
    try {
      final status = await Permission.notification.request();
      if (status.isPermanentlyDenied) {
        await openAppSettings();
      }
      return status.isGranted;
    } catch (_) {
      return false;
    }
  }

  /// Check if background watchdog alarm is active
  static Future<bool> isWatchdogActive() async {
    if (!Platform.isAndroid) return false;
    try {
      final res = await _wifiLockChannel.invokeMethod<bool>('isWatchdogActive');
      return res ?? false;
    } catch (_) {
      return false;
    }
  }

  /// Enable or disable background watchdog alarm
  static Future<void> setWatchdogActive(bool active) async {
    if (!Platform.isAndroid) return;
    try {
      await _wifiLockChannel.invokeMethod('setWatchdogActive', {'active': active});
    } catch (_) {}
  }

  /// Get OEM-specific explanation based on device manufacturer
  static Future<String> getOemExplanation() async {
    if (!Platform.isAndroid) return 'Allow CloudPocket to run in the background.';
    try {
      final explanation = await _wifiLockChannel.invokeMethod<String>('getOemExplanation');
      return explanation ?? 'Allow CloudPocket to run in the background without battery restrictions.';
    } catch (_) {
      return 'Allow CloudPocket to run in the background without battery restrictions.';
    }
  }

  /// Launch OEM autostart or battery deep link
  static Future<bool> openOemDeepLink() async {
    if (!Platform.isAndroid) return true;
    try {
      final res = await _wifiLockChannel.invokeMethod<bool>('openOemDeepLink');
      return res ?? false;
    } catch (_) {
      return false;
    }
  }

  /// Request system battery optimization exemption dialog
  static Future<bool> requestIgnoreBatteryOptimization() async {
    if (!Platform.isAndroid) return true;
    try {
      final status = await Permission.ignoreBatteryOptimizations.request();
      return status.isGranted;
    } catch (_) {
      return false;
    }
  }

  /// Open device battery optimization or app details settings
  static Future<bool> openBatteryOptimizationSettings() async {
    if (!Platform.isAndroid) return true;
    try {
      await _wifiLockChannel.invokeMethod('openBatterySettings');
      return true;
    } catch (_) {
      return await openAppSettings();
    }
  }

  /// Launch OEM-specific auto-start or background protection management screen
  static Future<bool> openOemAutoStartSettings() async {
    if (!Platform.isAndroid) return true;
    try {
      final res = await _wifiLockChannel.invokeMethod<bool>('openOemAutoStartSettings');
      return res ?? false;
    } catch (_) {
      return false;
    }
  }

  /// Sets window brightness for high-contrast QR display (1.0 = max, -1.0 = system default)
  static Future<void> setScreenBrightness(double brightness) async {
    if (!Platform.isAndroid) return;
    try {
      await _wifiLockChannel.invokeMethod('setScreenBrightness', {'brightness': brightness});
    } catch (_) {}
  }

  /// Copies sensitive text to clipboard (with EXTRA_IS_SENSITIVE on Android 13+) and auto-clears after 60s if unchanged
  static Future<void> copySensitiveClipboard(
    String text, {
    String label = 'CloudPocket',
    bool autoClear = true,
    Duration clearAfter = const Duration(seconds: 60),
  }) async {
    try {
      if (Platform.isAndroid) {
        await _wifiLockChannel.invokeMethod('copySensitiveClipboard', {
          'text': text,
          'label': label,
        });
      } else {
        await Clipboard.setData(ClipboardData(text: text));
      }
      if (autoClear) {
        Future.delayed(clearAfter, () async {
          try {
            final current = await Clipboard.getData(Clipboard.kTextPlain);
            if (current?.text == text) {
              await Clipboard.setData(const ClipboardData(text: ''));
            }
          } catch (_) {}
        });
      }
    } catch (_) {
      await Clipboard.setData(ClipboardData(text: text));
    }
  }
}
