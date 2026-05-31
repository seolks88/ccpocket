import 'package:ccpocket/widgets/bubbles/streaming_bubble.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('shouldRenderStreamingMarkdown', () {
    test('keeps live markdown for short stable text', () {
      expect(shouldRenderStreamingMarkdown('Hello **world**'), isTrue);
    });

    test('falls back for long streaming text', () {
      expect(shouldRenderStreamingMarkdown('a'.padRight(2401, 'a')), isFalse);
    });

    test('falls back while a code fence is still open', () {
      expect(
        shouldRenderStreamingMarkdown('```dart\nvoid main() {\n'),
        isFalse,
      );
    });

    test('restores markdown after a short code fence closes', () {
      expect(
        shouldRenderStreamingMarkdown('```dart\nvoid main() {}\n```'),
        isTrue,
      );
    });
  });
}
