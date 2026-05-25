import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart'
    show debugPrint, kDebugMode, kIsWeb, visibleForTesting;
import 'package:http/http.dart' as http;
import 'package:path_provider/path_provider.dart';
import 'package:record/record.dart';
import 'package:uuid/uuid.dart';

import '../utils/platform_helper.dart';
import 'bridge_service.dart';

class VoiceInputService {
  static const _transcriptionModel = 'gpt-4o-mini-transcribe';
  static const _transcriptionTimeout = Duration(seconds: 60);

  final AudioRecorder _recorder = AudioRecorder();
  final Uuid _uuid = const Uuid();

  bool _isAvailable = false;
  bool _isListening = false;
  VoiceRecordingFormat? _currentRecordingFormat;

  bool get isAvailable => _isAvailable;
  bool get isListening => _isListening;

  Future<bool> initialize() async {
    if (kIsWeb || isDesktopPlatform) {
      _isAvailable = false;
      return false;
    }
    _isAvailable = true;
    return _isAvailable;
  }

  Future<void> startRecording() async {
    if (!_isAvailable || _isListening) return;
    final hasPermission = await _recorder.hasPermission();
    if (!hasPermission) {
      throw StateError('Microphone permission is required for voice input');
    }
    final format = await selectVoiceRecordingFormat(_recorder);
    final directory = await getTemporaryDirectory();
    final path =
        '${directory.path}/ccpocket-voice-${DateTime.now().microsecondsSinceEpoch}.${format.extension}';
    await _recorder.start(
      RecordConfig(
        encoder: format.encoder,
        bitRate: format.bitRate,
        sampleRate: 16000,
        numChannels: 1,
        noiseSuppress: true,
      ),
      path: path,
    );
    _currentRecordingFormat = format;
    _isListening = true;
    _logVoiceInput(
      'recording started encoder=${format.encoder.name} '
      'extension=${format.extension} mimeType=${format.mimeType}',
    );
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
      final format =
          _currentRecordingFormat ?? voiceRecordingFormatForPath(path);

      final requestId = _uuid.v4();
      final baseUrl = bridge.httpBaseUrl;
      if (baseUrl == null) {
        throw StateError('Bridge is not connected');
      }
      _logVoiceInput(
        'transcribe request $requestId bytes=${bytes.length} '
        'extension=${format.extension} mimeType=${format.mimeType} '
        'language=${_normalizeLanguage(language) ?? 'auto'}',
      );
      final response = await http
          .post(
            Uri.parse('$baseUrl/api/transcribe'),
            headers: const {'Content-Type': 'application/json'},
            body: jsonEncode({
              'requestId': requestId,
              'audioBase64': base64Encode(bytes),
              'mimeType': format.mimeType,
              'fileName': 'voice-command.${format.extension}',
              'model': _transcriptionModel,
              'language': _normalizeLanguage(language),
            }),
          )
          .timeout(_transcriptionTimeout);
      _logVoiceInput(
        'transcribe response $requestId status=${response.statusCode}',
      );
      final decoded = jsonDecode(response.body) as Map<String, dynamic>;
      if (response.statusCode < 200 ||
          response.statusCode >= 300 ||
          decoded['success'] != true) {
        final error = decoded['error'] as String?;
        throw StateError(error ?? 'Voice transcription failed');
      }
      return (decoded['text'] as String? ?? '').trim();
    } finally {
      _currentRecordingFormat = null;
      unawaited(file.delete().catchError((_) => file));
    }
  }

  Future<void> cancel() async {
    if (!_isListening) return;
    await _recorder.cancel();
    _isListening = false;
    _currentRecordingFormat = null;
  }

  void dispose() {
    unawaited(_recorder.dispose());
    _isListening = false;
    _currentRecordingFormat = null;
  }
}

@visibleForTesting
class VoiceRecordingFormat {
  const VoiceRecordingFormat({
    required this.encoder,
    required this.extension,
    required this.mimeType,
    required this.bitRate,
  });

  final AudioEncoder encoder;
  final String extension;
  final String mimeType;
  final int bitRate;
}

const _wavVoiceRecordingFormat = VoiceRecordingFormat(
  encoder: AudioEncoder.wav,
  extension: 'wav',
  mimeType: 'audio/wav',
  bitRate: 256000,
);

const _m4aVoiceRecordingFormat = VoiceRecordingFormat(
  encoder: AudioEncoder.aacLc,
  extension: 'm4a',
  mimeType: 'audio/mp4',
  bitRate: 64000,
);

Future<VoiceRecordingFormat> selectVoiceRecordingFormat(
  AudioRecorder recorder,
) async {
  try {
    if (await recorder.isEncoderSupported(_wavVoiceRecordingFormat.encoder)) {
      return _wavVoiceRecordingFormat;
    }
  } catch (_) {
    // Fall back to the legacy AAC path if encoder probing is unavailable.
  }
  return _m4aVoiceRecordingFormat;
}

@visibleForTesting
VoiceRecordingFormat voiceRecordingFormatForPath(String path) {
  final extension = path.split('.').last.toLowerCase();
  return extension == _wavVoiceRecordingFormat.extension
      ? _wavVoiceRecordingFormat
      : _m4aVoiceRecordingFormat;
}

String? _normalizeLanguage(String? localeId) {
  final value = localeId?.trim();
  if (value == null || value.isEmpty) return null;
  return value.split(RegExp('[-_]')).first.toLowerCase();
}

@visibleForTesting
String? normalizeVoiceInputLanguage(String? localeId) =>
    _normalizeLanguage(localeId);

void _logVoiceInput(String message) {
  if (kDebugMode) {
    debugPrint('[voice-input] $message');
  }
}
