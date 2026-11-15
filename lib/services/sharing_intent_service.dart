import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:mime/mime.dart';
import 'package:path/path.dart' as p;
import 'package:cloud_pocket/main.dart';
import 'package:cloud_pocket/models/share_session.dart';
import 'package:cloud_pocket/providers/session_provider.dart';
import 'package:cloud_pocket/ui/app_shell.dart';
import 'package:cloud_pocket/ui/screens/room_chat_screen.dart';
import 'package:cloud_pocket/ui/widgets/apple_widgets.dart';

/// Handles incoming files and text shared into CloudPocket via the Android Share Sheet.
class SharingIntentService {
  static const MethodChannel _channel = MethodChannel('com.cloudpocket.app/sharing_intent');

  /// Set up listeners for runtime shares and check for cold-start share intents.
  static void initialize(WidgetRef ref) {
    _channel.setMethodCallHandler((call) async {
      if (call.method == 'onSharedDataReceived') {
        final data = call.arguments;
        if (data is Map) {
          _processSharedData(ref, Map<String, dynamic>.from(data));
        }
      }
    });

    // Check for cold-start share intent
    _channel.invokeMethod<Map<dynamic, dynamic>>('getInitialSharedData').then((data) {
      if (data != null && data.isNotEmpty) {
        _processSharedData(ref, Map<String, dynamic>.from(data));
      }
    }).catchError((_) {});
  }

  /// Process incoming shared files and text payload into active ShareSession
  static void _processSharedData(WidgetRef ref, Map<String, dynamic> data) {
    processSharedData(
      setIsReceiveMode: (val) => ref.read(sessionProvider.notifier).setIsReceiveMode(val),
      addItems: (items) => ref.read(sessionProvider.notifier).addItems(items),
      setActiveTab: (tab) => ref.read(activeTabProvider.notifier).state = tab,
      setSharedText: (text) => ref.read(sessionProvider.notifier).setSharedText(text),
      data: data,
    );
  }

  /// Extracted processing logic that is directly testable and UI-decoupled
  static void processSharedData({
    required void Function(bool) setIsReceiveMode,
    required void Function(List<SharedItem>) addItems,
    required void Function(int) setActiveTab,
    void Function(String)? setSharedText,
    required Map<String, dynamic> data,
    bool showFeedback = true,
  }) {
    final roomUrl = data['roomUrl'] as String?;
    if (roomUrl != null && roomUrl.isNotEmpty) {
      final pin = data['roomPin'] as String?;
      final nick = data['roomNick'] as String?;
      final nav = rootNavigatorKey.currentState;
      if (nav != null) {
        nav.push(
          MaterialPageRoute(
            builder: (_) => RoomChatScreen(
              roomUrl: roomUrl,
              initialPin: pin,
              initialNickname: nick,
            ),
          ),
        );
      }
      return;
    }

    final rawFiles = data['files'];
    final rawText = data['text'] as String?;

    final validItems = <SharedItem>[];
    if (rawFiles is List && rawFiles.isNotEmpty) {
      for (final rawPath in rawFiles) {
        final path = rawPath.toString();
        final file = File(path);
        if (file.existsSync()) {
          final stat = file.statSync();
          final name = p.basename(path);
          final mime = lookupMimeType(path) ?? 'application/octet-stream';
          validItems.add(SharedItem(
            path: path,
            name: name,
            sizeBytes: stat.size,
            isDirectory: false,
            mimeType: mime,
          ));
        } else {
          final dir = Directory(path);
          if (dir.existsSync()) {
            final name = p.basename(path);
            validItems.add(SharedItem(
              path: path,
              name: name,
              sizeBytes: 0,
              isDirectory: true,
              mimeType: 'inode/directory',
            ));
          }
        }
      }

      if (validItems.isNotEmpty) {
        // Ensure in Send Mode
        setIsReceiveMode(false);
        addItems(validItems);
        // Switch to Home screen
        setActiveTab(0);

        if (showFeedback) {
          final ctx = rootScaffoldMessengerKey.currentContext;
          if (ctx != null) {
            AppleToast.show(ctx, 'Added ${validItems.length} shared file${validItems.length > 1 ? "s" : ""} to CloudPocket');
          }
        }
      }
    }

    if (rawText != null && rawText.trim().isNotEmpty) {
      setSharedText?.call(rawText.trim());
      setActiveTab(0);

      if (validItems.isEmpty && showFeedback) {
        final ctx = rootScaffoldMessengerKey.currentContext;
        if (ctx != null) {
          AppleToast.show(ctx, 'Shared text note added to CloudPocket');
        }
      }
    }
  }
}
