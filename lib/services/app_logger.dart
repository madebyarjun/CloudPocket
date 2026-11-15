import 'dart:async';
import 'dart:collection';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';

enum LogLevel {
  debug,
  info,
  warn,
  error,
}

class LogEntry {
  final DateTime timestamp;
  final LogLevel level;
  final String tag;
  final String message;

  const LogEntry({
    required this.timestamp,
    required this.level,
    required this.tag,
    required this.message,
  });

  String get formattedTime {
    final h = timestamp.hour.toString().padLeft(2, '0');
    final m = timestamp.minute.toString().padLeft(2, '0');
    final s = timestamp.second.toString().padLeft(2, '0');
    final ms = timestamp.millisecond.toString().padLeft(3, '0');
    return '$h:$m:$s.$ms';
  }

  @override
  String toString() {
    final lvl = level.name.toUpperCase().padRight(5);
    return '[$formattedTime] [$lvl] [$tag] $message';
  }
}

class AppLogger {
  static final AppLogger _instance = AppLogger._internal();
  factory AppLogger() => _instance;
  AppLogger._internal();

  static const int _maxEntries = 1000;
  final Queue<LogEntry> _entries = Queue<LogEntry>();
  final StreamController<LogEntry> _streamController = StreamController<LogEntry>.broadcast();

  Stream<LogEntry> get onLog => _streamController.stream;

  List<LogEntry> get entries => List.unmodifiable(_entries.toList());

  void log(LogLevel level, String tag, String message) {
    final entry = LogEntry(
      timestamp: DateTime.now(),
      level: level,
      tag: tag.toUpperCase(),
      message: message,
    );

    if (_entries.length >= _maxEntries) {
      _entries.removeFirst();
    }
    _entries.addLast(entry);

    if (kDebugMode) {
      debugPrint(entry.toString());
    }

    _streamController.add(entry);
  }

  void info(String tag, String message) => log(LogLevel.info, tag, message);
  void warn(String tag, String message) => log(LogLevel.warn, tag, message);
  void error(String tag, String message) => log(LogLevel.error, tag, message);
  void debug(String tag, String message) => log(LogLevel.debug, tag, message);

  void clear() {
    _entries.clear();
  }

  String exportToString() {
    final buffer = StringBuffer();
    buffer.writeln('========================================');
    buffer.writeln('CLOUDPOCKET DIAGNOSTIC LOG REPORT');
    buffer.writeln('Generated: ${DateTime.now().toIso8601String()}');
    buffer.writeln('Platform: ${Platform.operatingSystem} ${Platform.operatingSystemVersion}');
    buffer.writeln('Dart: ${Platform.version}');
    buffer.writeln('Total Log Entries: ${_entries.length}');
    buffer.writeln('========================================\n');

    for (final entry in _entries) {
      buffer.writeln(entry.toString());
    }
    return buffer.toString();
  }

  Future<File> saveLogToFile() async {
    final tempDir = await getTemporaryDirectory();
    final now = DateTime.now();
    final timestamp = '${now.year}${now.month.toString().padLeft(2, '0')}${now.day.toString().padLeft(2, '0')}_'
        '${now.hour.toString().padLeft(2, '0')}${now.minute.toString().padLeft(2, '0')}${now.second.toString().padLeft(2, '0')}';
    final file = File('${tempDir.path}/cloudpocket_log_$timestamp.txt');
    await file.writeAsString(exportToString());
    return file;
  }
}
