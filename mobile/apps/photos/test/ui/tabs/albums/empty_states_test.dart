import "package:ente_components/ente_components.dart";
import "package:ente_strings/ente_strings.dart";
import "package:flutter/material.dart";
import "package:flutter_test/flutter_test.dart";
import "package:photos/ente_theme_data.dart";
import "package:photos/ui/home/home_bottom_nav_bar.dart";
import "package:photos/ui/social/widgets/feed_empty_state.dart";
import "package:photos/ui/tabs/albums/empty_states/empty_state_layout.dart";
import "package:photos/ui/tabs/albums/empty_states/on_device_empty_state.dart";
import "package:photos/ui/tabs/albums/empty_states/on_ente_empty_state.dart";
import "package:photos/ui/tabs/albums/empty_states/received_empty_state.dart";
import "package:photos/ui/tabs/albums/empty_states/shared_empty_state.dart";

const _screenSize = Size(402, 874);
const _bottomSafeArea = 34.0;

void main() {
  final cases = <(String, Widget, String, String, String, String?)>[
    (
      "Ente",
      const OnEnteEmptyState(),
      "assets/on_ente.png",
      "Back up your memories",
      "Access them on any device and share them with loved ones.",
      "Select albums to backup",
    ),
    (
      "Device without permission",
      const OnDeviceEmptyState.permission(),
      "assets/on_device.png",
      "Allow access to your photos",
      "Your photos get organized with face recognition, right on your device.",
      "Allow access",
    ),
    (
      "Device without albums",
      const OnDeviceEmptyState.noFolders(),
      "assets/on_device_empty.png",
      "No albums on this device",
      "Start snapping, your photos will show up here.",
      null,
    ),
    (
      "Shared",
      const SharedEmptyState(),
      "assets/shared.png",
      "Share your memories",
      "Loved ones can view, react and add comments, without an account.",
      "Share an album",
    ),
    (
      "Received",
      const ReceivedEmptyState(),
      "assets/received.png",
      "Memories shared with you",
      "Albums shared with you appear here, ready to view and save.",
      "Share an album",
    ),
    (
      "Feed",
      const FeedEmptyState(),
      "assets/feed.png",
      "Share your memories",
      "Loved ones can view, react and add comments, without an account.",
      "Share an album",
    ),
  ];

  for (final (name, state, asset, title, description, action) in cases) {
    testWidgets("$name empty state shows its illustration, copy and action", (
      tester,
    ) async {
      await _pumpInHost(tester, state);

      expect(_assetImage(asset), findsOneWidget);
      expect(find.text(title), findsOneWidget);
      expect(find.text(description), findsOneWidget);
      if (action == null) {
        expect(find.byType(ButtonComponent), findsNothing);
      } else {
        expect(find.widgetWithText(ButtonComponent, action), findsOneWidget);
      }
    });
  }

  testWidgets("centers content in the space above the bottom navigation", (
    tester,
  ) async {
    await _pumpInHost(tester, const ReceivedEmptyState());

    final content = tester.getRect(_layoutColumn());
    expect(
      content.center.dy,
      moreOrLessEquals((_screenSize.height - _bottomSafeArea - 52) / 2),
    );
    expect(content.center.dx, moreOrLessEquals(_screenSize.width / 2));
  });

  testWidgets("centers content in the full height without navigation", (
    tester,
  ) async {
    await _pump(
      tester,
      const FeedEmptyState(reservesBottomNavigationSpace: false),
    );

    expect(
      tester.getRect(_layoutColumn()).center.dy,
      moreOrLessEquals((_screenSize.height - _bottomSafeArea) / 2),
    );
  });

  for (final (name, state, size, textScale) in <(String, Widget, Size, double)>[
    ("Received", const ReceivedEmptyState(), const Size(402, 480), 2),
    ("Received", const ReceivedEmptyState(), const Size(375, 500), 2),
    ("Ente", const OnEnteEmptyState(), const Size(402, 400), 1.5),
    ("Feed", const FeedEmptyState(), const Size(320, 480), 2),
  ]) {
    testWidgets(
      "$name empty state at ${size.width.toInt()}x${size.height.toInt()} "
      "with ${textScale}x text scrolls its action clear of the nav bar",
      (tester) async {
        await _pumpInHost(
          tester,
          state,
          size: size,
          textScaler: TextScaler.linear(textScale),
        );

        expect(tester.takeException(), isNull);
        await tester.drag(
          find.byType(SingleChildScrollView),
          const Offset(0, -2000),
        );
        await tester.pumpAndSettle();
        final action = find.byType(ButtonComponent);
        expect(action.hitTestable(), findsOneWidget);
        expect(
          tester.getRect(action).bottom,
          lessThanOrEqualTo(
            size.height - _bottomSafeArea - homeBottomNavigationBarHeight,
          ),
        );
      },
    );
  }
}

Finder _assetImage(String path) => find.byWidgetPredicate(
  (widget) =>
      widget is Image &&
      widget.image is AssetImage &&
      (widget.image as AssetImage).assetName == path,
);

Finder _layoutColumn() => find
    .descendant(
      of: find.byType(EmptyStateLayout),
      matching: find.byType(Column),
    )
    .first;

Future<void> _pumpInHost(
  WidgetTester tester,
  Widget state, {
  Size size = _screenSize,
  TextScaler textScaler = TextScaler.noScaling,
}) {
  return _pump(
    tester,
    state is! FeedEmptyState
        ? CustomScrollView(slivers: [SliverFillRemaining(child: state)])
        : state,
    size: size,
    textScaler: textScaler,
  );
}

Future<void> _pump(
  WidgetTester tester,
  Widget child, {
  Size size = _screenSize,
  TextScaler textScaler = TextScaler.noScaling,
}) async {
  tester.view.physicalSize = size * tester.view.devicePixelRatio;
  addTearDown(tester.view.resetPhysicalSize);

  await tester.pumpWidget(
    MaterialApp(
      theme: lightThemeData,
      localizationsDelegates: StringsLocalizations.localizationsDelegates,
      supportedLocales: StringsLocalizations.supportedLocales,
      home: MediaQuery(
        data: MediaQueryData(
          size: size,
          padding: const EdgeInsets.only(bottom: _bottomSafeArea),
          textScaler: textScaler,
        ),
        child: Scaffold(body: child),
      ),
    ),
  );
  await tester.pumpAndSettle();
}
