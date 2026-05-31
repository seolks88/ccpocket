import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import 'streaming_state.dart';

final streamingPerformanceProbe = StreamingPerformanceProbe();

class StreamingPerformanceProbe {
  int appendTextCalls = 0;
  int appendThinkingCalls = 0;
  int textChars = 0;
  int thinkingChars = 0;
  int scheduledFlushes = 0;
  int immediateFlushes = 0;
  int flushes = 0;
  int emittedStates = 0;
  int resets = 0;

  void reset() {
    appendTextCalls = 0;
    appendThinkingCalls = 0;
    textChars = 0;
    thinkingChars = 0;
    scheduledFlushes = 0;
    immediateFlushes = 0;
    flushes = 0;
    emittedStates = 0;
    resets = 0;
  }

  Map<String, Object?> summary() {
    return {
      'appendTextCalls': appendTextCalls,
      'appendThinkingCalls': appendThinkingCalls,
      'textChars': textChars,
      'thinkingChars': thinkingChars,
      'scheduledFlushes': scheduledFlushes,
      'immediateFlushes': immediateFlushes,
      'flushes': flushes,
      'emittedStates': emittedStates,
      'resets': resets,
    };
  }
}

/// Manages the high-frequency streaming state for a chat session.
///
/// Kept separate from [ChatSessionCubit] to avoid rebuilding the
/// entire message list on every streaming delta.
class StreamingStateCubit extends Cubit<StreamingState> {
  StreamingStateCubit({this.coalesceDelay = Duration.zero})
    : super(const StreamingState());

  final Duration coalesceDelay;
  final StringBuffer _textBuffer = StringBuffer();
  final StringBuffer _thinkingBuffer = StringBuffer();
  Timer? _flushTimer;
  var _hasVisibleContent = false;

  bool get hasVisibleContent => _hasVisibleContent;

  void markWaitingForResponse() {
    if (state.isStreaming && hasVisibleContent) return;
    _emit(const StreamingState(isStreaming: true));
  }

  void appendText(String text) {
    if (kDebugMode) {
      streamingPerformanceProbe
        ..appendTextCalls += 1
        ..textChars += text.length;
    }
    _textBuffer.write(text);
    if (!_hasVisibleContent && text.trim().isNotEmpty) {
      _hasVisibleContent = true;
    }
    _flushOrSchedule();
  }

  void appendThinking(String text) {
    if (kDebugMode) {
      streamingPerformanceProbe
        ..appendThinkingCalls += 1
        ..thinkingChars += text.length;
    }
    _thinkingBuffer.write(text);
    if (!_hasVisibleContent && text.trim().isNotEmpty) {
      _hasVisibleContent = true;
    }
    _flushOrSchedule();
  }

  void reset() {
    if (kDebugMode) streamingPerformanceProbe.resets += 1;
    _flushTimer?.cancel();
    _flushTimer = null;
    _textBuffer.clear();
    _thinkingBuffer.clear();
    _hasVisibleContent = false;
    _emit(const StreamingState());
  }

  void _flushOrSchedule() {
    if (coalesceDelay <= Duration.zero) {
      if (kDebugMode) streamingPerformanceProbe.immediateFlushes += 1;
      _flush();
      return;
    }
    if (!state.isStreaming) {
      _emit(state.copyWith(isStreaming: true));
    }
    if (_flushTimer != null) return;
    if (kDebugMode) streamingPerformanceProbe.scheduledFlushes += 1;
    _flushTimer = Timer(coalesceDelay, () {
      _flushTimer = null;
      _flush();
    });
  }

  void _flush() {
    if (isClosed) return;
    if (kDebugMode) streamingPerformanceProbe.flushes += 1;
    _emit(
      StreamingState(
        text: _textBuffer.toString(),
        thinking: _thinkingBuffer.toString(),
        isStreaming: true,
      ),
    );
  }

  void _emit(StreamingState state) {
    if (kDebugMode) streamingPerformanceProbe.emittedStates += 1;
    emit(state);
  }

  @override
  Future<void> close() {
    _flushTimer?.cancel();
    return super.close();
  }
}
