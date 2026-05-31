import 'dart:async';

import 'package:flutter_bloc/flutter_bloc.dart';

import 'streaming_state.dart';

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

  bool get hasVisibleContent =>
      _textBuffer.toString().trim().isNotEmpty ||
      _thinkingBuffer.toString().trim().isNotEmpty;

  void markWaitingForResponse() {
    if (state.isStreaming && hasVisibleContent) return;
    emit(const StreamingState(isStreaming: true));
  }

  void appendText(String text) {
    _textBuffer.write(text);
    _flushOrSchedule();
  }

  void appendThinking(String text) {
    _thinkingBuffer.write(text);
    _flushOrSchedule();
  }

  void reset() {
    _flushTimer?.cancel();
    _flushTimer = null;
    _textBuffer.clear();
    _thinkingBuffer.clear();
    emit(const StreamingState());
  }

  void _flushOrSchedule() {
    if (coalesceDelay <= Duration.zero) {
      _flush();
      return;
    }
    if (!state.isStreaming) {
      emit(state.copyWith(isStreaming: true));
    }
    _flushTimer ??= Timer(coalesceDelay, () {
      _flushTimer = null;
      _flush();
    });
  }

  void _flush() {
    if (isClosed) return;
    emit(
      StreamingState(
        text: _textBuffer.toString(),
        thinking: _thinkingBuffer.toString(),
        isStreaming: true,
      ),
    );
  }

  @override
  Future<void> close() {
    _flushTimer?.cancel();
    return super.close();
  }
}
