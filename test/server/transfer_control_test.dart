import 'dart:io';
import 'dart:typed_data';
import 'package:flutter_test/flutter_test.dart';
import 'package:shelf/shelf.dart';
import 'package:cloud_pocket/models/share_session.dart';
import 'package:cloud_pocket/server/server_engine.dart';
import 'package:cloud_pocket/server/upload_handler.dart';

void main() {
  test('Cancelling a paused transfer wakes and terminates its server wait', () async {
    final engine = ServerEngine(session: const ShareSession(), uploadDir: Directory.systemTemp.path);
    engine.togglePauseTransfer('fixture.bin');
    final wait = engine.waitIfPaused('fixture.bin');
    final result = expectLater(wait, throwsStateError);
    engine.cancelTransfer('fixture.bin');
    await result;
    expect(engine.isTransferCancelled('fixture.bin'), isTrue);
    expect(engine.isTransferPaused('fixture.bin'), isFalse);
  });

  test('Cancelled upload removes its incomplete file before returning', () async {
    final directory = await Directory.systemTemp.createTemp('cp_cancel_');
    addTearDown(() => directory.delete(recursive: true));
    var checks = 0;
    final handler = UploadHandler(
      saveDirectoryPath: directory.path, allowUploads: true,
      pauseChecker: (_) async { if (++checks == 2) throw StateError('Transfer cancelled'); },
    );
    final response = await handler.handleUpload(Request(
      'POST', Uri.parse('http://localhost/api/upload'),
      headers: {'x-filename': 'fixture.bin'},
      body: Stream<List<int>>.fromIterable(List.generate(4, (_) => Uint8List(512 * 1024))),
    ));
    expect(response.statusCode, 500);
    expect(await directory.list().toList(), isEmpty);
  });
}
