import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path/path.dart' as p;
import 'package:cloud_pocket/models/transfer_record.dart';
import 'package:cloud_pocket/providers/stats_provider.dart';
import 'package:cloud_pocket/providers/transfers_provider.dart';
import 'package:cloud_pocket/providers/server_provider.dart';
import 'package:cloud_pocket/ui/theme.dart';
import 'package:cloud_pocket/ui/widgets/apple_widgets.dart';

class TransfersTab extends ConsumerStatefulWidget {
  const TransfersTab({super.key});

  @override
  ConsumerState<TransfersTab> createState() => _TransfersTabState();
}

class _TransfersTabState extends ConsumerState<TransfersTab> {
  int _selectedFilterIndex = 0; // 0: All, 1: Downloads, 2: Uploads

  Color _getTypeColor(String ext, CloudPocketColors colors) {
    final lower = ext.toLowerCase().replaceAll('.', '');
    if (['pdf', 'doc', 'docx', 'txt', 'md'].contains(lower)) return colors.blue;
    if (['mp4', 'mkv', 'mov', 'webm', 'avi'].contains(lower)) return const Color(0xFFFF375F);
    if (['jpg', 'jpeg', 'png', 'webp', 'gif', 'dng'].contains(lower)) return colors.green;
    if (['mp3', 'm4a', 'wav', 'flac'].contains(lower)) return colors.orange;
    if (['zip', 'rar', 'tar', 'gz', 'iso'].contains(lower)) return const Color(0xFF8E8E93);
    return colors.blue;
  }

  String _getTypeLabel(String ext) {
    final clean = ext.toUpperCase().replaceAll('.', '');
    if (clean.isEmpty) return 'FILE';
    return clean.length > 4 ? clean.substring(0, 3) : clean;
  }

  @override
  Widget build(BuildContext context) {
    final allTransfers = ref.watch(transfersProvider);
    final stats = ref.watch(statsProvider);
    final colors = Theme.of(context).extension<CloudPocketColors>() ?? CloudPocketColors.light;

    final aggregateSpeedMb = (stats.bandwidthBytesPerSec / (1024 * 1024)).toStringAsFixed(1);

    final filteredTransfers = allTransfers.where((t) {
      if (_selectedFilterIndex == 1) return t.direction == TransferDirection.download;
      if (_selectedFilterIndex == 2) return t.direction == TransferDirection.upload;
      return true;
    }).toList();

    return Scaffold(
      backgroundColor: colors.bg,
      body: SafeArea(
        child: Column(
          children: [
            // Top Bar: Transfers H1 + Aggregate Speed Chip (.top)
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 12, 20, 4),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Text(
                    'Transfers',
                    style: TextStyle(
                      fontSize: 34,
                      fontWeight: FontWeight.w700,
                      letterSpacing: -0.8,
                      height: 1.1,
                      color: colors.label,
                      fontFamilyFallback: CloudPocketTheme.fontFallbacks,
                    ),
                  ),
                  if (aggregateSpeedMb != "0.0") Container(
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
                    decoration: BoxDecoration(
                      color: colors.card,
                      borderRadius: BorderRadius.circular(20),
                      boxShadow: colors.shadow,
                    ),
                    child: Text(
                      '$aggregateSpeedMb MB/s',
                      style: TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                        color: colors.blue,
                        fontFeatures: const [FontFeature.tabularFigures()],
                        fontFamilyFallback: CloudPocketTheme.fontFallbacks,
                      ),
                    ),
                  ),
                ],
              ),
            ),

            // Filter Segmented Control
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20),
              child: AppleSegmentedControl<int>(
                margin: const EdgeInsets.only(top: 14, bottom: 8),
                values: const [0, 1, 2],
                labels: const ['All', 'Downloads', 'Uploads'],
                selectedValue: _selectedFilterIndex,
                onValueChanged: (v) => setState(() => _selectedFilterIndex = v),
              ),
            ),

            // Transfers list (.tc)
            Expanded(
              child: filteredTransfers.isEmpty
                  ? Center(
                      child: Text(
                        _selectedFilterIndex == 1 ? 'No downloads' : _selectedFilterIndex == 2 ? 'No uploads' : 'No transfers',
                        style: TextStyle(
                          fontSize: 15,
                          color: colors.label2,
                          fontFamilyFallback: CloudPocketTheme.fontFallbacks,
                        ),
                      ),
                    )
                  : ListView.builder(
                      padding: const EdgeInsets.fromLTRB(20, 4, 20, 118),
                      itemCount: filteredTransfers.length,
                      itemBuilder: (context, index) {
                        final transfer = filteredTransfers[index];
                        final ext = p.extension(transfer.filename);
                        final typeColor = _getTypeColor(ext, colors);
                        final typeLabel = _getTypeLabel(ext);

                        final progress = transfer.progress.clamp(0.0, 1.0);
                        final isDone = transfer.status == TransferStatus.completed || progress >= 1.0;
                        final isFailed = transfer.status == TransferStatus.failed;
                        final percent = (progress * 100).toInt();

                        final speedMb = (transfer.speedBytesPerSec / (1024 * 1024)).toStringAsFixed(1);
                        final eta = transfer.estimatedTimeRemaining;

                        return Container(
                          margin: const EdgeInsets.only(top: 12),
                          padding: const EdgeInsets.all(16),
                          decoration: BoxDecoration(
                            color: colors.card,
                            borderRadius: BorderRadius.circular(20),
                            boxShadow: colors.shadow,
                          ),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              // Top item row: Icon tile + Name/Sub + Percentage/Done
                              Row(
                                children: [
                                  AppleIconTile(
                                    size: 40,
                                    radius: 11,
                                    backgroundColor: typeColor,
                                    text: typeLabel,
                                  ),
                                  const SizedBox(width: 12),
                                  Expanded(
                                    child: Column(
                                      crossAxisAlignment: CrossAxisAlignment.start,
                                      children: [
                                        Text(
                                          transfer.filename,
                                          style: TextStyle(
                                            fontSize: 15,
                                            fontWeight: FontWeight.w600,
                                            color: colors.label,
                                            fontFamilyFallback: CloudPocketTheme.fontFallbacks,
                                          ),
                                          maxLines: 1,
                                          overflow: TextOverflow.ellipsis,
                                        ),
                                        const SizedBox(height: 2),
                                        Text(
                                          '${transfer.formattedTransferredBytes} of ${transfer.formattedTotalBytes}${transfer.clientIp != null ? " · ${transfer.clientIp}" : ""}',
                                          style: TextStyle(
                                            fontSize: 13,
                                            color: colors.label2,
                                            fontFamilyFallback: CloudPocketTheme.fontFallbacks,
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                  const SizedBox(width: 8),
                                  Text(
                                    isFailed ? (transfer.errorMessage == 'Cancelled' ? 'Cancelled' : 'Failed') : (isDone ? 'Done' : '$percent%'),
                                    style: TextStyle(
                                      fontSize: 15,
                                      fontWeight: FontWeight.w600,
                                      color: isFailed ? colors.red : (isDone ? colors.green : colors.blue),
                                      fontFamilyFallback: CloudPocketTheme.fontFallbacks,
                                    ),
                                  ),
                                ],
                              ),
                              const SizedBox(height: 12),
                              // Progress bar (.bar)
                              AppleProgressBar(progress: progress, isDone: isDone),
                              const SizedBox(height: 8),
                              // Footer row (.m): Speed/ETA + Pause/Cancel actions
                              Row(
                                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                children: [
                                  Text(
                                    isFailed ? (transfer.errorMessage ?? 'Failed') : isDone
                                        ? 'Finished'
                                        : (transfer.status == TransferStatus.paused
                                            ? 'Paused'
                                            : '$speedMb MB/s · $eta'),
                                    style: TextStyle(
                                      fontSize: 13,
                                      color: colors.label2,
                                      fontFeatures: const [FontFeature.tabularFigures()],
                                      fontFamilyFallback: CloudPocketTheme.fontFallbacks,
                                    ),
                                  ),
                                  if (!isDone && !isFailed)
                                    Row(
                                      mainAxisSize: MainAxisSize.min,
                                      children: [
                                        // Pause / Resume button
                                        GestureDetector(
                                          onTap: () {
                                            ref.read(serverProvider.notifier).togglePauseTransfer(transfer.id);
                                          },
                                          child: Container(
                                            width: 30,
                                            height: 30,
                                            decoration: BoxDecoration(
                                              shape: BoxShape.circle,
                                              color: colors.fill,
                                            ),
                                            alignment: Alignment.center,
                                            child: Text(
                                              transfer.status == TransferStatus.paused ? '▶' : '❚❚',
                                              style: TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: colors.label),
                                            ),
                                          ),
                                        ),
                                        const SizedBox(width: 6),
                                        // Cancel button
                                        GestureDetector(
                                          onTap: () {
                                            ref.read(serverProvider.notifier).cancelTransfer(transfer.id);
                                          },
                                          child: Container(
                                            width: 30,
                                            height: 30,
                                            decoration: BoxDecoration(
                                              shape: BoxShape.circle,
                                              color: colors.fill,
                                            ),
                                            alignment: Alignment.center,
                                            child: Text(
                                              '✕',
                                              style: TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: colors.label),
                                            ),
                                          ),
                                        ),
                                      ],
                                    ),
                                ],
                              ),
                            ],
                          ),
                        );
                      },
                    ),
            ),
          ],
        ),
      ),
    );
  }
}
