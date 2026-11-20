import 'dart:io';
import 'package:flutter/services.dart';
import 'package:flutter_foreground_task/flutter_foreground_task.dart';

class CloudPocketForegroundService {
  static const MethodChannel _wifiLockChannel = MethodChannel('com.cloudpocket.app/wifi_lock');
  static DateTime? _lastNotificationUpdateTime;
  static String? _lastNotificationText;

  static void init() {
    if (!Platform.isAndroid) return;

    FlutterForegroundTask.init(
      androidNotificationOptions: AndroidNotificationOptions(
        channelId: 'cloud_pocket_server_v2',
        channelName: 'CloudPocket Background Service',
        channelDescription: 'Maintains personal file server in the background.',
        channelImportance: NotificationChannelImportance.LOW,
        priority: NotificationPriority.LOW,
      ),
      iosNotificationOptions: const IOSNotificationOptions(),
      foregroundTaskOptions: ForegroundTaskOptions(
        eventAction: ForegroundTaskEventAction.repeat(5000),
        autoRunOnBoot: false,
        allowWakeLock: true,
        allowWifiLock: true,
      ),
    );
  }

  static Future<void> acquireLocks() async {
    if (!Platform.isAndroid) return;
    try {
      await _wifiLockChannel.invokeMethod('acquireWifiLock');
      await _wifiLockChannel.invokeMethod('acquireMulticastLock');
      await _wifiLockChannel.invokeMethod('acquireWakeLock');
    } catch (_) {}
  }

  static Future<void> releaseLocksIfServiceIdle() async {
    if (!Platform.isAndroid) return;
    try {
      if (!await FlutterForegroundTask.isRunningService) {
        await _wifiLockChannel.invokeMethod('releaseWifiLock');
        await _wifiLockChannel.invokeMethod('releaseMulticastLock');
        await _wifiLockChannel.invokeMethod('releaseWakeLock');
      }
    } catch (_) {}
  }

  static Future<void> start({
    required String title,
    required String text,
  }) async {
    if (!Platform.isAndroid) return;

    _lastNotificationUpdateTime = DateTime.now();
    _lastNotificationText = text;

    // Acquire native WifiLock, MulticastLock & CPU WakeLock
    await acquireLocks();

    if (await FlutterForegroundTask.isRunningService) {
      try {
        await _wifiLockChannel.invokeMethod('updateForegroundNotification', {
          'title': title,
          'text': text,
        });
      } catch (_) {}
      return;
    }

    await FlutterForegroundTask.startService(
      notificationTitle: title,
      notificationText: text,
      notificationButtons: const [NotificationButton(id: 'stop_button', text: 'Stop')],
      callback: startCallback,
    );
  }

  static Future<void> updateNotification({
    required String title,
    required String text,
    bool force = false,
  }) async {
    if (!Platform.isAndroid) return;

    final now = DateTime.now();
    if (!force) {
      if (_lastNotificationText == text) return;
      if (_lastNotificationUpdateTime != null &&
          now.difference(_lastNotificationUpdateTime!) < const Duration(seconds: 5)) {
        return;
      }
    }

    _lastNotificationUpdateTime = now;
    _lastNotificationText = text;

    // Re-assert CPU & Wi-Fi locks and update notification via NotificationManager
    // without triggering ForegroundService.releaseLockMode() in flutter_foreground_task
    await acquireLocks();
    try {
      await _wifiLockChannel.invokeMethod('updateForegroundNotification', {
        'title': title,
        'text': text,
      });
    } catch (_) {}
  }

  static Future<void> stop() async {
    if (!Platform.isAndroid) return;

    try {
      await _wifiLockChannel.invokeMethod('releaseWifiLock');
      await _wifiLockChannel.invokeMethod('releaseMulticastLock');
      await _wifiLockChannel.invokeMethod('releaseWakeLock');
    } catch (_) {}

    if (await FlutterForegroundTask.isRunningService) {
      await FlutterForegroundTask.stopService();
    }
  }
}

@pragma('vm:entry-point')
void startCallback() {
  FlutterForegroundTask.setTaskHandler(CloudPocketTaskHandler());
}

class CloudPocketTaskHandler extends TaskHandler {
  @override
  Future<void> onStart(DateTime timestamp, TaskStarter starter) async {}

  @override
  void onRepeatEvent(DateTime timestamp) {}

  @override
  void onNotificationButtonPressed(String id) {
    if (id == 'stop_button') {
      CloudPocketForegroundService.stop();
    }
  }

  @override
  Future<void> onDestroy(DateTime timestamp, bool isTimeout) async {}
}
