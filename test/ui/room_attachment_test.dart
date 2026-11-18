import 'package:cloud_pocket/models/chat_message.dart';
import 'package:cloud_pocket/ui/theme.dart';
import 'package:cloud_pocket/ui/widgets/room_media_viewer.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('Room attachments expose the matching viewer action', (tester) async {
    const cases = {
      'image.PNG': 'View Photo',
      'clip.mp4': 'Play Video',
      'report.pdf': 'View PDF',
      'notes.txt': 'Read Text',
      'README.MD': 'Read Markdown',
    };
    for (final entry in cases.entries) {
      await tester.pumpWidget(MaterialApp(
        theme: ThemeData(extensions: const [CloudPocketColors.light]),
        home: Scaffold(body: RoomMediaBubble(message: ChatMessage(
          seq: 1, type: ChatMessageType.file, senderId: 'user',
          senderNickname: 'User', timestamp: DateTime(2026), filename: entry.key,
        ))),
      ));
      expect(find.text(entry.value), findsOneWidget);
    }
  });
}
