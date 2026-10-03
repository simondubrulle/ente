import "package:ente_components/ente_components.dart";
import "package:ente_strings/ente_strings.dart";
import "package:flutter/material.dart";
import "package:flutter_test/flutter_test.dart";
import "package:photos/ente_theme_data.dart";
import "package:photos/ui/components/bottom_action_bar/selection_action_button_widget.dart";
import "package:photos/ui/viewer/gallery/hooks/album_actions_sheet.dart";

void main() {
  group("showAlbumActionsSheet", () {
    testWidgets("keeps the destructive option last in the shelf", (
      tester,
    ) async {
      await _pumpLauncher(tester, (_) {});
      await _openLauncher(tester);

      final tileLabels = tester
          .widgetList<SelectionActionButton>(find.byType(SelectionActionButton))
          .map((tile) => tile.labelText);
      expect(tileLabels, ["Edit", "Pin", "Archive", "Delete"]);
      expect(find.text("Hide"), findsOneWidget);
      expect(find.text("Cast"), findsOneWidget);
    });

    testWidgets("returns the tapped row", (tester) async {
      String? result;
      await _pumpLauncher(tester, (value) => result = value);
      await _openLauncher(tester);

      await tester.tap(find.text("Hide"));
      await tester.pumpAndSettle();

      expect(result, "hide");
      expect(find.byType(BottomSheetComponent), findsNothing);
    });

    testWidgets("scrolls instead of overflowing on short screens", (
      tester,
    ) async {
      tester.view.physicalSize = const Size(667, 240);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      String? result;
      await _pumpLauncher(tester, (value) => result = value);
      await _openLauncher(tester);

      await tester.dragUntilVisible(
        find.text("Cast"),
        find.byType(SingleChildScrollView),
        const Offset(0, -50),
      );
      await tester.tap(find.text("Cast"));
      await tester.pumpAndSettle();

      expect(tester.takeException(), isNull);
      expect(result, "cast");
    });

    testWidgets("returns the tapped tile", (tester) async {
      String? result;
      await _pumpLauncher(tester, (value) => result = value);
      await _openLauncher(tester);

      await tester.tap(find.text("Delete"));
      await tester.pumpAndSettle();

      expect(result, "delete");
    });
  });
}

List<EntePopupMenuOption<String>> _options(BuildContext context) {
  EntePopupMenuOption<String> option(String label, {Color? labelColor}) {
    return EntePopupMenuOption(
      value: label.toLowerCase(),
      label: label,
      labelColor: labelColor,
      leadingWidget: const Icon(Icons.circle),
    );
  }

  return [
    option("Edit"),
    option("Pin"),
    option("Archive"),
    option("Hide"),
    option("Cast"),
    option("Delete", labelColor: context.componentColors.warning),
  ];
}

Future<void> _pumpLauncher(
  WidgetTester tester,
  ValueChanged<String?> onResult,
) async {
  await tester.pumpWidget(
    MaterialApp(
      theme: lightThemeData,
      localizationsDelegates: StringsLocalizations.localizationsDelegates,
      supportedLocales: StringsLocalizations.supportedLocales,
      home: Scaffold(
        body: Builder(
          builder: (context) {
            return TextButton(
              onPressed: () async {
                onResult(
                  await showAlbumActionsSheet(context, _options(context)),
                );
              },
              child: const Text("Open sheet"),
            );
          },
        ),
      ),
    ),
  );
}

Future<void> _openLauncher(WidgetTester tester) async {
  await tester.tap(find.text("Open sheet"));
  await tester.pumpAndSettle();
}
