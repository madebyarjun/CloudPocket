import 'dart:io';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:mime/mime.dart';
import 'package:path/path.dart' as p;
import 'package:cloud_pocket/models/server_stats.dart';
import 'package:cloud_pocket/models/share_session.dart';
import 'package:cloud_pocket/providers/session_provider.dart';
import 'package:cloud_pocket/ui/widgets/apple_widgets.dart';

class FileSelectorList extends ConsumerWidget {
  const FileSelectorList({super.key});

  Future<void> _pickFiles(BuildContext context, WidgetRef ref) async {
    try {
      final result = await FilePicker.platform.pickFiles(allowMultiple: true);
      if (result != null && result.files.isNotEmpty) {
        final newItems = <SharedItem>[];
        for (final platformFile in result.files) {
          final path = platformFile.path;
          if (path != null) {
            final file = File(path);
            if (await file.exists()) {
              final size = await file.length();
              final name = p.basename(path);
              newItems.add(SharedItem(
                path: path,
                name: name,
                sizeBytes: size,
                isDirectory: false,
                mimeType: lookupMimeType(name) ?? 'application/octet-stream',
              ));
            }
          }
        }
        ref.read(sessionProvider.notifier).addItems(newItems);
      }
    } catch (e) {
      if (context.mounted) {
        AppleToast.show(context, 'Failed to select files: $e');
      }
    }
  }

  Future<void> _pickDirectory(BuildContext context, WidgetRef ref) async {
    try {
      final dirPath = await FilePicker.platform.getDirectoryPath();
      if (dirPath != null) {
        final dir = Directory(dirPath);
        if (await dir.exists()) {
          var totalBytes = 0;
          await for (final entity in dir.list(recursive: true, followLinks: false)) {
            if (entity is File) {
              totalBytes += await entity.length();
            }
          }
          final name = p.basename(dirPath);
          ref.read(sessionProvider.notifier).addItems([
            SharedItem(
              path: dirPath,
              name: name,
              sizeBytes: totalBytes,
              isDirectory: true,
              mimeType: 'inode/directory',
            ),
          ]);
        }
      }
    } catch (e) {
      if (context.mounted) {
        AppleToast.show(context, 'Failed to select folder: $e');
      }
    }
  }

  IconData _getIcon(SharedItem item) {
    if (item.isDirectory) return Icons.folder;
    final mime = item.mimeType.toLowerCase();
    if (mime.startsWith('image/')) return Icons.image;
    if (mime.startsWith('video/')) return Icons.movie;
    if (mime.startsWith('audio/')) return Icons.music_note;
    if (mime.contains('pdf')) return Icons.picture_as_pdf;
    if (mime.contains('zip') || mime.contains('archive')) return Icons.folder_zip;
    return Icons.insert_drive_file;
  }

  Color _getIconColor(SharedItem item, ThemeData theme) {
    if (item.isDirectory) return Colors.amber.shade700;
    final mime = item.mimeType.toLowerCase();
    if (mime.startsWith('image/')) return Colors.teal;
    if (mime.startsWith('video/')) return Colors.red.shade400;
    if (mime.startsWith('audio/')) return Colors.purple.shade400;
    if (mime.contains('pdf')) return Colors.red.shade700;
    return theme.colorScheme.primary;
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final session = ref.watch(sessionProvider);
    final theme = Theme.of(context);

    final totalSize = session.items.fold<int>(0, (sum, i) => sum + i.sizeBytes);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // Picker Action Buttons
        Row(
          children: [
            Expanded(
              child: FilledButton.tonalIcon(
                onPressed: () => _pickFiles(context, ref),
                icon: const Icon(Icons.file_upload_outlined),
                label: const Text('Add Files'),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: FilledButton.tonalIcon(
                onPressed: () => _pickDirectory(context, ref),
                icon: const Icon(Icons.create_new_folder_outlined),
                label: const Text('Add Folder'),
              ),
            ),
          ],
        ),
        const SizedBox(height: 16),

        // Selected Items Summary
        if (session.items.isNotEmpty) ...[
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 4.0),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  '${session.items.length} item(s) selected',
                  style: theme.textTheme.labelMedium?.copyWith(color: theme.colorScheme.secondary),
                ),
                Text(
                  'Total: ${ServerStats.formatBytes(totalSize)}',
                  style: theme.textTheme.labelMedium?.copyWith(fontWeight: FontWeight.bold),
                ),
              ],
            ),
          ),
          const SizedBox(height: 8),
        ],

        // Items List
        if (session.items.isEmpty)
          Container(
            padding: const EdgeInsets.symmetric(vertical: 40),
            alignment: Alignment.center,
            decoration: BoxDecoration(
              border: Border.all(color: theme.colorScheme.outlineVariant, style: BorderStyle.solid),
              borderRadius: BorderRadius.circular(16),
            ),
            child: Column(
              children: [
                Icon(Icons.cloud_upload_outlined, size: 48, color: theme.colorScheme.outline),
                const SizedBox(height: 12),
                Text(
                  'No files or folders selected',
                  style: theme.textTheme.bodyMedium?.copyWith(color: theme.colorScheme.outline),
                ),
                const SizedBox(height: 4),
                Text(
                  'Tap "Add Files" or "Add Folder" above',
                  style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.outline),
                ),
              ],
            ),
          )
        else
          ListView.separated(
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            itemCount: session.items.length,
            separatorBuilder: (_, __) => const Divider(height: 1),
            itemBuilder: (context, index) {
              final item = session.items[index];
              return ListTile(
                contentPadding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                leading: CircleAvatar(
                  backgroundColor: _getIconColor(item, theme).withOpacity(0.15),
                  child: Icon(_getIcon(item), color: _getIconColor(item, theme), size: 22),
                ),
                title: Text(
                  item.name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.bodyMedium?.copyWith(fontWeight: FontWeight.w500),
                ),
                subtitle: Text(
                  item.isDirectory
                      ? 'Folder · ${ServerStats.formatBytes(item.sizeBytes)}'
                      : ServerStats.formatBytes(item.sizeBytes),
                  style: theme.textTheme.bodySmall,
                ),
                trailing: IconButton(
                  icon: const Icon(Icons.close, size: 20),
                  onPressed: () {
                    ref.read(sessionProvider.notifier).removeItem(item);
                  },
                ),
              );
            },
          ),
      ],
    );
  }
}
