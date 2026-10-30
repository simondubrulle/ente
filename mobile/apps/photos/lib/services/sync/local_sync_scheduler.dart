import "dart:async";

class LocalSyncOperation {
  LocalSyncOperation(this._sync);

  final Future<void> Function() _sync;
  Completer<void>? _running;

  Future<void>? get current => _running?.future;

  Future<void> run() {
    final running = _running;
    if (running != null) {
      return running.future;
    }

    final completion = Completer<void>();
    _running = completion;
    completion.complete(
      Future<void>.sync(_sync).whenComplete(() {
        _running = null;
      }),
    );
    return completion.future;
  }
}

class LocalChangeSyncScheduler {
  LocalChangeSyncScheduler(this._sync);

  final Future<void> Function() _sync;
  late final _operation = LocalSyncOperation(_drain);
  bool _requested = false;

  Future<void> request() {
    _requested = true;
    return _operation.run();
  }

  Future<void> _drain() async {
    do {
      _requested = false;
      await _sync();
    } while (_requested);
  }
}
