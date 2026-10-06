import "dart:async";

class MlRunPolicy {
  static final _remoteSyncOnlyKey = Object();

  static bool get remoteSyncOnly => Zone.current[_remoteSyncOnlyKey] == true;

  static Future<T> run<T>({
    required bool remoteSyncOnly,
    required Future<T> Function() action,
  }) => runZoned(action, zoneValues: {_remoteSyncOnlyKey: remoteSyncOnly});
}
