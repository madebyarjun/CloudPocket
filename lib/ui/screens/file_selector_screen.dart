import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:file_picker/file_picker.dart';
import 'package:path/path.dart' as p;
import 'package:mime/mime.dart';
import 'package:cloud_pocket/models/share_session.dart';
import 'package:cloud_pocket/providers/session_provider.dart';
import 'package:cloud_pocket/services/permission_service.dart';
import 'package:cloud_pocket/ui/theme.dart';
import 'package:cloud_pocket/ui/widgets/apple_widgets.dart';
import 'package:cloud_pocket/ui/widgets/thumbnail_loading_indicator.dart';
import 'package:permission_handler/permission_handler.dart';

enum _FilterCategory { all, files, folders, media }

class FileSelectorScreen extends ConsumerStatefulWidget {
  const FileSelectorScreen({super.key});

  @override
  ConsumerState<FileSelectorScreen> createState() => _FileSelectorScreenState();
}

class _FileSelectorScreenState extends ConsumerState<FileSelectorScreen> {
  _FilterCategory _category = _FilterCategory.all;
  bool _isLoading = false;

  @override
  Widget build(BuildContext context) {
    final session = ref.watch(sessionProvider);
    final items = session.items;

    final filteredItems = items.where((item) {
      if (_category == _FilterCategory.folders) return item.isDirectory;
      if (_category == _FilterCategory.files) return !item.isDirectory;
      if (_category == _FilterCategory.media) {
        final ext = p.extension(item.name).toLowerCase();
        return ['.jpg', '.jpeg', '.png', '.gif', '.webp', '.mp4', '.mkv', '.mov', '.mp3', '.wav', '.flac']
            .contains(ext);
      }
      return true;
    }).toList();

    final totalBytes = items.fold<int>(0, (sum, item) => sum + item.sizeBytes);
    final formattedSize = _formatBytes(totalBytes);

    final colors = Theme.of(context).extension<CloudPocketColors>() ?? CloudPocketColors.light;

    return Scaffold(
      backgroundColor: colors.bg,
      appBar: AppBar(
        backgroundColor: colors.bg,
        elevation: 0,
        foregroundColor: colors.label,
        leading: IconButton(
          icon: Icon(Icons.close_rounded, color: colors.label),
          onPressed: () => Navigator.of(context).pop(),
        ),
        title: Text(
          'Select Files',
          style: TextStyle(
            fontSize: 17,
            fontWeight: FontWeight.w600,
            color: colors.label,
            fontFamilyFallback: CloudPocketTheme.fontFallbacks,
          ),
        ),
      ),
      body: Column(
        children: [
          // Filter Tabs (Apple Segmented Control)
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20.0, vertical: 8.0),
            child: AppleSegmentedControl<_FilterCategory>(
              values: const [_FilterCategory.all, _FilterCategory.files, _FilterCategory.folders, _FilterCategory.media],
              labels: const ['All', 'Files', 'Folders', 'Media'],
              selectedValue: _category,
              onValueChanged: (cat) => setState(() => _category = cat),
            ),
          ),

          // Add Buttons Row
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20.0, vertical: 8.0),
            child: Row(
              children: [
                Expanded(
                  child: AppleButton.gray(
                    text: '+ Add Files',
                    isSmall: true,
                    onPressed: _isLoading ? null : _pickFiles,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: AppleButton.gray(
                    text: '+ Add Folder',
                    isSmall: true,
                    onPressed: _isLoading ? null : _pickFolder,
                  ),
                ),
              ],
            ),
          ),

          // Animated thumbnail generation indicator
          const Padding(
            padding: EdgeInsets.symmetric(horizontal: 20.0),
            child: ThumbnailLoadingIndicator(),
          ),

          const SizedBox(height: 6),

          // File List
          Expanded(
            child: _isLoading
                ? const Center(
                    child: CircularProgressIndicator(),
                  )
                : filteredItems.isEmpty
                    ? Center(
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Icon(
                              Icons.folder_open_rounded,
                              size: 64,
                              color: colors.label2.withOpacity(0.4),
                            ),
                            const SizedBox(height: 16),
                            Text(
                              'No files selected yet',
                              style: TextStyle(
                                color: colors.label,
                                fontSize: 16,
                                fontWeight: FontWeight.w600,
                                fontFamilyFallback: CloudPocketTheme.fontFallbacks,
                              ),
                            ),
                            const SizedBox(height: 6),
                            Text(
                              'Tap + Add Files or + Add Folder above',
                              style: TextStyle(
                                color: colors.label2,
                                fontSize: 13,
                                fontFamilyFallback: CloudPocketTheme.fontFallbacks,
                              ),
                            ),
                          ],
                        ),
                      )
                    : ListView.separated(
                        padding: const EdgeInsets.fromLTRB(20, 8, 20, 20),
                        itemCount: filteredItems.length,
                        separatorBuilder: (_, __) => const SizedBox(height: 10),
                        itemBuilder: (context, index) {
                          final item = filteredItems[index];
                          return _FileItemTile(
                            item: item,
                            colors: colors,
                            onRemove: () {
                              ref.read(sessionProvider.notifier).removeItem(item);
                            },
                          );
                        },
                      ),
          ),

          // Bottom Bar
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
            decoration: BoxDecoration(
              color: colors.card,
              boxShadow: colors.shadow,
            ),
            child: SafeArea(
              top: false,
              child: Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          '${items.length} ${items.length == 1 ? 'item' : 'items'} ready',
                          style: TextStyle(
                            color: colors.label,
                            fontSize: 15,
                            fontWeight: FontWeight.w700,
                            fontFamilyFallback: CloudPocketTheme.fontFallbacks,
                          ),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          formattedSize,
                          style: TextStyle(
                            color: colors.label2,
                            fontSize: 13,
                            fontFamilyFallback: CloudPocketTheme.fontFallbacks,
                          ),
                        ),
                      ],
                    ),
                  ),
                  SizedBox(
                    width: 140,
                    child: AppleButton.primary(
                      text: items.isEmpty ? 'Choose items' : 'Use ${items.length} ${items.length == 1 ? 'item' : 'items'}',
                      onPressed: items.isEmpty
                          ? null
                          : () {
                              Navigator.of(context).pop();
                            },
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _pickFiles() async {
    setState(() => _isLoading = true);
    try {
      final result = await FilePicker.platform.pickFiles(allowMultiple: true);
      if (result != null && result.files.isNotEmpty) {
        final newItems = result.files
            .where((f) => f.path != null)
            .map((f) {
              final file = File(f.path!);
              final size = file.existsSync() ? file.lengthSync() : (f.size);
              return SharedItem(
                path: f.path!,
                name: f.name,
                sizeBytes: size,
                isDirectory: false,
                mimeType: lookupMimeType(f.name) ?? 'application/octet-stream',
              );
            })
            .toList();
        ref.read(sessionProvider.notifier).addItems(newItems);
      }
    } catch (e) {
      if (mounted) {
        AppleToast.show(context, 'Error picking files: $e');
      }
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Future<void> _pickFolder() async {
    if (Platform.isAndroid) {
      final hasPerm = await PermissionService.ensureManageExternalStorage();
      if (!hasPerm && mounted) {
        final colors = Theme.of(context).extension<CloudPocketColors>() ?? CloudPocketColors.light;
        final proceed = await AppleDialog.show<bool>(
          context: context,
          title: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(Icons.folder_shared_rounded, color: colors.blue, size: 22),
              const SizedBox(width: 8),
              const Text('Storage Access Needed'),
            ],
          ),
          content: const Text(
            'To share folders directly from your device, CloudPocket requires "All files access" permission in Android settings.\n\nWould you like to open Settings to grant this permission?',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(false),
              child: Text('Cancel', style: TextStyle(color: colors.label2)),
            ),
            TextButton(
              onPressed: () {
                Navigator.of(context).pop(true);
                openAppSettings();
              },
              child: Text('Open Settings', style: TextStyle(color: colors.blue, fontWeight: FontWeight.bold)),
            ),
          ],
        );
        if (proceed != true) return;
        return;
      }
    }

    setState(() => _isLoading = true);
    try {
      final dirPath = await FilePicker.platform.getDirectoryPath();
      if (dirPath != null) {
        final normalizedPath = p.normalize(dirPath);
        final dir = Directory(normalizedPath);
        if (dir.existsSync()) {
          int size = 0;
          try {
            await for (final entity in dir.list(recursive: true, followLinks: false)) {
              if (entity is File && !p.basename(entity.path).startsWith('.')) {
                try {
                  size += await entity.length();
                } catch (_) {}
              }
            }
          } catch (_) {}

          final folderName = p.basename(normalizedPath);
          final folderItem = SharedItem(
            path: normalizedPath,
            name: folderName.isEmpty ? 'Shared Folder' : folderName,
            sizeBytes: size,
            isDirectory: true,
            mimeType: 'inode/directory',
          );
          ref.read(sessionProvider.notifier).addItems([folderItem]);
        }
      }
    } catch (e) {
      if (mounted) {
        AppleToast.show(context, 'Error picking folder: $e');
      }
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  static String _formatBytes(int bytes) {
    if (bytes <= 0) return '0 B';
    const suffixes = ['B', 'KB', 'MB', 'GB', 'TB'];
    var i = 0;
    double count = bytes.toDouble();
    while (count >= 1024 && i < suffixes.length - 1) {
      count /= 1024;
      i++;
    }
    return '${count.toStringAsFixed(i == 0 ? 0 : 1)} ${suffixes[i]}';
  }
}

class _FileItemTile extends StatelessWidget {
  final SharedItem item;
  final CloudPocketColors colors;
  final VoidCallback onRemove;

  const _FileItemTile({
    required this.item,
    required this.colors,
    required this.onRemove,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: colors.card,
        borderRadius: BorderRadius.circular(CloudPocketTheme.radiusGroup),
        boxShadow: colors.shadow,
      ),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      child: Row(
        children: [
          ItemThumbnailWidget(item: item, size: 44),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  item.name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: colors.label,
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                    fontFamilyFallback: CloudPocketTheme.fontFallbacks,
                  ),
                ),
                const SizedBox(height: 3),
                Text(
                  item.isDirectory ? 'Folder' : _formatBytes(item.sizeBytes),
                  style: TextStyle(
                    color: colors.label2,
                    fontSize: 12,
                    fontFamilyFallback: CloudPocketTheme.fontFallbacks,
                  ),
                ),
              ],
            ),
          ),
          IconButton(
            icon: Icon(
              Icons.close_rounded,
              color: colors.label2,
              size: 20,
            ),
            onPressed: onRemove,
          ),
        ],
      ),
    );
  }

  static String _formatBytes(int bytes) {
    if (bytes <= 0) return '0 B';
    const suffixes = ['B', 'KB', 'MB', 'GB', 'TB'];
    var i = 0;
    double count = bytes.toDouble();
    while (count >= 1024 && i < suffixes.length - 1) {
      count /= 1024;
      i++;
    }
    return '${count.toStringAsFixed(i == 0 ? 0 : 1)} ${suffixes[i]}';
  }
}
