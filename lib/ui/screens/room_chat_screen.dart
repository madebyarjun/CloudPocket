import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:ui';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;
import 'package:path/path.dart' as p;
import 'package:web_socket_channel/web_socket_channel.dart';
import 'package:cloud_pocket/models/chat_message.dart';
import 'package:cloud_pocket/services/e2e_encryption_service.dart';
import 'package:cloud_pocket/services/foreground_service.dart';
import 'package:cloud_pocket/ui/theme.dart';
import 'package:cloud_pocket/ui/widgets/apple_widgets.dart';
import 'package:cloud_pocket/ui/widgets/room_media_viewer.dart';

class RoomChatScreen extends StatefulWidget {
  final String roomUrl;
  final String? initialNickname;
  final String? initialPin;
  final String? initialToken;
  final String? initialRoomName;

  const RoomChatScreen({
    super.key,
    required this.roomUrl,
    this.initialNickname,
    this.initialPin,
    this.initialToken,
    this.initialRoomName,
  });

  @override
  State<RoomChatScreen> createState() => _RoomChatScreenState();
}

class _RoomChatScreenState extends State<RoomChatScreen> {
  static const MethodChannel _securityChannel =
      MethodChannel('com.cloudpocket.app/security');

  WebSocketChannel? _channel;
  final List<ChatMessage> _messages = [];
  final TextEditingController _textController = TextEditingController();
  final ScrollController _scrollController = ScrollController();

  String _nickname = 'App User';
  String _roomName = 'Disposable Room';
  String _roomCode = '';
  String? _activePin;
  String? _activeToken;
  bool _admitted = false;
  String? _myParticipantId;
  String? _attachmentKey;
  int? _participantCount;
  int _remainingSeconds = 0;
  Timer? _countdownTimer;
  Timer? _reconnectTimer;
  bool _isBurned = false;
  bool _isDisposed = false;
  bool _isUploadingMedia = false;
  String _burnReason = '';
  E2eEncryptionService? _e2eService;

  @override
  void initState() {
    super.initState();
    _nickname = widget.initialNickname ?? 'App User';
    _roomName = widget.initialRoomName ?? 'Disposable Room';
    _activePin = widget.initialPin;
    _activeToken = widget.initialToken;
    _initE2e();
    _enableSecureMode();
    CloudPocketForegroundService.acquireLocks();
    _connectToRoom();
  }

  void _initE2e() {
    final secret = E2eEncryptionService.computeSecret(
      token: _activeToken,
      pin: _activePin,
    );
    if (secret != null) {
      _e2eService = E2eEncryptionService.fromSecret(secret);
    } else {
      _e2eService = null;
    }
  }

  Future<void> _enableSecureMode() async {
    try {
      await _securityChannel.invokeMethod(
          'enableSecureMode', identityHashCode(this).toString());
    } catch (_) {}
  }

  Future<void> _disableSecureMode() async {
    try {
      await _securityChannel.invokeMethod(
          'disableSecureMode', identityHashCode(this).toString());
    } catch (_) {}
  }

  @override
  void dispose() {
    _isDisposed = true;
    _countdownTimer?.cancel();
    _reconnectTimer?.cancel();
    _channel?.sink.close();
    _textController.dispose();
    _scrollController.dispose();
    _disableSecureMode();
    super.dispose();
  }

  void _connectToRoom() {
    if (_isDisposed) return;

    try {
      final wsUri = _buildWsUri(widget.roomUrl);
      _channel = WebSocketChannel.connect(wsUri);

      _channel!.stream.listen(
        _handleIncomingMessage,
        onError: (_) => _scheduleReconnect(),
        onDone: () => _scheduleReconnect(),
        cancelOnError: true,
      );

      final joinPayload = {
        'type': 'join',
        'nickname': _nickname,
        'client': 'app',
        'secureMode': true,
        if (_activePin != null && _activePin!.isNotEmpty) 'pin': _activePin,
        if (_activeToken != null) 'token': _activeToken,
      };
      _channel!.sink.add(jsonEncode(joinPayload));
    } catch (_) {
      _scheduleReconnect();
    }
  }

  Uri _buildWsUri(String url) {
    final uri = Uri.parse(url);
    final scheme = uri.scheme == 'https' ? 'wss' : 'ws';
    var path = uri.path;
    if (!path.endsWith('/api/room/ws')) {
      if (path.endsWith('/room')) {
        path = path.replaceFirst(RegExp(r'/room$'), '/api/room/ws');
      } else {
        path = '/api/room/ws';
      }
    }
    return Uri(
      scheme: scheme,
      host: uri.host,
      port: uri.hasPort ? uri.port : null,
      path: path,
      queryParameters:
          uri.queryParameters.isNotEmpty ? uri.queryParameters : null,
    );
  }

  void _scheduleReconnect() {
    if (_isDisposed || _isBurned) return;
    if (mounted && _admitted) setState(() => _admitted = false);
    _reconnectTimer?.cancel();
    _reconnectTimer = Timer(const Duration(seconds: 3), () {
      if (!_isDisposed && !_isBurned) {
        _connectToRoom();
      }
    });
  }

  void _handleIncomingMessage(dynamic raw) {
    if (!mounted || _isDisposed) return;
    if (raw == null) return;
    Map<String, dynamic> json;
    try {
      json = jsonDecode(raw as String) as Map<String, dynamic>;
    } catch (_) {
      return;
    }

    final type = json['type'] as String?;
    switch (type) {
      case 'welcome':
        _activeToken = json['roomToken'] as String? ?? _activeToken;
        _initE2e();
        setState(() {
          _attachmentKey = json['attachmentKey'] as String?;
          _admitted = true;
          _myParticipantId = json['participantId'] as String?;
          _roomName = json['roomName'] as String? ?? _roomName;
          _roomCode = json['roomCode'] as String? ?? '';
          _remainingSeconds = json['remainingSeconds'] as int? ?? 0;

          final history = json['messages'] as List<dynamic>?;
          if (history != null && _messages.isEmpty) {
            for (final item in history) {
              if (item is Map<String, dynamic>) {
                _messages
                    .add(_processIncomingMessage(ChatMessage.fromJson(item)));
              }
            }
          }
        });
        _startLocalCountdown();
        _scrollToBottom();
        break;

      case 'heartbeat':
        final rem = json['remainingSeconds'] as int? ?? 0;
        setState(() {
          _remainingSeconds = rem;
          _participantCount =
              json['participantCount'] as int? ?? _participantCount;
        });
        if (_countdownTimer == null || !_countdownTimer!.isActive) {
          _startLocalCountdown();
        }
        break;

      case 'chat_message':
        final msg = _processIncomingMessage(ChatMessage.fromJson(json));
        setState(() {
          _messages.add(msg);
        });
        _scrollToBottom();
        break;

      case 'room_destroyed':
        final chatRoute = ModalRoute.of(context);
        if (chatRoute != null) Navigator.of(context).popUntil((route) => route == chatRoute || route.isFirst);
        setState(() {
          _isBurned = true;
          _burnReason = json['reason'] as String? ?? 'Room burned';
        });
        break;

      case 'error':
        final code = json['code'] as String?;
        if (code == 'PIN_REQUIRED' || code == 'INVALID_PIN') {
          _promptForPin(isRetry: code == 'INVALID_PIN');
        }
        break;
    }
  }

  ChatMessage _processIncomingMessage(ChatMessage msg) {
    if (msg.isE2e &&
        _e2eService != null &&
        msg.ciphertext != null &&
        msg.iv != null) {
      try {
        final decrypted = _e2eService!.decrypt(
          ciphertext: msg.ciphertext!,
          iv: msg.iv!,
        );
        return msg.copyWith(text: decrypted);
      } catch (_) {
        return msg.copyWith(text: '🔒 [Decryption failed]');
      }
    }
    return msg;
  }

  Future<void> _promptForPin({bool isRetry = false}) async {
    final pinController = TextEditingController();
    final colors = Theme.of(context).extension<CloudPocketColors>() ??
        CloudPocketColors.light;

    final enteredPin = await AppleDialog.show<String>(
      context: context,
      title: Text(isRetry ? 'Incorrect PIN' : 'Room PIN Required'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            isRetry
                ? 'The PIN was incorrect. Please try again:'
                : 'Enter room PIN to join:',
            style: TextStyle(fontSize: 14, color: colors.label2),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 12),
          TextField(
            controller: pinController,
            autofocus: true,
            keyboardType: TextInputType.number,
            style: TextStyle(color: colors.label),
            decoration: InputDecoration(
              hintText: 'PIN',
              hintStyle: TextStyle(color: colors.label2),
              filled: true,
              fillColor: colors.fill,
              border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: BorderSide.none),
            ),
            onSubmitted: (val) => Navigator.of(context).pop(val.trim()),
          ),
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(null),
          child: Text('Leave', style: TextStyle(color: colors.label2)),
        ),
        TextButton(
          onPressed: () => Navigator.of(context).pop(pinController.text.trim()),
          child: Text('Enter',
              style:
                  TextStyle(color: colors.blue, fontWeight: FontWeight.bold)),
        ),
      ],
    );

    if (!mounted) return;

    if (enteredPin != null && enteredPin.isNotEmpty) {
      _activePin = enteredPin;
      _initE2e();
      _channel?.sink.add(jsonEncode({
        'type': 'join',
        'nickname': _nickname,
        'client': 'app',
        'secureMode': true,
        'pin': enteredPin,
        if (_activeToken?.isNotEmpty == true) 'token': _activeToken!,
      }));
    } else {
      Navigator.of(context).pop();
    }
  }

  void _startLocalCountdown() {
    _countdownTimer?.cancel();
    _countdownTimer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (_remainingSeconds > 0) {
        if (mounted) {
          setState(() {
            _remainingSeconds--;
          });
        }
      } else {
        _countdownTimer?.cancel();
      }
    });
  }

  void _scrollToBottom() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scrollController.hasClients) {
        _scrollController.animateTo(
          _scrollController.position.maxScrollExtent,
          duration: const Duration(milliseconds: 250),
          curve: appleCurve,
        );
      }
    });
  }

  void _sendMessage() {
    final text = _textController.text.trim();
    if (!_admitted || text.isEmpty || _channel == null) return;

    if (_e2eService != null) {
      final enc = _e2eService!.encrypt(text);
      _channel!.sink.add(jsonEncode({
        'type': 'message',
        'text': '',
        'e2e': true,
        'ciphertext': enc.ciphertext,
        'iv': enc.iv,
      }));
    } else {
      _channel!.sink.add(jsonEncode({
        'type': 'message',
        'text': text,
      }));
    }

    _textController.clear();
  }

  String _formatRemaining() {
    final m = _remainingSeconds ~/ 60;
    final s = _remainingSeconds % 60;
    return '${m.toString().padLeft(2, '0')}:${s.toString().padLeft(2, '0')}';
  }

  String get _baseHttpUrl {
    final uri = Uri.parse(widget.roomUrl);
    return Uri(
      scheme: uri.scheme,
      host: uri.host,
      port: uri.hasPort ? uri.port : null,
    ).toString();
  }

  Future<void> _pickAndUploadMedia() async {
    try {
      final result = await FilePicker.platform.pickFiles(
        type: FileType.custom,
        allowedExtensions: kAllowedRoomMediaExtensions,
      );
      if (result == null || result.files.isEmpty) return;
      final path = result.files.single.path;
      if (path == null) return;

      final file = File(path);
      if (!await file.exists()) return;

      setState(() => _isUploadingMedia = true);

      final filename = p.basename(file.path);
      final fileSize = await file.length();
      final uploadUri = Uri.parse('$_baseHttpUrl/api/room/upload');
      final req = http.StreamedRequest('POST', uploadUri);
      req.contentLength = fileSize;
      req.headers['X-Filename'] = Uri.encodeComponent(filename);
      req.headers['X-Filesize'] = fileSize.toString();
      req.headers['X-Nickname'] = _nickname;
      req.headers['X-Sender-Id'] = _myParticipantId ?? 'app_user';
      req.headers['X-Secure-Client'] = 'true';
      if (_activeToken?.isNotEmpty == true) {
        req.headers['X-Room-Token'] = _activeToken!;
      }
      if (_activePin != null && _activePin!.isNotEmpty) {
        req.headers['X-Room-Pin'] = _activePin!;
      }

      file.openRead().listen(
            (chunk) => req.sink.add(chunk),
            onDone: () => req.sink.close(),
            onError: (Object err) => req.sink.addError(err),
            cancelOnError: true,
          );

      final streamedRes = await req.send().timeout(const Duration(minutes: 2));
      final res = await http.Response.fromStream(streamedRes);

      if (mounted) {
        setState(() => _isUploadingMedia = false);
        if (res.statusCode != 200) {
          AppleToast.show(
              context, 'Media upload failed (HTTP ${res.statusCode})');
        }
      }
    } catch (_) {
      if (mounted) {
        setState(() => _isUploadingMedia = false);
        AppleToast.show(context, 'Failed to upload media to room');
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).extension<CloudPocketColors>() ??
        CloudPocketColors.light;
    final timeStr = _formatRemaining();

    if (_isBurned) {
      return Scaffold(
        backgroundColor: colors.bg,
        body: Center(
          child: Padding(
            padding: const EdgeInsets.all(24.0),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(Icons.local_fire_department_rounded,
                    size: 64, color: colors.red),
                const SizedBox(height: 16),
                Text(
                  'Room ended',
                  style: TextStyle(
                      fontSize: 22,
                      fontWeight: FontWeight.w700,
                      color: colors.label),
                ),
                const SizedBox(height: 8),
                Text(
                  _burnReason,
                  style: TextStyle(fontSize: 14, color: colors.label2),
                ),
                const SizedBox(height: 24),
                AppleButton.primary(
                  text: 'Exit Room',
                  onPressed: () => Navigator.of(context).pop(),
                ),
              ],
            ),
          ),
        ),
      );
    }

    return Scaffold(
      backgroundColor: colors.bg,
      body: SafeArea(
        child: Column(
          children: [
            // Glass Navigation Bar (.nav)
            ClipRRect(
              child: BackdropFilter(
                filter: ImageFilter.blur(sigmaX: 24, sigmaY: 24),
                child: Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                  decoration: BoxDecoration(
                    color: colors.glass,
                    border: Border(
                        bottom: BorderSide(color: colors.sep, width: 0.5)),
                  ),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      BackButton(color: colors.blue),
                      Expanded(
                          child: Text(_roomName,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                  color: colors.label,
                                  fontSize: 18,
                                  fontWeight: FontWeight.bold))),
                      Icon(Icons.access_time, size: 15, color: colors.orange),
                      const SizedBox(width: 6),
                      Text(timeStr,
                          style: TextStyle(
                              color: colors.red,
                              fontSize: 18,
                              fontFeatures: const [
                                FontFeature.tabularFigures()
                              ])),
                    ],
                  ),
                ),
              ),
            ),

            Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 9),
              color: colors.fill,
              child:
                  Wrap(alignment: WrapAlignment.center, crossAxisAlignment: WrapCrossAlignment.center, spacing: 12, children: [
                if (_participantCount != null) Text('$_participantCount online'),
                TextButton(onPressed: () => showModalBottomSheet<void>(context: context, builder: (_) => SafeArea(
                  child: Padding(padding: const EdgeInsets.all(20), child: Column(mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start, children: [
                      Text(_roomName, style: Theme.of(context).textTheme.titleLarge),
                      if (_roomCode.isNotEmpty) ListTile(title: const Text('Room code'), trailing: Text(_roomCode)),
                      if (_e2eService != null) const ListTile(leading: Icon(Icons.lock_outline), title: Text('Encrypted payloads')),
                      const Text('The host holds the room credentials. When a relay is used, it can access them too.'),
                    ])))),
                  child: const Text('Room details')),
              ]),
            ),
            // Chat Message Feed (.chat)
            Expanded(
              child: CustomPaint(
                  painter: _RoomWatermark(
                      _nickname, colors.label.withOpacity(0.035)),
                  child: ListView.builder(
                    controller: _scrollController,
                    padding: const EdgeInsets.symmetric(
                        horizontal: 16, vertical: 14),
                    itemCount: _messages.length + 1,
                    itemBuilder: (context, index) {
                      if (index == 0) {
                        return const Padding(
                            padding: EdgeInsets.only(bottom: 10),
                            child: Text(
                                'Room files and messages expire when the room closes.',
                                textAlign: TextAlign.center,
                                style: TextStyle(fontSize: 12)));
                      }
                      final msg = _messages[index - 1];
                      final isMe = msg.senderId == _myParticipantId;

                      // System message (.b.sys)
                      if (msg.type == ChatMessageType.system) {
                        return Padding(
                          padding: const EdgeInsets.symmetric(vertical: 4),
                          child: Center(
                            child: Text(
                              msg.text ?? '',
                              textAlign: TextAlign.center,
                              style: TextStyle(
                                fontSize: 12,
                                color: colors.label2,
                                fontFamilyFallback:
                                    CloudPocketTheme.fontFallbacks,
                              ),
                            ),
                          ),
                        );
                      }

                      // Media Attachment Bubble (.b.med)
                      if (msg.type == ChatMessageType.file) {
                        return Align(
                          alignment: isMe
                              ? Alignment.centerRight
                              : Alignment.centerLeft,
                          child: Container(
                            constraints: const BoxConstraints(maxWidth: 280),
                            margin: const EdgeInsets.symmetric(vertical: 5),
                            padding: const EdgeInsets.all(12),
                            decoration: BoxDecoration(
                                color: colors.card,
                                borderRadius: BorderRadius.circular(18)),
                            child: RoomMediaBubble(
                              message: msg,
                              remoteUrl: msg.fileDownloadPath == null
                                  ? null
                                  : '$_baseHttpUrl${msg.fileDownloadPath}',
                              headers: {
                                if (_attachmentKey != null)
                                  'X-Room-View-Key': _attachmentKey!,
                                if (_activePin?.isNotEmpty == true)
                                  'X-Room-Pin': _activePin!,
                                if (_activeToken?.isNotEmpty == true)
                                  'X-Room-Token': _activeToken!,
                              },
                              onViewerClosed: () {
                                if (mounted) _enableSecureMode();
                              },
                            ),
                          ),
                        );
                      }
                      final previous = index > 1 ? _messages[index - 2] : null;
                      final showAuthor = previous == null || previous.type != ChatMessageType.text ||
                          previous.senderId != msg.senderId || previous.isE2e != msg.isE2e ||
                          msg.timestamp.difference(previous.timestamp).inMinutes.abs() >= 2;
                      // Text Message Bubble (.b.out / .b.in)
                      return Align(
                        alignment:
                            isMe ? Alignment.centerRight : Alignment.centerLeft,
                        child: Column(
                            crossAxisAlignment: isMe
                                ? CrossAxisAlignment.end
                                : CrossAxisAlignment.start,
                            children: [
                              if (showAuthor) Padding(
                                  padding: const EdgeInsets.only(top: 12),
                                  child: Wrap(
                                      spacing: 5,
                                      crossAxisAlignment:
                                          WrapCrossAlignment.center,
                                      children: [
                                        CircleAvatar(
                                            radius: 10,
                                            backgroundColor: Color(int.tryParse(
                                                    msg.color.replaceFirst(
                                                        "#", "ff"),
                                                    radix: 16) ??
                                                0xff64748b),
                                            child: Text(
                                                msg.senderNickname.isEmpty
                                                    ? "?"
                                                    : msg.senderNickname
                                                        .characters.first,
                                                style: const TextStyle(
                                                    color: Colors.white,
                                                    fontSize: 10))),
                                        Text(isMe ? "You" : msg.senderNickname,
                                            style: TextStyle(
                                                color: colors.label,
                                                fontSize: 11,
                                                fontWeight: FontWeight.bold)),
                                        Container(
                                            padding: const EdgeInsets.symmetric(
                                                horizontal: 5, vertical: 2),
                                            decoration: BoxDecoration(
                                                color: colors.fill,
                                                borderRadius:
                                                    BorderRadius.circular(5)),
                                            child: Text(
                                                msg.isSecureClient
                                                    ? "App"
                                                    : "Browser",
                                                style: TextStyle(
                                                    color: colors.label2,
                                                    fontSize: 10))),
                                        Text(
                                            TimeOfDay.fromDateTime(
                                                    msg.timestamp.toLocal())
                                                .format(context),
                                            style: TextStyle(
                                                color: colors.label2,
                                                fontSize: 10)),
                                        if (msg.isE2e)
                                          Icon(Icons.lock_outline,
                                              size: 12, color: colors.label2),
                                      ])),
                              Container(
                                margin: const EdgeInsets.symmetric(vertical: 4),
                                padding: const EdgeInsets.symmetric(
                                    horizontal: 14, vertical: 9),
                                constraints: BoxConstraints(
                                    maxWidth:
                                        MediaQuery.of(context).size.width *
                                            0.86),
                                decoration: BoxDecoration(
                                  color: isMe ? colors.blue : colors.card,
                                  borderRadius: BorderRadius.only(
                                    topLeft: const Radius.circular(20),
                                    topRight: const Radius.circular(20),
                                    bottomLeft: Radius.circular(isMe ? 20 : 6),
                                    bottomRight: Radius.circular(isMe ? 6 : 20),
                                  ),
                                  boxShadow: isMe ? null : colors.shadow,
                                ),
                                child: Text(
                                  msg.text ?? '',
                                  style: TextStyle(
                                    fontSize: 15,
                                    color: isMe ? Colors.white : colors.label,
                                    fontFamilyFallback:
                                        CloudPocketTheme.fontFallbacks,
                                  ),
                                ),
                              ),
                            ]),
                      );
                    },
                  )),
            ),

            // Input Bar (.inp)
            Container(
              padding: const EdgeInsets.fromLTRB(12, 10, 12, 14),
              decoration: BoxDecoration(
                  color: colors.glass,
                  border: Border(top: BorderSide(color: colors.sep))),
              child: Row(
                children: [
                  // Attachment button
                  GestureDetector(
                    onTap: !_admitted || _isUploadingMedia ? null : _pickAndUploadMedia,
                    child: Container(
                      width: 36,
                      height: 36,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: colors.fill,
                      ),
                      alignment: Alignment.center,
                      child: _isUploadingMedia
                          ? SizedBox(
                              width: 16,
                              height: 16,
                              child: CircularProgressIndicator(
                                  strokeWidth: 2, color: colors.blue),
                            )
                          : Icon(Icons.add_rounded,
                              color: colors.blue, size: 24),
                    ),
                  ),
                  const SizedBox(width: 8),
                  // Input field
                  Expanded(
                    child: Container(
                      decoration: BoxDecoration(
                        color: colors.card,
                        borderRadius: BorderRadius.circular(20),
                        boxShadow: colors.shadow,
                      ),
                      child: TextField(
                        controller: _textController,
                        minLines: 1,
                        maxLines: 5,
                        style: TextStyle(
                          fontSize: 15,
                          color: colors.label,
                          fontFamilyFallback: CloudPocketTheme.fontFallbacks,
                        ),
                        decoration: InputDecoration(
                          hintText: _admitted ? 'Message' : _myParticipantId == null ? 'Connecting to room…' : 'Reconnecting…',
                          hintStyle: TextStyle(
                            color: colors.label2,
                            fontSize: 15,
                            fontFamilyFallback: CloudPocketTheme.fontFallbacks,
                          ),
                          border: InputBorder.none,
                          contentPadding: const EdgeInsets.symmetric(
                              horizontal: 16, vertical: 11),
                        ),
                        onSubmitted: (_) => _sendMessage(),
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  // Send button (.send: 38x38 circle, blue, white arrow)
                  GestureDetector(
                    onTap: _admitted ? _sendMessage : null,
                    child: Container(
                      width: 46,
                      height: 46,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: colors.blue,
                      ),
                      alignment: Alignment.center,
                      child: const Icon(Icons.send_rounded,
                          color: Colors.white, size: 21),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _RoomWatermark extends CustomPainter {
  final String name;
  final Color color;
  _RoomWatermark(this.name, this.color);

  @override
  void paint(Canvas canvas, Size size) {
    final label = TextPainter(
        text: TextSpan(
            text: name,
            style: TextStyle(
                color: color, fontSize: 19, fontWeight: FontWeight.bold)),
        textDirection: TextDirection.ltr,
        maxLines: 1,
        ellipsis: '…')
      ..layout(maxWidth: 110);
    canvas.save();
    canvas.clipRect(Offset.zero & size);
    for (double y = 16; y < size.height + 26; y += 72) {
      for (double x = 8; x < size.width; x += 126) {
        canvas.save();
        canvas.translate(x, y);
        canvas.rotate(-0.43);
        label.paint(canvas, Offset.zero);
        canvas.restore();
      }
    }
    canvas.restore();
    label.dispose();
  }

  @override
  bool shouldRepaint(_RoomWatermark oldDelegate) =>
      oldDelegate.name != name || oldDelegate.color != color;
}
