import 'dart:math';
import 'package:cloud_pocket/services/pocket_link_words.dart';

class PocketLinkGenerator {
  static final _random = Random();

  /// Generates a memorable 3-segment slug like `swift-forest-moon` or `pocket-river-star`
  static String generateSlug({String? prefix}) {
    final adj = PocketLinkWords.adjectives[_random.nextInt(PocketLinkWords.adjectives.length)];
    final noun1 = PocketLinkWords.nouns[_random.nextInt(PocketLinkWords.nouns.length)];
    final noun2 = PocketLinkWords.nouns[_random.nextInt(PocketLinkWords.nouns.length)];

    if (prefix != null && prefix.trim().isNotEmpty) {
      final sanitizedPrefix = prefix
          .trim()
          .toLowerCase()
          .replaceAll(RegExp(r"[^a-z0-9]"), '');
      final pfx = sanitizedPrefix.isNotEmpty ? sanitizedPrefix : adj;
      return '$pfx-$noun1-$noun2';
    }

    return '$adj-$noun1-$noun2';
  }

  /// Formats the complete Pocket Link URL
  static String formatPocketUrl(String slug) {
    return 'https://cloudpocket.app/$slug';
  }
}
