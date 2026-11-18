import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;
import 'package:path/path.dart' as p;
import 'package:cloud_pocket/models/chat_message.dart';
import 'package:cloud_pocket/ui/theme.dart';

enum RoomMediaCategory {
  image,
  video,
  audio,
  pdf,
  text,
}

const List<String> kAllowedRoomMediaExtensions = [
  'jpg',
  'jpeg',
  'png',
  'gif',
  'webp',
  'bmp',
  'mp4',
  'mkv',
  'webm',
  'mov',
  'avi',
  '3gp',
  'mp3',
  'wav',
  'aac',
  'm4a',
  'flac',
  'ogg',
  'opus',
  'pdf',
  'txt',
  'md',
  'json',
  'csv',
  'log',
  'xml',
  'yaml',
  'yml',
];

RoomMediaCategory classifyRoomMedia(String filename, String? mimeType) {
  final ext = p.extension(filename).toLowerCase().replaceFirst('.', '');
  final mime = (mimeType ?? '').toLowerCase();

  if (mime.startsWith('image/') ||
      const {'jpg', 'jpeg', 'png', 'gif', 'webp', 'bmp'}.contains(ext)) {
    return RoomMediaCategory.image;
  }
  if (mime.startsWith('video/') ||
      const {'mp4', 'mkv', 'webm', 'mov', 'avi', '3gp'}.contains(ext)) {
    return RoomMediaCategory.video;
  }
  if (mime.startsWith('audio/') ||
      const {'mp3', 'wav', 'aac', 'm4a', 'flac', 'ogg', 'opus'}.contains(ext)) {
    return RoomMediaCategory.audio;
  }
  if (mime == 'application/pdf' || ext == 'pdf') {
    return RoomMediaCategory.pdf;
  }
  return RoomMediaCategory.text;
}

String formatRoomMediaBytes(int bytes) {
  if (bytes <= 0) return '0 B';
  if (bytes < 1024) return '$bytes B';
  if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(1)} KB';
  return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
}

/// Chat bubble widget for view/play-only media inside the Disposable Room app chat.
class RoomMediaBubble extends StatelessWidget {
  final ChatMessage message;
  final String? localFilePath;
  final String? remoteUrl;
  final Map<String, String>? headers;

  final VoidCallback? onViewerClosed;

  const RoomMediaBubble({
    super.key,
    required this.message,
    this.onViewerClosed,
    this.localFilePath,
    this.remoteUrl,
    this.headers,
  });

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final cpColors = Theme.of(context).extension<CloudPocketColors>()!;
    final filename = message.filename ?? 'Shared Media';
    final category = classifyRoomMedia(filename, message.fileMimeType);
    final sizeText = formatRoomMediaBytes(message.fileSize ?? 0);

    final bool hasLocal = localFilePath != null && File(localFilePath!).existsSync();

    IconData icon;
    String actionLabel;
    Color accentColor;

    switch (category) {
      case RoomMediaCategory.image:
        icon = Icons.image_rounded;
        actionLabel = 'View Photo';
        accentColor = cpColors.info;
        break;
      case RoomMediaCategory.video:
        icon = Icons.play_circle_fill_rounded;
        actionLabel = 'Play Video';
        accentColor = colorScheme.primary;
        break;
      case RoomMediaCategory.audio:
        icon = Icons.graphic_eq_rounded;
        actionLabel = 'Play Music';
        accentColor = cpColors.success;
        break;
      case RoomMediaCategory.pdf:
        icon = Icons.picture_as_pdf_rounded;
        actionLabel = 'View PDF';
        accentColor = cpColors.danger;
        break;
      case RoomMediaCategory.text:
        icon = Icons.description_rounded;
        actionLabel = filename.toLowerCase().endsWith('.md') ? 'Read Markdown' : 'Read Text';
        accentColor = cpColors.warning;
        break;
    }

    return InkWell(
      borderRadius: BorderRadius.circular(10),
      onTap: !hasLocal && remoteUrl == null ? null : () async {
        await Navigator.of(context).push(
          MaterialPageRoute(
            builder: (_) => RoomMediaViewerScreen(
              filename: filename,
              fileSize: message.fileSize ?? 0,
              category: category,
              localFilePath: hasLocal ? localFilePath : null,
              remoteUrl: remoteUrl,
              headers: headers,
            ),
          ),
        );
        onViewerClosed?.call();
      },
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          if (category == RoomMediaCategory.image && (hasLocal || remoteUrl != null)) ...[
            ClipRRect(
              borderRadius: BorderRadius.circular(8),
              child: ConstrainedBox(
                constraints: const BoxConstraints(
                  maxHeight: 170,
                  minWidth: 160,
                  maxWidth: 240,
                ),
                child: Stack(
                  alignment: Alignment.bottomRight,
                  children: [
                    hasLocal
                        ? Image.file(
                            File(localFilePath!),
                            fit: BoxFit.cover,
                            width: 240,
                            errorBuilder: (_, __, ___) => _buildFallbackThumb(icon, accentColor),
                          )
                        : Image.network(
                            remoteUrl!,
                            headers: headers,
                            fit: BoxFit.cover,
                            width: 240,
                            errorBuilder: (_, __, ___) => _buildFallbackThumb(icon, accentColor),
                          ),
                    Container(
                      margin: const EdgeInsets.all(6),
                      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
                      decoration: BoxDecoration(
                        color: Colors.black.withOpacity(0.65),
                        borderRadius: BorderRadius.circular(6),
                      ),
                      child: const Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(Icons.visibility_rounded, size: 11, color: Colors.white),
                          SizedBox(width: 4),
                          Text(
                            'Tap to zoom',
                            style: TextStyle(
                              color: Colors.white,
                              fontSize: 10,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 6),
          ],
          Container(
            constraints: const BoxConstraints(maxWidth: 250),
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: colorScheme.surface.withOpacity(0.6),
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: accentColor.withOpacity(0.35)),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  width: 38,
                  height: 38,
                  decoration: BoxDecoration(
                    color: accentColor.withOpacity(0.15),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Icon(icon, color: accentColor, size: 22),
                ),
                const SizedBox(width: 10),
                Flexible(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        filename,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          color: colorScheme.onSurface,
                          fontSize: 12,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        '$sizeText • View-only',
                        style: TextStyle(
                          color: colorScheme.onSurfaceVariant,
                          fontSize: 10,
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 8),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
                  decoration: BoxDecoration(
                    color: accentColor.withOpacity(0.16),
                    borderRadius: BorderRadius.circular(6),
                  ),
                  child: Text(
                    actionLabel,
                    style: TextStyle(
                      color: accentColor,
                      fontSize: 10,
                      fontWeight: FontWeight.w800,
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

  Widget _buildFallbackThumb(IconData icon, Color accentColor) {
    return Container(
      width: 220,
      height: 110,
      color: accentColor.withOpacity(0.12),
      alignment: Alignment.center,
      child: Icon(icon, size: 36, color: accentColor),
    );
  }
}

/// Full-screen View/Play-Only Media Viewer with hardware FLAG_SECURE and zero save/export options.
class RoomMediaViewerScreen extends StatefulWidget {
  final String filename;
  final int fileSize;
  final RoomMediaCategory category;
  final String? localFilePath;
  final String? remoteUrl;
  final Map<String, String>? headers;

  const RoomMediaViewerScreen({
    super.key,
    required this.filename,
    required this.fileSize,
    required this.category,
    this.localFilePath,
    this.remoteUrl,
    this.headers,
  });

  @override
  State<RoomMediaViewerScreen> createState() => _RoomMediaViewerScreenState();
}

class _RoomMediaViewerScreenState extends State<RoomMediaViewerScreen> {
  static const _securityChannel = MethodChannel('com.cloudpocket.app/security');
  static const _mediaChannel = MethodChannel('com.cloudpocket.app/room_media');

  bool _isLoading = true;
  String? _errorMessage;
  File? _ephemeralTempFile;

  // Text viewer state
  String? _textContent;

  // PDF viewer state
  String? _pdfFilePath;
  int _pdfPageCount = 0;
  int _currentPdfPage = 0;
  final PageController _pdfPageController = PageController();
  final Map<int, Uint8List> _pdfPageCache = {};
  final Set<int> _pdfRenderingPages = {};

  // Audio / Video player state
  int? _textureId;
  double _videoAspectRatio = 16 / 9;
  bool _isPlaying = false;
  int _positionMs = 0;
  int _durationMs = 0;
  Timer? _statusTimer;

  @override
  void initState() {
    super.initState();
    _enableSecureScreen();
    _initMedia();
  }

  Future<void> _enableSecureScreen() async {
    try {
      await _securityChannel.invokeMethod('enableSecureMode', identityHashCode(this).toString());
    } catch (_) {}
  }

  @override
  void dispose() {
    _statusTimer?.cancel();
    _pdfPageController.dispose();
    if (widget.category == RoomMediaCategory.audio ||
        widget.category == RoomMediaCategory.video) {
      _mediaChannel.invokeMethod('mediaRelease').catchError((_) {});
    }
    _securityChannel.invokeMethod('disableSecureMode', identityHashCode(this).toString()).catchError((_) {});
    final temp = _ephemeralTempFile;
    if (temp != null) {
      Future.microtask(() async {
        try {
          if (await temp.exists()) {
            await temp.delete();
          }
        } catch (_) {}
      });
    }
    super.dispose();
  }

  Future<void> _initMedia() async {
    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    try {
      switch (widget.category) {
        case RoomMediaCategory.image:
          if (widget.localFilePath == null && widget.remoteUrl == null) {
            throw Exception('Media source unavailable');
          }
          if (mounted) {
            setState(() => _isLoading = false);
          }
          break;

        case RoomMediaCategory.text:
          await _loadTextContent();
          break;

        case RoomMediaCategory.pdf:
          await _loadPdfDocument();
          break;

        case RoomMediaCategory.audio:
          await _loadAudioOrVideo(isVideo: false);
          break;

        case RoomMediaCategory.video:
          await _loadAudioOrVideo(isVideo: true);
          break;
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _isLoading = false;
          _errorMessage = e.toString().replaceFirst('Exception: ', '');
        });
      }
    }
  }

  /// Streams remote file into a private temporary file in systemTemp (Zero-Buffer compliant)
  /// which is deleted as soon as the viewer closes.
  Future<File> _ensureLocalViewFile() async {
    if (widget.localFilePath != null) {
      final f = File(widget.localFilePath!);
      if (await f.exists()) return f;
    }
    if (_ephemeralTempFile != null && await _ephemeralTempFile!.exists()) {
      return _ephemeralTempFile!;
    }
    if (widget.remoteUrl == null) {
      throw Exception('Media URL unavailable');
    }

    final ext = p.extension(widget.filename);
    final tempFile = File(
      '${Directory.systemTemp.path}${Platform.pathSeparator}cp_view_${DateTime.now().millisecondsSinceEpoch}$ext',
    );


    final client = http.Client();
    try {
      final req = http.Request('GET', Uri.parse(widget.remoteUrl!));
      if (widget.headers != null) {
        req.headers.addAll(widget.headers!);
      }
      final streamed = await client.send(req).timeout(const Duration(seconds: 45));
      if (streamed.statusCode != 200 && streamed.statusCode != 206) {
        throw Exception('Server returned HTTP ${streamed.statusCode}');
      }
      final sink = tempFile.openWrite();
      try {
        await streamed.stream.pipe(sink);
      } finally {
        await sink.close();
      }
      if (!mounted) throw StateError("Viewer closed");
      _ephemeralTempFile = tempFile;
      return tempFile;
    } catch (_) {
      if (await tempFile.exists()) await tempFile.delete();
      rethrow;
    } finally {
      client.close();
    }
  }

  Future<void> _loadTextContent() async {
    const int maxTextBytes = 512 * 1024; // 512 KB cap for safe in-memory text display
    final List<int> bytes = [];

    if (widget.localFilePath != null && await File(widget.localFilePath!).exists()) {
      final stream = File(widget.localFilePath!).openRead(0, maxTextBytes);
      await for (final chunk in stream) {
        bytes.addAll(chunk);
        if (bytes.length >= maxTextBytes) break;
      }
    } else if (widget.remoteUrl != null) {
      final client = http.Client();
      try {
        final req = http.Request('GET', Uri.parse(widget.remoteUrl!));
        if (widget.headers != null) {
          req.headers.addAll(widget.headers!);
        }
        req.headers['range'] = 'bytes=0-${maxTextBytes - 1}';
        final res = await client.send(req).timeout(const Duration(seconds: 20));
        if (res.statusCode != 200 && res.statusCode != 206) {
          throw Exception('Failed to load text (HTTP ${res.statusCode})');
        }
        await for (final chunk in res.stream) {
          bytes.addAll(chunk.take(maxTextBytes - bytes.length));
          if (bytes.length >= maxTextBytes) break;
        }
      } finally {
        client.close();
      }
    } else {
      throw Exception('Text file unavailable');
    }

    final decoded = utf8.decode(bytes, allowMalformed: true);
    if (mounted) {
      setState(() {
        _textContent = decoded;
        _isLoading = false;
      });
    }
  }

  Future<void> _loadPdfDocument() async {
    final file = await _ensureLocalViewFile();
    final count = await _mediaChannel.invokeMethod<int>('pdfGetPageCount', {
      'path': file.path,
    });
    if (count == null || count <= 0) {
      throw Exception('Unable to open PDF pages');
    }
    _pdfFilePath = file.path;
    _pdfPageCount = count;
    await _renderPdfPageIfNeeded(0);
    if (mounted) {
      setState(() => _isLoading = false);
    }
  }

  Future<void> _renderPdfPageIfNeeded(int index) async {
    if (_pdfFilePath == null ||
        index < 0 ||
        index >= _pdfPageCount ||
        _pdfPageCache.containsKey(index) ||
        _pdfRenderingPages.contains(index)) {
      return;
    }
    _pdfRenderingPages.add(index);
    try {
      final bytes = await _mediaChannel.invokeMethod<Uint8List>('pdfRenderPage', {
        'path': _pdfFilePath,
        'pageIndex': index,
        'width': 1280,
      });
      if (bytes != null && mounted) {
        setState(() {
          if (_pdfPageCache.length >= 6) {
            final furthestKey = _pdfPageCache.keys.firstWhere(
              (k) => (k - _currentPdfPage).abs() > 2,
              orElse: () => _pdfPageCache.keys.first,
            );
            _pdfPageCache.remove(furthestKey);
          }
          _pdfPageCache[index] = bytes;
        });
      }
    } catch (_) {
    } finally {
      _pdfRenderingPages.remove(index);
    }
  }

  Future<void> _loadAudioOrVideo({required bool isVideo}) async {
    Map<dynamic, dynamic>? info;
    if (widget.localFilePath != null && await File(widget.localFilePath!).exists()) {
      info = await _mediaChannel.invokeMethod<Map<dynamic, dynamic>>('mediaPrepare', {
        'source': widget.localFilePath,
        'isVideo': isVideo,
      });
    } else if (widget.remoteUrl != null) {
      try {
        info = await _mediaChannel.invokeMethod<Map<dynamic, dynamic>>('mediaPrepare', {
          'source': widget.remoteUrl,
          'isVideo': isVideo,
          'headers': widget.headers ?? <String, String>{},
        });
      } catch (_) {
        // Fallback: stream to ephemeral private temp file and play locally
        final localFile = await _ensureLocalViewFile();
        info = await _mediaChannel.invokeMethod<Map<dynamic, dynamic>>('mediaPrepare', {
          'source': localFile.path,
          'isVideo': isVideo,
        });
      }
    } else {
      throw Exception('Media source unavailable');
    }

    if (info == null) {
      throw Exception('Failed to initialize media player');
    }

    final texId = (info['textureId'] as num?)?.toInt() ?? -1;
    final dur = (info['durationMs'] as num?)?.toInt() ?? 0;
    final w = (info['width'] as num?)?.toInt() ?? 0;
    final h = (info['height'] as num?)?.toInt() ?? 0;

    if (mounted) {
      setState(() {
        _textureId = texId >= 0 ? texId : null;
        _durationMs = dur;
        if (w > 0 && h > 0) {
          _videoAspectRatio = w / h;
        }
        _isLoading = false;
      });
      await _togglePlayPause();
      _startStatusTicker();
    }
  }

  void _startStatusTicker() {
    _statusTimer?.cancel();
    _statusTimer = Timer.periodic(const Duration(milliseconds: 350), (_) async {
      if (!mounted) return;
      try {
        final status = await _mediaChannel.invokeMethod<Map<dynamic, dynamic>>('mediaGetStatus');
        if (status != null && mounted) {
          final playing = status['isPlaying'] == true;
          final pos = (status['positionMs'] as num?)?.toInt() ?? 0;
          final dur = (status['durationMs'] as num?)?.toInt() ?? _durationMs;
          setState(() {
            _isPlaying = playing;
            _positionMs = pos;
            if (dur > 0) _durationMs = dur;
          });
        }
      } catch (_) {}
    });
  }

  Future<void> _togglePlayPause() async {
    try {
      if (_isPlaying) {
        await _mediaChannel.invokeMethod('mediaPause');
        if (mounted) setState(() => _isPlaying = false);
      } else {
        if (_durationMs > 0 && _positionMs >= _durationMs - 300) {
          await _mediaChannel.invokeMethod('mediaSeek', {'positionMs': 0});
        }
        await _mediaChannel.invokeMethod('mediaPlay');
        if (mounted) setState(() => _isPlaying = true);
      }
    } catch (_) {}
  }

  Future<void> _seekTo(int targetMs) async {
    final clamped = targetMs.clamp(0, _durationMs > 0 ? _durationMs : 0);
    setState(() => _positionMs = clamped);
    try {
      await _mediaChannel.invokeMethod('mediaSeek', {'positionMs': clamped});
    } catch (_) {}
  }

  String _formatDuration(int ms) {
    final totalSeconds = (ms ~/ 1000).clamp(0, 86400);
    final m = totalSeconds ~/ 60;
    final s = totalSeconds % 60;
    return '${m.toString().padLeft(2, '0')}:${s.toString().padLeft(2, '0')}';
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final cpColors = Theme.of(context).extension<CloudPocketColors>()!;

    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.black.withOpacity(0.85),
        foregroundColor: Colors.white,
        elevation: 0,
        titleSpacing: 0,
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              widget.filename,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                color: Colors.white,
                fontSize: 14,
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(height: 2),
            Row(
              children: [
                Icon(Icons.shield_rounded, size: 11, color: cpColors.success),
                const SizedBox(width: 4),
                Text(
                  'View only',
                  style: TextStyle(
                    color: cpColors.success,
                    fontSize: 9,
                    fontWeight: FontWeight.w800,
                    letterSpacing: 0.4,
                  ),
                ),
              ],
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: Text(
              'Dismiss & Purge',
              style: TextStyle(
                color: cpColors.danger,
                fontWeight: FontWeight.w700,
                fontSize: 13,
              ),
            ),
          ),
          const SizedBox(width: 8),
        ],
      ),
      body: SafeArea(
        child: _isLoading
            ? Center(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    CircularProgressIndicator(color: colorScheme.primary),
                    const SizedBox(height: 14),
                    const Text(
                      'Opening attachment…',
                      style: TextStyle(color: Colors.white70, fontSize: 13),
                    ),
                  ],
                ),
              )
            : _errorMessage != null
                ? Center(
                    child: Padding(
                      padding: const EdgeInsets.all(24),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(Icons.error_outline_rounded, size: 48, color: cpColors.danger),
                          const SizedBox(height: 12),
                          Text(
                            _errorMessage!,
                            textAlign: TextAlign.center,
                            style: const TextStyle(color: Colors.white, fontSize: 14),
                          ),
                          const SizedBox(height: 16),
                          FilledButton.icon(
                            onPressed: _initMedia,
                            icon: const Icon(Icons.refresh_rounded, size: 18),
                            label: const Text('Retry'),
                          ),
                        ],
                      ),
                    ),
                  )
                : _buildViewerBody(colorScheme, cpColors),
      ),
    );
  }

  Widget _buildViewerBody(ColorScheme colorScheme, CloudPocketColors cpColors) {
    switch (widget.category) {
      case RoomMediaCategory.image:
        final hasLocal = widget.localFilePath != null && File(widget.localFilePath!).existsSync();
        return InteractiveViewer(
          minScale: 0.8,
          maxScale: 5.0,
          child: Center(
            child: hasLocal
                ? Image.file(
                    File(widget.localFilePath!),
                    fit: BoxFit.contain,
                  )
                : Image.network(
                    widget.remoteUrl!,
                    headers: widget.headers,
                    fit: BoxFit.contain,
                  ),
          ),
        );

      case RoomMediaCategory.text:
        return SelectionContainer.disabled(
          child: Container(
            width: double.infinity,
            height: double.infinity,
            color: Colors.black,
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(16),
              child: Text(
                _textContent ?? '',
                style: const TextStyle(
                  color: Color(0xFFE2E8F0),
                  fontSize: 13,
                  height: 1.5,
                  fontFamily: 'monospace',
                ),
              ),
            ),
          ),
        );

      case RoomMediaCategory.pdf:
        return Stack(
          alignment: Alignment.bottomCenter,
          children: [
            PageView.builder(
              controller: _pdfPageController,
              itemCount: _pdfPageCount,
              onPageChanged: (index) {
                setState(() => _currentPdfPage = index);
                _renderPdfPageIfNeeded(index);
                if (index + 1 < _pdfPageCount) {
                  _renderPdfPageIfNeeded(index + 1);
                }
              },
              itemBuilder: (context, index) {
                _renderPdfPageIfNeeded(index);
                final pageBytes = _pdfPageCache[index];
                if (pageBytes == null) {
                  return Center(
                    child: CircularProgressIndicator(color: colorScheme.primary),
                  );
                }
                return InteractiveViewer(
                  minScale: 1.0,
                  maxScale: 4.0,
                  child: Center(
                    child: Image.memory(
                      pageBytes,
                      fit: BoxFit.contain,
                    ),
                  ),
                );
              },
            ),
            Container(
              margin: const EdgeInsets.only(bottom: 16),
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
              decoration: BoxDecoration(
                color: Colors.black.withOpacity(0.75),
                borderRadius: BorderRadius.circular(20),
                border: Border.all(color: Colors.white24),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  IconButton(
                    icon: const Icon(Icons.chevron_left_rounded, color: Colors.white),
                    padding: EdgeInsets.zero,
                    constraints: const BoxConstraints(minWidth: 28, minHeight: 28),
                    onPressed: _currentPdfPage > 0
                        ? () => _pdfPageController.previousPage(
                              duration: const Duration(milliseconds: 220),
                              curve: Curves.easeOut,
                            )
                        : null,
                  ),
                  const SizedBox(width: 8),
                  Text(
                    'Page ${_currentPdfPage + 1} of $_pdfPageCount',
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 12,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const SizedBox(width: 8),
                  IconButton(
                    icon: const Icon(Icons.chevron_right_rounded, color: Colors.white),
                    padding: EdgeInsets.zero,
                    constraints: const BoxConstraints(minWidth: 28, minHeight: 28),
                    onPressed: _currentPdfPage + 1 < _pdfPageCount
                        ? () => _pdfPageController.nextPage(
                              duration: const Duration(milliseconds: 220),
                              curve: Curves.easeOut,
                            )
                        : null,
                  ),
                ],
              ),
            ),
          ],
        );

      case RoomMediaCategory.audio:
        return Center(
          child: Container(
            margin: const EdgeInsets.all(24),
            padding: const EdgeInsets.all(24),
            decoration: BoxDecoration(
              color: const Color(0xFF1C1C1E),
              borderRadius: BorderRadius.circular(24),
              border: Border.all(color: Colors.white12),
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  width: 96,
                  height: 96,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: cpColors.success.withOpacity(0.15),
                    border: Border.all(
                      color: cpColors.success.withOpacity(_isPlaying ? 0.6 : 0.25),
                      width: 2,
                    ),
                  ),
                  child: Icon(
                    _isPlaying ? Icons.graphic_eq_rounded : Icons.music_note_rounded,
                    size: 46,
                    color: cpColors.success,
                  ),
                ),
                const SizedBox(height: 18),
                Text(
                  widget.filename,
                  textAlign: TextAlign.center,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 16,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  '${formatRoomMediaBytes(widget.fileSize)} • Ephemeral Stream',
                  style: const TextStyle(color: Colors.white54, fontSize: 12),
                ),
                const SizedBox(height: 20),
                _buildTransportControls(cpColors.success),
              ],
            ),
          ),
        );

      case RoomMediaCategory.video:
        return Column(
          children: [
            Expanded(
              child: Center(
                child: _textureId != null
                    ? AspectRatio(
                        aspectRatio: _videoAspectRatio > 0 ? _videoAspectRatio : (16 / 9),
                        child: Texture(textureId: _textureId!),
                      )
                    : const Icon(Icons.movie_rounded, size: 64, color: Colors.white38),
              ),
            ),
            Container(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
              color: Colors.black.withOpacity(0.85),
              child: _buildTransportControls(colorScheme.primary),
            ),
          ],
        );
    }
  }

  Widget _buildTransportControls(Color accentColor) {
    final maxMs = _durationMs > 0 ? _durationMs.toDouble() : 1.0;
    final currentMs = _positionMs.toDouble().clamp(0.0, maxMs);

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        SliderTheme(
          data: SliderTheme.of(context).copyWith(
            activeTrackColor: accentColor,
            inactiveTrackColor: Colors.white24,
            thumbColor: accentColor,
            trackHeight: 3.5,
          ),
          child: Slider(
            value: currentMs,
            min: 0.0,
            max: maxMs,
            onChanged: (val) => _seekTo(val.round()),
          ),
        ),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                _formatDuration(_positionMs),
                style: const TextStyle(color: Colors.white70, fontSize: 11),
              ),
              Text(
                _formatDuration(_durationMs),
                style: const TextStyle(color: Colors.white70, fontSize: 11),
              ),
            ],
          ),
        ),
        const SizedBox(height: 8),
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            IconButton(
              onPressed: () => _seekTo(_positionMs - 10000),
              icon: const Icon(Icons.replay_10_rounded, color: Colors.white, size: 28),
              tooltip: 'Rewind 10s',
            ),
            const SizedBox(width: 16),
            InkWell(
              onTap: _togglePlayPause,
              borderRadius: BorderRadius.circular(32),
              child: Container(
                width: 56,
                height: 56,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: accentColor,
                ),
                child: Icon(
                  _isPlaying ? Icons.pause_rounded : Icons.play_arrow_rounded,
                  color: Colors.black,
                  size: 32,
                ),
              ),
            ),
            const SizedBox(width: 16),
            IconButton(
              onPressed: () => _seekTo(_positionMs + 10000),
              icon: const Icon(Icons.forward_10_rounded, color: Colors.white, size: 28),
              tooltip: 'Forward 10s',
            ),
          ],
        ),
      ],
    );
  }
}
