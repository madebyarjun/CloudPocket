import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:cloud_pocket/ui/theme.dart';

const appleCurve = Cubic(0.32, 0.72, 0.0, 1.0);

/// Floating frosted Apple-style tab bar with 14px inset, radius 30, backdrop blur 24,
/// active tab fill pill, drag-to-scrub, and tactile haptic feedback.
class AppleFloatingTabBar extends StatefulWidget {
  final List<NavBarItem> items;
  final int currentIndex;
  final ValueChanged<int> onTap;
  final Color barColor;
  final Color activeButtonColor;
  final Color backgroundColor;
  final double height;

  const AppleFloatingTabBar({
    super.key,
    required this.items,
    required this.currentIndex,
    required this.onTap,
    required this.barColor,
    required this.activeButtonColor,
    required this.backgroundColor,
    this.height = 68.0,
  });

  @override
  State<AppleFloatingTabBar> createState() => _AppleFloatingTabBarState();
}

class _AppleFloatingTabBarState extends State<AppleFloatingTabBar> {
  int _lastDraggedIndex = -1;

  void _handleDrag(double localX, double totalWidth) {
    if (totalWidth <= 0 || widget.items.isEmpty) return;
    final index = ((localX / totalWidth) * widget.items.length).floor().clamp(0, widget.items.length - 1);
    if (index != _lastDraggedIndex && index != widget.currentIndex) {
      _lastDraggedIndex = index;
      HapticFeedback.selectionClick();
      widget.onTap(index);
    }
  }

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).extension<CloudPocketColors>() ?? CloudPocketColors.light;
    final itemCount = widget.items.length;

    return Padding(
      padding: const EdgeInsets.only(left: 14, right: 14, bottom: 14),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(30),
        child: BackdropFilter(
          filter: ImageFilter.blur(sigmaX: 24, sigmaY: 24),
          child: LayoutBuilder(
            builder: (context, constraints) {
              final barWidth = constraints.maxWidth;
              final usableWidth = barWidth - 12; // account for 6px padding on left/right
              final tabWidth = usableWidth / itemCount;

              return GestureDetector(
                behavior: HitTestBehavior.opaque,
                onHorizontalDragStart: (details) => _handleDrag(details.localPosition.dx, barWidth),
                onHorizontalDragUpdate: (details) => _handleDrag(details.localPosition.dx, barWidth),
                onHorizontalDragEnd: (_) => _lastDraggedIndex = -1,
                onHorizontalDragCancel: () => _lastDraggedIndex = -1,
                child: Container(
                  height: widget.height,
                  padding: const EdgeInsets.all(6),
                  decoration: BoxDecoration(
                    color: colors.glass,
                    borderRadius: BorderRadius.circular(30),
                    border: Border.all(color: colors.sep, width: 0.5),
                    boxShadow: const [
                      BoxShadow(
                        color: Color.fromRGBO(0, 0, 0, 0.16),
                        blurRadius: 34,
                        offset: Offset(0, 10),
                      ),
                    ],
                  ),
                  child: Stack(
                    children: [
                      // Active fill pill
                      AnimatedPositioned(
                        duration: const Duration(milliseconds: 350),
                        curve: appleCurve,
                        left: widget.currentIndex * tabWidth,
                        top: 0,
                        bottom: 0,
                        width: tabWidth,
                        child: Container(
                          decoration: BoxDecoration(
                            color: colors.fill,
                            borderRadius: BorderRadius.circular(24),
                          ),
                        ),
                      ),
                      // Tab buttons row
                      Row(
                        children: List.generate(itemCount, (index) {
                          final item = widget.items[index];
                          final isActive = index == widget.currentIndex;

                          return Expanded(
                            child: GestureDetector(
                              behavior: HitTestBehavior.opaque,
                              onTap: () {
                                HapticFeedback.selectionClick();
                                widget.onTap(index);
                              },
                              child: Container(
                                padding: const EdgeInsets.symmetric(vertical: 6),
                                decoration: BoxDecoration(
                                  borderRadius: BorderRadius.circular(24),
                                ),
                                child: Column(
                                  mainAxisAlignment: MainAxisAlignment.center,
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    IconTheme(
                                      data: IconThemeData(
                                        size: 24,
                                        color: isActive ? colors.blue : colors.label2,
                                      ),
                                      child: isActive ? item.activeIcon : item.icon,
                                    ),
                                    const SizedBox(height: 2),
                                    Text(
                                      _getTabLabel(index),
                                      style: TextStyle(
                                        fontSize: 10,
                                        fontWeight: FontWeight.w600,
                                        color: isActive ? colors.blue : colors.label2,
                                        fontFamilyFallback: CloudPocketTheme.fontFallbacks,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ),
                          );
                        }),
                      ),
                    ],
                  ),
                ),
              );
            },
          ),
        ),
      ),
    );
  }

  String _getTabLabel(int index) {
    switch (index) {
      case 0:
        return 'Home';
      case 1:
        return 'Received';
      case 2:
        return 'Transfers';
      case 3:
        return 'History';
      case 4:
        return 'Settings';
      default:
        return '';
    }
  }
}

/// Data class for a navigation bar item.
class NavBarItem {
  final Widget icon;
  final Widget activeIcon;
  final Color inactiveColor;
  final Color activeColor;

  const NavBarItem({
    required this.icon,
    required this.activeIcon,
    required this.inactiveColor,
    required this.activeColor,
  });
}
