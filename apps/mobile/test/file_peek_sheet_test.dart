import 'dart:async';

import 'package:ccpocket/features/file_peek/file_peek_sheet.dart';
import 'package:ccpocket/l10n/app_localizations.dart';
import 'package:ccpocket/models/messages.dart';
import 'package:ccpocket/services/bridge_service.dart';
import 'package:ccpocket/theme/app_theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

class _FilePeekBridge extends BridgeService {
  _FilePeekBridge({required this.filePath, required this.content});

  final String filePath;
  final String content;
  final _fileContentController =
      StreamController<FileContentMessage>.broadcast();
  String? lastClientMessageType;

  @override
  Stream<FileContentMessage> get fileContent => _fileContentController.stream;

  @override
  void send(ClientMessage message) {
    lastClientMessageType = message.type;
    scheduleMicrotask(() {
      if (_fileContentController.isClosed) return;
      _fileContentController.add(
        FileContentMessage(
          filePath: filePath,
          content: content,
          language: 'markdown',
          totalLines: content.split('\n').length,
        ),
      );
    });
  }

  @override
  void dispose() {
    _fileContentController.close();
    super.dispose();
  }
}

void main() {
  testWidgets('file peek copy button copies loaded file content', (
    tester,
  ) async {
    final bridge = _FilePeekBridge(
      filePath: 'docs/context.md',
      content: '# Context\n\nCopy this body.',
    );
    addTearDown(bridge.dispose);

    String? clipboardText;
    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
      SystemChannels.platform,
      (call) async {
        if (call.method == 'Clipboard.setData') {
          final args = call.arguments as Map<Object?, Object?>;
          clipboardText = args['text'] as String?;
          return null;
        }
        if (call.method == 'Clipboard.getData') {
          return {'text': clipboardText};
        }
        return null;
      },
    );
    addTearDown(() {
      tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        SystemChannels.platform,
        null,
      );
    });

    await tester.pumpWidget(
      MaterialApp(
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        theme: AppTheme.darkTheme,
        home: Scaffold(
          body: Builder(
            builder: (context) {
              return TextButton(
                onPressed: () => showFilePeekSheet(
                  context,
                  bridge: bridge,
                  projectPath: '/tmp/project',
                  filePath: 'docs/context.md',
                ),
                child: const Text('Open'),
              );
            },
          ),
        ),
      ),
    );

    await tester.tap(find.text('Open'));
    await tester.pumpAndSettle();

    expect(bridge.lastClientMessageType, 'read_file');
    expect(find.byKey(const ValueKey('file_peek_copy_button')), findsOneWidget);

    await tester.tap(find.byKey(const ValueKey('file_peek_copy_button')));
    await tester.pump();

    expect(clipboardText, '# Context\n\nCopy this body.');
  });
}
