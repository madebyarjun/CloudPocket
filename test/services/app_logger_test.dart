import 'package:flutter_test/flutter_test.dart';
import 'package:cloud_pocket/services/app_logger.dart';

void main() {
  group('AppLogger Unit Tests', () {
    final logger = AppLogger();

    setUp(() {
      logger.clear();
    });

    test('records entries with correct level and tag', () {
      logger.info('SERVER', 'Server started');
      logger.warn('TUNNEL', 'High latency detected');
      logger.error('AUTH', 'Invalid PIN');
      logger.debug('NETWORK', 'Packet received');

      final entries = logger.entries;
      expect(entries.length, equals(4));

      expect(entries[0].level, equals(LogLevel.info));
      expect(entries[0].tag, equals('SERVER'));
      expect(entries[0].message, equals('Server started'));

      expect(entries[1].level, equals(LogLevel.warn));
      expect(entries[1].tag, equals('TUNNEL'));

      expect(entries[2].level, equals(LogLevel.error));
      expect(entries[2].tag, equals('AUTH'));

      expect(entries[3].level, equals(LogLevel.debug));
      expect(entries[3].tag, equals('NETWORK'));
    });

    test('entry toString formats properly', () {
      final entry = LogEntry(
        timestamp: DateTime(2026, 9, 11, 14, 30, 45, 123),
        level: LogLevel.info,
        tag: 'TEST',
        message: 'Hello World',
      );

      expect(entry.formattedTime, equals('14:30:45.123'));
      expect(entry.toString(), equals('[14:30:45.123] [INFO ] [TEST] Hello World'));
    });

    test('exportToString contains diagnostics header and entries', () {
      logger.info('TEST', 'Sample diagnostic entry');
      final export = logger.exportToString();

      expect(export, contains('CLOUDPOCKET DIAGNOSTIC LOG REPORT'));
      expect(export, contains('[TEST] Sample diagnostic entry'));
      expect(export, contains('Total Log Entries: 1'));
    });

    test('clear removes all entries', () {
      logger.info('TEST', 'To be cleared');
      expect(logger.entries.length, equals(1));

      logger.clear();
      expect(logger.entries.isEmpty, isTrue);
    });

    test('stream emits new log entries', () async {
      final expectation = expectLater(
        logger.onLog,
        emits(predicate<LogEntry>((e) => e.tag == 'STREAM' && e.message == 'Stream message')),
      );

      logger.info('STREAM', 'Stream message');
      await expectation;
    });
  });
}
