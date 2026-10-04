import 'dart:convert';
import 'dart:ui';

import 'package:ente_auth/services/window_placement.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  const primary = Monitor(
    'primary',
    Rect.fromLTWH(0, 0, 1920, 1040),
    1,
    primary: true,
  );
  const normal = Placement('primary', Rect.fromLTWH(180, 150, 500, 420), false);
  test('normal bounds survive serialization and restart', () {
    final decoded = Placement.fromJson(jsonDecode(jsonEncode(normal.toJson())));
    expect(
      restoreBounds(decoded, [primary], const Size(800, 1200)),
      normal.logicalBounds,
    );
  });
  for (final area in const [
    Rect.fromLTWH(0, 48, 1920, 1032),
    Rect.fromLTWH(0, 0, 1920, 1032),
    Rect.fromLTWH(48, 0, 1872, 1080),
    Rect.fromLTWH(0, 0, 1872, 1080),
  ]) {
    test('oversized defaults fit taskbar work area $area', () {
      final restored = restoreBounds(null, [
        Monitor('primary', area, 1, primary: true),
      ], const Size(800, 1200));
      expect(restored.top, greaterThanOrEqualTo(area.top));
      expect(restored.bottom, lessThanOrEqualTo(area.bottom));
      expect(restored.left, greaterThanOrEqualTo(area.left));
      expect(restored.right, lessThanOrEqualTo(area.right));
    });
  }
  test('secondary monitor with negative origin restores in its own scale', () {
    const secondary = Monitor(
      'second',
      Rect.fromLTWH(-2560, 60, 2560, 1380),
      1.5,
    );
    const bounds = Rect.fromLTWH(-2260, 210, 750, 630);
    final saved = captureBounds(bounds, secondary, false);
    expect(
      restoreBounds(saved, [primary, secondary], const Size(800, 1200)),
      bounds,
    );
  });
  test(
    'DPI and monitor-layout changes retain logical size and local offset',
    () {
      const moved = Monitor(
        'primary',
        Rect.fromLTWH(1920, 80, 2560, 1360),
        2,
        primary: true,
      );
      expect(
        restoreBounds(normal, [moved], const Size(800, 1200)),
        const Rect.fromLTWH(2280, 380, 1000, 840),
      );
    },
  );
  test('removed monitor falls back to primary and fits its work area', () {
    const lost = Placement(
      'removed',
      Rect.fromLTWH(2000, 2000, 3000, 2000),
      false,
    );
    expect(
      restoreBounds(lost, [primary], const Size(800, 1200)),
      primary.workArea,
    );
  });
  test('invalid persisted geometry is rejected', () {
    for (final invalid in [double.nan, double.infinity, -1.0, 0.0]) {
      expect(
        () => readRect({'x': 0, 'y': 0, 'width': invalid, 'height': 400}),
        throwsFormatException,
      );
    }
  });
}
