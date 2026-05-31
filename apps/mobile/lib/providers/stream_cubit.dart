import 'dart:async';

import 'package:flutter_bloc/flutter_bloc.dart';

/// Generic Cubit that mirrors a Stream as state.
/// Replaces Riverpod's StreamProvider for simple stream-wrapping use cases.
class StreamCubit<T> extends Cubit<T> {
  StreamSubscription<T>? _sub;
  final bool Function(T previous, T next)? equals;

  StreamCubit(super.initial, Stream<T> stream, {this.equals}) {
    _sub = stream.listen(equals == null ? emit : _emitIfChanged);
  }

  void _emitIfChanged(T value) {
    final unchanged = equals?.call(state, value) ?? false;
    if (!unchanged) emit(value);
  }

  @override
  Future<void> close() {
    _sub?.cancel();
    return super.close();
  }
}
