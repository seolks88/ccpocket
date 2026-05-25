import 'package:flutter/material.dart';
import 'package:flutter_hooks/flutter_hooks.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:ccpocket/hooks/use_voice_input.dart';
import 'package:ccpocket/l10n/app_localizations.dart';
import 'package:ccpocket/services/voice_input_service.dart';

void main() {
  group('useVoiceInput', () {
    test('inserts recognized text at the cursor position', () {
      const baseValue = TextEditingValue(
        text: 'before after',
        selection: TextSelection.collapsed(offset: 7),
      );

      final result = composeVoiceInputValue(baseValue, 'voice ');

      expect(result.text, 'before voice after');
      expect(result.selection, const TextSelection.collapsed(offset: 13));
    });

    test('replaces the selected range with recognized text', () {
      const baseValue = TextEditingValue(
        text: 'replace this text',
        selection: TextSelection(baseOffset: 8, extentOffset: 12),
      );

      final result = composeVoiceInputValue(baseValue, 'that');

      expect(result.text, 'replace that text');
      expect(result.selection, const TextSelection.collapsed(offset: 12));
    });

    test('uses the end of the text when selection is invalid', () {
      const baseValue = TextEditingValue(text: 'append');

      final result = composeVoiceInputValue(baseValue, ' voice');

      expect(result.text, 'append voice');
      expect(result.selection, const TextSelection.collapsed(offset: 12));
    });

    test('uses wav metadata for wav recordings', () {
      final format = voiceRecordingFormatForPath('/tmp/voice-command.wav');

      expect(format.extension, 'wav');
      expect(format.mimeType, 'audio/wav');
    });

    test('keeps m4a metadata for legacy aac recordings', () {
      final format = voiceRecordingFormatForPath('/tmp/voice-command.m4a');

      expect(format.extension, 'm4a');
      expect(format.mimeType, 'audio/mp4');
    });

    test('normalizes speech locale for transcription API', () {
      expect(normalizeVoiceInputLanguage('ko-KR'), 'ko');
      expect(normalizeVoiceInputLanguage('en_US'), 'en');
      expect(normalizeVoiceInputLanguage(''), isNull);
    });

    testWidgets('returns initial state correctly', (tester) async {
      late VoiceInputResult result;
      final controller = TextEditingController();

      await tester.pumpWidget(
        MaterialApp(
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          locale: const Locale('en'),
          home: HookBuilder(
            builder: (context) {
              result = useVoiceInput(controller);
              return const SizedBox.shrink();
            },
          ),
        ),
      );

      // Voice input is not available by default (SpeechToText init fails in
      // test environment).
      expect(result.isAvailable, isFalse);
      expect(result.isRecording, isFalse);
      expect(result.isTranscribing, isFalse);

      controller.dispose();
    });
  });
}
