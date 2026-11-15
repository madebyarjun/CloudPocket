import 'dart:convert';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:cloud_pocket/models/share_history.dart';

const String _kHistoryStorageKey = 'cloudpocket_share_history_v1';

class HistoryNotifier extends Notifier<List<ShareHistoryRecord>> {
  @override
  List<ShareHistoryRecord> build() {
    _loadFromStorage();
    return const [];
  }

  Future<void> _loadFromStorage() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final jsonString = prefs.getString(_kHistoryStorageKey);
      if (jsonString != null && jsonString.isNotEmpty) {
        final List<dynamic> decoded = jsonDecode(jsonString);
        state = decoded
            .map((e) => ShareHistoryRecord.fromJson(e as Map<String, dynamic>))
            .toList();
      }
    } catch (_) {
      // Graceful fallback to empty list
    }
  }

  Future<void> addRecord(ShareHistoryRecord record) async {
    state = [record, ...state];
    await _saveToStorage();
  }

  Future<void> deleteRecord(String id) async {
    state = state.where((r) => r.id != id).toList();
    await _saveToStorage();
  }

  Future<void> clearHistory() async {
    state = const [];
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_kHistoryStorageKey);
  }

  Future<void> _saveToStorage() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final jsonString = jsonEncode(state.map((r) => r.toJson()).toList());
      await prefs.setString(_kHistoryStorageKey, jsonString);
    } catch (_) {}
  }
}

final historyProvider = NotifierProvider<HistoryNotifier, List<ShareHistoryRecord>>(
  HistoryNotifier.new,
);
