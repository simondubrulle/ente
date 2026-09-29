import 'dart:io';

import 'package:dio/dio.dart';
import 'package:ente_auth/core/configuration.dart';
import 'package:ente_auth/locale.dart';
import 'package:ente_auth/services/preference_service.dart';
import 'package:ente_auth/ui/settings/about_settings_page.dart';
import 'package:ente_auth/ui/settings/data/data_settings_page.dart';
import 'package:ente_auth/ui/settings/widgets/change_log_strings.dart';
import 'package:ente_auth/ui/settings_page.dart';
import 'package:ente_components/ente_components.dart';
import 'package:ente_network/network.dart';
import 'package:ente_strings/ente_strings.dart';
import 'package:ente_ui/pages/settings_search_page.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late Directory directory;

  setUpAll(() async {
    directory = await Directory.systemTemp.createTemp('auth_whats_new_');
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
          const MethodChannel('plugins.flutter.io/path_provider'),
          (_) async => directory.path,
        );
    FlutterSecureStorage.setMockInitialValues({});
    SharedPreferences.setMockInitialValues({});
    PackageInfo.setMockInitialValues(
      appName: 'Ente Auth',
      packageName: 'io.ente.auth',
      version: '4.4.27',
      buildNumber: '1007',
      buildSignature: '',
    );
    await Configuration.instance.init([]);
    await PreferenceService.instance.init();
    await Network.instance.init(Configuration.instance);
    // Settings already refreshes account details. Simulate no connectivity.
    Network.instance.enteDio.interceptors.add(
      InterceptorsWrapper(
        onRequest: (options, handler) => handler.reject(
          DioException(
            requestOptions: options,
            type: DioExceptionType.connectionError,
          ),
        ),
      ),
    );
  });

  tearDownAll(() async {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
          const MethodChannel('plugins.flutter.io/path_provider'),
          null,
        );
    await directory.delete(recursive: true);
  });

  for (final locale in appSupportedLocales) {
    if (locale.languageCode != 'en') {
      test('changelog translates every entry for $locale', () {
        final english = ChangeLogStrings.forLocale(const Locale('en'));
        final translated = ChangeLogStrings.forLocale(locale);
        expect(translated.entries, hasLength(english.entries.length));
        for (var i = 0; i < translated.entries.length; i++) {
          expect(translated.entries[i].title, isNotEmpty);
          expect(translated.entries[i].description, isNotEmpty);
          expect(translated.entries[i].title, isNot(english.entries[i].title));
          expect(
            translated.entries[i].description,
            isNot(english.entries[i].description),
          );
        }
      });
    }

    testWidgets('changelog renders and scrolls in $locale', (tester) async {
      tester.view.physicalSize = const Size(320, 568);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      await tester.pumpWidget(
        MaterialApp(
          locale: locale,
          theme: ComponentTheme.lightTheme(app: ComponentApp.auth),
          localizationsDelegates: StringsLocalizations.localizationsDelegates,
          supportedLocales: appSupportedLocales,
          builder: (context, child) => MediaQuery(
            data: MediaQuery.of(
              context,
            ).copyWith(textScaler: const TextScaler.linear(1.5)),
            child: child!,
          ),
          home: const AboutSettingsPage(),
        ),
      );
      await tester.pumpAndSettle();
      final l10n = tester.element(find.byType(AboutSettingsPage)).strings;
      await tester.tap(find.text(l10n.whatsNew));
      await tester.pumpAndSettle();
      final sheet = find.byType(BottomSheetComponent);
      expect(Localizations.localeOf(tester.element(sheet)), locale);
      expect(
        Directionality.of(tester.element(sheet)),
        ['ar', 'fa', 'he'].contains(locale.languageCode)
            ? TextDirection.rtl
            : TextDirection.ltr,
      );
      final entries = ChangeLogStrings.forLocale(locale).entries;
      for (final entry in entries) {
        await tester.scrollUntilVisible(
          find.text(entry.description),
          100,
          scrollable: find.descendant(
            of: sheet,
            matching: find.byType(Scrollable),
          ),
        );
        expect(find.text(entry.title), findsOneWidget);
        expect(find.text(entry.description), findsOneWidget);
      }
      expect(tester.takeException(), isNull);
      await tester.tap(find.text(l10n.continueLabel));
      await tester.pumpAndSettle();
      expect(sheet, findsNothing);
    });
  }

  test('changelog falls back by language, then to English', () {
    expect(
      ChangeLogStrings.forLocale(const Locale('es', 'MX')),
      same(ChangeLogStrings.forLocale(const Locale('es', 'ES'))),
    );
    expect(
      ChangeLogStrings.forLocale(const Locale('xx')),
      same(ChangeLogStrings.forLocale(const Locale('en'))),
    );
  });

  for (final signedIn in [false, true]) {
    group(signedIn ? 'signed in without internet' : 'offline mode', () {
      setUp(() async {
        await Configuration.instance.logout();
        if (signedIn) {
          await Configuration.instance.setKey('dGVzdA==');
          await Configuration.instance.setToken('test-token');
        }
        expect(Configuration.instance.hasConfiguredAccount(), signedIn);
      });

      testWidgets('version opens the changelog and can reopen it', (
        tester,
      ) async {
        await _pumpSettings(tester);
        await tester.scrollUntilVisible(find.text('Version 4.4.27'), 350);
        await tester.tap(find.text('Version 4.4.27'));
        await tester.pumpAndSettle();
        _expectChangeLog();
        await tester.tap(find.text('Continue'));
        await tester.pumpAndSettle();
        expect(find.text('Newest first'), findsNothing);
        await tester.tap(find.text('Version 4.4.27'));
        await tester.pumpAndSettle();
        _expectChangeLog();
      });

      testWidgets('About opens the changelog without a loading animation', (
        tester,
      ) async {
        await _pumpSettings(tester);
        await tester.scrollUntilVisible(find.text('About'), 250);
        await tester.tap(find.text('About'));
        await tester.pumpAndSettle();
        final row = tester.widget<SettingsItem>(
          find.widgetWithText(SettingsItem, "What's new"),
        );
        expect(row.showOnlyLoadingState, isFalse);
        await tester.tap(find.text("What's new"));
        await tester.pump(const Duration(milliseconds: 350));
        expect(find.byType(CircularProgressIndicator), findsNothing);
        await tester.pumpAndSettle();
        _expectChangeLog();
        await tester.tap(find.byTooltip('Close'));
        await tester.pumpAndSettle();
        expect(find.byType(AboutSettingsPage), findsOneWidget);
        expect(find.text('Newest first'), findsNothing);
      });

      testWidgets('search finds release notes and respects account mode', (
        tester,
      ) async {
        await _pumpSettings(tester);
        await tester.tap(find.byTooltip('Search settings'));
        await tester.pumpAndSettle();
        for (final query in [
          "What's new",
          'changelog',
          'release notes',
          'updates',
          '  RELEASE NOTES  ',
        ]) {
          await tester.enterText(find.byType(TextField), query);
          await tester.pumpAndSettle();
          expect(
            find.widgetWithText(MenuComponent, "What's new"),
            findsOneWidget,
          );
        }
        await tester.tap(find.text("What's new"));
        await tester.pumpAndSettle();
        expect(find.byType(AboutSettingsPage), findsOneWidget);
        await tester.tap(find.text("What's new"));
        await tester.pumpAndSettle();
        _expectChangeLog();
        await tester.tap(find.text('Continue'));
        await tester.pumpAndSettle();
        await tester.tap(find.byIcon(Icons.arrow_back));
        await tester.pumpAndSettle();
        await tester.enterText(find.byType(TextField), 'Account');
        await tester.pumpAndSettle();
        expect(
          find.widgetWithText(MenuComponent, 'Account'),
          signedIn ? findsOneWidget : findsNothing,
        );
        await tester.enterText(find.byType(TextField), 'no matching setting');
        await tester.pumpAndSettle();
        expect(find.text('No results found'), findsOneWidget);
        expect(find.text("What's new"), findsNothing);

        for (final section in [
          'Data',
          'Security',
          'Theme',
          'General',
          'Support',
          'About',
        ]) {
          await tester.enterText(find.byType(TextField), section);
          await tester.pumpAndSettle();
          expect(find.widgetWithText(SettingsItem, section), findsWidgets);
        }
        await tester.enterText(find.byType(TextField), '');
        await tester.pumpAndSettle();
        expect(find.text('Suggestions'), findsOneWidget);
        await tester.tap(find.text("What's new"));
        await tester.pumpAndSettle();
        expect(find.byType(AboutSettingsPage), findsOneWidget);
      });
    });
  }

  for (final completed in [false, true]) {
    testWidgets('search closes the drawer only after completion: $completed', (
      tester,
    ) async {
      final scaffoldKey = GlobalKey<ScaffoldState>();
      final emailNotifier = ValueNotifier<String?>(null);
      addTearDown(emailNotifier.dispose);
      await tester.pumpWidget(
        MaterialApp(
          theme: ComponentTheme.lightTheme(app: ComponentApp.auth),
          localizationsDelegates: StringsLocalizations.localizationsDelegates,
          supportedLocales: StringsLocalizations.supportedLocales,
          home: Scaffold(
            key: scaffoldKey,
            drawer: Drawer(
              width: 428,
              child: SettingsPage(
                emailNotifier: emailNotifier,
                scaffoldKey: scaffoldKey,
              ),
            ),
          ),
        ),
      );
      scaffoldKey.currentState!.openDrawer();
      await tester.pumpAndSettle();
      await tester.tap(find.byTooltip('Search settings'));
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextField), 'Data');
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(MenuComponent, 'Data'));
      await tester.pumpAndSettle();
      Navigator.of(
        tester.element(find.byType(DataSettingsPage)),
      ).pop(completed ? true : null);
      await tester.pumpAndSettle();
      expect(scaffoldKey.currentState!.isDrawerOpen, !completed);
      expect(
        find.byType(SettingsSearchPage),
        completed ? findsNothing : findsOneWidget,
      );
    });
  }

  testWidgets('search refreshes when language and theme change', (
    tester,
  ) async {
    var locale = const Locale('en');
    var dark = false;
    late StateSetter updateApp;
    final emailNotifier = ValueNotifier<String?>(null);
    addTearDown(emailNotifier.dispose);
    await tester.pumpWidget(
      StatefulBuilder(
        builder: (context, setState) {
          updateApp = setState;
          return MaterialApp(
            locale: locale,
            theme: dark
                ? ComponentTheme.darkTheme(app: ComponentApp.auth)
                : ComponentTheme.lightTheme(app: ComponentApp.auth),
            localizationsDelegates: StringsLocalizations.localizationsDelegates,
            supportedLocales: StringsLocalizations.supportedLocales,
            home: SettingsPage(
              emailNotifier: emailNotifier,
              scaffoldKey: GlobalKey<ScaffoldState>(),
            ),
          );
        },
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('Search settings'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField), 'release notes');
    await tester.pumpAndSettle();
    updateApp(() {
      locale = const Locale('fr');
      dark = true;
    });
    await tester.pumpAndSettle();
    final search = find.byType(SettingsSearchPage);
    final context = tester.element(search);
    expect(
      tester.widget<TextField>(find.byType(TextField)).controller!.text,
      '',
    );
    expect(find.text(context.strings.suggestions), findsOneWidget);
    expect(find.text(context.strings.data), findsOneWidget);
    expect(find.text(context.strings.security), findsOneWidget);
    expect(find.text(context.strings.whatsNew), findsOneWidget);
    final background = tester.widget<ColoredBox>(
      find.ancestor(of: search, matching: find.byType(ColoredBox)).first,
    );
    expect(background.color, context.componentColors.backgroundBase);
    expect(Theme.of(context).brightness, Brightness.dark);
    await tester.enterText(find.byType(TextField), context.strings.data);
    await tester.pumpAndSettle();
    expect(
      find.widgetWithText(MenuComponent, context.strings.data),
      findsOneWidget,
    );
  });

  testWidgets('search keeps Auth settings width in a desktop window', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1440, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await _pumpSettings(tester);
    await tester.tap(find.byTooltip('Search settings'));
    await tester.pumpAndSettle();
    expect(
      tester.getSize(find.byType(TextField)).width,
      lessThanOrEqualTo(720),
    );
    await tester.enterText(find.byType(TextField), 'Data');
    await tester.pumpAndSettle();
    expect(
      tester.getSize(find.widgetWithText(MenuComponent, 'Data')).width,
      lessThanOrEqualTo(720),
    );
    await tester.enterText(find.byType(TextField), "What's new");
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(MenuComponent, "What's new"));
    await tester.pumpAndSettle();
    await tester.tap(find.text("What's new"));
    await tester.pumpAndSettle();
    expect(find.byType(Dialog), findsOneWidget);
    _expectChangeLog();
    expect(tester.takeException(), isNull);
    await tester.tap(find.byTooltip('Close'));
    await tester.pumpAndSettle();
    expect(find.byType(Dialog), findsNothing);
  }, variant: TargetPlatformVariant.only(TargetPlatform.windows));

  for (final ratio in [2.0, 3.0]) {
    testWidgets('changelog uses the ${ratio}x illustration', (tester) async {
      final key = await const AssetImage(
        'assets/whats_new_illustration.png',
      ).obtainKey(ImageConfiguration(devicePixelRatio: ratio));
      expect(key.name, 'assets/${ratio}x/whats_new_illustration.png');
    });
  }

  testWidgets('changelog scrolls on a small screen with large text', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(320, 568);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(
      MaterialApp(
        theme: ComponentTheme.lightTheme(app: ComponentApp.auth),
        localizationsDelegates: StringsLocalizations.localizationsDelegates,
        supportedLocales: StringsLocalizations.supportedLocales,
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(
            context,
          ).copyWith(textScaler: const TextScaler.linear(2)),
          child: child!,
        ),
        home: const AboutSettingsPage(),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text("What's new"));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    await tester.scrollUntilVisible(
      find.text(
        'Bring your codes into Ente Auth from an Open Authenticator backup.',
      ),
      100,
      scrollable: find.descendant(
        of: find.byType(BottomSheetComponent),
        matching: find.byType(Scrollable),
      ),
    );
    expect(tester.takeException(), isNull);
    await tester.tap(find.text('Continue'));
    await tester.pumpAndSettle();
    expect(find.byType(BottomSheetComponent), findsNothing);
  });
}

Future<void> _pumpSettings(WidgetTester tester) async {
  final emailNotifier = ValueNotifier<String?>(null);
  addTearDown(emailNotifier.dispose);
  await tester.pumpWidget(
    MaterialApp(
      theme: ComponentTheme.lightTheme(app: ComponentApp.auth),
      localizationsDelegates: StringsLocalizations.localizationsDelegates,
      supportedLocales: StringsLocalizations.supportedLocales,
      home: SettingsPage(
        emailNotifier: emailNotifier,
        scaffoldKey: GlobalKey<ScaffoldState>(),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

void _expectChangeLog() {
  expect(find.text('Newest first'), findsOneWidget);
  expect(
    find.text('Show your most recently added codes first.'),
    findsOneWidget,
  );
  expect(find.text('Import from Open Authenticator'), findsOneWidget);
  expect(
    find.text(
      'Bring your codes into Ente Auth from an Open Authenticator backup.',
    ),
    findsOneWidget,
  );
}
