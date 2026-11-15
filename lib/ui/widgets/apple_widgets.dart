import 'dart:async';
import 'dart:io';
import 'dart:math';
import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:cloud_pocket/ui/theme.dart';

const appleCurve = Cubic(0.32, 0.72, 0.0, 1.0);

/// Grouped inset card container (.grp)
class AppleGroup extends StatelessWidget {
  final List<Widget> children;
  final EdgeInsetsGeometry margin;

  const AppleGroup({
    super.key,
    required this.children,
    this.margin = const EdgeInsets.only(top: 6),
  });

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).extension<CloudPocketColors>() ?? CloudPocketColors.light;

    return Container(
      margin: margin,
      decoration: BoxDecoration(
        color: colors.card,
        borderRadius: BorderRadius.circular(CloudPocketTheme.radiusGroup),
        boxShadow: colors.shadow,
      ),
      clipBehavior: Clip.antiAlias,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: children,
      ),
    );
  }
}

/// Inset row for AppleGroup (.row)
class AppleRow extends StatefulWidget {
  final Widget? icon;
  final String title;
  final String? subtitle;
  final Widget? trailing;
  final VoidCallback? onTap;
  final bool showSeparator;
  final double minHeight;

  const AppleRow({
    super.key,
    this.icon,
    required this.title,
    this.subtitle,
    this.trailing,
    this.onTap,
    this.showSeparator = true,
    this.minHeight = 52.0,
  });

  @override
  State<AppleRow> createState() => _AppleRowState();
}

class _AppleRowState extends State<AppleRow> {
  bool _isPressed = false;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).extension<CloudPocketColors>() ?? CloudPocketColors.light;

    final content = AnimatedContainer(
      duration: const Duration(milliseconds: 150),
      color: _isPressed && widget.onTap != null ? colors.fill : Colors.transparent,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 11),
      constraints: BoxConstraints(minHeight: widget.minHeight),
      child: Row(
        children: [
          if (widget.icon != null) ...[
            widget.icon!,
            const SizedBox(width: 12),
          ],
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  widget.title,
                  style: TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w400,
                    color: colors.label,
                    fontFamilyFallback: CloudPocketTheme.fontFallbacks,
                  ),
                ),
                if (widget.subtitle != null) ...[
                  const SizedBox(height: 2),
                  Text(
                    widget.subtitle!,
                    style: TextStyle(
                      fontSize: 13,
                      color: colors.label2,
                      fontFamilyFallback: CloudPocketTheme.fontFallbacks,
                    ),
                  ),
                ],
              ],
            ),
          ),
          if (widget.trailing != null) ...[
            const SizedBox(width: 8),
            widget.trailing!,
          ],
        ],
      ),
    );

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        if (widget.showSeparator)
          Padding(
            padding: const EdgeInsets.only(left: 58),
            child: Divider(
              height: 0.5,
              thickness: 0.5,
              color: colors.sep,
            ),
          ),
        GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTapDown: widget.onTap != null ? (_) => setState(() => _isPressed = true) : null,
          onTapUp: widget.onTap != null ? (_) => setState(() => _isPressed = false) : null,
          onTapCancel: widget.onTap != null ? () => setState(() => _isPressed = false) : null,
          onTap: widget.onTap,
          child: content,
        ),
      ],
    );
  }
}

/// 30x30 colored icon tile (.ic)
class AppleIconTile extends StatelessWidget {
  final Color backgroundColor;
  final Widget? icon;
  final String? text;
  final double size;
  final double radius;

  const AppleIconTile({
    super.key,
    required this.backgroundColor,
    this.icon,
    this.text,
    this.size = 30.0,
    this.radius = 8.0,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        color: backgroundColor,
        borderRadius: BorderRadius.circular(radius),
      ),
      alignment: Alignment.center,
      child: icon ??
          (text != null
              ? Text(
                  text!,
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: size > 30 ? 12 : 10,
                    fontWeight: FontWeight.w700,
                    fontFamilyFallback: CloudPocketTheme.fontFallbacks,
                  ),
                )
              : const SizedBox.shrink()),
    );
  }
}

/// Sliding segmented control (.seg)
class AppleSegmentedControl<T> extends StatelessWidget {
  final List<T> values;
  final List<String> labels;
  final T selectedValue;
  final ValueChanged<T> onValueChanged;
  final EdgeInsetsGeometry margin;

  const AppleSegmentedControl({
    super.key,
    required this.values,
    required this.labels,
    required this.selectedValue,
    required this.onValueChanged,
    this.margin = const EdgeInsets.only(top: 16),
  }) : assert(values.length == labels.length);

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).extension<CloudPocketColors>() ?? CloudPocketColors.light;
    final selectedIndex = values.indexOf(selectedValue);

    return Container(
      margin: margin,
      padding: const EdgeInsets.all(3),
      height: 38,
      decoration: BoxDecoration(
        color: colors.fill,
        borderRadius: BorderRadius.circular(CloudPocketTheme.radiusSegment),
      ),
      child: LayoutBuilder(
        builder: (context, constraints) {
          final totalWidth = constraints.maxWidth;
          final thumbWidth = totalWidth / values.length;

          return Stack(
            children: [
              // Animated thumb
              if (selectedIndex >= 0) AnimatedPositioned(
                duration: const Duration(milliseconds: 500),
                curve: appleCurve,
                left: selectedIndex * thumbWidth,
                top: 0,
                bottom: 0,
                width: thumbWidth,
                child: Container(
                  decoration: BoxDecoration(
                    color: colors.thumb,
                    borderRadius: BorderRadius.circular(CloudPocketTheme.radiusSegmentThumb),
                    boxShadow: const [
                      BoxShadow(
                        color: Color.fromRGBO(0, 0, 0, 0.14),
                        blurRadius: 7,
                        offset: Offset(0, 2),
                      ),
                    ],
                  ),
                ),
              ),
              // Buttons row
              Row(
                children: List.generate(values.length, (index) {
                  return Expanded(
                    child: GestureDetector(
                      behavior: HitTestBehavior.opaque,
                      onTap: () => onValueChanged(values[index]),
                      child: Center(
                        child: Text(
                          labels[index],
                          style: TextStyle(
                            fontSize: 14,
                            fontWeight: FontWeight.w600,
                            color: colors.label,
                            fontFamilyFallback: CloudPocketTheme.fontFallbacks,
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                    ),
                  );
                }),
              ),
            ],
          );
        },
      ),
    );
  }
}

/// iOS Toggle 51x31 (.tg)
class AppleToggle extends StatelessWidget {
  final String? label;
  final bool value;
  final ValueChanged<bool>? onChanged;

  const AppleToggle({
    super.key,
    required this.value,
    this.onChanged,
    this.label,
  });

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).extension<CloudPocketColors>() ?? CloudPocketColors.light;

    return Semantics(label: label, toggled: value, enabled: onChanged != null, child: GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: onChanged != null ? () => onChanged!(!value) : null,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 300),
        curve: Curves.easeInOut,
        width: 51,
        height: 31,
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(16),
          color: value ? colors.green : colors.fill,
        ),
        child: Stack(
          alignment: Alignment.centerLeft,
          children: [
            AnimatedPositioned(
              duration: const Duration(milliseconds: 400),
              curve: appleCurve,
              left: value ? 22 : 2,
              child: Container(
                width: 27,
                height: 27,
                decoration: const BoxDecoration(
                  shape: BoxShape.circle,
                  color: Colors.white,
                  boxShadow: [
                    BoxShadow(
                      color: Color.fromRGBO(0, 0, 0, 0.28),
                      blurRadius: 6,
                      offset: Offset(0, 2),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    ));
  }
}

/// Apple style button (.btn) with scale down to 0.97
class AppleButton extends StatefulWidget {
  final String text;
  final VoidCallback? onPressed;
  final Color? backgroundColor;
  final Color? textColor;
  final bool isSmall;
  final bool isFullWidth;
  final Widget? icon;

  const AppleButton({
    super.key,
    required this.text,
    this.onPressed,
    this.backgroundColor,
    this.textColor,
    this.isSmall = false,
    this.isFullWidth = true,
    this.icon,
  });

  factory AppleButton.primary({
    required String text,
    VoidCallback? onPressed,
    bool isSmall = false,
    bool isFullWidth = true,
    Widget? icon,
  }) {
    return AppleButton(
      text: text,
      onPressed: onPressed,
      isSmall: isSmall,
      isFullWidth: isFullWidth,
      icon: icon,
    );
  }

  factory AppleButton.gray({
    required String text,
    VoidCallback? onPressed,
    Color? textColor,
    bool isSmall = false,
    bool isFullWidth = true,
    Widget? icon,
  }) {
    return AppleButton(
      text: text,
      onPressed: onPressed,
      textColor: textColor,
      isSmall: isSmall,
      isFullWidth: isFullWidth,
      icon: icon,
    );
  }

  factory AppleButton.red({
    required String text,
    VoidCallback? onPressed,
    bool isSmall = false,
    bool isFullWidth = true,
  }) {
    return AppleButton(
      text: text,
      onPressed: onPressed,
      isSmall: isSmall,
      isFullWidth: isFullWidth,
    );
  }

  @override
  State<AppleButton> createState() => _AppleButtonState();
}

class _AppleButtonState extends State<AppleButton> {
  bool _isPressed = false;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).extension<CloudPocketColors>() ?? CloudPocketColors.light;
    final bg = widget.backgroundColor ?? colors.blue;
    final fg = widget.textColor ?? Colors.white;

    Widget button = AnimatedScale(
      scale: _isPressed && widget.onPressed != null ? 0.97 : 1.0,
      duration: const Duration(milliseconds: 300),
      curve: appleCurve,
      child: Container(
        decoration: BoxDecoration(
          color: widget.onPressed != null ? bg : bg.withOpacity(0.4),
          borderRadius: BorderRadius.circular(widget.isSmall ? 14 : CloudPocketTheme.radiusButton),
        ),
        padding: widget.isSmall
            ? const EdgeInsets.symmetric(horizontal: 16, vertical: 11)
            : const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
        alignment: Alignment.center,
        child: Row(
          mainAxisSize: widget.isFullWidth ? MainAxisSize.max : MainAxisSize.min,
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            if (widget.icon != null) ...[
              widget.icon!,
              const SizedBox(width: 8),
            ],
            Text(
              widget.text,
              style: TextStyle(
                fontSize: widget.isSmall ? 15 : 17,
                fontWeight: FontWeight.w600,
                color: widget.onPressed != null ? fg : fg.withOpacity(0.5),
                fontFamilyFallback: CloudPocketTheme.fontFallbacks,
              ),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ],
        ),
      ),
    );

    return Semantics(button: true, enabled: widget.onPressed != null, child: GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTapDown: widget.onPressed != null ? (_) => setState(() => _isPressed = true) : null,
      onTapUp: widget.onPressed != null ? (_) => setState(() => _isPressed = false) : null,
      onTapCancel: widget.onPressed != null ? () => setState(() => _isPressed = false) : null,
      onTap: widget.onPressed,
      child: widget.isFullWidth ? SizedBox(width: double.infinity, child: button) : button,
    ));
  }
}

/// Pulsing green dot (.dot)
class PulsingDot extends StatefulWidget {
  final double size;
  final Color? color;

  const PulsingDot({
    super.key,
    this.size = 8.0,
    this.color,
  });

  @override
  State<PulsingDot> createState() => _PulsingDotState();
}

class _PulsingDotState extends State<PulsingDot> with SingleTickerProviderStateMixin {
  late AnimationController _controller;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 2),
    );
    if (!Platform.environment.containsKey('FLUTTER_TEST')) {
      _controller.repeat();
    } else {
      _controller.value = 0.5;
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).extension<CloudPocketColors>() ?? CloudPocketColors.light;
    final dotColor = widget.color ?? colors.green;

    return AnimatedBuilder(
      animation: _controller,
      builder: (context, child) {
        final spread = _controller.value * 9.0;
        final opacity = (1.0 - _controller.value).clamp(0.0, 1.0);

        return Container(
          width: widget.size,
          height: widget.size,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: dotColor,
            boxShadow: [
              BoxShadow(
                color: dotColor.withOpacity(opacity * 0.55),
                blurRadius: 0,
                spreadRadius: spread,
              ),
            ],
          ),
        );
      },
    );
  }
}

/// Apple pill badge (.pill)
class ApplePill extends StatelessWidget {
  final String text;
  final Widget? leading;
  final Color? backgroundColor;
  final Color? textColor;

  const ApplePill({
    super.key,
    required this.text,
    this.leading,
    this.backgroundColor,
    this.textColor,
  });

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).extension<CloudPocketColors>() ?? CloudPocketColors.light;
    final bg = backgroundColor ?? colors.green.withOpacity(0.16);
    final fg = textColor ?? colors.green;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(CloudPocketTheme.radiusPill),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (leading != null) ...[
            leading!,
            const SizedBox(width: 6),
          ],
          Text(
            text,
            style: TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w600,
              color: fg,
              fontFamilyFallback: CloudPocketTheme.fontFallbacks,
            ),
          ),
        ],
      ),
    );
  }
}

/// Apple animated progress bar (.bar)
class AppleProgressBar extends StatelessWidget {
  final double progress; // 0.0 to 1.0
  final bool isDone;
  final double height;

  const AppleProgressBar({
    super.key,
    required this.progress,
    this.isDone = false,
    this.height = 8.0,
  });

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).extension<CloudPocketColors>() ?? CloudPocketColors.light;
    final clamped = progress.clamp(0.0, 1.0);

    return Container(
      height: height,
      decoration: BoxDecoration(
        color: colors.fill,
        borderRadius: BorderRadius.circular(height / 2),
      ),
      clipBehavior: Clip.antiAlias,
      child: LayoutBuilder(
        builder: (context, constraints) {
          final barWidth = constraints.maxWidth * clamped;

          return Align(
            alignment: Alignment.centerLeft,
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 900),
              curve: appleCurve,
              width: barWidth,
              height: height,
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(height / 2),
                gradient: isDone
                    ? null
                    : LinearGradient(
                        colors: [colors.blue, colors.green],
                      ),
                color: isDone ? colors.green : null,
              ),
            ),
          );
        },
      ),
    );
  }
}

/// Animated radar rings (.radar) for Receive Mode
class RadarVisualizer extends StatefulWidget {
  final Widget centerIcon;

  const RadarVisualizer({
    super.key,
    required this.centerIcon,
  });

  @override
  State<RadarVisualizer> createState() => _RadarVisualizerState();
}

class _RadarVisualizerState extends State<RadarVisualizer> with SingleTickerProviderStateMixin {
  late AnimationController _controller;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 2700),
    );
    if (!Platform.environment.containsKey('FLUTTER_TEST')) {
      _controller.repeat();
    } else {
      _controller.value = 0.5;
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).extension<CloudPocketColors>() ?? CloudPocketColors.light;

    return SizedBox(
      width: 120,
      height: 120,
      child: Stack(
        alignment: Alignment.center,
        children: [
          _buildRing(0.0, colors.green),
          _buildRing(1.0 / 3.0, colors.green),
          _buildRing(2.0 / 3.0, colors.green),
          widget.centerIcon,
        ],
      ),
    );
  }

  Widget _buildRing(double offset, Color color) {
    return AnimatedBuilder(
      animation: _controller,
      builder: (context, child) {
        final progress = (_controller.value + offset) % 1.0;
        final scale = 0.5 + progress * 0.55;
        final opacity = progress < 0.2 ? progress / 0.2 * 0.7 : (1.0 - progress) * 0.7;

        return Transform.scale(
          scale: scale,
          child: Opacity(
            opacity: opacity.clamp(0.0, 1.0),
            child: Container(
              width: 120,
              height: 120,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                border: Border.all(color: color, width: 1.5),
              ),
            ),
          ),
        );
      },
    );
  }
}

/// Countdown ring (.ring) with orange to red gradient
class CountdownRing extends StatelessWidget {
  final String timeString;
  final double progress; // 1.0 full, 0.0 empty

  const CountdownRing({
    super.key,
    required this.timeString,
    required this.progress,
  });

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).extension<CloudPocketColors>() ?? CloudPocketColors.light;

    return SizedBox(
      width: 176,
      height: 176,
      child: Stack(
        alignment: Alignment.center,
        children: [
          CustomPaint(
            size: const Size(176, 176),
            painter: _CountdownRingPainter(
              progress: progress.clamp(0.0, 1.0),
              trackColor: colors.fill,
              startColor: const Color(0xFFFF9F0A),
              endColor: const Color(0xFFFF375F),
            ),
          ),
          Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                timeString,
                style: TextStyle(
                  fontSize: 38,
                  fontWeight: FontWeight.w700,
                  letterSpacing: -1,
                  color: colors.label,
                  fontFamilyFallback: CloudPocketTheme.fontFallbacks,
                ),
              ),
              Text(
                'until it disappears',
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w500,
                  color: colors.label2,
                  fontFamilyFallback: CloudPocketTheme.fontFallbacks,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _CountdownRingPainter extends CustomPainter {
  final double progress;
  final Color trackColor;
  final Color startColor;
  final Color endColor;

  _CountdownRingPainter({
    required this.progress,
    required this.trackColor,
    required this.startColor,
    required this.endColor,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    final radius = (size.width - 18) / 2;

    // Track
    final trackPaint = Paint()
      ..color = trackColor
      ..style = PaintingStyle.stroke
      ..strokeWidth = 9;
    canvas.drawCircle(center, radius, trackPaint);

    // Gradient Arc
    if (progress > 0) {
      final rect = Rect.fromCircle(center: center, radius: radius);
      final gradient = SweepGradient(
        startAngle: -pi / 2,
        endAngle: 3 * pi / 2,
        colors: [startColor, endColor],
      );

      final arcPaint = Paint()
        ..shader = gradient.createShader(rect)
        ..style = PaintingStyle.stroke
        ..strokeCap = StrokeCap.round
        ..strokeWidth = 9;

      final sweepAngle = 2 * pi * progress;
      canvas.drawArc(rect, -pi / 2, sweepAngle, false, arcPaint);
    }
  }

  @override
  bool shouldRepaint(_CountdownRingPainter oldDelegate) {
    return oldDelegate.progress != progress ||
        oldDelegate.trackColor != trackColor ||
        oldDelegate.startColor != startColor ||
        oldDelegate.endColor != endColor;
  }
}

/// Floating glass toast (.toast)
class AppleToast extends StatelessWidget {
  final String message;
  final bool isVisible;

  const AppleToast({
    super.key,
    required this.message,
    required this.isVisible,
  });

  static OverlayEntry? _activeEntry;
  static Timer? _activeTimer;

  static void show(BuildContext context, String message, {Duration duration = const Duration(milliseconds: 2200)}) {
    _activeTimer?.cancel();
    try {
      _activeEntry?.remove();
    } catch (_) {}
    _activeEntry = null;

    final overlay = Overlay.maybeOf(context, rootOverlay: true);
    if (overlay == null) return;

    final entry = OverlayEntry(builder: (ctx) => _ToastOverlay(message: message));
    _activeEntry = entry;
    overlay.insert(entry);

    _activeTimer = Timer(duration, () {
      if (_activeEntry == entry) {
        try {
          entry.remove();
        } catch (_) {}
        _activeEntry = null;
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).extension<CloudPocketColors>() ?? CloudPocketColors.light;

    return AnimatedPositioned(
      duration: const Duration(milliseconds: 450),
      curve: appleCurve,
      bottom: isVisible ? 104 : 84,
      left: 20,
      right: 20,
      child: Center(
        child: AnimatedOpacity(
          duration: const Duration(milliseconds: 350),
          opacity: isVisible ? 1.0 : 0.0,
          child: ClipRRect(
            borderRadius: BorderRadius.circular(22),
            child: BackdropFilter(
              filter: ImageFilter.blur(sigmaX: 24, sigmaY: 24),
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 11),
                decoration: BoxDecoration(
                  color: colors.glass,
                  borderRadius: BorderRadius.circular(22),
                  border: Border.all(color: colors.sep, width: 0.5),
                  boxShadow: const [
                    BoxShadow(
                      color: Color.fromRGBO(0, 0, 0, 0.2),
                      blurRadius: 30,
                      offset: Offset(0, 8),
                    ),
                  ],
                ),
                child: Text(
                  message,
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                    color: colors.label,
                    fontFamilyFallback: CloudPocketTheme.fontFallbacks,
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _ToastOverlay extends StatefulWidget {
  final String message;
  const _ToastOverlay({required this.message});

  @override
  State<_ToastOverlay> createState() => _ToastOverlayState();
}

class _ToastOverlayState extends State<_ToastOverlay> with SingleTickerProviderStateMixin {
  late AnimationController _controller;
  late Animation<double> _opacity;
  late Animation<double> _slide;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(vsync: this, duration: const Duration(milliseconds: 280));
    _opacity = CurvedAnimation(parent: _controller, curve: Curves.easeOut);
    _slide = Tween<double>(begin: 14.0, end: 0.0).animate(CurvedAnimation(parent: _controller, curve: appleCurve));
    _controller.forward();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).extension<CloudPocketColors>() ?? CloudPocketColors.light;
    return Positioned(
      bottom: MediaQuery.of(context).padding.bottom + 90,
      left: 20,
      right: 20,
      child: Center(
        child: AnimatedBuilder(
          animation: _controller,
          builder: (context, child) {
            return Transform.translate(
              offset: Offset(0, _slide.value),
              child: Opacity(
                opacity: _opacity.value,
                child: child,
              ),
            );
          },
          child: ClipRRect(
            borderRadius: BorderRadius.circular(22),
            child: BackdropFilter(
              filter: ImageFilter.blur(sigmaX: 24, sigmaY: 24),
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
                decoration: BoxDecoration(
                  color: colors.glass,
                  borderRadius: BorderRadius.circular(22),
                  border: Border.all(color: colors.sep, width: 0.5),
                  boxShadow: const [
                    BoxShadow(
                      color: Color.fromRGBO(0, 0, 0, 0.2),
                      blurRadius: 30,
                      offset: Offset(0, 8),
                    ),
                  ],
                ),
                child: Material(
                  color: Colors.transparent,
                  child: Text(
                    widget.message,
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w600,
                      color: colors.label,
                      fontFamilyFallback: CloudPocketTheme.fontFallbacks,
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// iOS-style alert dialog (.dialog)
class AppleDialog extends StatelessWidget {
  final Widget? title;
  final Widget? content;
  final List<Widget> actions;

  const AppleDialog({
    super.key,
    this.title,
    this.content,
    this.actions = const [],
  });

  static Future<T?> show<T>({
    required BuildContext context,
    Widget? title,
    Widget? content,
    List<Widget> actions = const [],
  }) {
    return showDialog<T>(
      context: context,
      builder: (ctx) => AppleDialog(
        title: title,
        content: content,
        actions: actions,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).extension<CloudPocketColors>() ?? CloudPocketColors.light;

    return Dialog(
      backgroundColor: colors.card,
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(20),
        side: BorderSide(color: colors.sep, width: 0.5),
      ),
      insetPadding: const EdgeInsets.symmetric(horizontal: 40, vertical: 24),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 20, 20, 16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (title != null) ...[
              DefaultTextStyle(
                style: TextStyle(
                  fontSize: 17,
                  fontWeight: FontWeight.w600,
                  color: colors.label,
                  fontFamilyFallback: CloudPocketTheme.fontFallbacks,
                ),
                textAlign: TextAlign.center,
                child: title!,
              ),
              const SizedBox(height: 8),
            ],
            if (content != null) ...[
              DefaultTextStyle(
                style: TextStyle(
                  fontSize: 13,
                  color: colors.label2,
                  fontFamilyFallback: CloudPocketTheme.fontFallbacks,
                ),
                textAlign: TextAlign.center,
                child: content!,
              ),
              const SizedBox(height: 18),
            ],
            if (actions.isNotEmpty) ...[
              Divider(height: 0.5, thickness: 0.5, color: colors.sep),
              const SizedBox(height: 8),
              Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: actions,
              ),
            ],
          ],
        ),
      ),
    );
  }
}
