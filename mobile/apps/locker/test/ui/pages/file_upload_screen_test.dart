import 'dart:io';

import 'package:ente_components/ente_components.dart';
import 'package:ente_strings/ente_strings.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:locker/services/configuration.dart';
import 'package:locker/ui/pages/file_upload_screen.dart';

import '../../test_utils/configuration_test_util.dart';

void main() {
  late Directory testRoot;

  setUp(() async {
    testRoot = await setupLockerConfigurationForTest('file_upload_screen');
    await Configuration.instance.setUserID(1);
  });

  tearDown(() async {
    clearLockerConfigurationTestHandlers();
    await testRoot.delete(recursive: true);
  });

  for (final bottomInset in [0.0, 24.0]) {
    testWidgets('Save has spacing above a $bottomInset bottom inset', (
      tester,
    ) async {
      tester.view.devicePixelRatio = 1;
      tester.view.physicalSize = const Size(400, 800);
      tester.view.padding = FakeViewPadding(bottom: bottomInset);
      addTearDown(tester.view.reset);

      await tester.pumpWidget(
        MaterialApp(
          localizationsDelegates: StringsLocalizations.localizationsDelegates,
          supportedLocales: const [Locale('en')],
          home: FileUploadScreen(
            files: [File('${testRoot.path}/document.pdf')],
            collections: const [],
          ),
        ),
      );

      final save = find.widgetWithText(ButtonComponent, 'Save');
      expect(tester.getRect(save).bottom, 800 - bottomInset - 8);
    });
  }
}
