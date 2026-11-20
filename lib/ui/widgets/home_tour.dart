import 'dart:math' as math;
import 'package:material_ui/material_ui.dart';

/// Highlights the actual control after layout, including after a scroll or resize.
class HomeTour extends StatefulWidget {
  const HomeTour({
    super.key,
    required this.step,
    required this.target,
    this.fallback,
    required this.onShown,
    required this.onNext,
    required this.onSkip,
  });

  final int step;
  final GlobalKey target;
  final GlobalKey? fallback;
  final VoidCallback onShown, onNext, onSkip;

  @override
  State<HomeTour> createState() => _HomeTourState();
}

class _HomeTourState extends State<HomeTour> {
  static const messages = [
    'Pick files or folders to share from your phone.',
    'Share on your Wi-Fi, or switch to an internet link for people far away.',
    'Let others send files to your phone from their browser.',
    'Create a temporary chat room that closes when you end it.',
    'See what was sent and received.',
    'Change limits and options here. You can replay this tour anytime.',
  ];
  Rect? _target;
  bool _reveal = true;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback(_measure);
  }

  @override
  void didUpdateWidget(HomeTour oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.step != widget.step) {
      _reveal = true;
      _target = null;
    }
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _reveal = true;
  }

  void _measure(Duration _) {
    if (!mounted) return;
    // Subscribe to the next already-scheduled frame; idle tours need no ticker.
    WidgetsBinding.instance.addPostFrameCallback(_measure);
    final anchor =
        widget.target.currentContext ?? widget.fallback?.currentContext;
    if (anchor == null) return;
    if (_reveal) {
      _reveal = false;
      Scrollable.ensureVisible(anchor, alignment: 0.45);
    }
    final box = anchor.findRenderObject() as RenderBox?;
    final overlay = context.findRenderObject() as RenderBox?;
    if (box == null || overlay == null || !box.hasSize || !overlay.hasSize) {
      return;
    }
    final origin = overlay.globalToLocal(box.localToGlobal(Offset.zero));
    final rect =
        (origin & box.size).inflate(4).intersect(Offset.zero & overlay.size);
    if (!rect.isEmpty && rect != _target) {
      setState(() => _target = rect);
      widget.onShown();
    }
  }

  @override
  Widget build(BuildContext context) {
    final insets = MediaQuery.paddingOf(context);
    final theme = Theme.of(context);
    final target = _target;
    return Material(
      type: MaterialType.transparency,
      child: LayoutBuilder(builder: (context, constraints) {
        if (target == null) {
          return const AbsorbPointer(child: SizedBox.expand());
        }
        final width = constraints.maxWidth;
        final height = constraints.maxHeight;
        final safeLeft = insets.left + 8;
        final safeRight = width - insets.right - 8;
        final bubbleWidth = math.min(340.0, safeRight - safeLeft);
        final left = (target.center.dx - bubbleWidth / 2)
            .clamp(safeLeft, math.max(safeLeft, safeRight - bubbleWidth))
            .toDouble();
        final above = target.top - insets.top - 8;
        final below = height - insets.bottom - 8 - target.bottom;
        final down = below >= above;
        final space = math.max(1.0, (down ? below : above) - 10);
        final tip =
            target.center.dx.clamp(left + 8, left + bubbleWidth - 8).toDouble();
        return Stack(fit: StackFit.expand, children: [
          const ModalBarrier(dismissible: false, color: Colors.transparent),
          IgnorePointer(
              child: CustomPaint(
                  painter: _Spotlight(
            target,
            tip,
            down,
            theme.colorScheme.surface,
          ))),
          Positioned(
            left: left,
            width: bubbleWidth,
            top: down ? target.bottom + 10 : null,
            bottom: down ? null : height - target.top + 10,
            child: Material(
              color: theme.colorScheme.surface,
              borderRadius: BorderRadius.circular(16),
              clipBehavior: Clip.antiAlias,
              child: ConstrainedBox(
                constraints: BoxConstraints(maxHeight: space),
                child: SingleChildScrollView(
                  key: ValueKey(widget.step),
                  padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
                  child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Semantics(
                            liveRegion: true,
                            child: Text('${widget.step + 1} of 6',
                                style: theme.textTheme.labelMedium)),
                        const SizedBox(height: 6),
                        Text(messages[widget.step],
                            style: theme.textTheme.bodyLarge),
                        const SizedBox(height: 6),
                        Wrap(spacing: 12, children: [
                          TextButton(
                              onPressed: widget.onSkip,
                              child: const Text('Skip')),
                          FilledButton(
                              onPressed: widget.onNext,
                              child: Text(widget.step == 5 ? 'Done' : 'Next')),
                        ]),
                      ]),
                ),
              ),
            ),
          ),
        ]);
      }),
    );
  }
}

class _Spotlight extends CustomPainter {
  const _Spotlight(this.rect, this.tip, this.down, this.surface);
  final Rect rect;
  final double tip;
  final bool down;
  final Color surface;

  @override
  void paint(Canvas canvas, Size size) {
    final mask = Path()
      ..fillType = PathFillType.evenOdd
      ..addRect(Offset.zero & size)
      ..addRRect(RRect.fromRectAndRadius(rect, const Radius.circular(10)));
    canvas.drawPath(mask, Paint()..color = Colors.black.withValues(alpha: .68));
    final y = down ? rect.bottom : rect.top;
    final base = y + (down ? 11 : -11);
    canvas.drawPath(
        Path()
          ..moveTo(tip, y)
          ..lineTo(tip - 8, base)
          ..lineTo(tip + 8, base)
          ..close(),
        Paint()..color = surface);
  }

  @override
  bool shouldRepaint(_Spotlight old) =>
      old.rect != rect ||
      old.tip != tip ||
      old.down != down ||
      old.surface != surface;
}
