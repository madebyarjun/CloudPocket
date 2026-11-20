import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
import 'package:path/path.dart' as p;

class ZipEntryMeta {
  final String relativePath;
  final int offset;
  final int crc32;
  final int compressedSize;
  final int uncompressedSize;
  final int modTime;
  final int modDate;

  ZipEntryMeta({
    required this.relativePath,
    required this.offset,
    required this.crc32,
    required this.compressedSize,
    required this.uncompressedSize,
    required this.modTime,
    required this.modDate,
  });
}

class StreamingZipArchive {
  static final List<int> _crcTable = _makeCrcTable();

  static List<int> _makeCrcTable() {
    final table = List<int>.filled(256, 0);
    for (var n = 0; n < 256; n++) {
      var c = n;
      for (var k = 0; k < 8; k++) {
        if ((c & 1) != 0) {
          c = 0xedb88320 ^ (c >>> 1);
        } else {
          c = c >>> 1;
        }
      }
      table[n] = c;
    }
    return table;
  }

  static int updateCrc32(int crc, List<int> buffer) {
    var c = crc ^ 0xffffffff;
    for (var i = 0; i < buffer.length; i++) {
      c = _crcTable[(c ^ buffer[i]) & 0xff] ^ (c >>> 8);
    }
    return c ^ 0xffffffff;
  }

  /// Streams a collection of files as a single ZIP archive into a `Stream<List<int>>`
  static Stream<List<int>> streamFiles(
    List<File> files, {
    String? basePrefix,
    Map<String, String>? entryPathMap,
  }) async* {
    final entries = <ZipEntryMeta>[];
    var currentOffset = 0;

    for (final file in files) {
      if (!await file.exists()) continue;

      final stat = await file.stat();
      final modDateTime = stat.modified;
      final modTime = (modDateTime.hour << 11) | (modDateTime.minute << 5) | (modDateTime.second ~/ 2);
      final year = modDateTime.year < 1980 ? 1980 : modDateTime.year;
      final modDate = ((year - 1980) << 9) | (modDateTime.month << 5) | modDateTime.day;

      var relName = entryPathMap?[file.path];
      if (relName == null) {
        relName = file.path.replaceAll('\\', '/');
        if (basePrefix != null && relName.startsWith(basePrefix)) {
          relName = relName.substring(basePrefix.length);
        } else if (basePrefix == null) {
          relName = p.basename(file.path);
        }
      }
      if (relName.startsWith('/')) relName = relName.substring(1);

      final nameBytes = Uint8List.fromList(utf8.encode(relName));
      final localHeaderOffset = currentOffset;

      // Local file header with Bit 3 set (data descriptor) & Bit 11 set (UTF-8 filename)
      final localHeader = BytesBuilder();
      localHeader.add([0x50, 0x4b, 0x03, 0x04]); // Local file header signature
      localHeader.add([20, 0]); // Version needed: 2.0
      localHeader.add([0x08, 0x08]); // General purpose bit flag: Bit 3 and Bit 11 set
      localHeader.add([0x00, 0x00]); // Compression method: 0 (Store)
      localHeader.add([modTime & 0xff, (modTime >> 8) & 0xff]);
      localHeader.add([modDate & 0xff, (modDate >> 8) & 0xff]);
      localHeader.add([0, 0, 0, 0]); // CRC-32 (deferred)
      localHeader.add([0, 0, 0, 0]); // Compressed size (deferred)
      localHeader.add([0, 0, 0, 0]); // Uncompressed size (deferred)
      localHeader.add([nameBytes.length & 0xff, (nameBytes.length >> 8) & 0xff]); // File name length
      localHeader.add([0, 0]); // Extra field length
      localHeader.add(nameBytes);

      final localHeaderBytes = localHeader.toBytes();
      currentOffset += localHeaderBytes.length;
      yield localHeaderBytes;

      // Stream file content chunk by chunk
      var crc = 0;
      var fileBytesCount = 0;
      await for (final chunk in file.openRead()) {
        crc = updateCrc32(crc, chunk);
        fileBytesCount += chunk.length;
        currentOffset += chunk.length;
        yield chunk;
      }

      // Data descriptor (signature 0x08074b50, CRC, compressed size, uncompressed size)
      final descriptor = BytesBuilder();
      descriptor.add([0x50, 0x4b, 0x07, 0x08]); // Signature
      descriptor.add([crc & 0xff, (crc >> 8) & 0xff, (crc >> 16) & 0xff, (crc >> 24) & 0xff]);
      descriptor.add([fileBytesCount & 0xff, (fileBytesCount >> 8) & 0xff, (fileBytesCount >> 16) & 0xff, (fileBytesCount >> 24) & 0xff]);
      descriptor.add([fileBytesCount & 0xff, (fileBytesCount >> 8) & 0xff, (fileBytesCount >> 16) & 0xff, (fileBytesCount >> 24) & 0xff]);

      final descriptorBytes = descriptor.toBytes();
      currentOffset += descriptorBytes.length;
      yield descriptorBytes;

      entries.add(ZipEntryMeta(
        relativePath: relName,
        offset: localHeaderOffset,
        crc32: crc,
        compressedSize: fileBytesCount,
        uncompressedSize: fileBytesCount,
        modTime: modTime,
        modDate: modDate,
      ));
    }

    // Central directory records
    final cdStartOffset = currentOffset;
    final cdBuilder = BytesBuilder();

    for (final entry in entries) {
      final nameBytes = Uint8List.fromList(utf8.encode(entry.relativePath));
      cdBuilder.add([0x50, 0x4b, 0x01, 0x02]); // Central directory header signature
      cdBuilder.add([20, 0]); // Version made by: 2.0
      cdBuilder.add([20, 0]); // Version needed: 2.0
      cdBuilder.add([0x08, 0x08]); // Bit 3 and Bit 11 set (UTF-8 filename)
      cdBuilder.add([0x00, 0x00]); // Compression: Store
      cdBuilder.add([entry.modTime & 0xff, (entry.modTime >> 8) & 0xff]);
      cdBuilder.add([entry.modDate & 0xff, (entry.modDate >> 8) & 0xff]);
      cdBuilder.add([entry.crc32 & 0xff, (entry.crc32 >> 8) & 0xff, (entry.crc32 >> 16) & 0xff, (entry.crc32 >> 24) & 0xff]);
      cdBuilder.add([entry.compressedSize & 0xff, (entry.compressedSize >> 8) & 0xff, (entry.compressedSize >> 16) & 0xff, (entry.compressedSize >> 24) & 0xff]);
      cdBuilder.add([entry.uncompressedSize & 0xff, (entry.uncompressedSize >> 8) & 0xff, (entry.uncompressedSize >> 16) & 0xff, (entry.uncompressedSize >> 24) & 0xff]);
      cdBuilder.add([nameBytes.length & 0xff, (nameBytes.length >> 8) & 0xff]);
      cdBuilder.add([0, 0]); // Extra field len
      cdBuilder.add([0, 0]); // Comment len
      cdBuilder.add([0, 0]); // Disk number start
      cdBuilder.add([0, 0]); // Internal attributes
      cdBuilder.add([0, 0, 0, 0]); // External attributes
      cdBuilder.add([entry.offset & 0xff, (entry.offset >> 8) & 0xff, (entry.offset >> 16) & 0xff, (entry.offset >> 24) & 0xff]);
      cdBuilder.add(nameBytes);
    }

    final cdBytes = cdBuilder.toBytes();
    currentOffset += cdBytes.length;
    yield cdBytes;

    // End of central directory record (EOCD)
    final eocd = BytesBuilder();
    eocd.add([0x50, 0x4b, 0x05, 0x06]); // EOCD signature
    eocd.add([0, 0]); // Disk number
    eocd.add([0, 0]); // Disk with CD
    final entryCount = entries.length;
    eocd.add([entryCount & 0xff, (entryCount >> 8) & 0xff]); // Entries on this disk
    eocd.add([entryCount & 0xff, (entryCount >> 8) & 0xff]); // Total entries
    eocd.add([cdBytes.length & 0xff, (cdBytes.length >> 8) & 0xff, (cdBytes.length >> 16) & 0xff, (cdBytes.length >> 24) & 0xff]); // Size of CD
    eocd.add([cdStartOffset & 0xff, (cdStartOffset >> 8) & 0xff, (cdStartOffset >> 16) & 0xff, (cdStartOffset >> 24) & 0xff]); // Offset of CD
    eocd.add([0, 0]); // ZIP comment length

    yield eocd.toBytes();
  }
}
