import 'dart:async';
import 'dart:convert';

import 'package:ente_auth/services/window_placement.dart';
import 'package:ente_auth/services/windows_window_placement.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const channel = MethodChannel('io.ente.auth/window_geometry');
  const key = 'windowsWindowPlacement';
  const size = Size(500, 420);
  const normal = Rect.fromLTWH(180, 150, 500, 420);
  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
  late SharedPreferences preferences;
  late WindowsWindowPlacement placement;
  late Map<String, dynamic> snapshot;
  Rect? restored;
  var captures = 0;
  var fail = false;
  Completer<void>? blocked;

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    preferences = await SharedPreferences.getInstance();
    placement = WindowsWindowPlacement(preferences);
    restored = null;
    captures = 0;
    fail = false;
    blocked = null;
    snapshot = {
      'normalBounds': rectJson(normal),
      'normalMonitorId': 'primary',
      'maximized': false,
      'minimized': false,
      'monitors': [
        {
          'id': 'primary',
          'workArea': rectJson(const Rect.fromLTWH(0, 0, 1920, 1040)),
          'dpi': 96,
          'primary': true,
        },
      ],
    };
    messenger.setMockMethodCallHandler(channel, (call) async {
      if (call.method == 'snapshot') {
        captures++;
        if (fail) throw PlatformException(code: 'test-failure');
        await blocked?.future;
        return snapshot;
      }
      if (call.method == 'setBounds') {
        restored = readRect(call.arguments as Map);
      }
      return null;
    });
  });

  tearDown(() {
    messenger.setMockMethodCallHandler(channel, null);
  });

  Placement saved() => Placement.fromJson(
    jsonDecode(preferences.getString(key)!) as Map<String, dynamic>,
  );

  test('restores the saved normal bounds and maximized state', () async {
    await preferences.setString(
      key,
      jsonEncode(const Placement('primary', normal, true).toJson()),
    );
    expect(await placement.restore(size, false), isTrue);
    expect(restored, normal);
  });

  test(
    'first launch retains the legacy size and maximized preference',
    () async {
      expect(await placement.restore(size, true), isTrue);
      expect(restored, const Rect.fromLTWH(70, 70, 500, 420));
    },
  );

  test('invalid stored data uses the legacy defaults', () async {
    await preferences.setString(key, '{broken');
    expect(await placement.restore(size, false), isFalse);
    expect(restored?.size, size);
  });

  test('startup events cannot overwrite saved placement', () async {
    await placement.save(maximized: true);
    await placement.restore(size, false);
    await placement.save();
    expect(captures, 1);
    expect(preferences.getString(key), isNull);
    await placement.startSaving();
    expect(saved().logicalBounds, normal);
  });

  test('maximized capture reads the current native normal rectangle', () async {
    await placement.startSaving();
    const moved = Rect.fromLTWH(300, 180, 460, 380);
    snapshot['normalBounds'] = rectJson(moved);
    snapshot['maximized'] = true;
    await placement.save(maximized: true);
    expect(saved().logicalBounds, moved);
    expect(saved().maximized, isTrue);
  });

  test(
    'rapid maximize then minimize keeps the latest normal bounds and state',
    () async {
      await placement.startSaving();
      const moved = Rect.fromLTWH(300, 180, 460, 380);
      snapshot['normalBounds'] = rectJson(moved);
      snapshot['minimized'] = true;
      final maximize = placement.save(maximized: true);
      final minimize = placement.save();
      await Future.wait([maximize, minimize]);
      expect(saved().logicalBounds, moved);
      expect(saved().maximized, isTrue);
      snapshot['minimized'] = false;
      await placement.save(maximized: false);
      expect(saved().maximized, isFalse);
    },
  );

  test('a failed capture does not block a later save', () async {
    fail = true;
    await placement.startSaving();
    expect(preferences.getString(key), isNull);
    fail = false;
    await placement.save();
    expect(saved().logicalBounds, normal);
  });

  test('a failed capture retains state events before minimizing', () async {
    await placement.startSaving();
    fail = true;
    await placement.save(maximized: true);
    fail = false;
    snapshot['minimized'] = true;
    await placement.save();
    expect(saved().maximized, isTrue);
  });

  test('the final save waits for earlier captures and persistence', () async {
    await placement.startSaving();
    final initialCaptures = captures;
    blocked = Completer<void>();
    final first = placement.save();
    final flush = placement.save();
    await Future<void>.delayed(Duration.zero);
    expect(captures, initialCaptures + 1);
    blocked!.complete();
    await Future.wait([first, flush]);
    expect(captures, initialCaptures + 2);
    expect(saved().logicalBounds, normal);
  });
}
