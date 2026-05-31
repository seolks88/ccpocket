import 'dart:async';

import 'package:flutter_test/flutter_test.dart';

import 'package:ccpocket/providers/bridge_cubits.dart';
import 'package:ccpocket/providers/stream_cubit.dart';

void main() {
  group('StreamCubit', () {
    test('initial state matches provided value', () {
      final controller = StreamController<int>.broadcast();
      addTearDown(controller.close);

      final cubit = StreamCubit<int>(0, controller.stream);
      addTearDown(cubit.close);

      expect(cubit.state, 0);
    });

    test('emits stream values as state', () async {
      final controller = StreamController<int>.broadcast();
      addTearDown(controller.close);

      final cubit = StreamCubit<int>(0, controller.stream);
      addTearDown(cubit.close);

      controller.add(42);
      await Future.microtask(() {});

      expect(cubit.state, 42);
    });

    test('returns the same type when used as typedef', () {
      final controller = StreamController<List<String>>.broadcast();
      addTearDown(controller.close);

      final cubit = StreamCubit<List<String>>(const [], controller.stream);
      addTearDown(cubit.close);

      expect(cubit.state, isEmpty);
    });

    test('updates state on each stream emission', () async {
      final controller = StreamController<String>.broadcast();
      addTearDown(controller.close);

      final cubit = StreamCubit<String>('init', controller.stream);
      addTearDown(cubit.close);

      controller.add('first');
      await Future.microtask(() {});
      expect(cubit.state, 'first');

      controller.add('second');
      await Future.microtask(() {});
      expect(cubit.state, 'second');
    });

    test('preserves default duplicate suppression semantics', () async {
      final controller = StreamController<int>.broadcast();
      addTearDown(controller.close);

      final cubit = StreamCubit<int>(0, controller.stream);
      addTearDown(cubit.close);
      final emitted = <int>[];
      final sub = cubit.stream.listen(emitted.add);
      addTearDown(sub.cancel);

      controller.add(0);
      await Future.microtask(() {});

      expect(emitted, isEmpty);
    });

    test('stops listening after close', () async {
      final controller = StreamController<int>.broadcast();
      addTearDown(controller.close);

      final cubit = StreamCubit<int>(0, controller.stream);
      await cubit.close();

      controller.add(99);
      await Future.microtask(() {});

      // State should remain at initial value after close
      expect(cubit.state, 0);
    });

    test('supports semantic equality for repeated stream values', () async {
      final controller = StreamController<List<String>>.broadcast();
      addTearDown(controller.close);

      final cubit = FileListCubit(const [], controller.stream);
      addTearDown(cubit.close);
      final emitted = <List<String>>[];
      final sub = cubit.stream.listen(emitted.add);
      addTearDown(sub.cancel);

      controller.add(['lib/main.dart']);
      await Future.microtask(() {});
      controller.add(['lib/main.dart']);
      await Future.microtask(() {});

      expect(cubit.state, ['lib/main.dart']);
      expect(emitted, [
        ['lib/main.dart'],
      ]);
    });
  });
}
