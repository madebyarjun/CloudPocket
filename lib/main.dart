import 'package:flutter/material.dart';
import 'package:flutter_foreground_task/flutter_foreground_task.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:cloud_pocket/providers/settings_provider.dart';
import 'package:cloud_pocket/services/foreground_service.dart';
import 'package:cloud_pocket/ui/app_shell.dart';
import 'package:cloud_pocket/ui/theme.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();

  // Initialize background foreground task settings
  CloudPocketForegroundService.init();

  runApp(
    const ProviderScope(
      child: CloudPocketApp(),
    ),
  );
}

final GlobalKey<ScaffoldMessengerState> rootScaffoldMessengerKey = GlobalKey<ScaffoldMessengerState>();
final GlobalKey<NavigatorState> rootNavigatorKey = GlobalKey<NavigatorState>();

class CloudPocketApp extends ConsumerWidget {
  const CloudPocketApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final settings = ref.watch(settingsProvider);
    final themeMode = settings.themeMode;
    final primaryColor = Color(settings.primaryColorValue);

    return MaterialApp(
      title: 'CloudPocket',
      scaffoldMessengerKey: rootScaffoldMessengerKey,
      navigatorKey: rootNavigatorKey,
      debugShowCheckedModeBanner: false,
      themeMode: themeMode,
      theme: CloudPocketTheme.buildLightTheme(primaryColor),
      darkTheme: CloudPocketTheme.buildDarkTheme(primaryColor),
      home: const WithForegroundTask(
        child: AppShell(),
      ),
    );
  }
}
