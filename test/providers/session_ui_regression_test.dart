import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:cloud_pocket/providers/session_provider.dart';
import 'package:cloud_pocket/models/room_config.dart';

void main() {
  test('Entering room setup preserves an explicitly selected local connection', () {
    SharedPreferences.setMockInitialValues({});
    final container = ProviderContainer();
    addTearDown(container.dispose);
    final notifier = container.read(sessionProvider.notifier);
    notifier.setEnableTunnel(false);
    notifier.setIsDisposableRoom(true);
    expect(container.read(sessionProvider).enableTunnel, isFalse);
    expect(container.read(sessionProvider).roomConfig!.enableTunnel, isFalse);
  });

  test('PIN protection without configured key material fails closed', () {
    expect(const RoomConfig(requirePin: true).verifyPin('anything'), isFalse);
  });
}
