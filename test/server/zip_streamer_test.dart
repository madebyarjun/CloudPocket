import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:cloud_pocket/server/zip_streamer.dart';

void main() {
  group('StreamingZipArchive', () {
    late Directory tempDir;
    late File file1;
    late File file2;

    setUp(() async {
      tempDir = await Directory.systemTemp.createTemp('cp_zip_test_');
      file1 = File('${tempDir.path}/hello.txt');
      await file1.writeAsString('Hello, CloudPocket streaming ZIP!');

      file2 = File('${tempDir.path}/data.csv');
      await file2.writeAsString('id,name,value\n1,alpha,100\n2,beta,200\n');
    });

    tearDown(() async {
      if (await tempDir.exists()) {
        await tempDir.delete(recursive: true);
      }
    });

    test('streams multiple files with valid ZIP headers and EOCD', () async {
      final zipChunks = <List<int>>[];
      await for (final chunk in StreamingZipArchive.streamFiles([file1, file2], basePrefix: tempDir.path)) {
        zipChunks.add(chunk);
      }

      final fullZipBytes = zipChunks.expand((c) => c).toList();
      expect(fullZipBytes.isNotEmpty, true);

      // Verify ZIP local header signature at start: 0x50, 0x4b, 0x03, 0x04 ("PK\x03\x04")
      expect(fullZipBytes[0], 0x50);
      expect(fullZipBytes[1], 0x4b);
      expect(fullZipBytes[2], 0x03);
      expect(fullZipBytes[3], 0x04);

      // Verify EOCD signature at end: 0x50, 0x4b, 0x05, 0x06 ("PK\x05\x06")
      final len = fullZipBytes.length;
      expect(fullZipBytes[len - 22], 0x50);
      expect(fullZipBytes[len - 21], 0x4b);
      expect(fullZipBytes[len - 20], 0x05);
      expect(fullZipBytes[len - 19], 0x06);
    });

    test('CRC32 checksum calculation matches expected', () {
      final data = '123456789'.codeUnits;
      final crc = StreamingZipArchive.updateCrc32(0, data);
      // Standard CRC-32 for "123456789" is 0xCBF43926
      expect(crc, 0xcbf43926);
    });
  });
}
