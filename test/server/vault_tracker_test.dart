import 'package:flutter_test/flutter_test.dart';
import 'package:cloud_pocket/server/vault_tracker.dart';

void main() {
  group('VaultTracker Tests', () {
    test('non-vault mode allows unlimited downloads', () {
      final tracker = VaultTracker(isVaultMode: false);
      expect(tracker.canDownload('/file.pdf'), isTrue);
      tracker.recordDownload('/file.pdf');
      expect(tracker.canDownload('/file.pdf'), isTrue);
      expect(tracker.getRemainingDownloads('/file.pdf'), isNull);
    });

    test('vault mode enforces max download limits', () {
      final tracker = VaultTracker(isVaultMode: true, maxDownloadsPerFile: 2);
      const file = '/shared/secret.pdf';

      expect(tracker.canDownload(file), isTrue);
      expect(tracker.getRemainingDownloads(file), equals(2));

      tracker.recordDownload(file);
      expect(tracker.canDownload(file), isTrue);
      expect(tracker.getRemainingDownloads(file), equals(1));

      tracker.recordDownload(file);
      expect(tracker.canDownload(file), isFalse);
      expect(tracker.getRemainingDownloads(file), equals(0));
    });
  });
}
