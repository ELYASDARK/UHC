import 'dart:async';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cloud_functions/cloud_functions.dart';
import 'firebase_callable.dart';
import 'package:uuid/uuid.dart';

/// Loads only admin statistics. Pending reads are shared across local retries.
class StatisticsRequestsPending implements Exception {}

class AnalyticsCancelled implements Exception {}

class AnalyticsLoad {
  bool cancelled = false;
  void Function(int processed)? onProgress;
}

class AdminStatisticsService {
  AdminStatisticsService(
      {Future<int> Function()? userCount, Future<int> Function()? doctorCount})
      : _userCount = userCount,
        _doctorCount = doctorCount;

  final Future<int> Function()? _userCount;
  final Future<int> Function()? _doctorCount;
  static const timeout = Duration(seconds: 15);
  final Map<String, Future<dynamic>> _pending = {};
  final Map<String, Set<Future<dynamic>>> _outstanding = {};

  Future<T> _read<T>(String key, Future<T> Function() start,
      {Duration wait = timeout}) {
    final existing = _pending[key];
    if (existing != null) {
      return existing.then((value) => value as T).timeout(wait);
    }
    final outstanding = _outstanding.putIfAbsent(key, () => {});
    // Native reads cannot be cancelled. Permit one replacement after timeout,
    // then wait for an outstanding RPC instead of accumulating requests.
    if (outstanding.length >= 2) {
      return Future.error(StatisticsRequestsPending());
    }
    final request = Future<T>.sync(start);
    outstanding.add(request);
    _pending[key] = request;
    // Observe both outcomes even if the caller's bounded wait has ended.
    request.then<void>((_) {
      outstanding.remove(request);
      if (outstanding.isEmpty) _outstanding.remove(key);
      if (identical(_pending[key], request)) _pending.remove(key);
    }, onError: (Object _, StackTrace __) {
      outstanding.remove(request);
      if (outstanding.isEmpty) _outstanding.remove(key);
      if (identical(_pending[key], request)) _pending.remove(key);
    });
    return request.timeout(wait, onTimeout: () {
      if (identical(_pending[key], request)) _pending.remove(key);
      throw TimeoutException('Statistics wait exceeded 15 seconds.');
    });
  }

  Future<int> users() => _read('users', () async {
        if (_userCount != null) return _userCount();
        final result = await FirebaseFirestore.instance
            .collection('users')
            .where('role', isEqualTo: 'student')
            .count()
            .get();
        return result.count!;
      });

  Future<int> doctors() => _read('doctors', () async {
        if (_doctorCount != null) return _doctorCount();
        final result = await FirebaseFirestore.instance
            .collection('doctors')
            .count()
            .get();
        return result.count!;
      });

  AnalyticsLoad? activeLoad;
  int _activeAnalyticsJobs = 0;

  Future<Map<String, dynamic>> analytics(String period) =>
      _read(period == 'dashboard' ? period : const Uuid().v4(), () async {
        if (period == 'dashboard') {
          return Map<String, dynamic>.from(await invokeFirebaseCallable(
              FirebaseFunctions.instance,
              'getAppointmentAnalytics',
              {'period': period},
              timeout: timeout));
        }
        if (_activeAnalyticsJobs >= 2) throw StatisticsRequestsPending();
        _activeAnalyticsJobs++;
        try {
          final load = activeLoad;
          final requestId = const Uuid().v4();
          var version = 0;
          var action = 'start';
          while (true) {
            final payload = {
              'protocol': 2,
              'period': period,
              'requestId': requestId,
              'action': action,
              'version': version
            };
            if (load?.cancelled == true) {
              unawaited(invokeFirebaseCallable(
                      FirebaseFunctions.instance,
                      'getAppointmentAnalytics',
                      {...payload, 'action': 'cancel'},
                      timeout: timeout)
                  .catchError((Object _) => null));
              throw AnalyticsCancelled();
            }
            final response = Map<String, dynamic>.from(
                await invokeFirebaseCallable(FirebaseFunctions.instance,
                    'getAppointmentAnalytics', payload,
                    timeout: timeout));
            if (load?.cancelled == true) continue;
            load?.onProgress?.call((response['total'] as num).toInt());
            if (response['complete'] == true) return response;
            final nextVersion = (response['version'] as num).toInt();
            if (nextVersion <= version) {
              throw StateError('Analytics page did not advance.');
            }
            version = nextVersion;
            action = 'next';
          }
        } finally {
          _activeAnalyticsJobs--;
        }
      }, wait: period == 'dashboard' ? timeout : const Duration(minutes: 16));
}
