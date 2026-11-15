import 'dart:io';
import 'package:flutter/services.dart';

class ExternalLinkService {
  static const _channel = MethodChannel('com.cloudpocket.app/wifi_lock');
  static bool isWebUrl(String value) {
    final uri = Uri.tryParse(value);
    return uri != null && const {'http', 'https'}.contains(uri.scheme) && uri.host.isNotEmpty && uri.userInfo.isEmpty;
  }
  static Future<bool> open(String value) async {
    if (!isWebUrl(value) || !Platform.isAndroid) return false;
    try {
      return await _channel.invokeMethod<bool>('openExternalUrl', {'url': value}) ?? false;
    } on PlatformException {
      return false;
    } on MissingPluginException {
      return false;
    }
  }
}
