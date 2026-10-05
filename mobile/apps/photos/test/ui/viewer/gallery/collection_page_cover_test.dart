import "dart:convert";
import "dart:io";

import "package:dio/dio.dart";
import "package:ente_strings/ente_strings.dart";
import "package:flutter/material.dart";
import "package:flutter_test/flutter_test.dart";
import "package:package_info_plus/package_info_plus.dart";
import "package:path_provider_platform_interface/path_provider_platform_interface.dart";
import "package:photos/core/cache/thumbnail_in_memory_cache.dart";
import "package:photos/core/configuration.dart";
import "package:photos/core/constants.dart";
import "package:photos/core/event_bus.dart";
import "package:photos/db/files_db.dart";
import "package:photos/ente_theme_data.dart";
import "package:photos/events/collection_meta_event.dart";
import "package:photos/events/collection_updated_event.dart";
import "package:photos/models/api/collection/user.dart";
import "package:photos/models/collection/collection.dart";
import "package:photos/models/collection/collection_items.dart";
import "package:photos/models/file/file.dart";
import "package:photos/models/file/file_type.dart";
import "package:photos/models/ignored_file.dart";
import "package:photos/models/metadata/collection_magic.dart";
import "package:photos/service_locator.dart";
import "package:photos/services/collections_service.dart";
import "package:photos/services/favorites_service.dart";
import "package:photos/services/ignored_files_service.dart";
import "package:photos/ui/viewer/gallery/collection_page.dart";
import "package:photos/ui/viewer/gallery/component/album_cover_app_bar.dart";
import "package:photos/ui/viewer/gallery/state/gallery_files_inherited_widget.dart";
import "package:shared_preferences/shared_preferences.dart";

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late Directory tempDir;
  late PathProviderPlatform previousPathProvider;

  setUpAll(() async {
    tempDir = await Directory.systemTemp.createTemp("collection_page_cover_");
    previousPathProvider = PathProviderPlatform.instance;
    PathProviderPlatform.instance = _FakePathProvider(tempDir.path);
    SharedPreferences.setMockInitialValues({});
    final preferences = await SharedPreferences.getInstance();
    ServiceLocator.instance.init(
      preferences,
      Dio(),
      Dio(),
      Dio(),
      PackageInfo(
        appName: "Photos",
        packageName: "photos",
        version: "1.0.0",
        buildNumber: "1",
      ),
    );
    try {
      await Configuration.instance.init(preferences);
    } catch (_) {}
    await Configuration.instance.setUserID(1);
    await CollectionsService.instance.init(preferences);
    await FavoritesService.instance.initFav();
    expect(flagService.internalUser, isTrue);
  });

  setUp(() async {
    await FilesDB.instance.clearTable();
    await IgnoredFilesService.instance.reset();
  });

  tearDownAll(() async {
    PathProviderPlatform.instance = previousPathProvider;
    await tempDir.delete(recursive: true);
  });

  testWidgets("uses a pending local photo and excludes ignored photos", (
    tester,
  ) async {
    final collection = _collection();
    final files = List.generate(
      101,
      (index) => _file(index + 1, uploaded: false),
    );
    final cover = files[99];
    final ignored = files.last;
    await tester.runAsync(() async {
      await FilesDB.instance.insertMultiple(files);
      await IgnoredFilesService.instance.cacheAndInsert([
        IgnoredFile(
          ignored.localID,
          ignored.title,
          ignored.deviceFolder,
          "ignored",
        ),
      ]);
    });

    await _pumpAlbum(tester, collection);
    await _expectCover(tester, cover, count: 100);
    expect(find.text("1 JAN – 10 APR 2026"), findsOneWidget);
    await _disposeAlbum(tester);
  });

  testWidgets(
    "refreshes sorted covers and preserves an explicitly selected cover",
    (tester) async {
      final collection = _collection();
      final oldest = _file(1);
      final newest = _file(3);
      await tester.runAsync(() async {
        await FilesDB.instance.insertMultiple([oldest, newest]);
        expect(await CollectionsService.instance.getCover(collection), newest);
      });
      await _pumpAlbum(tester, collection);
      await _expectCover(tester, newest, count: 2);

      collection.pubMagicMetadata = CollectionPubMagicMetadata(asc: true);
      Bus.instance.fire(
        CollectionMetaEvent(collection.id, CollectionMetaEventType.sortChanged),
      );
      await _expectCover(tester, oldest, count: 2);
      expect(find.text("1–3 JAN 2026"), findsOneWidget);

      final middle = _file(2);
      await tester.runAsync(() => FilesDB.instance.insertMultiple([middle]));
      Bus.instance.fire(
        CollectionUpdatedEvent(collection.id, [middle], "added"),
      );
      await _expectCover(tester, oldest, count: 3);

      collection.pubMagicMetadata = CollectionPubMagicMetadata(
        asc: true,
        coverID: 3,
      );
      Bus.instance.fire(
        CollectionUpdatedEvent(collection.id, [], "cover_change"),
      );
      await _expectCover(tester, newest);

      collection.pubMagicMetadata = CollectionPubMagicMetadata(asc: true);
      Bus.instance.fire(
        CollectionUpdatedEvent(collection.id, [], "cover_change"),
      );
      await _expectCover(tester, oldest);

      await tester.runAsync(
        () => FilesDB.instance.deleteCollection(collection.id),
      );
      Bus.instance.fire(CollectionUpdatedEvent(collection.id, [], "removed"));
      await _expectCover(tester, null);
      await _disposeAlbum(tester);
    },
  );
}

Collection _collection() => Collection(
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
);

EnteFile _file(int id, {bool uploaded = true}) {
  final file = EnteFile()
    ..generatedID = id
    ..uploadedFileID = uploaded ? id : null
    ..ownerID = 1
    ..collectionID = 1
    ..localID = "local-$id"
    ..title = "$id.jpg"
    ..deviceFolder = "Camera"
    ..fileType = FileType.image
    ..creationTime = DateTime(2026, 1, id).microsecondsSinceEpoch
    ..modificationTime = DateTime(2026, 1, id).microsecondsSinceEpoch;
  final bytes = base64Decode(_onePixelPng);
  ThumbnailInMemoryLruCache.put(file, bytes, thumbnailSmallSize);
  ThumbnailInMemoryLruCache.put(file, bytes, thumbnailLargeSize);
  return file;
}

Future<void> _pumpAlbum(WidgetTester tester, Collection collection) async {
  await tester.pumpWidget(
    MaterialApp(
      theme: lightThemeData,
      localizationsDelegates: StringsLocalizations.localizationsDelegates,
      supportedLocales: StringsLocalizations.supportedLocales,
      home: CollectionPage(CollectionWithThumbnail(collection, null)),
    ),
  );
}

Future<void> _expectCover(
  WidgetTester tester,
  EnteFile? file, {
  int? count,
}) async {
  await tester.runAsync(() async {
    for (var i = 0; i < 100; i++) {
      await tester.pump(const Duration(milliseconds: 100));
      final covers = tester.widgetList<AlbumCoverAppBar>(
        find.byType(AlbumCoverAppBar),
      );
      final hasExpectedCover = file == null
          ? covers.isEmpty
          : covers.singleOrNull?.cover == file;
      final hasExpectedCount =
          count == null ||
          tester
                  .widget<GalleryFilesState>(find.byType(GalleryFilesState))
                  .galleryFilesOrNull
                  ?.length ==
              count;
      if (hasExpectedCover && hasExpectedCount) {
        await tester.pump(const Duration(seconds: 1));
        return;
      }
      await Future<void>.delayed(const Duration(milliseconds: 10));
    }
  });
  final covers = tester.widgetList<AlbumCoverAppBar>(
    find.byType(AlbumCoverAppBar),
  );
  expect(covers.map((cover) => cover.cover), file == null ? isEmpty : [file]);
  if (count != null) {
    expect(
      tester
          .widget<GalleryFilesState>(find.byType(GalleryFilesState))
          .galleryFilesOrNull
          ?.length,
      count,
    );
  }
  expect(tester.takeException(), isNull);
}

Future<void> _disposeAlbum(WidgetTester tester) async {
  await tester.pumpWidget(const SizedBox.shrink());
  await tester.pump(const Duration(seconds: 1));
}

class _FakePathProvider extends PathProviderPlatform {
  _FakePathProvider(this.path);

  final String path;

  @override
  Future<String?> getApplicationDocumentsPath() async => path;

  @override
  Future<String?> getApplicationSupportPath() async => path;
}

const _onePixelPng =
    "iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mNk+M9QDwADhgGAWjR9awAAAABJRU5ErkJggg==";
