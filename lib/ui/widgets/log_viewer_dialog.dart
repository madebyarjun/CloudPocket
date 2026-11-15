import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:share_plus/share_plus.dart';
import 'package:cloud_pocket/services/app_logger.dart';
import 'package:cloud_pocket/ui/theme.dart';
import 'package:cloud_pocket/ui/widgets/apple_widgets.dart';

class LogViewerDialog extends StatefulWidget {
  const LogViewerDialog({super.key});

  static void show(BuildContext context) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (_) => const LogViewerDialog(),
    );
  }

  @override
  State<LogViewerDialog> createState() => _LogViewerDialogState();
}

class _LogViewerDialogState extends State<LogViewerDialog> {
  final ScrollController _scrollController = ScrollController();
  StreamSubscription<LogEntry>? _logSub;
  List<LogEntry> _logs = [];
  final bool _autoScroll = true;

  @override
  void initState() {
    super.initState();
    _logs = List<LogEntry>.from(AppLogger().entries);
    _logSub = AppLogger().onLog.listen((entry) {
      if (mounted) {
        setState(() {
          _logs.add(entry);
        });
        if (_autoScroll && _scrollController.hasClients) {
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (_scrollController.hasClients) {
              _scrollController.jumpTo(_scrollController.position.maxScrollExtent);
            }
          });
        }
      }
    });

    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scrollController.hasClients) {
        _scrollController.jumpTo(_scrollController.position.maxScrollExtent);
      }
    });
  }

  @override
  void dispose() {
    _logSub?.cancel();
    _scrollController.dispose();
    super.dispose();
  }

  Color _getLevelColor(LogLevel level, BuildContext context) {
    final cpColors = Theme.of(context).extension<CloudPocketColors>();
    final colorScheme = Theme.of(context).colorScheme;
    switch (level) {
      case LogLevel.error:
        return cpColors?.danger ?? colorScheme.error;
      case LogLevel.warn:
        return cpColors?.warning ?? const Color(0xFFF59E0B);
      case LogLevel.info:
        return cpColors?.info ?? colorScheme.primary;
      case LogLevel.debug:
        return colorScheme.outline;
    }
  }

  Future<void> _copyAllLogs() async {
    final text = AppLogger().exportToString();
    await Clipboard.setData(ClipboardData(text: text));
    if (mounted) {
      AppleToast.show(context, 'All logs copied to clipboard!');
    }
  }

  Future<void> _exportAndShare() async {
    try {
      final file = await AppLogger().saveLogToFile();
      await Share.shareXFiles(
        [XFile(file.path)],
        text: 'CloudPocket Diagnostic Log Report',
      );
    } catch (e) {
      if (mounted) {
        AppleToast.show(context, 'Failed to export logs: $e');
      }
    }
  }

  void _clearLogs() {
    AppLogger().clear();
    setState(() {
      _logs = [];
    });
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final cpColors = theme.extension<CloudPocketColors>();
    final height = MediaQuery.of(context).size.height * 0.85;

    return SizedBox(
      height: height,
      child: Column(
        children: [
          // Drag handle
          Center(
            child: Container(
              margin: const EdgeInsets.only(top: 12, bottom: 8),
              width: 40,
              height: 4,
              decoration: BoxDecoration(
                color: colorScheme.outlineVariant,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
          ),

          // Header
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 8.0),
            child: Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: (cpColors?.success ?? colorScheme.primary).withOpacity(0.15),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Icon(
                    Icons.terminal_rounded,
                    color: cpColors?.success ?? colorScheme.primary,
                    size: 20,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Diagnostics & Logs',
                        style: TextStyle(
                          color: colorScheme.onSurface,
                          fontSize: 16,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      Text(
                        '${_logs.length} entries recorded',
                        style: TextStyle(
                          color: colorScheme.onSurfaceVariant,
                          fontSize: 12,
                        ),
                      ),
                    ],
                  ),
                ),
                IconButton(
                  tooltip: 'Copy all logs',
                  icon: Icon(Icons.copy_rounded, color: colorScheme.onSurfaceVariant, size: 20),
                  onPressed: _logs.isEmpty ? null : _copyAllLogs,
                ),
                IconButton(
                  tooltip: 'Export & Share log file',
                  icon: Icon(Icons.share_rounded, color: colorScheme.onSurfaceVariant, size: 20),
                  onPressed: _logs.isEmpty ? null : _exportAndShare,
                ),
                IconButton(
                  tooltip: 'Clear logs',
                  icon: Icon(Icons.delete_outline_rounded, color: colorScheme.onSurfaceVariant, size: 20),
                  onPressed: _logs.isEmpty ? null : _clearLogs,
                ),
              ],
            ),
          ),

          Divider(height: 1, color: colorScheme.outlineVariant),

          // Terminal log console
          Expanded(
            child: Container(
              color: const Color(0xFF0D1117),
              child: _logs.isEmpty
                  ? Center(
                      child: Text(
                        'No logs recorded yet.',
                        style: TextStyle(color: colorScheme.outline, fontSize: 13),
                      ),
                    )
                  : ListView.builder(
                      controller: _scrollController,
                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                      itemCount: _logs.length,
                      itemBuilder: (context, index) {
                        final entry = _logs[index];
                        final lvlColor = _getLevelColor(entry.level, context);

                        return Padding(
                          padding: const EdgeInsets.symmetric(vertical: 2.0),
                          child: SelectableText.rich(
                            TextSpan(
                              style: const TextStyle(
                                fontFamily: 'monospace',
                                fontSize: 11,
                                height: 1.4,
                              ),
                              children: [
                                TextSpan(
                                  text: '[${entry.formattedTime}] ',
                                  style: const TextStyle(color: Color(0xFF64748B)),
                                ),
                                TextSpan(
                                  text: '[${entry.level.name.toUpperCase()}] ',
                                  style: TextStyle(
                                    color: lvlColor,
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                                TextSpan(
                                  text: '[${entry.tag}] ',
                                  style: const TextStyle(
                                    color: Color(0xFFA855F7),
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                                TextSpan(
                                  text: entry.message,
                                  style: const TextStyle(color: Color(0xFFE2E8F0)),
                                ),
                              ],
                            ),
                          ),
                        );
                      },
                    ),
            ),
          ),

          // Footer Action Bar
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            decoration: BoxDecoration(
              color: colorScheme.surface,
              border: Border(top: BorderSide(color: colorScheme.outlineVariant)),
            ),
            child: Row(
              children: [
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: _copyAllLogs,
                    icon: const Icon(Icons.copy_rounded, size: 16),
                    label: const Text('Copy All'),
                    style: OutlinedButton.styleFrom(
                      foregroundColor: colorScheme.onSurface,
                      side: BorderSide(color: colorScheme.outlineVariant),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: FilledButton.icon(
                    onPressed: _exportAndShare,
                    icon: const Icon(Icons.share_rounded, size: 16),
                    label: const Text('Export & Share'),
                    style: FilledButton.styleFrom(
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
