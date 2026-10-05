import "dart:async";
import "dart:convert";

import "package:ente_pure_utils/ente_pure_utils.dart";
import "package:flutter/material.dart";
import "package:flutter/services.dart";
import "package:flutter_localizations/flutter_localizations.dart";
import "package:flutter_test/flutter_test.dart";
import "package:intl/date_symbol_data_local.dart";
import "package:photos/core/cache/thumbnail_in_memory_cache.dart";
import "package:photos/core/page_route_observer.dart";
import "package:photos/ente_theme_data.dart";
import "package:photos/models/api/collection/user.dart";
import "package:photos/models/collection/collection.dart";
import "package:photos/models/file/file.dart";
import "package:photos/ui/viewer/gallery/component/album_cover_app_bar.dart";
import "package:photos/ui/viewer/gallery/state/gallery_files_inherited_widget.dart";

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
  testWidgets(
    "shows a sort-independent date range and hides undated captions",
    (tester) async {
      await initializeDateFormatting();
      final cover = EnteFile()
        ..uploadedFileID = 2
        ..generatedID = 2;
      ThumbnailInMemoryLruCache.put(cover, base64Decode(_onePixelPng));
      final cases = <(DateTime?, DateTime?, String?, String)>[
        (DateTime(2021, 6, 24), DateTime(2021, 6, 24), "24 JUN 2021", "en"),
        (DateTime(2024, 6, 2), DateTime(2024, 6, 18), "2–18 JUN 2024", "en"),
        (
          DateTime(2024, 1, 2),
          DateTime(2024, 6, 18),
          "2 JAN – 18 JUN 2024",
          "en",
        ),
        (
          DateTime(2023, 12, 28),
          DateTime(2024, 1, 3),
          "28 DEC 2023 – 3 JAN 2024",
          "en",
        ),
        (DateTime(2019, 1, 1), DateTime(2024, 1, 1), "2019 – 2024", "en"),
        (null, DateTime(2030, 1, 1), "1 JAN 2030", "en"),
        (null, null, null, "en"),
        (DateTime.fromMicrosecondsSinceEpoch(0), null, null, "en"),
        (
          DateTime(2024, 6, 2),
          DateTime(2024, 6, 18),
          "2–18 DE JUN. DE 2024",
          "pt",
        ),
        (DateTime(2024, 6, 2), DateTime(2024, 6, 18), "2024年6月2–18日", "zh"),
      ];
      for (final (start, end, caption, language) in cases) {
        final files = [
          EnteFile()..creationTime = end?.microsecondsSinceEpoch,
          EnteFile()..creationTime = start?.microsecondsSinceEpoch,
        ];
        await tester.pumpWidget(
          MaterialApp(
            theme: lightThemeData,
            locale: Locale(language),
            supportedLocales: const [Locale("en"), Locale("pt"), Locale("zh")],
            localizationsDelegates: GlobalMaterialLocalizations.delegates,
            home: GalleryFilesState(
              child: Scaffold(
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
            )..setGalleryFiles = files,
          ),
        );
        await tester.pump();
        if (caption == null) {
          expect(find.textContaining(RegExp(r"\d")), findsNothing);
        } else {
          expect(
            find.text(caption),
            findsOneWidget,
            reason: tester
                .widgetList<Text>(find.byType(Text))
                .map((w) => w.data)
                .join(" | "),
          );
        }
        expect(tester.takeException(), isNull);
      }
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump(const Duration(seconds: 1));
    },
  );
}

const _onePixelPng =
    "iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mNk+M9QDwADhgGAWjR9awAAAABJRU5ErkJggg==";
