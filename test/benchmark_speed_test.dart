// ignore_for_file: avoid_print, unused_local_variable, unnecessary_import, unused_import, curly_braces_in_flow_control_structures

import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:image/image.dart' as img;
import 'package:path/path.dart' as p;
import 'package:cloud_pocket/models/share_session.dart';
import 'package:cloud_pocket/server/server_engine.dart';
import 'package:cloud_pocket/tunnel/bore_client.dart';
import 'package:cloud_pocket/tunnel/localtunnel_client.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  HttpOverrides.global = null;

  test('CLOUDPOCKET SPEED & PERFORMANCE LIVE BENCHMARK', () async {
    print('\n================================================================');
    print('          CLOUDPOCKET SPEED & PERFORMANCE BENCHMARK             ');
    print('================================================================');

    final tempDir = await Directory.systemTemp.createTemp('cp_speed_benchmark_');
    final uploadDir = Directory(p.join(tempDir.path, 'uploads'))..createSync(recursive: true);

    try {
      // 1. Generate test assets
      print('\n[1/5] Generating test payloads & high-res image assets...');
      final file1Mb = File(p.join(tempDir.path, 'payload_1mb.bin'));
      final file10Mb = File(p.join(tempDir.path, 'payload_10mb.bin'));
      final file25Mb = File(p.join(tempDir.path, 'payload_25mb.bin'));

      final chunk1Mb = Uint8List(1024 * 1024);
      for (int i = 0; i < chunk1Mb.length; i++) {
        chunk1Mb[i] = (i % 256);
      }
      await file1Mb.writeAsBytes(chunk1Mb);

      final sink10 = file10Mb.openWrite();
      for (int i = 0; i < 10; i++) sink10.add(chunk1Mb);
      await sink10.close();

      final sink25 = file25Mb.openWrite();
      for (int i = 0; i < 25; i++) sink25.add(chunk1Mb);
      await sink25.close();

      // Create a realistic high-res JPEG photo (3000x2000 pixels)
      print('  Creating high-res photo asset (3000x2000 px)...');
      final rawPhoto = img.Image(width: 3000, height: 2000);
      img.fill(rawPhoto, color: img.ColorRgb8(45, 85, 155));
      for (int y = 0; y < 2000; y += 100) {
        img.drawLine(rawPhoto, x1: 0, y1: y, x2: 3000, y2: y, color: img.ColorRgb8(220, 180, 50));
      }
      final encodedJpeg = img.encodeJpg(rawPhoto, quality: 85);
      final photoFile = File(p.join(tempDir.path, 'photo_highres.jpg'))..writeAsBytesSync(encodedJpeg);

      print('  Generated test assets:');
      print('  - payload_1mb.bin (${(file1Mb.lengthSync() / 1024 / 1024).toStringAsFixed(1)} MB)');
      print('  - payload_10mb.bin (${(file10Mb.lengthSync() / 1024 / 1024).toStringAsFixed(1)} MB)');
      print('  - payload_25mb.bin (${(file25Mb.lengthSync() / 1024 / 1024).toStringAsFixed(1)} MB)');
      print('  - photo_highres.jpg (${(photoFile.lengthSync() / 1024).toStringAsFixed(1)} KB, 3000x2000 px)');

      // 2. Start Shelf ServerEngine
      print('\n[2/5] Starting local Shelf ServerEngine...');
      final session = ShareSession(
        items: [
          SharedItem(
            path: file1Mb.path,
            name: 'payload_1mb.bin',
            sizeBytes: file1Mb.lengthSync(),
            isDirectory: false,
            mimeType: 'application/octet-stream',
          ),
          SharedItem(
            path: file10Mb.path,
            name: 'payload_10mb.bin',
            sizeBytes: file10Mb.lengthSync(),
            isDirectory: false,
            mimeType: 'application/octet-stream',
          ),
          SharedItem(
            path: file25Mb.path,
            name: 'payload_25mb.bin',
            sizeBytes: file25Mb.lengthSync(),
            isDirectory: false,
            mimeType: 'application/octet-stream',
          ),
          SharedItem(
            path: photoFile.path,
            name: 'photo_highres.jpg',
            sizeBytes: photoFile.lengthSync(),
            isDirectory: false,
            mimeType: 'image/jpeg',
          ),
        ],
        allowUploads: true,
      );

      final server = ServerEngine(
        session: session,
        uploadDir: uploadDir.path,
      );
      final boundPort = await server.start(preferredPort: 0);
      final localBaseUrl = 'http://127.0.0.1:$boundPort';
      print('  Server running on $localBaseUrl');

      // 3. Test Localhost / LAN Speed (Simulates direct Wi-Fi / Hotspot)
      print('\n[3/5] Benchmarking Local Network / Wi-Fi / Hotspot Mode...');
      final client = http.Client();

      // TTFB
      final ttfbSw = Stopwatch()..start();
      final listRes = await http.get(Uri.parse('$localBaseUrl/api/files'));
      ttfbSw.stop();
      print('  - Time to First Byte (TTFB): ${ttfbSw.elapsedMilliseconds} ms (Status: ${listRes.statusCode}, reason: ${listRes.reasonPhrase}, headers: ${listRes.headers}, Body: ${listRes.body})');

      // 1 MB download
      final speed1Mb = await _measureDownloadSpeed(client, '$localBaseUrl/api/files/payload_1mb.bin', file1Mb.lengthSync());
      print('  - 1 MB File Download:   ${speed1Mb.durationMs} ms | ${speed1Mb.speedMBs.toStringAsFixed(1)} MB/s (${speed1Mb.speedMbps.toStringAsFixed(1)} Mbps)');

      // 10 MB download
      final speed10Mb = await _measureDownloadSpeed(client, '$localBaseUrl/api/files/payload_10mb.bin', file10Mb.lengthSync());
      print('  - 10 MB File Download:  ${speed10Mb.durationMs} ms | ${speed10Mb.speedMBs.toStringAsFixed(1)} MB/s (${speed10Mb.speedMbps.toStringAsFixed(1)} Mbps)');

      // 25 MB download
      final speed25Mb = await _measureDownloadSpeed(client, '$localBaseUrl/api/files/payload_25mb.bin', file25Mb.lengthSync());
      print('  - 25 MB File Download:  ${speed25Mb.durationMs} ms | ${speed25Mb.speedMBs.toStringAsFixed(1)} MB/s (${speed25Mb.speedMbps.toStringAsFixed(1)} Mbps)');

      // HTTP Range Request (Video streaming seek test: 2 MB slice)
      final rangeSw = Stopwatch()..start();
      final rangeRes = await client.get(
        Uri.parse('$localBaseUrl/api/files/payload_10mb.bin'),
        headers: {'Range': 'bytes=1048576-3145727'}, // 2 MB range
      );
      rangeSw.stop();
      final rangeSpeed = _calculateSpeed(rangeRes.bodyBytes.length, rangeSw.elapsedMilliseconds);
      print('  - HTTP Range (2 MB):    ${rangeSw.elapsedMilliseconds} ms | ${rangeSpeed.speedMBs.toStringAsFixed(1)} MB/s (Status: ${rangeRes.statusCode})');

      // File Upload benchmark (10 MB upload)
      final uploadSw = Stopwatch()..start();
      final uploadReq = http.Request('POST', Uri.parse('$localBaseUrl/api/upload'));
      uploadReq.headers['x-filename'] = 'uploaded_bench_10mb.bin';
      uploadReq.bodyBytes = file10Mb.readAsBytesSync();
      final uploadStreamedRes = await client.send(uploadReq);
      final uploadBody = await uploadStreamedRes.stream.toBytes();
      uploadSw.stop();
      final uploadSpeed = _calculateSpeed(file10Mb.lengthSync(), uploadSw.elapsedMilliseconds);
      print('  - 10 MB File Upload:    ${uploadSw.elapsedMilliseconds} ms | ${uploadSpeed.speedMBs.toStringAsFixed(1)} MB/s (${uploadSpeed.speedMbps.toStringAsFixed(1)} Mbps) (Status: ${uploadStreamedRes.statusCode})');

      // 4. Benchmark Two-Tier Thumbnail Service
      print('\n[4/5] Benchmarking Browsing Tier: Thumbnail Generation & Caching...');
      
      // Cold thumbnail (first request: isolate decode, downscale to 200px, quality 65 JPEG)
      final thumbColdSw = Stopwatch()..start();
      final thumbRes1 = await client.get(Uri.parse('$localBaseUrl/api/thumbnail?path=photo_highres.jpg&size=200'));
      thumbColdSw.stop();
      final etag = thumbRes1.headers['etag'];
      print('  - Cold Thumbnail (3000x2000 -> 200px): ${thumbColdSw.elapsedMilliseconds} ms | Output: ${(thumbRes1.bodyBytes.length / 1024).toStringAsFixed(1)} KB (Status: ${thumbRes1.statusCode})');

      // Warm thumbnail (second request: disk cache hit)
      final thumbWarmSw = Stopwatch()..start();
      final thumbRes2 = await client.get(Uri.parse('$localBaseUrl/api/thumbnail?path=photo_highres.jpg&size=200'));
      thumbWarmSw.stop();
      print('  - Warm Cache Hit (Disk cache):       ${thumbWarmSw.elapsedMilliseconds} ms | Output: ${(thumbRes2.bodyBytes.length / 1024).toStringAsFixed(1)} KB');

      // HTTP 304 Not Modified validation (Browser ETag validation)
      final thumb304Sw = Stopwatch()..start();
      final thumbRes304 = await client.get(
        Uri.parse('$localBaseUrl/api/thumbnail?path=photo_highres.jpg&size=200'),
        headers: {'If-None-Match': etag ?? ''},
      );
      thumb304Sw.stop();
      print('  - HTTP 304 Validation (Browser Cache): ${thumb304Sw.elapsedMilliseconds} ms | Status: ${thumbRes304.statusCode} (0 bytes transferred)');

      // 5 concurrent thumbnail requests (tests isolate worker concurrency limiter & deduplication)
      final parallelSw = Stopwatch()..start();
      final parallelFutures = List.generate(5, (_) => client.get(Uri.parse('$localBaseUrl/api/thumbnail?path=photo_highres.jpg&size=200')));
      final parallelResponses = await Future.wait(parallelFutures);
      parallelSw.stop();
      print('  - 5 Parallel Requests (Deduplicated): ${parallelSw.elapsedMilliseconds} ms total (~${(parallelSw.elapsedMilliseconds / 5).toStringAsFixed(1)} ms/req)');

      // 5. Test Remote Tunnels (Bore & LocalTunnel)
      print('\n[5/5] Benchmarking Remote Internet Tunnels...');

      // Test Bore Tunnel
      print('\n  --- [A] Bore Reverse Proxy Tunnel (TCP Socket Client) ---');
      BoreClient? bore;
      try {
        final boreStartSw = Stopwatch()..start();
        bore = BoreClient(localPort: server.port!);
        final boreUrl = await bore.start().timeout(const Duration(seconds: 10));
        boreStartSw.stop();
        print('  - Bore Tunnel Connected: $boreUrl (Handshake: ${boreStartSw.elapsedMilliseconds} ms)');

        // TTFB over public internet tunnel
        final boreTtfbSw = Stopwatch()..start();
        final boreListRes = await client.get(Uri.parse('$boreUrl/api/files')).timeout(const Duration(seconds: 10));
        boreTtfbSw.stop();
        print('  - Bore Public Internet TTFB: ${boreTtfbSw.elapsedMilliseconds} ms (Status: ${boreListRes.statusCode})');

        // 1 MB download over Bore
        final bore1Mb = await _measureDownloadSpeed(client, '$boreUrl/api/files/payload_1mb.bin', file1Mb.lengthSync(), timeoutSec: 20);
        print('  - Bore 1 MB Download:        ${bore1Mb.durationMs} ms | ${bore1Mb.speedMBs.toStringAsFixed(2)} MB/s (${bore1Mb.speedMbps.toStringAsFixed(1)} Mbps)');

        // Thumbnail over Bore
        final boreThumbSw = Stopwatch()..start();
        final boreThumbRes = await client.get(Uri.parse('$boreUrl/api/thumbnail?path=photo_highres.jpg&size=200')).timeout(const Duration(seconds: 10));
        boreThumbSw.stop();
        print('  - Bore Thumbnail Fetch:      ${boreThumbSw.elapsedMilliseconds} ms (${(boreThumbRes.bodyBytes.length / 1024).toStringAsFixed(1)} KB)');
      } catch (e) {
        print('  - Bore Tunnel Note: Relay skipped or unreachable ($e)');
      } finally {
        bore?.stop();
      }

      // Test LocalTunnel
      print('\n  --- [B] LocalTunnel (HTTPS Relay) ---');
      LocaltunnelClient? lt;
      try {
        final ltStartSw = Stopwatch()..start();
        lt = LocaltunnelClient(localPort: server.port!);
        final ltUrl = await lt.start().timeout(const Duration(seconds: 10));
        ltStartSw.stop();
        print('  - LocalTunnel Connected: $ltUrl (Handshake: ${ltStartSw.elapsedMilliseconds} ms)');

        // TTFB over LocalTunnel
        final ltTtfbSw = Stopwatch()..start();
        final ltListRes = await client.get(
          Uri.parse('$ltUrl/api/files'),
          headers: {'Bypass-Tunnel-Reminder': 'true'},
        ).timeout(const Duration(seconds: 10));
        ltTtfbSw.stop();
        print('  - LocalTunnel HTTPS TTFB:    ${ltTtfbSw.elapsedMilliseconds} ms (Status: ${ltListRes.statusCode})');

        // 1 MB download over LocalTunnel
        final lt1Mb = await _measureDownloadSpeed(
          client,
          '$ltUrl/api/files/payload_1mb.bin',
          file1Mb.lengthSync(),
          headers: {'Bypass-Tunnel-Reminder': 'true'},
          timeoutSec: 25,
        );
        print('  - LocalTunnel 1 MB Download: ${lt1Mb.durationMs} ms | ${lt1Mb.speedMBs.toStringAsFixed(2)} MB/s (${lt1Mb.speedMbps.toStringAsFixed(1)} Mbps)');
      } catch (e) {
        print('  - LocalTunnel Note: Relay skipped or unreachable ($e)');
      } finally {
        lt?.stop();
      }

      // Stop server
      await server.stop();
      client.close();

      print('\n================================================================');
      print('                      BENCHMARK COMPLETE                        ');
      print('================================================================\n');
    } finally {
      if (tempDir.existsSync()) {
        try {
          tempDir.deleteSync(recursive: true);
        } catch (_) {}
      }
    }
  }, timeout: const Timeout(Duration(minutes: 3)));
}

class SpeedResult {
  final int durationMs;
  final double speedMBs;
  final double speedMbps;
  final int bytesReceived;

  SpeedResult({
    required this.durationMs,
    required this.speedMBs,
    required this.speedMbps,
    required this.bytesReceived,
  });
}

Future<SpeedResult> _measureDownloadSpeed(
  http.Client client,
  String url,
  int expectedBytes, {
  Map<String, String>? headers,
  int timeoutSec = 25,
}) async {
  final sw = Stopwatch()..start();
  final req = http.Request('GET', Uri.parse(url));
  if (headers != null) req.headers.addAll(headers);

  final streamedRes = await client.send(req).timeout(Duration(seconds: timeoutSec));
  var bytesCount = 0;
  await for (final chunk in streamedRes.stream) {
    bytesCount += chunk.length;
  }
  sw.stop();

  return _calculateSpeed(bytesCount, sw.elapsedMilliseconds);
}

SpeedResult _calculateSpeed(int bytes, int durationMs) {
  final durationSec = durationMs > 0 ? (durationMs / 1000.0) : 0.001;
  final speedMBs = (bytes / (1024.0 * 1024.0)) / durationSec;
  final speedMbps = speedMBs * 8.0;
  return SpeedResult(
    durationMs: durationMs,
    speedMBs: speedMBs,
    speedMbps: speedMbps,
    bytesReceived: bytes,
  );
}
