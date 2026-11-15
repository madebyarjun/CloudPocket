import 'dart:convert';
import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:shelf/shelf.dart';
import 'package:http/http.dart' as http;
import 'package:cloud_pocket/server/server_engine.dart';
import 'package:cloud_pocket/models/share_session.dart';
import 'package:cloud_pocket/server/file_handler.dart';
import 'package:cloud_pocket/server/security_headers.dart';
import 'package:cloud_pocket/server/upload_handler.dart';
import 'package:cloud_pocket/server/vault_tracker.dart';

void main() {
  late Directory directory;
  setUp(() { directory = Directory.systemTemp.createTempSync('cp_hardening_'); });
  tearDown(() async { await directory.delete(recursive: true); });

  test('simultaneous same-name uploads preserve every body and remove temp files', () async {
    final handler = UploadHandler(saveDirectoryPath: directory.path, allowUploads: true);
    final responses = await Future.wait(List.generate(8, (i) => handler.handleUpload(
      Request('POST', Uri.parse('http://localhost/api/upload'), headers: {'x-filename': 'same.txt'}, body: 'body-$i'))));
    expect(responses.map((r) => r.statusCode), everyElement(200));
    final files = directory.listSync().whereType<File>().toList();
    expect(files.length, 8);
    expect(files.map((f) => f.readAsStringSync()).toSet(), Set.from(List.generate(8, (i) => 'body-$i')));
    expect(files.any((f) => f.path.endsWith('.tmp')), isFalse);
  });

  test('upload rejects escaped folders and invalid names without writing files', () async {
    final handler = UploadHandler(saveDirectoryPath: directory.path, allowUploads: true);
    for (final headers in [
      {'x-filename': 'bad.txt', 'x-subpath': '..%2Foutside'},
      {'x-filename': '..'},
      {'x-filename': 'bad%00.txt'},
    ]) {
      final response = await handler.handleUpload(Request('POST', Uri.parse('http://localhost/api/upload'), headers: headers, body: 'data'));
      expect(response.statusCode, anyOf(400, 403));
    }
    expect(directory.listSync(), isEmpty);
  });

  test('receive and room endpoints cannot serve residual Send files or ZIPs', () async {
    final file = File('${directory.path}/old.txt')..writeAsStringSync('old Send data');
    final item = SharedItem(path: file.path, name: 'old.txt', sizeBytes: 13, isDirectory: false, mimeType: 'text/plain');
    for (final session in [ShareSession(items: [item], isReceiveMode: true), ShareSession(items: [item], isDisposableRoom: true)]) {
      final handler = FileHandler(session);
      final listing = jsonDecode(await handler.listFiles(Request('GET', Uri.parse('http://localhost/api/files'))).readAsString());
      expect(listing['items'], isEmpty);
      expect((await handler.serveFile(Request('GET', Uri.parse('http://localhost/api/files/old.txt')), 'old.txt')).statusCode, 403);
      expect((await handler.downloadZip(Request('POST', Uri.parse('http://localhost/api/download-zip'), body: '{}'))).statusCode, 403);
    }
  });

  test('active shared content is downloaded rather than executed in portal origin', () async {
    final file = File('${directory.path}/page.html')..writeAsStringSync('<script>alert(1)</script>');
    final handler = FileHandler(ShareSession(items: [SharedItem(path: file.path, name: 'page.html', sizeBytes: 25, isDirectory: false, mimeType: 'text/html')]));
    final response = await securityHeaders()((request) => handler.serveFile(request, 'page.html'))(Request('GET', Uri.parse('http://localhost/api/files/page.html')));
    expect(response.headers['content-disposition'], startsWith('attachment;'));
    expect(response.headers['content-security-policy'], contains('sandbox;'));
    expect(response.headers['x-content-type-options'], 'nosniff');
  });

  test('control bodies bounded with and without Content-Length; uploads stream', () async {
    var called = false;
    final endpoint = securityHeaders()((request) async { called = true; return Response.ok(await request.readAsString()); });
    final large = List.filled(65537, 65);
    for (final body in [large, Stream<List<int>>.fromIterable([large.sublist(0, 40000), large.sublist(40000)])]) {
      final response = await endpoint(Request('POST', Uri.parse('http://localhost/api/auth/password'), body: body));
      expect(response.statusCode, 413);
      expect(called, isFalse);
    }
    expect((await endpoint(Request('POST', Uri.parse('http://localhost/api/upload'), body: large))).statusCode, 200);
    expect(called, isTrue);
  });
  test('live server serves shared theme and refuses foreign browser origins', () async {
    final engine = ServerEngine(session: const ShareSession(), uploadDir: directory.path);
    final port = await engine.start(preferredPort: 0);
    addTearDown(engine.stop);
    final base = 'http://127.0.0.1:$port';
    for (final path in ['/theme.css', '/theme.js']) {
      expect((await http.get(Uri.parse('$base$path'))).statusCode, 200);
    }
    final foreign = await http.get(Uri.parse('$base/api/files'), headers: {'origin': 'https://foreign.example'});
    expect(foreign.statusCode, 403);
    expect(foreign.headers['access-control-allow-origin'], isNull);
    final same = await http.get(Uri.parse('$base/api/files'), headers: {'origin': base});
    expect(same.statusCode, 200);
    expect(same.headers['access-control-allow-origin'], base);
    expect(same.headers['cache-control'], 'no-store');
  });

  test('vault reserves before streaming so parallel and Range requests cannot bypass access', () async {
    final file = File('${directory.path}/limited.txt')..writeAsStringSync('limited data');
    final tracker = VaultTracker(isVaultMode: true, maxDownloadsPerFile: 1);
    final handler = FileHandler(ShareSession(items: [SharedItem(path: file.path, name: 'limited.txt', sizeBytes: 12, isDirectory: false, mimeType: 'text/plain')]), vaultTracker: tracker);
    final responses = await Future.wait(List.generate(4, (_) => handler.serveFile(Request('GET', Uri.parse('http://localhost/api/files/limited.txt'), headers: {'range': 'bytes=0-3'}), 'limited.txt')));
    expect(responses.where((r) => r.statusCode == 206).length, 1);
    expect(responses.where((r) => r.statusCode == 410).length, 3);
    // Access is reserved even before the accepted body is consumed.
    expect(tracker.getRemainingDownloads(file.path), 0);
    expect(await responses.firstWhere((r) => r.statusCode == 206).readAsString(), 'limi');
  });

  test('invalid ranges do not consume access; ordinary responses reserve immediately', () async {
    final file = File('${directory.path}/limited.txt')..writeAsStringSync('limited data');
    final tracker = VaultTracker(isVaultMode: true, maxDownloadsPerFile: 1);
    final handler = FileHandler(ShareSession(items: [SharedItem(path: file.path, name: 'limited.txt', sizeBytes: 12, isDirectory: false, mimeType: 'text/plain')]), vaultTracker: tracker);
    expect((await handler.serveFile(Request('GET', Uri.parse('http://localhost/api/files/limited.txt'), headers: {'range': 'bytes=99-100'}), 'limited.txt')).statusCode, 416);
    expect(tracker.getRemainingDownloads(file.path), 1);
    expect((await handler.serveFile(Request('GET', Uri.parse('http://localhost/api/files/limited.txt')), 'limited.txt')).statusCode, 200);
    expect((await handler.serveFile(Request('GET', Uri.parse('http://localhost/api/files/limited.txt')), 'limited.txt')).statusCode, 410);
  });

  test('archive quota reservation is atomic and repeated entries count once', () {
    final tracker = VaultTracker(isVaultMode: true, maxDownloadsPerFile: 1);
    tracker.recordDownload('spent');
    expect(tracker.reserveDownloads(['fresh', 'spent']), isFalse);
    expect(tracker.getRemainingDownloads('fresh'), 1);
    expect(tracker.reserveDownloads(['fresh', 'fresh']), isTrue);
    expect(tracker.getRemainingDownloads('fresh'), 0);
  });

}
