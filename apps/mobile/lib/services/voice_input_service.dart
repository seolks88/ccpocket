import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:path_provider/path_provider.dart';
import 'package:record/record.dart';
import 'package:uuid/uuid.dart';

import '../models/messages.dart';
import '../utils/platform_helper.dart';
import 'bridge_service.dart';

class VoiceInputService {
  static const _transcriptionModel = 'gpt-4o-mini-transcribe';
  static const _transcriptionTimeout = Duration(seconds: 60);

  final AudioRecorder _recorder = AudioRecorder();
  final Uuid _uuid = const Uuid();

  bool _isAvailable = false;
  bool _isListening = false;

  bool get isAvailable => _isAvailable;
  bool get isListening => _isListening;

  Future<bool> initialize() async {
    if (kIsWeb || isDesktopPlatform) {
      _isAvailable = false;
      return false;
    }
    _isAvailable = await _recorder.hasPermission();
    return _isAvailable;
  }

  Future<void> startRecording() async {
    if (!_isAvailable || _isListening) return;
    final directory = await getTemporaryDirectory();
    final path =
        '${directory.path}/ccpocket-voice-${DateTime.now().microsecondsSinceEpoch}.m4a';
    await _recorder.start(
      const RecordConfig(
        encoder: AudioEncoder.aacLc,
        bitRate: 64000,
        sampleRate: 16000,
        numChannels: 1,
        noiseSuppress: true,
      ),
      path: path,
    );
    _isListening = true;
  }

  Future<String> stopAndTranscribe({
    required BridgeService bridge,
    String? language,
  }) async {
    if (!_isListening) return '';
    final path = await _recorder.stop();
    _isListening = false;
    if (path == null || path.isEmpty) return '';

    final file = File(path);
    try {
      final bytes = await file.readAsBytes();
      if (bytes.isEmpty) return '';

      final requestId = _uuid.v4();
      final resultFuture = bridge.messages
          .where((message) => message is VoiceTranscriptionResultMessage)
          .cast<VoiceTranscriptionResultMessage>()
          .firstWhere((message) => message.requestId == requestId)
          .timeout(_transcriptionTimeout);

      bridge.send(
        ClientMessage.transcribeAudio(
          requestId: requestId,
          audioBase64: base64Encode(bytes),
          mimeType: 'audio/mp4',
          fileName: 'voice-command.m4a',
          model: _transcriptionModel,
          language: _normalizeLanguage(language),
        ),
      );

      final result = await resultFuture;
      if (!result.success) {
        throw StateError(result.error ?? 'Voice transcription failed');
      }
      return result.text?.trim() ?? '';
    } finally {
      unawaited(file.delete().catchError((_) => file));
    }
  }

  Future<void> cancel() async {
    if (!_isListening) return;
    await _recorder.cancel();
    _isListening = false;
  }

  void dispose() {
    unawaited(_recorder.dispose());
    _isListening = false;
  }
}

String? _normalizeLanguage(String? localeId) {
  final value = localeId?.trim();
  if (value == null || value.isEmpty) return null;
  return value.split(RegExp('[-_]')).first.toLowerCase();
}
