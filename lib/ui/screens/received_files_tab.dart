import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:open_filex/open_filex.dart';
import 'package:share_plus/share_plus.dart';
import 'package:cloud_pocket/providers/received_files_provider.dart';
import 'package:cloud_pocket/ui/theme.dart';
import 'package:cloud_pocket/ui/widgets/apple_widgets.dart';

class ReceivedFilesTab extends ConsumerStatefulWidget {
  const ReceivedFilesTab({super.key});

  @override
  ConsumerState<ReceivedFilesTab> createState() => _ReceivedFilesTabState();
}

class _ReceivedFilesTabState extends ConsumerState<ReceivedFilesTab> {
  String _activeCategory = 'All'; // 'All', 'Photos', 'Videos', 'Docs', 'Audio'

  Future<void> _openFile(String path) async {
    try {
      final result = await OpenFilex.open(path);
      if (result.type != ResultType.done && mounted) {
        _showToast('Unable to open file (${result.message})');
      }
    } catch (e) {
      if (mounted) {
        _showToast('Could not open file: $e');
      }
    }
  }

  Future<void> _shareFile(ReceivedFileItem item) async {
    try {
      await Share.shareXFiles(
        [XFile(item.path)],
        subject: item.name,
      );
    } catch (e) {
      if (mounted) {
        _showToast('Could not share file: $e');
      }
    }
  }

  Future<void> _confirmDelete(ReceivedFileItem item) async {
    final colors = Theme.of(context).extension<CloudPocketColors>() ?? CloudPocketColors.light;

    final confirmed = await AppleDialog.show<bool>(
      context: context,
      title: const Text('Delete File?'),
      content: Text('Are you sure you want to delete "${item.name}"?'),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(false),
          child: Text('Cancel', style: TextStyle(color: colors.label2)),
        ),
        TextButton(
          onPressed: () => Navigator.of(context).pop(true),
          child: Text('Delete', style: TextStyle(color: colors.red, fontWeight: FontWeight.bold)),
        ),
      ],
    );

    if (confirmed == true) {
      final success = await ref.read(receivedFilesProvider.notifier).deleteFile(item.path);
      if (mounted) {
        _showToast(success ? 'Deleted "${item.name}"' : 'Failed to delete file');
      }
    }
  }

  void _showToast(String message) {
    AppleToast.show(context, message);
  }

  Color _getCategoryColor(ReceivedFileItem item, CloudPocketColors colors) {
    if (item.isImage) return colors.green;
    if (item.isVideo) return const Color(0xFFFF375F);
    if (item.isAudio) return colors.orange;
    if (item.isArchive) return const Color(0xFFA259FF);
    return colors.blue;
  }

  String _getFileExtLabel(String name) {
    final dot = name.lastIndexOf('.');
    if (dot != -1 && dot < name.length - 1) {
      final ext = name.substring(dot + 1).toUpperCase();
      return ext.length > 4 ? ext.substring(0, 3) : ext;
    }
    return 'FILE';
  }

  String _formatRelativeTime(DateTime dateTime) {
    final diff = DateTime.now().difference(dateTime);
    if (diff.inSeconds < 60) return 'Just now';
    if (diff.inMinutes < 60) return '${diff.inMinutes} min ago';
    if (diff.inHours < 24) return '${diff.inHours} hr ago';
    return '${diff.inDays} d ago';
  }

  @override
  Widget build(BuildContext context) {
    final receivedState = ref.watch(receivedFilesProvider);
    final colors = Theme.of(context).extension<CloudPocketColors>() ?? CloudPocketColors.light;
    final stateValue = receivedState.valueOrNull;
    final allFiles = stateValue?.files ?? const <ReceivedFileItem>[];

    final filteredFiles = allFiles.where((f) {
      if (_activeCategory == 'All') return true;
      if (_activeCategory == 'Photos') return f.isImage;
      if (_activeCategory == 'Videos') return f.isVideo;
      if (_activeCategory == 'Docs') return f.isDocument;
      if (_activeCategory == 'Audio') return f.isAudio;
      return true;
    }).toList();

    final formattedUsed = stateValue?.formattedTotalSize ?? '0 B';

    const categories = ['All', 'Photos', 'Videos', 'Docs', 'Audio'];

    return Scaffold(
      backgroundColor: colors.bg,
      body: SafeArea(
        child: RefreshIndicator(
          onRefresh: () => ref.read(receivedFilesProvider.notifier).refresh(),
          child: SingleChildScrollView(
            physics: const AlwaysScrollableScrollPhysics(),
            padding: const EdgeInsets.fromLTRB(20, 12, 20, 118),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Top Bar: Received H1 (.top)
                Text(
                  'Received',
                  style: TextStyle(
                    fontSize: 34,
                    fontWeight: FontWeight.w700,
                    letterSpacing: -0.8,
                    height: 1.1,
                    color: colors.label,
                    fontFamilyFallback: CloudPocketTheme.fontFallbacks,
                  ),
                ),
                const SizedBox(height: 14),

                // Storage card (.card)
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 16),
                  decoration: BoxDecoration(
                    color: colors.card,
                    borderRadius: BorderRadius.circular(CloudPocketTheme.radiusCard),
                    boxShadow: colors.shadow,
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        '$formattedUsed in received files',
                        style: TextStyle(
                          fontSize: 15,
                          fontWeight: FontWeight.w700,
                          color: colors.label,
                          fontFamilyFallback: CloudPocketTheme.fontFallbacks,
                        ),
                      ),
                      const SizedBox(height: 6),
                      Text(
                        '${allFiles.length} ${allFiles.length == 1 ? 'file' : 'files'} in your receive folder',
                        style: TextStyle(
                          fontSize: 13,
                          color: colors.label2,
                          fontFamilyFallback: CloudPocketTheme.fontFallbacks,
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 14),

                // Filter pills (.pills)
                SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  child: Row(
                    children: categories.map((cat) {
                      final isSelected = cat == _activeCategory;
                      return Padding(
                        padding: const EdgeInsets.only(right: 8),
                        child: GestureDetector(
                          onTap: () => setState(() => _activeCategory = cat),
                          child: AnimatedContainer(
                            duration: const Duration(milliseconds: 300),
                            curve: appleCurve,
                            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                            decoration: BoxDecoration(
                              color: isSelected ? colors.blue : colors.card,
                              borderRadius: BorderRadius.circular(20),
                              boxShadow: colors.shadow,
                            ),
                            child: Text(
                              cat,
                              style: TextStyle(
                                fontSize: 14,
                                fontWeight: FontWeight.w600,
                                color: isSelected ? Colors.white : colors.label,
                                fontFamilyFallback: CloudPocketTheme.fontFallbacks,
                              ),
                            ),
                          ),
                        ),
                      );
                    }).toList(),
                  ),
                ),
                const SizedBox(height: 14),

                // Grouped file list (.grp #fl)
                if (filteredFiles.isEmpty)
                  Padding(
                    padding: const EdgeInsets.only(top: 40),
                    child: Center(
                      child: Text(
                        'No files received yet',
                        style: TextStyle(
                          fontSize: 15,
                          color: colors.label2,
                          fontFamilyFallback: CloudPocketTheme.fontFallbacks,
                        ),
                      ),
                    ),
                  )
                else
                  AppleGroup(
                    margin: EdgeInsets.zero,
                    children: filteredFiles.asMap().entries.map((entry) {
                      final index = entry.key;
                      final file = entry.value;
                      final catColor = _getCategoryColor(file, colors);
                      final extLabel = _getFileExtLabel(file.name);
                      final relTime = _formatRelativeTime(file.modified);

                      return AppleRow(
                        showSeparator: index > 0,
                        icon: AppleIconTile(
                          backgroundColor: catColor,
                          text: extLabel,
                        ),
                        title: file.name,
                        subtitle: '${file.formattedSize} · $relTime',
                        trailing: PopupMenuButton<String>(
                          icon: Text(
                            '›',
                            style: TextStyle(
                              fontSize: 22,
                              color: colors.label2,
                              fontWeight: FontWeight.w300,
                            ),
                          ),
                          onSelected: (action) {
                            if (action == 'open') _openFile(file.path);
                            if (action == 'share') _shareFile(file);
                            if (action == 'delete') _confirmDelete(file);
                          },
                          itemBuilder: (ctx) => [
                            const PopupMenuItem(value: 'open', child: Text('Open')),
                            const PopupMenuItem(value: 'share', child: Text('Share')),
                            const PopupMenuItem(value: 'delete', child: Text('Delete', style: TextStyle(color: Colors.red))),
                          ],
                        ),
                        onTap: () => _openFile(file.path),
                      );
                    }).toList(),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
