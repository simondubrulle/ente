import "dart:async";
import "dart:convert";

import "package:ente_pure_utils/ente_pure_utils.dart";
import "package:flutter/material.dart";
import "package:flutter/services.dart";
import "package:flutter_test/flutter_test.dart";
import "package:photos/core/cache/thumbnail_in_memory_cache.dart";
import "package:photos/core/page_route_observer.dart";
import "package:photos/ente_theme_data.dart";
import "package:photos/models/api/collection/user.dart";
import "package:photos/models/collection/collection.dart";
import "package:photos/models/file/file.dart";
import "package:photos/ui/viewer/gallery/component/album_cover_app_bar.dart";

void main() {
  testWidgets("resets the status bar style only when a page covers it", (
    tester,
  ) async {
    final iconBrightness = <String>[];
    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
      SystemChannels.platform,
      (call) async {
        if (call.method == "SystemChrome.setSystemUIOverlayStyle") {
          iconBrightness.add(
            (call.arguments as Map)["statusBarIconBrightness"] as String,
          );
        }
        return null;
      },
    );
    addTearDown(
      () => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        SystemChannels.platform,
        null,
      ),
    );

    final cover = EnteFile()
      ..uploadedFileID = 1
      ..generatedID = 1;
    ThumbnailInMemoryLruCache.put(cover, base64Decode(_onePixelPng));

    await tester.pumpWidget(
      MaterialApp(
        theme: lightThemeData,
        navigatorObservers: [pageRouteObserver],
        home: Scaffold(
          body: CustomScrollView(
            slivers: [
              AlbumCoverAppBar(
                collection: Collection(
                  1,
                  User(id: 1, email: "a@b.c"),
                  "",
                  null,
                  "Album",
                  null,
                  null,
                  CollectionType.album,
                  CollectionAttributes(),
                  [],
                  [],
                  0,
                ),
                cover: cover,
                title: "Album",
                backgroundColor: Colors.white,
                collapsedHeight: kToolbarHeight,
                actionsBuilder: (_) => const [],
                coverActions: const [],
              ),
            ],
          ),
        ),
      ),
    );
    await tester.pump();
    expect(iconBrightness.last, "Brightness.light");

    final context = tester.element(find.byType(Scaffold));
    unawaited(
      showDialog<void>(
        context: context,
        builder: (_) => const AlertDialog(title: Text("dialog")),
      ),
    );
    await tester.pumpAndSettle();
    expect(iconBrightness.last, "Brightness.light");

    Navigator.of(context).pop();
    await tester.pumpAndSettle();

    unawaited(routeToPage(context, const Scaffold(body: Text("next page"))));
    await tester.pumpAndSettle();
    expect(iconBrightness.last, "Brightness.dark");

    Navigator.of(context).pop();
    await tester.pumpAndSettle();
    expect(iconBrightness.last, "Brightness.light");

    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump(const Duration(seconds: 1));
  });
}

const _onePixelPng =
    "iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mNk+M9QDwADhgGAWjR9awAAAABJRU5ErkJggg==";
