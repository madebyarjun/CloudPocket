import 'package:flutter_test/flutter_test.dart';
import 'package:cloud_pocket/services/pocket_link_generator.dart';

void main() {
  group('PocketLinkGenerator Tests', () {
    test('generateSlug generates 3-segment hyphenated string', () {
      final slug = PocketLinkGenerator.generateSlug();
      final parts = slug.split('-');
      expect(parts.length, equals(3));
      expect(parts[0].isNotEmpty, isTrue);
      expect(parts[1].isNotEmpty, isTrue);
      expect(parts[2].isNotEmpty, isTrue);
    });

    test('generateSlug uses sanitized custom prefix when provided', () {
      final slug = PocketLinkGenerator.generateSlug(prefix: "Pixel Phone");
      expect(slug.startsWith('pixelphone-'), isTrue);
      final parts = slug.split('-');
      expect(parts.length, equals(3));
    });

    test('formatPocketUrl formats complete cloudpocket.app URL', () {
      const slug = 'swift-river-star';
      final url = PocketLinkGenerator.formatPocketUrl(slug);
      expect(url, equals('https://cloudpocket.app/swift-river-star'));
    });
  });
}
