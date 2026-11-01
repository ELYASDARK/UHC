import 'dart:async';
import 'package:flutter_test/flutter_test.dart';
import 'package:uhc/core/utils/session_read_cache.dart';

void main() {
  test(
      'empty results are reused until expiry and explicit refresh is deduplicated',
      () async {
    var now = DateTime(2026, 11, 1);
    var reads = 0;
    final cache = SessionReadCache<List<String>>(
        retention: const Duration(minutes: 2), now: () => now)
      ..bindSession('patient-a');
    Future<List<String>> load() async {
      reads++;
      return [];
    }

    expect(await cache.read(load), isEmpty);
    expect(await cache.read(load), isEmpty);
    expect(reads, 1);
    now = now.add(const Duration(minutes: 3));
    await cache.read(load);
    expect(reads, 2);
    final pending = Completer<List<String>>();
    final first = cache.read(() {
      reads++;
      return pending.future;
    }, forceRefresh: true);
    final second = cache.read(load, forceRefresh: true);
    pending.complete(['fresh']);
    expect(await first, ['fresh']);
    expect(await second, ['fresh']);
    expect(reads, 3);
  });

  test('a late reply cannot repopulate a cleared or switched session',
      () async {
    final cache =
        SessionReadCache<List<String>>(retention: const Duration(minutes: 2))
          ..bindSession('patient-a');
    final pending = Completer<List<String>>();
    final first = cache.read(() => pending.future);
    final rejected = expectLater(first, throwsStateError);
    cache.bindSession('patient-b');
    expect(cache.hasValue, isFalse);
    expect(await cache.read(() async => ['b']), ['b']);
    pending.complete(['a']);
    await rejected;
    expect(cache.value, ['b']);
    cache.bindSession(null);
    expect(cache.value, isNull);
    await expectLater(cache.read(() async => ['forbidden']), throwsStateError);
  });

  test('timeouts share the outstanding request and errors retain previous data',
      () async {
    final cache = SessionReadCache<List<String>>(
        retention: Duration.zero, timeout: const Duration(milliseconds: 15))
      ..bindSession('admin');
    await cache.read(() async => ['authorized']);
    final pending = Completer<List<String>>();
    var reads = 0;
    Future<List<String>> load() {
      reads++;
      return pending.future;
    }

    await expectLater(cache.read(load), throwsA(isA<TimeoutException>()));
    await expectLater(cache.read(load), throwsA(isA<TimeoutException>()));
    expect(reads, 1);
    expect(cache.value, ['authorized']);
    pending.completeError(StateError('unavailable'));
    await Future<void>.delayed(Duration.zero);
    await expectLater(cache.read(() async => throw StateError('unavailable')),
        throwsStateError);
    expect(cache.value, ['authorized']);
    cache.invalidate();
    expect(cache.hasValue, isFalse);
  });
}
