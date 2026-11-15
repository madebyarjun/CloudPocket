import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:cloud_pocket/models/transfer_record.dart';

class TransfersNotifier extends Notifier<List<TransferRecord>> {
  @override
  List<TransferRecord> build() => const [];

  void addTransfer(TransferRecord transfer) {
    state = [...state.where((t) => t.id != transfer.id), transfer];
  }

  void updateProgress({
    required String id,
    required int transferredBytes,
    required double speedBytesPerSec,
  }) {
    state = state.map((t) {
      if (t.id == id) {
        final isComplete = t.totalBytes > 0 && transferredBytes >= t.totalBytes;
        final newStatus = isComplete
            ? TransferStatus.completed
            : (t.status == TransferStatus.paused ? TransferStatus.paused : TransferStatus.active);
        return t.copyWith(
          transferredBytes: transferredBytes,
          speedBytesPerSec: (isComplete || t.status == TransferStatus.paused) ? 0.0 : speedBytesPerSec,
          status: newStatus,
        );
      }
      return t;
    }).toList();
  }

  void togglePause(String id) {
    state = state.map((t) {
      if (t.id == id) {
        final newStatus = t.status == TransferStatus.paused
            ? TransferStatus.active
            : TransferStatus.paused;
        return t.copyWith(
          status: newStatus,
          speedBytesPerSec: newStatus == TransferStatus.paused ? 0.0 : t.speedBytesPerSec,
        );
      }
      return t;
    }).toList();
  }

  void completeTransfer(String id) {
    state = state.map((t) {
      if (t.id == id) {
        return t.copyWith(
          transferredBytes: t.totalBytes,
          status: TransferStatus.completed,
          speedBytesPerSec: 0.0,
        );
      }
      return t;
    }).toList();
  }

  void failTransfer(String id, String error) {
    state = state.map((t) {
      if (t.id == id) {
        return t.copyWith(
          status: TransferStatus.failed,
          errorMessage: error,
          speedBytesPerSec: 0.0,
        );
      }
      return t;
    }).toList();
  }

  void clearTransfers() {
    state = const [];
  }
}

final transfersProvider = NotifierProvider<TransfersNotifier, List<TransferRecord>>(
  TransfersNotifier.new,
);
