import 'dart:convert';
import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:cloud_pocket/models/share_session.dart';
import 'package:cloud_pocket/server/server_engine.dart';

void main() {
  group('End-to-End Live HTTP Server Integration Tests', () {
    late Directory tempDir;
    late Directory uploadDir;
    late File testFile;

    setUp(() async {
      tempDir = await Directory.systemTemp.createTemp('cp_e2e_test_');
      uploadDir = Directory('${tempDir.path}/Received');
      await uploadDir.create(recursive: true);

      testFile = File('${tempDir.path}/sample.txt');
      await testFile.writeAsString('CloudPocket live HTTP server test data payload.');
    });

    tearDown(() async {
      if (await tempDir.exists()) {
        await tempDir.delete(recursive: true);
      }
    });

    test('Live HTTP: Web assets, file streaming, Range headers, and ZIP download', () async {
      final session = ShareSession(
        items: [
          SharedItem(
            path: testFile.path,
            name: 'sample.txt',
            sizeBytes: await testFile.length(),
            isDirectory: false,
            mimeType: 'text/plain',
          ),
        ],
        requireGoogleAuth: false,
        requirePassword: false,
        allowUploads: true,
      );

      final engine = ServerEngine(
        session: session,
        uploadDir: uploadDir.path,
      );

      final port = await engine.start(preferredPort: 9100);
      final baseUrl = 'http://127.0.0.1:$port';

      try {
        // 1. Verify static web asset route: /styles.css, /favicon.png, /logo.png
        final stylesRes = await http.get(Uri.parse('$baseUrl/styles.css'));
        expect(stylesRes.statusCode, 200);
        expect(stylesRes.headers['content-type'], contains('text/css'));

        final faviconRes = await http.get(Uri.parse('$baseUrl/favicon.png'));
        expect(faviconRes.statusCode, 200);
        expect(faviconRes.headers['content-type'], contains('image/png'));
        expect(faviconRes.bodyBytes.length, greaterThan(100));

        final logoRes = await http.get(Uri.parse('$baseUrl/logo.png'));
        expect(logoRes.statusCode, 200);
        expect(logoRes.headers['content-type'], contains('image/png'));
        expect(logoRes.bodyBytes.length, greaterThan(100));

        // 2. Verify /api/security-mode endpoint
        final secRes = await http.get(Uri.parse('$baseUrl/api/security-mode'));
        expect(secRes.statusCode, 200);
        final secJson = jsonDecode(secRes.body) as Map<String, dynamic>;
        expect(secJson['requireGoogleAuth'], false);
        expect(secJson['requirePassword'], false);
        expect(secJson['allowUploads'], true);
        expect(secJson.containsKey('googleClientId'), true);

        // 3. Verify /api/files listing
        final filesRes = await http.get(Uri.parse('$baseUrl/api/files'));
        expect(filesRes.statusCode, 200);
        final filesJson = jsonDecode(filesRes.body) as Map<String, dynamic>;
        final items = filesJson['items'] as List;
        expect(items.length, 1);
        expect(items[0]['name'], 'sample.txt');

        // 4. Verify streaming file download
        final fileRes = await http.get(Uri.parse('$baseUrl/api/files/sample.txt'));
        expect(fileRes.statusCode, 200);
        expect(fileRes.body, 'CloudPocket live HTTP server test data payload.');
        expect(fileRes.headers['accept-ranges'], 'bytes');

        // 5. Verify HTTP Range request (206 Partial Content)
        final rangeRes = await http.get(
          Uri.parse('$baseUrl/api/files/sample.txt'),
          headers: {'range': 'bytes=0-10'},
        );
        expect(rangeRes.statusCode, 206);
        expect(rangeRes.body, 'CloudPocket');
        expect(rangeRes.headers['content-range'], contains('bytes 0-10/'));

        // 6. Verify streaming ZIP archive download
        final zipRes = await http.get(Uri.parse('$baseUrl/api/download-zip'));
        expect(zipRes.statusCode, 200);
        expect(zipRes.headers['content-type'], 'application/zip');
        expect(zipRes.bodyBytes.length, greaterThan(22)); // Valid ZIP with headers + EOCD
        // Verify ZIP header signature: PK\x03\x04
        expect(zipRes.bodyBytes[0], 0x50);
        expect(zipRes.bodyBytes[1], 0x4b);

        // 7. Verify live file upload directly to disk
        const uploadContent = 'File uploaded from recipient device';
        final uploadReq = http.Request('POST', Uri.parse('$baseUrl/api/upload'));
        uploadReq.headers['x-filename'] = 'uploaded_doc.txt';
        uploadReq.body = uploadContent;
        final streamedUpload = await uploadReq.send();
        final uploadRes = await http.Response.fromStream(streamedUpload);

        expect(uploadRes.statusCode, 200);
        final uploadJson = jsonDecode(uploadRes.body) as Map<String, dynamic>;
        expect(uploadJson['success'], true);
        expect(uploadJson['filename'], 'uploaded_doc.txt');

        // Verify uploaded file physically exists in upload directory
        final savedFile = File('${uploadDir.path}/uploaded_doc.txt');
        expect(await savedFile.exists(), true);
        expect(await savedFile.readAsString(), uploadContent);
      } finally {
        await engine.stop();
        expect(engine.isRunning, false);
      }
    });

    test('Live HTTP: Password authentication and session cookie flow', () async {
      final session = ShareSession(
        items: [
          SharedItem(
            path: testFile.path,
            name: 'sample.txt',
            sizeBytes: await testFile.length(),
            isDirectory: false,
            mimeType: 'text/plain',
          ),
        ],
        requireGoogleAuth: false,
        requirePassword: true,
        passwordHash: ShareSession.hashPassword('pocketPass99'),
      );

      final engine = ServerEngine(
        session: session,
        uploadDir: uploadDir.path,
      );

      final port = await engine.start(preferredPort: 9200);
      final baseUrl = 'http://127.0.0.1:$port';

      try {
        // 1. Unauthenticated request must return 401
        final unauthRes = await http.get(Uri.parse('$baseUrl/api/files'));
        expect(unauthRes.statusCode, 401);

        // 2. Wrong password must return 401
        final wrongPassRes = await http.post(
          Uri.parse('$baseUrl/api/auth/password'),
          headers: {'content-type': 'application/json'},
          body: jsonEncode({'password': 'wrong'}),
        );
        expect(wrongPassRes.statusCode, 401);

        // 3. Correct password must return 200 and issue Set-Cookie
        final authRes = await http.post(
          Uri.parse('$baseUrl/api/auth/password'),
          headers: {'content-type': 'application/json'},
          body: jsonEncode({'password': 'pocketPass99'}),
        );
        expect(authRes.statusCode, 200);
        final setCookie = authRes.headers['set-cookie'];
        expect(setCookie, isNotNull);
        expect(setCookie, contains('cp_session='));

        // Extract session cookie value
        final cookiePart = setCookie!.split(';').first;

        // 4. Authorized request with cookie must return 200
        final authFilesRes = await http.get(
          Uri.parse('$baseUrl/api/files'),
          headers: {'cookie': cookiePart},
        );
        expect(authFilesRes.statusCode, 200);
        final filesJson = jsonDecode(authFilesRes.body) as Map<String, dynamic>;
        expect((filesJson['items'] as List).length, 1);

        // 5. Logout endpoint revokes session
        final logoutRes = await http.post(
          Uri.parse('$baseUrl/api/auth/logout'),
          headers: {'cookie': cookiePart},
        );
        expect(logoutRes.statusCode, 200);

        // 6. After logout, subsequent request must return 401
        final afterLogoutRes = await http.get(
          Uri.parse('$baseUrl/api/files'),
          headers: {'cookie': cookiePart},
        );
        expect(afterLogoutRes.statusCode, 401);
      } finally {
        await engine.stop();
      }
    });

    test('Live HTTP: Disabled uploads returns 403 Forbidden', () async {
      const session = ShareSession(
        items: [],
        requireGoogleAuth: false,
        requirePassword: false,
        allowUploads: false, // Uploads disabled
      );

      final engine = ServerEngine(
        session: session,
        uploadDir: uploadDir.path,
      );

      final port = await engine.start(preferredPort: 9300);
      final baseUrl = 'http://127.0.0.1:$port';

      try {
        final uploadReq = http.Request('POST', Uri.parse('$baseUrl/api/upload'));
        uploadReq.headers['x-filename'] = 'blocked.txt';
        uploadReq.body = 'Should not be saved';
        final streamed = await uploadReq.send();
        final res = await http.Response.fromStream(streamed);

        expect(res.statusCode, 403);
      } finally {
        await engine.stop();
      }
    });

    test('Live HTTP: Shared folder navigation and file download', () async {
      final sharedFolder = Directory('${tempDir.path}/SharedFolder');
      await sharedFolder.create();
      final innerFile1 = File('${sharedFolder.path}/doc1.txt');
      await innerFile1.writeAsString('Doc 1 content');
      final innerFile2 = File('${sharedFolder.path}/doc2.txt');
      await innerFile2.writeAsString('Doc 2 content');

      final session = ShareSession(
        items: [
          SharedItem(
            path: sharedFolder.path,
            name: 'SharedFolder',
            sizeBytes: 100,
            isDirectory: true,
            mimeType: 'inode/directory',
          ),
        ],
        requireGoogleAuth: false,
        requirePassword: false,
      );

      final engine = ServerEngine(
        session: session,
        uploadDir: uploadDir.path,
      );

      final port = await engine.start(preferredPort: 9400);
      final baseUrl = 'http://127.0.0.1:$port';

      try {
        // 1. Root listing for single shared folder immediately returns inner files
        final rootRes = await http.get(Uri.parse('$baseUrl/api/files'));
        expect(rootRes.statusCode, 200);
        final rootJson = jsonDecode(rootRes.body) as Map<String, dynamic>;
        expect(rootJson['isSingleFolderShare'], true);
        expect(rootJson['folderName'], 'SharedFolder');
        final rootItems = rootJson['items'] as List;
        expect(rootItems.length, 2);
        expect(rootItems.any((i) => i['name'] == 'doc1.txt'), true);
        expect(rootItems.any((i) => i['name'] == 'doc2.txt'), true);

        // 2. Subpath listing also returns inner files
        final subRes = await http.get(Uri.parse('$baseUrl/api/files?subpath=SharedFolder'));
        expect(subRes.statusCode, 200);
        final subJson = jsonDecode(subRes.body) as Map<String, dynamic>;
        final subItems = subJson['items'] as List;
        expect(subItems.length, 2);

        // 3. Download inner file directly by name
        final downloadDirectRes = await http.get(Uri.parse('$baseUrl/api/files/doc1.txt'));
        expect(downloadDirectRes.statusCode, 200);
        expect(downloadDirectRes.body, 'Doc 1 content');

        // 4. Download inner file with folder prefix
        final downloadRes = await http.get(Uri.parse('$baseUrl/api/files/SharedFolder/doc1.txt'));
        expect(downloadRes.statusCode, 200);
        expect(downloadRes.body, 'Doc 1 content');

        // 5. Download with encoded slash
        final downloadEncodedRes = await http.get(Uri.parse('$baseUrl/api/files/SharedFolder%2Fdoc2.txt'));
        expect(downloadEncodedRes.statusCode, 200);
        expect(downloadEncodedRes.body, 'Doc 2 content');
      } finally {
        await engine.stop();
      }
    });
  });
}
