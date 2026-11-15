import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path/path.dart' as p;
import 'package:cloud_pocket/models/share_session.dart';
import 'package:cloud_pocket/providers/thumbnail_provider.dart';
import 'package:cloud_pocket/server/thumbnail_service.dart';
import 'package:cloud_pocket/ui/theme.dart';

/// Sweeping fluid shimmer effect that creates the perception of instant forward momentum,
/// seamlessly masking background preparation time.
class _FluidShimmer extends StatefulWidget {
  final double width;
  final double height;
  final double borderRadius;
  final Widget? child;

  const _FluidShimmer({
    super.key,
    required this.width,
    required this.height,
    this.borderRadius = 10,
    this.child,
  });

  @override
  State<_FluidShimmer> createState() => _FluidShimmerState();
}

class _FluidShimmerState extends State<_FluidShimmer> with SingleTickerProviderStateMixin {
  late final AnimationController _controller;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1500),
    )..repeat();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final baseColor = cs.surfaceVariant.withOpacity(0.35);
    final highlightColor = cs.surfaceVariant.withOpacity(0.85);

    return AnimatedBuilder(
      animation: _controller,
      builder: (context, _) {
        final animValue = _controller.value;
        return Container(
          width: widget.width,
          height: widget.height,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(widget.borderRadius),
            gradient: LinearGradient(
              begin: Alignment(-2.0 + (animValue * 4.0), -0.3),
              end: Alignment(-0.5 + (animValue * 4.0), 0.3),
              colors: [
                baseColor,
                highlightColor,
                baseColor,
              ],
              stops: const [0.0, 0.5, 1.0],
            ),
          ),
          child: widget.child,
        );
      },
    );
  }
}

/// Ambient, frosted preparation indicator.
/// Masks loading time seamlessly without exposing internal technical details (never mentions 'thumbnails').
class ThumbnailLoadingIndicator extends ConsumerStatefulWidget {
  final bool compact;
  const ThumbnailLoadingIndicator({super.key, this.compact = false});

  @override
  ConsumerState<ThumbnailLoadingIndicator> createState() => _ThumbnailLoadingIndicatorState();
}

class _ThumbnailLoadingIndicatorState extends ConsumerState<ThumbnailLoadingIndicator>
    with SingleTickerProviderStateMixin {
  late final AnimationController _rotationController;
  bool _dismissedSuccess = false;

  @override
  void initState() {
    super.initState();
    _rotationController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 2000),
    )..repeat();
  }

  @override
  void dispose() {
    _rotationController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(thumbnailProgressProvider);
    final cs = Theme.of(context).colorScheme;
    final extColors = Theme.of(context).extension<CloudPocketColors>()!;

    if (!state.isGenerating && (!state.isDone || state.total == 0 || _dismissedSuccess)) {
      return const SizedBox.shrink();
    }

    // Finished state: clean, subtle 'Ready' badge that seamlessly dissolves
    if (!state.isGenerating && state.isDone && state.total > 0 && !_dismissedSuccess) {
      Future.delayed(const Duration(milliseconds: 2500), () {
        if (mounted && !_dismissedSuccess) {
          setState(() => _dismissedSuccess = true);
        }
      });

      return AnimatedOpacity(
        opacity: _dismissedSuccess ? 0.0 : 1.0,
        duration: const Duration(milliseconds: 300),
        child: Container(
          margin: const EdgeInsets.symmetric(vertical: 6),
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
          decoration: BoxDecoration(
            color: extColors.success.withOpacity(0.12),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: extColors.success.withOpacity(0.3)),
          ),
          child: Row(
            children: [
              Icon(Icons.check_circle_rounded, size: 16, color: extColors.success),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  'All items ready to share',
                  style: TextStyle(
                    fontSize: 12.5,
                    fontWeight: FontWeight.w500,
                    color: cs.onSurface,
                  ),
                ),
              ),
            ],
          ),
        ),
      );
    }

    // Active preparation state: fluid frosted pill with animated sweeping progress
    return Container(
      margin: const EdgeInsets.symmetric(vertical: 6),
      padding: EdgeInsets.symmetric(
        horizontal: widget.compact ? 14 : 16,
        vertical: widget.compact ? 10 : 12,
      ),
      decoration: BoxDecoration(
        color: cs.surfaceVariant.withOpacity(0.35),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: cs.outlineVariant.withOpacity(0.6),
          width: 1,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          // Header Row: Ambient Orbit Spinner + Label + Minimal Count Pill
          Row(
            children: [
              RotationTransition(
                turns: _rotationController,
                child: Icon(
                  Icons.autorenew_rounded,
                  size: 16,
                  color: cs.primary,
                ),
              ),
              const SizedBox(width: 9),
              Expanded(
                child: Text(
                  'Preparing items...',
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                    color: cs.onSurface,
                    letterSpacing: -0.2,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),

          // Fluid Smooth Progress Track
          TweenAnimationBuilder<double>(
            tween: Tween<double>(begin: 0.0, end: state.progress),
            duration: const Duration(milliseconds: 350),
            curve: Curves.easeOutCubic,
            builder: (context, animatedValue, _) {
              return ClipRRect(
                borderRadius: BorderRadius.circular(4),
                child: SizedBox(
                  height: 4,
                  child: LinearProgressIndicator(
                    value: animatedValue > 0 ? animatedValue : null,
                    backgroundColor: cs.surfaceVariant.withOpacity(0.5),
                    valueColor: AlwaysStoppedAnimation<Color>(cs.primary),
                  ),
                ),
              );
            },
          ),
          const SizedBox(height: 6),

          // Subtle reassuring subtext
          Row(
            children: [
              Icon(
                Icons.bolt_rounded,
                size: 12,
                color: cs.onSurfaceVariant.withOpacity(0.75),
              ),
              const SizedBox(width: 4),
              Text(
                'Ready to share anytime',
                style: TextStyle(
                  fontSize: 11,
                  color: cs.onSurfaceVariant.withOpacity(0.8),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

/// Dynamic thumbnail widget for a SharedItem.
/// Renders crisp cached images with a silky smooth dissolve, or a sweeping fluid shimmer while preparing.
class ItemThumbnailWidget extends ConsumerWidget {
  final SharedItem item;
  final double size;

  const ItemThumbnailWidget({
    super.key,
    required this.item,
    this.size = 44,
  });

  bool get _isImage =>
      !item.isDirectory &&
      (item.mimeType.startsWith('image/') ||
          ThumbnailService.isSupportedImage(item.name));

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final colorScheme = Theme.of(context).colorScheme;

    if (!_isImage) {
      final (icon, color) = _getNonImageVisuals(context, item);
      return Container(
        width: size,
        height: size,
        decoration: BoxDecoration(
          color: color.withOpacity(0.15),
          borderRadius: BorderRadius.circular(10),
        ),
        child: Icon(icon, color: color, size: size * 0.54),
      );
    }

    // Watch revision so this widget updates as each item completes
    ref.watch(thumbnailProgressProvider.select((s) => s.revision));

    final sourceFile = File(item.path);
    final cachedFile = ThumbnailService().getCachedThumbnailSync(sourceFile);

    return AnimatedSwitcher(
      duration: const Duration(milliseconds: 350),
      switchInCurve: Curves.easeOutCubic,
      switchOutCurve: Curves.easeInCubic,
      child: (cachedFile != null && cachedFile.existsSync())
          ? ClipRRect(
              key: ValueKey('cached_${item.path}'),
              borderRadius: BorderRadius.circular(10),
              child: Image.file(
                cachedFile,
                width: size,
                height: size,
                fit: BoxFit.cover,
                cacheWidth: (size * 2.5).toInt(),
                errorBuilder: (_, __, ___) => _buildFallbackIcon(colorScheme),
              ),
            )
          : _FluidShimmer(
              key: ValueKey('shimmer_${item.path}'),
              width: size,
              height: size,
              borderRadius: 10,
              child: Center(
                child: Icon(
                  Icons.photo_outlined,
                  color: colorScheme.onSurfaceVariant.withOpacity(0.25),
                  size: size * 0.46,
                ),
              ),
            ),
    );
  }

  Widget _buildFallbackIcon(ColorScheme colorScheme) {
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        color: colorScheme.primary.withOpacity(0.15),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Icon(
        Icons.image_rounded,
        color: colorScheme.primary,
        size: size * 0.54,
      ),
    );
  }

  (IconData, Color) _getNonImageVisuals(BuildContext context, SharedItem item) {
    final colorScheme = Theme.of(context).colorScheme;
    final extColors = Theme.of(context).extension<CloudPocketColors>()!;

    if (item.isDirectory) {
      return (Icons.folder_rounded, extColors.warning);
    }
    final ext = p.extension(item.name).toLowerCase();
    switch (ext) {
      case '.pdf':
        return (Icons.picture_as_pdf_rounded, extColors.danger);
      case '.zip':
      case '.tar':
      case '.gz':
      case '.rar':
      case '.7z':
        return (Icons.folder_zip_rounded, colorScheme.tertiary);
      case '.mp4':
      case '.mkv':
      case '.mov':
      case '.avi':
      case '.webm':
        return (Icons.movie_rounded, colorScheme.primary);
      case '.mp3':
      case '.wav':
      case '.ogg':
      case '.flac':
      case '.m4a':
        return (Icons.music_note_rounded, extColors.success);
      case '.apk':
        return (Icons.android_rounded, extColors.success);
      case '.txt':
      case '.md':
      case '.json':
      case '.csv':
        return (Icons.description_rounded, colorScheme.onSurfaceVariant);
      default:
        return (Icons.insert_drive_file_rounded, colorScheme.primary);
    }
  }
}

/// Horizontal preview strip on HomeScreen showing selected files with fluid placeholders
class SelectedThumbnailsStrip extends ConsumerWidget {
  final List<SharedItem> items;
  final VoidCallback onTap;

  const SelectedThumbnailsStrip({
    super.key,
    required this.items,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    if (items.isEmpty) return const SizedBox.shrink();

    final cs = Theme.of(context).colorScheme;
    final maxPreview = items.take(6).toList();
    final remaining = items.length - maxPreview.length;

    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(12),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 4.0),
        child: SizedBox(
          height: 52,
          child: Row(
            children: [
              Expanded(
                child: ListView.separated(
                  scrollDirection: Axis.horizontal,
                  physics: const BouncingScrollPhysics(),
                  itemCount: maxPreview.length,
                  separatorBuilder: (_, __) => const SizedBox(width: 8),
                  itemBuilder: (context, index) {
                    final item = maxPreview[index];
                    return ItemThumbnailWidget(item: item, size: 52);
                  },
                ),
              ),
              if (remaining > 0) ...[
                const SizedBox(width: 8),
                Container(
                  width: 52,
                  height: 52,
                  decoration: BoxDecoration(
                    color: cs.surfaceVariant.withOpacity(0.8),
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(color: cs.outlineVariant.withOpacity(0.5)),
                  ),
                  child: Center(
                    child: Text(
                      '+$remaining',
                      style: TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.bold,
                        color: cs.primary,
                      ),
                    ),
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}
