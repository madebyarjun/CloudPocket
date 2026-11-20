import 'package:flutter_riverpod/legacy.dart' show StateProvider;
import 'package:material_ui/material_ui.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter/services.dart';
import 'package:cloud_pocket/providers/settings_provider.dart';
import 'package:cloud_pocket/ui/screens/history_tab.dart';
import 'package:cloud_pocket/ui/screens/home_screen.dart';
import 'package:cloud_pocket/ui/widgets/home_tour.dart';
import 'package:cloud_pocket/providers/server_provider.dart';
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

class _AppShellState extends ConsumerState<AppShell> with TickerProviderStateMixin, WidgetsBindingObserver {
  final _targets = List.generate(6, (_) => GlobalKey());
  final _sendMode = GlobalKey();
  bool _permissionsFinished = false;
  bool _replay = false;
  bool _automatic = false;
  int _step = 0;
  bool _foreground = true;

  @override
  void didChangeAppLifecycleState(AppLifecycleState value) {
    setState(() => _foreground = value == AppLifecycleState.resumed);
  }

  void _closeTour() {
    setState(() {
      _automatic = false;
      _replay = false;
      _step = 0;
    });
  }

  void _replayTour() {
    if (ref.read(serverProvider).isRunning) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Replay the tour after your sharing session ends.')),
      );
      return;
    }
    _handleNavigationTap(0);
    setState(() {
      _replay = true;
      _step = 0;
    });
  }

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
    WidgetsBinding.instance.addObserver(this);
    _foreground = WidgetsBinding.instance.lifecycleState == AppLifecycleState.resumed || WidgetsBinding.instance.lifecycleState == null;
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
    WidgetsBinding.instance.removeObserver(this);
    _fadeController.dispose();
    super.dispose();
  }

  late final List<Widget> _tabs = [
    HomeScreen(
      shareKey: _targets[0],
      reachKey: _targets[1],
      modeKeys: {0: _sendMode, 1: _targets[2], 2: _targets[3]},
      onPermissionsFinished: () => setState(() => _permissionsFinished = true),
    ),
    const ReceivedFilesTab(),
    const TransfersTab(),
    const HistoryTab(),
    SettingsTab(onReplayTour: _replayTour),
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

    final showTour = (_automatic || _replay || settings.isFirstLaunch) &&
        _permissionsFinished && _foreground && currentIndex == 0 &&
        ModalRoute.of(context)?.isCurrent == true && !ref.watch(serverProvider).isRunning;

    return PopScope(
      canPop: !showTour && currentIndex == 0,
      onPopInvokedWithResult: (didPop, _) {
        if (didPop) return;
        if (showTour) {
          _closeTour();
        } else if (currentIndex != 0) {
          _handleNavigationTap(0);
        }
      },
      child: Stack(fit: StackFit.expand, children: [
        ExcludeSemantics(excluding: showTour, child: Scaffold(
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
        bottomNavigationBar: SafeArea(
          top: false,
          child: LayoutBuilder(
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
                          icon: Icon(Icons.schedule_outlined, key: _targets[4]),
                          activeIcon: const Icon(Icons.schedule_rounded),
                          inactiveColor: colors.label2,
                          activeColor: colors.blue,
                        ),
                        NavBarItem(
                          icon: Icon(Icons.settings_outlined, key: _targets[5]),
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
      )),
      if (showTour)
        HomeTour(
          step: _step,
          target: _targets[_step],
          fallback: _step == 0 ? _sendMode : null,
          onShown: () {
            if (settings.isFirstLaunch && !_automatic) {
              setState(() => _automatic = true);
              ref.read(settingsProvider.notifier).completeOnboarding();
            }
          },
          onNext: () => _step == 5 ? _closeTour() : setState(() => _step++),
          onSkip: _closeTour,
        ),
      ]),
    );
  }
}
