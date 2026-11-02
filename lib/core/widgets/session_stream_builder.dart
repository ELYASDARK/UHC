import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:firebase_core/firebase_core.dart';
import '../../providers/auth_provider.dart';
import '../../l10n/app_localizations.dart';

/// Owns one subscription per query and authorization session, across rebuilds.
class SessionStreamBuilder<T> extends StatefulWidget {
  const SessionStreamBuilder({
    super.key,
    required this.queryKey,
    required this.createStream,
    required this.builder,
    required this.permission,
  });

  static int debugStarts = 0;
  static int debugActive = 0;
  static int debugCancellations = 0;

  final Object queryKey;
  final String permission;
  final Stream<T> Function() createStream;
  final AsyncWidgetBuilder<T> builder;

  @override
  State<SessionStreamBuilder<T>> createState() =>
      _SessionStreamBuilderState<T>();
}

class _SessionStreamBuilderState<T> extends State<SessionStreamBuilder<T>> {
  String? _session;
  Stream<T>? _stream;
  T? _lastValue;

  Stream<T> _createStream() {
    final source = widget.createStream();
    Stream<T> stream = source;
    assert(() {
      stream = Stream<T>.multi((events) {
        SessionStreamBuilder.debugStarts++;
        SessionStreamBuilder.debugActive++;
        final subscription = source.listen(events.add,
            onError: events.addError, onDone: events.close);
        events.onPause = subscription.pause;
        events.onResume = subscription.resume;
        events.onCancel = () {
          SessionStreamBuilder.debugActive--;
          SessionStreamBuilder.debugCancellations++;
          return subscription.cancel();
        };
      });
      return true;
    }());
    return stream;
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final auth = context.watch<AuthProvider>();
    final session = auth.isAuthenticated &&
            (auth.user?.hasPermission(widget.permission) ?? false)
        ? auth.cacheSessionKey
        : null;
    if (session != _session) {
      _session = session;
      _lastValue = null;
      _stream = session == null ? null : _createStream();
    }
  }

  @override
  void didUpdateWidget(covariant SessionStreamBuilder<T> oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (_session != null && oldWidget.queryKey != widget.queryKey) {
      _stream = _createStream();
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_session == null) {
      return Center(
          child: Text(AppLocalizations.of(context).noPermissionForAction));
    }
    return StreamBuilder<T>(
      // A new session must never inherit the previous session's snapshot.
      key: ValueKey(_session),
      stream: _stream,
      builder: (context, snapshot) {
        if (snapshot.hasData) _lastValue = snapshot.data;
        if (!snapshot.hasError) return widget.builder(context, snapshot);
        final error = snapshot.error;
        if (error is FirebaseException &&
            ['permission-denied', 'unauthenticated'].contains(error.code)) {
          _lastValue = null;
        }
        if (snapshot.connectionState == ConnectionState.waiting) {
          return _lastValue == null
              ? const Center(child: CircularProgressIndicator())
              : widget.builder(
                  context,
                  AsyncSnapshot.withData(
                      ConnectionState.waiting, _lastValue as T));
        }
        final l10n = AppLocalizations.of(context);
        final retry = Material(
          child: TextButton.icon(
            onPressed: () => setState(() => _stream = _createStream()),
            icon: const Icon(Icons.refresh),
            label: Text('${l10n.connectionError} ${l10n.tryAgain}'),
          ),
        );
        if (_lastValue == null) return Center(child: retry);
        return Stack(children: [
          widget.builder(context,
              AsyncSnapshot.withData(ConnectionState.active, _lastValue as T)),
          Positioned(top: 0, left: 0, right: 0, child: retry),
        ]);
      },
    );
  }
}
