import 'package:ccpocket/utils/file_mention_matcher.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('scoreFileMentionPath', () {
    test('matches exact basename before broader matches', () {
      expect(scoreFileMentionPath('apps/mobile/lib/main.dart', 'main'), 0);
      expect(
        scoreFileMentionPath('apps/mobile/lib/main.dart', 'mai'),
        lessThan(scoreFileMentionPath('apps/mobile/lib/domain.dart', 'mai')),
      );
    });

    test('matches compact fuzzy queries across path segments', () {
      expect(
        scoreFileMentionPath('docs/design/', 'dode'),
        greaterThanOrEqualTo(5),
      );
      expect(scoreFileMentionPath('docs/design/', 'dode'), isNot(-1));
      expect(scoreFileMentionPath('docs/design/api.md', 'dode'), isNot(-1));
    });

    test('keeps direct path contains ahead of fuzzy matches', () {
      final direct = scoreFileMentionPath('docs/design/', 'docs/des');
      final fuzzy = scoreFileMentionPath('docs/design/', 'dode');

      expect(direct, lessThan(fuzzy));
    });

    test('does not fuzzy match single-character queries', () {
      expect(scoreFileMentionPath('docs/design/', 'x'), -1);
    });
  });

  group('rankFileMentionPaths', () {
    test('matches full score sort while returning only top results', () {
      final files = [
        'apps/mobile/lib/domain.dart',
        'apps/mobile/lib/main.dart',
        'apps/mobile/test/main_widget_test.dart',
        'docs/design/api.md',
        'packages/bridge/src/index.ts',
      ];
      final expected =
          files
              .map(
                (file) =>
                    (file: file, score: scoreFileMentionPath(file, 'mai')),
              )
              .where((item) => item.score >= 0)
              .toList()
            ..sort((a, b) {
              final cmp = a.score.compareTo(b.score);
              return cmp != 0 ? cmp : a.file.length.compareTo(b.file.length);
            });

      expect(
        rankFileMentionPaths(files, 'mai', limit: 2),
        expected.take(2).map((item) => item.file).toList(),
      );
    });

    test('caps large result sets without dropping better short matches', () {
      final files = [
        'lib/a.dart',
        'lib/b.dart',
        for (var i = 0; i < 100; i++) 'lib/generated/path_$i.dart',
      ];

      final ranked = rankFileMentionPaths(files, '', limit: 15);

      expect(ranked, hasLength(15));
      expect(ranked.first, 'lib/a.dart');
      expect(ranked, contains('lib/b.dart'));
    });
  });
}
