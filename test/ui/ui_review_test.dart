import 'dart:io';
import 'dart:convert';
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:cloud_pocket/models/server_state.dart';
import 'package:cloud_pocket/models/share_session.dart';
import 'package:cloud_pocket/models/room_config.dart';
import 'package:cloud_pocket/models/transfer_record.dart';
import 'package:cloud_pocket/providers/network_provider.dart';
import 'package:cloud_pocket/providers/server_provider.dart';
import 'package:cloud_pocket/providers/settings_provider.dart';
import 'package:cloud_pocket/providers/session_provider.dart';
import 'package:cloud_pocket/providers/room_provider.dart';
import 'package:cloud_pocket/providers/transfers_provider.dart';
import 'package:cloud_pocket/providers/received_files_provider.dart';
import 'package:cloud_pocket/ui/screens/settings_tab.dart';
import 'package:cloud_pocket/services/network_monitor.dart';
import 'package:cloud_pocket/ui/screens/disposable_room_setup_screen.dart';
import 'package:cloud_pocket/ui/screens/file_selector_screen.dart';
import 'package:cloud_pocket/ui/screens/onboarding_screen.dart';
import 'package:cloud_pocket/ui/theme.dart';
import 'package:cloud_pocket/ui/app_shell.dart';
import 'package:cloud_pocket/ui/widgets/apple_widgets.dart';
import 'package:cloud_pocket/ui/widgets/sharing_live_view.dart';
import 'package:cloud_pocket/ui/screens/disposable_room_live_view.dart';
import 'package:cloud_pocket/ui/widgets/cloudflare_setup_dialog.dart';
import 'package:cloud_pocket/ui/widgets/custom_bore_dialog.dart';
import 'package:cloud_pocket/ui/widgets/tunnel_guide_dialog.dart';
import 'package:cloud_pocket/ui/widgets/room_media_viewer.dart';
import 'package:cloud_pocket/ui/screens/room_chat_screen.dart';
import 'package:cloud_pocket/server/server_engine.dart';

class _IdleServer extends ServerNotifier {
  final ServerState initial;
  _IdleServer([this.initial = const ServerState()]);
  @override
  ServerState build() => initial;
}

class _ReviewRoom extends RoomNotifier {
  @override
  RoomState build() => const RoomState(status: RoomStatus.live, remainingSeconds: 900);
}

class _ReviewReceived extends ReceivedFilesNotifier {
  @override
  Future<ReceivedFilesState> build() async => const ReceivedFilesState(directoryPath: 'Review receive folder');
}

class _ReviewSettings extends SettingsNotifier {
  @override
  SettingsState build() => const SettingsState(themeMode: ThemeMode.light);
}

void main() {
  const output = String.fromEnvironment('UI_REVIEW_DIR');
  final boundaryKey = GlobalKey();

  setUpAll(() async {
    HttpOverrides.global = null;
    final config = File('.dart_tool/package_config.json');
    final packages = jsonDecode(await config.readAsString())['packages'] as List<dynamic>;
    // Font files come from the selected Flutter SDK, without adding app assets.
    final packagePath = config.absolute.uri.resolve(packages.firstWhere((p) => p['name'] == 'flutter')['rootUri'] as String).toFilePath();
    final fonts = Directory('$packagePath/../../bin/cache/artifacts/material_fonts');
    for (final family in ['Roboto', '.SF Pro Text', 'SF Pro Text', 'SF Pro Display', 'Ahem']) {
      final loader = FontLoader(family)..addFont(Future.value(ByteData.sublistView(await File('${fonts.path}/roboto-regular.ttf').readAsBytes())));
      await loader.load();
    }
    final icons = FontLoader('MaterialIcons')..addFont(Future.value(ByteData.sublistView(await File('${fonts.path}/materialicons-regular.otf').readAsBytes())));
    await icons.load();
    if (output.isNotEmpty && Platform.isWindows) {
      for (final entry in {'monospace': 'consola.ttf', 'Segoe UI': 'seguisym.ttf'}.entries) {
        final font = File('C:/Windows/Fonts/${entry.value}');
        if (await font.exists()) {
          final loader = FontLoader(entry.key)..addFont(Future.value(ByteData.sublistView(await font.readAsBytes())));
          await loader.load();
        }
      }
    }
  });

  Future<void> capture(WidgetTester tester, String name) async {
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 500));
    final error = tester.takeException();
    if (!output.contains('/before')) {
      expect(error, isNull, reason: 'Rendering $name');
    }
    if (output.isEmpty) return;
    final boundary = boundaryKey.currentContext!.findRenderObject()! as RenderRepaintBoundary;
    await tester.runAsync(() async {
      final image = await boundary.toImage(pixelRatio: 2);
      final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
      await Directory(output).create(recursive: true);
      await File('$output/$name.png').writeAsBytes(bytes!.buffer.asUint8List());
      if (error != null) await File('$output/$name-error.txt').writeAsString(error.toString());
      image.dispose();
    });
  }

  Future<void> mount(WidgetTester tester, Widget child, {bool app = false, ServerState server = const ServerState()}) async {
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pumpWidget(ProviderScope(
      overrides: [
        serverProvider.overrideWith(() => _IdleServer(server)),
        settingsProvider.overrideWith(_ReviewSettings.new),
        roomProvider.overrideWith(_ReviewRoom.new),
        receivedFilesProvider.overrideWith(_ReviewReceived.new),
        uploadDirectoryProvider.overrideWith((ref) async => 'Review receive folder'),
        networkStateProvider.overrideWith((ref) => Stream.value(const NetworkInfoState(
          localIp: '192.168.1.42', isWifi: true, isConnected: true,
          allIps: ['192.168.1.42'],
        ))),
      ],
      child: RepaintBoundary(
        key: boundaryKey,
        child: MaterialApp(
          debugShowCheckedModeBanner: false,
          theme: CloudPocketTheme.buildLightTheme().copyWith(
            textTheme: CloudPocketTheme.buildLightTheme().textTheme.apply(fontFamily: 'Roboto'),
            appBarTheme: CloudPocketTheme.buildLightTheme().appBarTheme.copyWith(titleTextStyle: const TextStyle(fontFamily: 'Roboto', fontSize: 17, color: Colors.black)),
          ),
          home: app ? const AppShell() : child,
        ),
      ),
    ));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 500));
  }

  setUp(() {
    SharedPreferences.setMockInitialValues({'cp_setting_is_first_launch': true, 'cp_setting_theme_mode': 'light'});
  });

  testWidgets('Capture redesigned pages and inspect navigation', (tester) async {
    tester.view.physicalSize = const Size(393, 852);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await mount(tester, OnboardingScreen(onGetStarted: () {}));
    await capture(tester, '01-onboarding');
    await mount(tester, const AppShell(), app: true);
    await capture(tester, '02-home-send');
    await tester.tap(find.text('Receive Mode'));
    await capture(tester, '03-home-receive');
    await tester.tap(find.text('Room'));
    await capture(tester, '04-home-room');
    expect(find.text('Disposable room'), findsOneWidget);
    await tester.tap(find.text('1 hr'));
    await tester.pump();
    var container = ProviderScope.containerOf(tester.element(find.byType(AppShell)));
    expect(container.read(sessionProvider).expiryDuration, ExpiryDuration.hour1);
    await tester.tap(find.text('Send Files'));
    await tester.pump();
    await tester.tap(find.byType(AppleToggle).at(1));
    await tester.pump();
    expect(container.read(sessionProvider).maxDownloadsPerFile, 1);
    await tester.tap(find.text('Room'));
    await tester.pump();
    await tester.tap(find.text('Received'));
    await capture(tester, '05-received');
    await tester.tap(find.text('Transfers'));
    await capture(tester, '06-transfers');
    await tester.tap(find.text('History'));
    await capture(tester, '07-history');
    await tester.tap(find.text('Settings'));
    await capture(tester, '08-settings-top');
    await tester.drag(find.byType(SingleChildScrollView).first, const Offset(0, -550));
    await capture(tester, '09-settings-bottom');
    await tester.tap(find.text('Home'));
    await tester.pump(const Duration(milliseconds: 500));
    expect(find.text('Disposable room'), findsOneWidget, reason: 'Tab switches preserve the selected mode');
    await mount(tester, const FileSelectorScreen());
    await capture(tester, '10-file-selector');
    await mount(tester, const DisposableRoomSetupScreen());
    await capture(tester, '11-room-host');
    await tester.tap(find.text('Join Room'));
    await capture(tester, '12-room-join');
    await tester.tap(find.text('Host Room'));
    await tester.pump();
    await tester.tap(find.text('Self-Destruct Timer'));
    await capture(tester, '13-room-timer');
    await mount(tester, const Scaffold(body: SharingLiveView()), server: const ServerState(
      status: ServerStatus.running, localUrl: 'http://192.168.1.42:8080',
      allLocalUrls: ['http://192.168.1.42:8080'],
    ));
    await capture(tester, '14-sharing-live');
    await tester.drag(find.byType(SingleChildScrollView).first, const Offset(0, -500));
    await capture(tester, '15-sharing-actions');
    await mount(tester, const Scaffold(body: SharingLiveView()), server: const ServerState(
      status: ServerStatus.running, localUrl: 'http://192.168.1.42:8080',
      allLocalUrls: ['http://192.168.1.42:8080'], tunnelError: 'Test fixture: provider unavailable',
    ));
    await capture(tester, '16-tunnel-error');
    await mount(tester, const Scaffold(body: DisposableRoomLiveView()), server: const ServerState(
      status: ServerStatus.running, localUrl: 'http://192.168.1.42:8080',
      allLocalUrls: ['http://192.168.1.42:8080'],
    ));
    container = ProviderScope.containerOf(tester.element(find.byType(DisposableRoomLiveView)));
    container.read(sessionProvider.notifier).setIsDisposableRoom(true);
    container.read(sessionProvider.notifier).setRoomConfig(const RoomConfig(roomCode: 'AB-4829', inviteToken: 'synthetic-review-token'));
    await capture(tester, '17-room-live');
    await tester.drag(find.byType(SingleChildScrollView).first, const Offset(0, -450));
    await capture(tester, '18-room-actions');
    await mount(tester, const AppShell(), app: true);
    await tester.tap(find.text('Transfers'));
    await tester.pump(const Duration(milliseconds: 500));
    container = ProviderScope.containerOf(tester.element(find.byType(AppShell)));
    container.read(transfersProvider.notifier).addTransfer(TransferRecord(
      id: 'review.pdf', filename: 'review.pdf', totalBytes: 10000000, transferredBytes: 4500000,
      direction: TransferDirection.upload, status: TransferStatus.active, speedBytesPerSec: 1500000, startTime: DateTime(2026, 10, 28),
    ));
    await capture(tester, '19-transfer-active');
    await mount(tester, const Scaffold(body: SingleChildScrollView(padding: EdgeInsets.all(20), child: CloudflareSetupDialog())));
    await capture(tester, '20-cloudflare-setup');
    await mount(tester, const Scaffold(body: SingleChildScrollView(padding: EdgeInsets.all(20), child: CustomBoreDialog())));
    await capture(tester, '21-bore-setup');
    await mount(tester, const Scaffold(body: TunnelGuideDialog()));
    await capture(tester, '22-tunnel-guide');
    final fixture = await tester.runAsync(() async {
      final directory = await Directory.systemTemp.createTemp('cp_ui_media_');
      final file = File('${directory.path}/review.txt');
      await file.writeAsString('CloudPocket UI review\n\nSynthetic media fixture. No personal data.');
      return file;
    });
    await mount(tester, RoomMediaViewerScreen(filename: 'review.txt', fileSize: 72, category: RoomMediaCategory.text, localFilePath: fixture!.path));
    for (var i = 0; i < 5; i++) {
      await tester.runAsync(() async => Future<void>.delayed(const Duration(milliseconds: 50)));
      await tester.pump();
    }
    await capture(tester, '23-media-text');
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump();
    final engine = await tester.runAsync(() async {
      final server = ServerEngine(
        session: const ShareSession(isDisposableRoom: true, roomConfig: RoomConfig(inviteToken: 'synthetic-review-token', roomCode: 'AB-4829')),
        uploadDir: fixture.parent.path,
      );
      await server.start(preferredPort: 0);
      server.disposableRoom!.chatHub.sendHostMessage('Synthetic review message');
      return server;
    });
    await mount(tester, RoomChatScreen(roomUrl: 'http://127.0.0.1:${engine!.port}/room', initialToken: 'synthetic-review-token', initialNickname: 'Reviewer'));
    for (var i = 0; i < 6; i++) {
      await tester.runAsync(() async => Future<void>.delayed(const Duration(milliseconds: 50)));
      await tester.pump();
    }
    await capture(tester, '24-room-chat');
    expect(find.text('Synthetic review message'), findsOneWidget);
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump();
    await tester.runAsync(engine.stop);
    await tester.runAsync(() async {
      await Future<void>.delayed(const Duration(milliseconds: 100));
      await fixture.parent.delete(recursive: true);
    });
  });
}
