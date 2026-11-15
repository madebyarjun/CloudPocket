import 'dart:convert';
import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:shelf/shelf.dart';
import 'package:cloud_pocket/server/upload_handler.dart';

void main() {
  group('UploadHandler Comprehensive Tests', () {
    late Directory tempDir;

    setUp(() {
      tempDir = Directory.systemTemp.createTempSync('cp_upload_test_');
    });

    tearDown(() {
      if (tempDir.existsSync()) {
        tempDir.deleteSync(recursive: true);
      }
    });

    test('Rejects uploads when allowUploads is false with 403', () async {
      final handler = UploadHandler(
        saveDirectoryPath: tempDir.path,
        allowUploads: false,
      );

      final req = Request('POST', Uri.parse('http://localhost:8080/api/upload'),
          headers: {'x-filename': 'test.txt'}, body: 'Hello');
      final res = await handler.handleUpload(req);

      expect(res.statusCode, 403);
      final json = jsonDecode(await res.readAsString());
      expect(json['error'], 'UploadsDisabled');
    });

    test('Successfully uploads a file with X-Filename header', () async {
      final handler = UploadHandler(
        saveDirectoryPath: tempDir.path,
        allowUploads: true,
      );

      final req = Request('POST', Uri.parse('http://localhost:8080/api/upload'),
          headers: {'x-filename': 'document.txt'}, body: 'File content 123');
      final res = await handler.handleUpload(req);

      expect(res.statusCode, 200);
      final json = jsonDecode(await res.readAsString());
      expect(json['success'], true);
      expect(json['filename'], 'document.txt');

      final uploadedFile = File('${tempDir.path}/document.txt');
      expect(uploadedFile.existsSync(), true);
      expect(uploadedFile.readAsStringSync(), 'File content 123');
    });

    test('Renames collided files with counter', () async {
      final handler = UploadHandler(
        saveDirectoryPath: tempDir.path,
        allowUploads: true,
      );

      // Create pre-existing file
      File('${tempDir.path}/photo.png').writeAsStringSync('original');

      final req = Request('POST', Uri.parse('http://localhost:8080/api/upload'),
          headers: {'x-filename': 'photo.png'}, body: 'new version');
      final res = await handler.handleUpload(req);

      expect(res.statusCode, 200);
      final json = jsonDecode(await res.readAsString());
      expect(json['filename'], 'photo (1).png');

      expect(File('${tempDir.path}/photo.png').readAsStringSync(), 'original');
      expect(File('${tempDir.path}/photo (1).png').readAsStringSync(), 'new version');
    });

    test('Saves to subfolder when X-Subpath header is provided', () async {
      final handler = UploadHandler(
        saveDirectoryPath: tempDir.path,
        allowUploads: true,
      );

      final req = Request('POST', Uri.parse('http://localhost:8080/api/upload'),
          headers: {
            'x-filename': 'subfile.txt',
            'x-subpath': 'projects/cloud',
          },
          body: 'nested');
      final res = await handler.handleUpload(req);

      expect(res.statusCode, 200);
      final uploadedFile = File('${tempDir.path}/projects/cloud/subfile.txt');
      expect(uploadedFile.existsSync(), true);
      expect(uploadedFile.readAsStringSync(), 'nested');
    });

    test('Sanitizes path traversal in filename', () async {
      final handler = UploadHandler(
        saveDirectoryPath: tempDir.path,
        allowUploads: true,
      );

      final req = Request('POST', Uri.parse('http://localhost:8080/api/upload'),
          headers: {'x-filename': '../../outside.txt'}, body: 'traversal');
      final res = await handler.handleUpload(req);

      expect(res.statusCode, 200);
      final json = jsonDecode(await res.readAsString());
      expect(json['filename'], 'outside.txt');
      expect(File('${tempDir.path}/outside.txt').existsSync(), true);
    });

    test('Normalizes Windows backslashes in X-Subpath correctly', () async {
      final handler = UploadHandler(
        saveDirectoryPath: tempDir.path,
        allowUploads: true,
      );

      final req = Request('POST', Uri.parse('http://localhost:8080/api/upload'),
          headers: {
            'x-filename': 'windows_doc.txt',
            'x-subpath': r'MyFolder\SubFolder',
          },
          body: 'windows path content');
      final res = await handler.handleUpload(req);

      expect(res.statusCode, 200);
      final uploadedFile = File('${tempDir.path}/MyFolder/SubFolder/windows_doc.txt');
      expect(uploadedFile.existsSync(), true);
      expect(uploadedFile.readAsStringSync(), 'windows path content');
    });
  });
}
