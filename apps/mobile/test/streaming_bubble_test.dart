import 'package:ccpocket/widgets/bubbles/streaming_bubble.dart';
import 'package:ccpocket/l10n/app_localizations.dart';
import 'package:ccpocket/theme/app_theme.dart';
import 'package:ccpocket/theme/markdown_style.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

Widget _wrap(Widget child) {
  return MaterialApp(
    theme: AppTheme.darkTheme,
    localizationsDelegates: AppLocalizations.localizationsDelegates,
    supportedLocales: AppLocalizations.supportedLocales,
    locale: const Locale('en'),
    home: Scaffold(body: SingleChildScrollView(child: child)),
  );
}

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

  testWidgets('uses lightweight code blocks while streaming', (tester) async {
    markdownPerformanceProbe.reset();

    await tester.pumpWidget(
      _wrap(
        const StreamingBubble(
          text: '```dart\nvoid main() {\n  print("hi");\n}\n```',
        ),
      ),
    );

    expect(find.textContaining('void main'), findsOneWidget);
    expect(find.byType(SelectableText), findsNothing);
    expect(markdownPerformanceProbe.highlightCalls, 0);
  });
}
