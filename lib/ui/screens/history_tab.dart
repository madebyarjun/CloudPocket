import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:cloud_pocket/models/server_stats.dart';
import 'package:cloud_pocket/models/share_history.dart';
import 'package:cloud_pocket/providers/history_provider.dart';
import 'package:cloud_pocket/ui/theme.dart';
import 'package:cloud_pocket/ui/widgets/apple_widgets.dart';

class HistoryTab extends ConsumerWidget {
  const HistoryTab({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final history = ref.watch(historyProvider);
    final colors = Theme.of(context).extension<CloudPocketColors>() ?? CloudPocketColors.light;

    return Scaffold(
      backgroundColor: colors.bg,
      appBar: AppBar(
        backgroundColor: colors.bg,
        elevation: 0,
        foregroundColor: colors.label,
        title: Text(
          'Session history',
          style: TextStyle(
            fontSize: 17,
            fontWeight: FontWeight.w600,
            color: colors.label,
            fontFamilyFallback: CloudPocketTheme.fontFallbacks,
          ),
        ),
        actions: [
          if (history.isNotEmpty)
            IconButton(
              icon: Icon(Icons.delete_sweep_rounded, color: colors.red),
              tooltip: 'Clear History',
              onPressed: () => _confirmClearHistory(context, ref, colors),
            ),
          const SizedBox(width: 8),
        ],
      ),
      body: history.isEmpty
          ? Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(
                    Icons.history_rounded,
                    size: 64,
                    color: colors.label2.withOpacity(0.4),
                  ),
                  const SizedBox(height: 16),
                  Text(
                    'No sharing history yet',
                    style: TextStyle(
                      color: colors.label2,
                      fontSize: 16,
                      fontWeight: FontWeight.w600,
                      fontFamilyFallback: CloudPocketTheme.fontFallbacks,
                    ),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    'Completed sharing sessions will be saved here',
                    style: TextStyle(
                      color: colors.label2.withOpacity(0.7),
                      fontSize: 13,
                      fontFamilyFallback: CloudPocketTheme.fontFallbacks,
                    ),
                  ),
                ],
              ),
            )
          : ListView.separated(
              padding: const EdgeInsets.fromLTRB(20, 10, 20, 24),
              itemCount: history.length,
              separatorBuilder: (_, __) => const SizedBox(height: 12),
              itemBuilder: (context, index) {
                final record = history[index];
                return Dismissible(
                  key: Key(record.id),
                  direction: DismissDirection.endToStart,
                  background: Container(
                    alignment: Alignment.centerRight,
                    padding: const EdgeInsets.only(right: 20),
                    decoration: BoxDecoration(
                      color: colors.red.withOpacity(0.15),
                      borderRadius: BorderRadius.circular(18),
                    ),
                    child: Icon(Icons.delete_outline_rounded, color: colors.red),
                  ),
                  onDismissed: (_) {
                    ref.read(historyProvider.notifier).deleteRecord(record.id);
                  },
                  child: _HistoryCard(record: record, colors: colors),
                );
              },
            ),
    );
  }

  void _confirmClearHistory(BuildContext context, WidgetRef ref, CloudPocketColors colors) {
    AppleDialog.show(
      context: context,
      title: const Text('Clear All History?'),
      content: const Text('This will remove all past sharing records.'),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: Text('Cancel', style: TextStyle(color: colors.label2)),
        ),
        TextButton(
          onPressed: () {
            ref.read(historyProvider.notifier).clearHistory();
            Navigator.of(context).pop();
            AppleToast.show(context, 'History cleared');
          },
          child: Text('Clear', style: TextStyle(color: colors.red, fontWeight: FontWeight.bold)),
        ),
      ],
    );
  }
}

class _HistoryCard extends StatelessWidget {
  final ShareHistoryRecord record;
  final CloudPocketColors colors;

  const _HistoryCard({required this.record, required this.colors});

  @override
  Widget build(BuildContext context) {
    final formattedDate = _formatDate(record.timestamp);
    final formattedSize = ServerStats.formatBytes(record.totalBytes);
    final formattedDuration = _formatDuration(record.durationSeconds);
    final isProtected = record.securityLabel != 'Open Access' && record.securityLabel != 'Open';

    return Container(
      decoration: BoxDecoration(
        color: colors.card,
        borderRadius: BorderRadius.circular(CloudPocketTheme.radiusCard),
        boxShadow: colors.shadow,
      ),
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Top Row: Date & Status Badge
          Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              Container(
                width: 36,
                height: 36,
                decoration: BoxDecoration(
                  color: colors.blue.withOpacity(0.12),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Icon(
                  Icons.cloud_done_rounded,
                  size: 20,
                  color: colors.blue,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      formattedDate,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: colors.label,
                        fontSize: 14,
                        fontWeight: FontWeight.w600,
                        fontFamilyFallback: CloudPocketTheme.fontFallbacks,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      '${record.itemCount} ${record.itemCount == 1 ? 'file shared' : 'files shared'}',
                      style: TextStyle(
                        color: colors.label2,
                        fontSize: 12,
                        fontFamilyFallback: CloudPocketTheme.fontFallbacks,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 5),
                decoration: BoxDecoration(
                  color: isProtected ? colors.orange.withOpacity(0.14) : colors.fill,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      isProtected ? Icons.lock_rounded : Icons.public_rounded,
                      size: 11,
                      color: isProtected ? colors.orange : colors.label2,
                    ),
                    const SizedBox(width: 4),
                    Text(
                      record.securityLabel,
                      style: TextStyle(
                        color: isProtected ? colors.orange : colors.label2,
                        fontSize: 11,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),

          Padding(
            padding: const EdgeInsets.symmetric(vertical: 12),
            child: Divider(color: colors.sep, height: 1),
          ),

          // Bottom Metrics: Transferred data and Active Duration
          Row(
            children: [
              Expanded(
                child: Row(
                  children: [
                    Icon(Icons.swap_vert_rounded, size: 16, color: colors.blue),
                    const SizedBox(width: 6),
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Transferred',
                          style: TextStyle(color: colors.label2, fontSize: 11, fontFamilyFallback: CloudPocketTheme.fontFallbacks),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          formattedSize,
                          style: TextStyle(
                            color: colors.label,
                            fontSize: 13,
                            fontWeight: FontWeight.w600,
                            fontFamilyFallback: CloudPocketTheme.fontFallbacks,
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
              Expanded(
                child: Row(
                  children: [
                    Icon(Icons.timer_outlined, size: 16, color: colors.green),
                    const SizedBox(width: 6),
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Session Duration',
                          style: TextStyle(color: colors.label2, fontSize: 11, fontFamilyFallback: CloudPocketTheme.fontFallbacks),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          formattedDuration,
                          style: TextStyle(
                            color: colors.label,
                            fontSize: 13,
                            fontWeight: FontWeight.w600,
                            fontFamilyFallback: CloudPocketTheme.fontFallbacks,
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  String _formatDate(DateTime dt) {
    const months = ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'];
    final m = months[dt.month - 1];
    final hour = dt.hour % 12 == 0 ? 12 : dt.hour % 12;
    final ampm = dt.hour >= 12 ? 'PM' : 'AM';
    final minute = dt.minute.toString().padLeft(2, '0');
    return '$m ${dt.day}, ${dt.year} · $hour:$minute $ampm';
  }

  String _formatDuration(int seconds) {
    if (seconds < 60) return '${seconds}s';
    final minutes = seconds ~/ 60;
    if (minutes < 60) return '${minutes}m';
    final hours = minutes ~/ 60;
    final remMins = minutes % 60;
    return '${hours}h ${remMins}m';
  }
}
