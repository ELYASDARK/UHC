import 'dart:async';

/// A bounded, memory-only read cache. Empty values are valid loaded results.
/// A timeout stops waiting, while the original read remains single-flight.
class SessionReadCache<T> {
  SessionReadCache({
    required this.retention,
    this.timeout = const Duration(seconds: 12),
    DateTime Function()? now,
  }) : _now = now ?? DateTime.now;

  final Duration retention;
  final Duration timeout;
  final DateTime Function() _now;
  String? _session;
  int _generation = 0;
  T? _value;
  bool _loaded = false;
  DateTime? _loadedAt;
  Future<T>? _inFlight;

  bool get hasValue => _session != null && _loaded;
  T? get value => hasValue ? _value : null;

  void bindSession(String? session) {
    if (session == _session) return;
    _session = session;
    invalidate();
  }

  void invalidate() {
    _generation++;
    _value = null;
    _loaded = false;
    _loadedAt = null;
    _inFlight = null;
  }

  Future<T> read(Future<T> Function() load, {bool forceRefresh = false}) {
    if (_session == null) {
      return Future.error(StateError('An authenticated session is required.'));
    }
    if (!forceRefresh && _loaded && _now().difference(_loadedAt!) < retention) {
      return Future.value(_value as T);
    }
    if (_inFlight == null) {
      final generation = _generation;
      final request = Future.sync(load).then((result) {
        if (generation != _generation || _session == null) {
          throw StateError('The read belongs to an expired session.');
        }
        _value = result;
        _loaded = true;
        _loadedAt = _now();
        return result;
      });
      _inFlight = request.whenComplete(() {
        if (generation == _generation) _inFlight = null;
      });
    }
    return _inFlight!.timeout(timeout);
  }
}
