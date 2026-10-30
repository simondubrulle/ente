import "dart:async";

import "package:flutter_test/flutter_test.dart";
import "package:photos/services/sync/local_sync_scheduler.dart";

void main() {
  test(
    "a failed local scan releases joined callers and permits retry",
    () async {
      final scan = Completer<void>();
      final failure = StateError("local scan failed");
      var attempts = 0;
      final operation = LocalSyncOperation(() async {
        attempts++;
        if (attempts == 1) await scan.future;
      });

      final first = operation.run();
      final joined = operation.run();
      expect(attempts, 1);
      final expectations = [
        expectLater(first, throwsA(same(failure))),
        expectLater(joined, throwsA(same(failure))),
      ];
      scan.completeError(failure);
      await Future.wait(expectations);

      await operation.run();
      expect(attempts, 2);
      expect(operation.current, isNull);
    },
  );

  test("coalesces callbacks through import and album refresh", () async {
    final imports = List.generate(2, (_) => Completer<void>());
    final refreshes = List.generate(2, (_) => Completer<void>());
    final importStarted = List.generate(2, (_) => Completer<void>());
    final refreshStarted = List.generate(2, (_) => Completer<void>());
    final library = <String>{"existing"};
    final imported = <Set<String>>[];
    var passes = 0;
    var active = 0;
    var maxActive = 0;
    final scheduler = LocalChangeSyncScheduler(() async {
      final pass = passes++;
      active++;
      if (active > maxActive) maxActive = active;
      imported.add(Set.of(library));
      importStarted[pass].complete();
      await imports[pass].future;
      refreshStarted[pass].complete();
      await refreshes[pass].future;
      active--;
    });

    final requests = List.generate(200, (_) => scheduler.request());
    await importStarted[0].future;
    expect(passes, 1);
    imports[0].complete();
    await refreshStarted[0].future;

    library.add("added during refresh");
    requests.addAll(List.generate(200, (_) => scheduler.request()));
    var completed = false;
    final completion = Future.wait(requests).then((_) => completed = true);
    await Future<void>.delayed(Duration.zero);
    expect(passes, 1);
    expect(completed, isFalse);

    refreshes[0].complete();
    await importStarted[1].future;
    expect(imported.last, contains("added during refresh"));
    expect(completed, isFalse);
    imports[1].complete();
    await refreshStarted[1].future;
    expect(completed, isFalse);
    refreshes[1].complete();
    await completion;

    expect(passes, 2);
    expect(maxActive, 1);
    expect(completed, isTrue);
  });

  test("picks up another change during a follow-up pass", () async {
    final gates = List.generate(3, (_) => Completer<void>());
    final started = List.generate(3, (_) => Completer<void>());
    var libraryRevision = 0;
    final importedRevisions = <int>[];
    final scheduler = LocalChangeSyncScheduler(() async {
      final pass = importedRevisions.length;
      importedRevisions.add(libraryRevision);
      started[pass].complete();
      await gates[pass].future;
    });

    final requests = [scheduler.request()];
    await started[0].future;
    libraryRevision++;
    requests.add(scheduler.request());
    gates[0].complete();
    await started[1].future;

    libraryRevision++;
    requests.add(scheduler.request());
    gates[1].complete();
    await started[2].future;
    gates[2].complete();
    await Future.wait(requests);

    expect(importedRevisions, [0, 1, 2]);
  });

  test(
    "reports a failed refresh to waiters and allows a later retry",
    () async {
      final refreshStarted = Completer<void>();
      final refresh = Completer<void>();
      final failure = StateError("album refresh failed");
      var attempts = 0;
      final scheduler = LocalChangeSyncScheduler(() async {
        attempts++;
        if (attempts == 1) {
          refreshStarted.complete();
          await refresh.future;
          throw failure;
        }
      });

      final first = scheduler.request();
      await refreshStarted.future;
      final waiting = scheduler.request();
      final expectations = [
        expectLater(first, throwsA(same(failure))),
        expectLater(waiting, throwsA(same(failure))),
      ];
      refresh.complete();
      await Future.wait(expectations);

      await scheduler.request();
      expect(attempts, 2);
    },
  );
}
