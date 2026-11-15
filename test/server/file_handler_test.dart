import 'dart:convert';
import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:shelf/shelf.dart';
import 'package:cloud_pocket/models/share_session.dart';
import 'package:cloud_pocket/server/file_handler.dart';

void main() {
  group('FileHandler', () {
    late Directory tempDir;
    late File sharedFile;
    late File secretFile;
    late ShareSession session;
    late FileHandler handler;

    setUp(() async {
      tempDir = await Directory.systemTemp.createTemp('cp_file_test_');
      sharedFile = File('${tempDir.path}/public.txt');
      await sharedFile.writeAsString('This is public file content for CloudPocket testing.');

      secretFile = File('${tempDir.path}/secret_passwords.txt');
      await secretFile.writeAsString('SUPER_SECRET_KEYS');

      session = ShareSession(
        items: [
          SharedItem(
            path: sharedFile.path,
            name: 'public.txt',
            sizeBytes: await sharedFile.length(),
            isDirectory: false,
            mimeType: 'text/plain',
          ),
        ],
      );

      handler = FileHandler(session);
    });

    tearDown(() async {
      if (await tempDir.exists()) {
        await tempDir.delete(recursive: true);
      }
    });

    test('listFiles returns only configured shared items', () async {
      final req = Request('GET', Uri.parse('http://localhost:8080/api/files'));
      final res = handler.listFiles(req);

      expect(res.statusCode, 200);
      final body = await res.readAsString();
      final json = jsonDecode(body) as Map<String, dynamic>;
      final items = json['items'] as List;
      expect(items.length, 1);
      expect(items[0]['name'], 'public.txt');
    });

    test('serveFile returns 200 with full content for authorized file', () async {
      final req = Request('GET', Uri.parse('http://localhost:8080/api/files/public.txt'));
      final res = await handler.serveFile(req, 'public.txt');

      expect(res.statusCode, 200);
      expect(await res.readAsString(), 'This is public file content for CloudPocket testing.');
      expect(res.headers['content-type'], 'text/plain');
    });

    test('serveFile supports HTTP Range requests (206 Partial Content)', () async {
      final req = Request(
        'GET',
        Uri.parse('http://localhost:8080/api/files/public.txt'),
        headers: {'range': 'bytes=0-3'},
      );
      final res = await handler.serveFile(req, 'public.txt');

      expect(res.statusCode, 206);
      expect(await res.readAsString(), 'This');
      expect(res.headers['content-range'], contains('bytes 0-3/'));
    });

    test('serveFile blocks path traversal attempts with 403', () async {
      // Attempt to access unshared file via directory traversal
      final req = Request('GET', Uri.parse('http://localhost:8080/api/files/..%2Fsecret_passwords.txt'));
      final res = await handler.serveFile(req, '../secret_passwords.txt');

      expect(res.statusCode, 403);
    });

    test('single folder share automatically expands contents at root', () async {
      final subDir = Directory('${tempDir.path}/test_subfolder');
      await subDir.create();
      final nestedFile = File('${subDir.path}/nested.txt');
      await nestedFile.writeAsString('nested content');

      final folderSession = ShareSession(
        items: [
          SharedItem(
            path: subDir.path,
            name: 'test_subfolder',
            sizeBytes: 100,
            isDirectory: true,
            mimeType: 'inode/directory',
          ),
        ],
      );
      final folderHandler = FileHandler(folderSession);

      // Root listing immediately expands the single folder's contents
      final reqTop = Request('GET', Uri.parse('http://localhost:8080/api/files'));
      final resTop = folderHandler.listFiles(reqTop);
      expect(resTop.statusCode, 200);
      final bodyTop = jsonDecode(await resTop.readAsString()) as Map<String, dynamic>;
      expect(bodyTop['isSingleFolderShare'], true);
      expect(bodyTop['folderName'], 'test_subfolder');
      final items = bodyTop['items'] as List;
      expect(items.length, 1);
      expect(items[0]['name'], 'nested.txt');

      // Subpath listing also works directly
      final reqSub = Request('GET', Uri.parse('http://localhost:8080/api/files?subpath=test_subfolder'));
      final resSub = folderHandler.listFiles(reqSub);
      expect(resSub.statusCode, 200);
      final bodySub = jsonDecode(await resSub.readAsString()) as Map<String, dynamic>;
      expect((bodySub['items'] as List).length, 1);
      expect((bodySub['items'] as List)[0]['name'], 'nested.txt');

      // Direct file serve works both via direct name and prefixed path
      final reqFile1 = Request('GET', Uri.parse('http://localhost:8080/api/files/nested.txt'));
      final resFile1 = await folderHandler.serveFile(reqFile1, 'nested.txt');
      expect(resFile1.statusCode, 200);
      expect(await resFile1.readAsString(), 'nested content');

      final reqFile2 = Request('GET', Uri.parse('http://localhost:8080/api/files/test_subfolder/nested.txt'));
      final resFile2 = await folderHandler.serveFile(reqFile2, 'test_subfolder/nested.txt');
      expect(resFile2.statusCode, 200);
      expect(await resFile2.readAsString(), 'nested content');
    });

    test('multi-item share lists top-level containers at root and navigates into folder', () async {
      final subDir = Directory('${tempDir.path}/multi_subfolder');
      await subDir.create();
      final nestedFile = File('${subDir.path}/inner.txt');
      await nestedFile.writeAsString('inner content');

      final multiSession = ShareSession(
        items: [
          SharedItem(
            path: sharedFile.path,
            name: 'public.txt',
            sizeBytes: await sharedFile.length(),
            isDirectory: false,
            mimeType: 'text/plain',
          ),
          SharedItem(
            path: subDir.path,
            name: 'multi_subfolder',
            sizeBytes: 100,
            isDirectory: true,
            mimeType: 'inode/directory',
          ),
        ],
      );
      final multiHandler = FileHandler(multiSession);

      // Root listing returns top-level items
      final reqRoot = Request('GET', Uri.parse('http://localhost:8080/api/files'));
      final resRoot = multiHandler.listFiles(reqRoot);
      expect(resRoot.statusCode, 200);
      final bodyRoot = jsonDecode(await resRoot.readAsString()) as Map<String, dynamic>;
      final rootItems = bodyRoot['items'] as List;
      expect(rootItems.length, 2);
      expect(rootItems.any((i) => i['name'] == 'public.txt'), true);
      expect(rootItems.any((i) => i['name'] == 'multi_subfolder' && i['isDirectory'] == true), true);

      // Navigating into folder
      final reqNav = Request('GET', Uri.parse('http://localhost:8080/api/files?subpath=multi_subfolder'));
      final resNav = multiHandler.listFiles(reqNav);
      expect(resNav.statusCode, 200);
      final bodyNav = jsonDecode(await resNav.readAsString()) as Map<String, dynamic>;
      final navItems = bodyNav['items'] as List;
      expect(navItems.length, 1);
      expect(navItems[0]['name'], 'inner.txt');

      // Test multi-select zip download with specific paths parameter
      final reqZipPaths = Request('GET', Uri.parse('http://localhost:8080/api/download-zip?paths=public.txt'));
      final resZipPaths = await multiHandler.downloadZip(reqZipPaths);
      expect(resZipPaths.statusCode, 200);
      expect(resZipPaths.headers['content-type'], 'application/zip');
      final zipBytes = await resZipPaths.read().expand((c) => c).toList();
      expect(zipBytes.isNotEmpty, true);
      expect(zipBytes[0], 0x50); // 'P'
      expect(zipBytes[1], 0x4b); // 'K'

      // Test multi-select zip download including a folder
      final reqZipFolder = Request('GET', Uri.parse('http://localhost:8080/api/download-zip?paths=multi_subfolder'));
      final resZipFolder = await multiHandler.downloadZip(reqZipFolder);
      expect(resZipFolder.statusCode, 200);
      final folderZipBytes = await resZipFolder.read().expand((c) => c).toList();
      expect(folderZipBytes.isNotEmpty, true);
      expect(folderZipBytes[0], 0x50);
      expect(folderZipBytes[1], 0x4b);

      // Test download zip with invalid path returns 404
      final reqZipInvalid = Request('GET', Uri.parse('http://localhost:8080/api/download-zip?paths=non_existent.txt'));
      final resZipInvalid = await multiHandler.downloadZip(reqZipInvalid);
      expect(resZipInvalid.statusCode, 404);

      // Test POST multi-select zip download with form body (prevents HTTP 414 URL overflow)
      final reqZipPostForm = Request(
        'POST',
        Uri.parse('http://localhost:8080/api/download-zip'),
        headers: {'content-type': 'application/x-www-form-urlencoded'},
        body: 'paths=public.txt',
      );
      final resZipPostForm = await multiHandler.downloadZip(reqZipPostForm);
      expect(resZipPostForm.statusCode, 200);
      expect(resZipPostForm.headers['content-type'], 'application/zip');
      final formZipBytes = await resZipPostForm.read().expand((c) => c).toList();
      expect(formZipBytes.isNotEmpty, true);
      expect(formZipBytes[0], 0x50);
      expect(formZipBytes[1], 0x4b);

      // Test POST multi-select zip download with JSON body
      final reqZipPostJson = Request(
        'POST',
        Uri.parse('http://localhost:8080/api/download-zip'),
        headers: {'content-type': 'application/json'},
        body: jsonEncode({'paths': ['public.txt']}),
      );
      final resZipPostJson = await multiHandler.downloadZip(reqZipPostJson);
      expect(resZipPostJson.statusCode, 200);
      expect(resZipPostJson.headers['content-type'], 'application/zip');
      final jsonZipBytes = await resZipPostJson.read().expand((c) => c).toList();
      expect(jsonZipBytes.isNotEmpty, true);
      expect(jsonZipBytes[0], 0x50);
      expect(jsonZipBytes[1], 0x4b);
    });
  });
}
