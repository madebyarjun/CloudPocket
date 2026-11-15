import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter/services.dart';
import 'package:cloud_pocket/providers/server_provider.dart';
import 'package:cloud_pocket/providers/session_provider.dart';
import 'package:cloud_pocket/providers/settings_provider.dart';
import 'package:cloud_pocket/ui/screens/history_tab.dart';
import 'package:cloud_pocket/ui/screens/home_screen.dart';
import 'package:cloud_pocket/ui/screens/onboarding_screen.dart';
import 'package:cloud_pocket/ui/screens/settings_tab.dart';
import 'package:cloud_pocket/ui/screens/transfers_tab.dart';
import 'package:cloud_pocket/ui/screens/received_files_tab.dart';
import 'package:cloud_pocket/ui/theme.dart';
import 'package:cloud_pocket/ui/widgets/log_viewer_dialog.dart';
import 'package:cloud_pocket/ui/widgets/smooth_curved_nav_bar.dart';
import 'package:cloud_pocket/services/sharing_intent_service.dart';

final activeTabProvider = StateProvider<int>((ref) => 0);

class AppShell extends ConsumerStatefulWidget {
  const AppShell({super.key});

  @override
  ConsumerState<AppShell> createState() => _AppShellState();
}

class _AppShellState extends ConsumerState<AppShell> with TickerProviderStateMixin {
  int _settingsTapCount = 0;
  DateTime? _lastSettingsTapTime;
  int _previousIndex = 0;

  // Crossfade controller for page transitions (fade plus 12px rise at 400ms cubic-bezier(.32,.72,0,1))
  late AnimationController _fadeController;
  late Animation<double> _fadeIn;
  late Animation<double> _fadeOut;

  @override
  void initState() {
    super.initState();
    _fadeController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 400),
    );
    _fadeIn = CurvedAnimation(
      parent: _fadeController,
      curve: CloudPocketTheme.appleCurve,
    );
    _fadeOut = CurvedAnimation(
      parent: _fadeController,
      curve: const Interval(0.0, 0.45, curve: Curves.easeIn),
    );
    _fadeController.value = 1.0; // start fully visible

    WidgetsBinding.instance.addPostFrameCallback((_) {
      SharingIntentService.initialize(ref);
    });
  }

  @override
  void dispose() {
    _fadeController.dispose();
    super.dispose();
  }

  final List<Widget> _tabs = const [
    HomeScreen(),
    ReceivedFilesTab(),
    TransfersTab(),
    HistoryTab(),
    SettingsTab(),
  ];

  void _handleNavigationTap(int idx) {
    if (idx == 4) {
      final now = DateTime.now();
      if (_lastSettingsTapTime != null && now.difference(_lastSettingsTapTime!) > const Duration(seconds: 3)) {
        _settingsTapCount = 0;
      }
      _lastSettingsTapTime = now;
      _settingsTapCount++;

      if (_settingsTapCount >= 6) {
        _settingsTapCount = 0;
        HapticFeedback.mediumImpact();
        LogViewerDialog.show(context);
      }
    } else {
      _settingsTapCount = 0;
    }

    final current = ref.read(activeTabProvider);
    if (idx == current) return;

    // Trigger crossfade + rise
    _previousIndex = current;
    _fadeController.value = 0.0;
    ref.read(activeTabProvider.notifier).state = idx;
    _fadeController.forward();
  }

  void _onBarDrag(double localX, double barWidth) {
    if (barWidth <= 0) return;
    final tabIndex = ((localX / barWidth) * _tabs.length).floor().clamp(0, _tabs.length - 1);
    final current = ref.read(activeTabProvider);
    if (tabIndex != current) {
      HapticFeedback.selectionClick();
      _handleNavigationTap(tabIndex);
    }
  }

  @override
  Widget build(BuildContext context) {
    final settings = ref.watch(settingsProvider);
    final currentIndex = ref.watch(activeTabProvider);
    final colors = Theme.of(context).extension<CloudPocketColors>() ?? CloudPocketColors.light;

    final serverState = ref.watch(serverProvider);
    final session = ref.watch(sessionProvider);
    final isDisposableRoomActive = serverState.isRunning && session.isDisposableRoom;

    if (settings.isFirstLaunch) {
      return OnboardingScreen(
        onGetStarted: () {
          ref.read(settingsProvider.notifier).completeOnboarding();
        },
      );
    }

    return WillPopScope(
      onWillPop: () async {
        if (currentIndex != 0) {
          _handleNavigationTap(0);
          return false;
        }
        return true;
      },
      child: Scaffold(
        backgroundColor: colors.bg,
        extendBody: true,
        body: AnimatedBuilder(
          animation: _fadeController,
          builder: (context, _) {
            final isReducedMotion = MediaQuery.of(context).disableAnimations;
            final riseOffset = isReducedMotion ? 0.0 : 12.0 * (1.0 - _fadeIn.value);

            return Stack(
              children: List.generate(_tabs.length, (index) {
                final isCurrent = index == currentIndex;
                final isLeaving = _fadeController.isAnimating && index == _previousIndex;
                return Offstage(
                  offstage: !isCurrent && !isLeaving,
                  child: TickerMode(
                    enabled: isCurrent || isLeaving,
                    child: IgnorePointer(
                      ignoring: !isCurrent,
                      child: Opacity(
                        opacity: !_fadeController.isAnimating ? 1.0
                            : (isCurrent ? _fadeIn.value : 1.0 - _fadeOut.value).clamp(0.0, 1.0),
                        child: Transform.translate(
                          offset: Offset(0, isCurrent && _fadeController.isAnimating ? riseOffset : 0),
                          child: _tabs[index],
                        ),
                      ),
                    ),
                  ),
                );
              }),
            );
          },
        ),
        bottomNavigationBar: isDisposableRoomActive
            ? null
            : LayoutBuilder(
                builder: (context, constraints) {
                  final barWidth = constraints.maxWidth;
                  return GestureDetector(
                    behavior: HitTestBehavior.opaque,
                    onPanStart: (details) {
                      _onBarDrag(details.localPosition.dx, barWidth);
                    },
                    onPanUpdate: (details) {
                      _onBarDrag(details.localPosition.dx, barWidth);
                    },
                    child: AppleFloatingTabBar(
                      currentIndex: currentIndex,
                      barColor: colors.glass,
                      activeButtonColor: colors.blue,
                      backgroundColor: Colors.transparent,
                      onTap: _handleNavigationTap,
                      items: [
                        NavBarItem(
                          icon: const Icon(Icons.home_outlined),
                          activeIcon: const Icon(Icons.home_rounded),
                          inactiveColor: colors.label2,
                          activeColor: colors.blue,
                        ),
                        NavBarItem(
                          icon: const Icon(Icons.folder_shared_outlined),
                          activeIcon: const Icon(Icons.folder_shared_rounded),
                          inactiveColor: colors.label2,
                          activeColor: colors.blue,
                        ),
                        NavBarItem(
                          icon: const Icon(Icons.swap_vert_outlined),
                          activeIcon: const Icon(Icons.swap_vert_rounded),
                          inactiveColor: colors.label2,
                          activeColor: colors.blue,
                        ),
                        NavBarItem(
                          icon: const Icon(Icons.schedule_outlined),
                          activeIcon: const Icon(Icons.schedule_rounded),
                          inactiveColor: colors.label2,
                          activeColor: colors.blue,
                        ),
                        NavBarItem(
                          icon: const Icon(Icons.settings_outlined),
                          activeIcon: const Icon(Icons.settings_rounded),
                          inactiveColor: colors.label2,
                          activeColor: colors.blue,
                        ),
                      ],
                    ),
                  );
                },
              ),
      ),
    );
  }
}
