import 'dart:math' as math;

import 'package:ente_strings/ente_strings.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:photos/ente_theme_data.dart';
import 'package:photos/ui/tools/editor/image_editor/image_editor_layer_selection.dart';
import 'package:photos/ui/tools/editor/image_editor/image_editor_main_bottom_bar.dart';
import 'package:photos/ui/tools/editor/image_editor/image_editor_text_bar.dart';
import 'package:pro_image_editor/features/paint_editor/widgets/paint_editor_layer_editor.dart';
import 'package:pro_image_editor/features/text_editor/widgets/rounded_background_text/rounded_background_text.dart';
import 'package:pro_image_editor/pro_image_editor.dart';

void main() {
  setUpAll(() async {
    await (FontLoader('packages/ente_components/Inter')..addFont(
          rootBundle.load('packages/ente_components/fonts/Inter-Regular.ttf'),
        ))
        .load();
  });

  testWidgets('swatches and hue selection keep colors independent', (
    tester,
  ) async {
    final editor = await _openEditor(tester);
    final text = tester.state<TextEditorState>(find.byType(TextEditor));
    const cyan = Color(0xFF00FFFF);

    expect(find.byType(Slider), findsNothing);
    await _tap(tester, find.byTooltip('Custom color'));
    expect(tester.widget<Slider>(find.byType(Slider)).value, 0.5);
    expect(text.primaryColor, Colors.white);
    await _tap(tester, find.byType(Slider));
    expect(text.primaryColor, cyan);
    expect(text.secondaryColor, Colors.black);

    await _tap(tester, find.byTooltip('Background color'));
    expect(tester.widget<Slider>(find.byType(Slider)).value, 0.5);
    expect(text.secondaryColor, Colors.black);
    await _tap(tester, find.byType(Slider));
    expect(text.secondaryColor, cyan);
    await _tap(tester, find.byTooltip('Close'));
    expect(find.byType(Slider), findsNothing);
    await _tap(tester, find.byTooltip('White'));
    expect(text.primaryColor, cyan);
    expect(text.secondaryColor, Colors.white);

    await _tap(tester, find.byTooltip('Text color'));
    await _tap(tester, find.byTooltip('Custom color'));
    await tester.drag(find.byType(Slider), const Offset(60, 0));
    await tester.pumpAndSettle();
    final chosenColor = text.primaryColor;
    expect(chosenColor, isNot(cyan));
    expect(text.secondaryColor, Colors.white);
    await _tap(tester, find.text('Done'));

    final layer = editor.activeLayers.single as TextLayer;
    await _tap(tester, find.byKey(layer.keyInternalSize));
    final reopened = tester.state<TextEditorState>(find.byType(TextEditor));
    expect(reopened.primaryColor, chosenColor);
    expect(reopened.secondaryColor, Colors.white);
    await _tap(tester, find.byTooltip('Custom color'));
    expect(
      tester.widget<Slider>(find.byType(Slider)).value,
      closeTo(HSVColor.fromColor(chosenColor).hue / 360, 0.001),
    );
  });

  testWidgets('applied text renders the selected font and style', (
    tester,
  ) async {
    final editor = await _openEditor(tester);
    RoundedBackgroundText rendered() => tester.widget<RoundedBackgroundText>(
      find.byType(RoundedBackgroundText),
    );
    Future<void> reopen() =>
        _tap(tester, find.byKey(editor.activeLayers.single.keyInternalSize));

    var current = 'Inter';
    for (final font in ['Outfit', 'Gochi Hand', 'Inter']) {
      await _tap(tester, find.text(current));
      await _tap(tester, find.text(font).last);
      await _tap(tester, find.text('Done'));
      expect(
        rendered().text.style!.fontFamily,
        'packages/ente_components/$font',
      );
      await reopen();
      current = font;
    }

    await _tap(tester, find.byTooltip('Bold'));
    await _tap(tester, find.byTooltip('Italic'));
    await _tap(tester, find.text('Inter'));
    await _tap(tester, find.text('Outfit'));
    await _tap(tester, find.text('Done'));
    expect(
      rendered().text.style!.fontFamily,
      'packages/ente_components/Outfit',
    );
    expect(rendered().text.style!.fontWeight, FontWeight.w700);
    expect(rendered().text.style!.fontStyle, FontStyle.italic);

    await reopen();
    await _tap(tester, find.byTooltip('Bold'));
    await _tap(tester, find.byTooltip('Italic'));
    await _tap(tester, find.text('Done'));
    expect(rendered().text.style!.fontWeight, FontWeight.w500);
    expect(rendered().text.style!.fontStyle, isNull);
  });

  for (final (style, taps, opacity) in [
    ('No background', 2, 0.0),
    ('Translucent background', 1, 0.5),
  ]) {
    testWidgets('$style preserves the chosen background when reopened', (
      tester,
    ) async {
      final editor = await _openEditor(tester);
      await _tap(tester, find.byTooltip('Background color'));
      await _tap(tester, find.byTooltip('Custom color'));
      await _tap(tester, find.byType(Slider));
      await _tap(tester, find.byTooltip('Solid background'));
      if (taps == 2) {
        await _tap(tester, find.byTooltip('Translucent background'));
      }
      expect(find.byTooltip(style), findsOneWidget);
      await _tap(tester, find.text('Done'));
      final layer = editor.activeLayers.single as TextLayer;
      expect(layer.background.a, closeTo(opacity, 1 / 255));
      expect(layer.background.withValues(alpha: 1), const Color(0xFF00FFFF));

      await _tap(tester, find.byKey(layer.keyInternalSize));
      final reopened = tester.state<TextEditorState>(find.byType(TextEditor));
      expect(reopened.secondaryColor, layer.background);
      if (opacity == 0) {
        await _tap(tester, find.byTooltip('Background color'));
      } else {
        await _tap(tester, find.byTooltip(style));
        await _tap(tester, find.byTooltip('No background'));
      }
      expect(reopened.secondaryColor, const Color(0xFF00FFFF));
      expect(reopened.primaryColor, Colors.white);
    });
  }

  testWidgets('large text keeps the preview and controls usable', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(320, 640);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final editor = await _openEditor(tester, textScale: 1.5);
    expect(
      MediaQuery.textScalerOf(tester.element(find.byType(TextField))).scale(14),
      14,
    );
    expect(
      MediaQuery.textScalerOf(tester.element(find.text('Inter'))).scale(14),
      21,
    );
    await _tap(tester, find.text('Inter'));
    await _tap(tester, find.text('Gochi Hand'));
    await _tap(tester, find.byTooltip('Custom color'));
    expect(
      tester
          .state<TextEditorState>(find.byType(TextEditor))
          .editorBodySize
          .height,
      greaterThanOrEqualTo(tester.getSize(find.byType(TextField)).height),
    );
    expect(tester.takeException(), isNull);
    await tester.tapAt(const Offset(10, 100));
    await tester.pumpAndSettle();
    expect(find.byType(TextEditor), findsNothing);
    expect(editor.activeLayers, hasLength(1));
    await tester.ensureVisible(find.text('Filter'));
    await _tap(tester, find.text('Filter'));
    expect(
      MediaQuery.textScalerOf(
        tester.element(find.byType(FilterEditor)),
      ).scale(14),
      21,
    );
  });

  testWidgets('color controls have 48 point tap targets', (tester) async {
    await _openEditor(tester);
    expect(tester.getSize(find.byTooltip('Text color')), const Size(48, 48));
    expect(tester.getSize(find.byTooltip('White')), const Size(48, 48));
  });

  testWidgets('portrait text control rows stay separated on a narrow screen', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(320, 640);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await _openEditor(tester);
    await _tap(tester, find.text('Inter'));
    await _tap(tester, find.text('Gochi Hand'));
    await _tap(tester, find.byTooltip('Italic'));

    final styleRowBottom = tester.getRect(find.byTooltip('Italic')).bottom;
    final colorRowTop = tester.getRect(find.byTooltip('Text color')).top;
    expect(colorRowTop - styleRowBottom, greaterThanOrEqualTo(16));
    expect(tester.takeException(), isNull);
  });

  testWidgets('applied text is selected and can be duplicated or deleted', (
    tester,
  ) async {
    final editor = await _openEditor(tester, selectable: true);
    await _tap(tester, find.text('Done'));
    expect(editor.activeLayers, hasLength(1));
    await _tap(tester, find.byTooltip('Duplicate'));
    expect(editor.activeLayers, hasLength(2));
    await _tap(tester, find.byTooltip('Delete'));
    expect(editor.activeLayers, hasLength(1));
  });

  testWidgets('double tapping applied text reopens it for typing', (
    tester,
  ) async {
    var now = DateTime(2026);
    final editor = await _openEditor(tester, selectable: true, now: () => now);
    await _tap(tester, find.text('Done'));
    final layer = find.byKey(editor.activeLayers.single.keyInternalSize);

    await _tap(tester, layer);
    expect(find.byType(TextEditor), findsNothing);
    now = now.add(kDoubleTapTimeout + const Duration(milliseconds: 1));
    await tester.tap(layer);
    await tester.pump(const Duration(milliseconds: 50));
    expect(find.byType(TextEditor), findsNothing);
    now = now.add(const Duration(milliseconds: 50));
    await _tap(tester, layer);
    final reopened = tester.state<TextEditorState>(find.byType(TextEditor));
    expect(reopened.textCtrl.text, 'Hello');
    expect(reopened.focusNode.hasFocus, isTrue);
    expect(tester.testTextInput.isVisible, isTrue);

    await tester.enterText(find.byType(TextField), 'Hello again');
    await _tap(tester, find.text('Done'));
    expect((editor.activeLayers.single as TextLayer).text, 'Hello again');
  });

  testWidgets('text cannot reopen while the creation editor is closing', (
    tester,
  ) async {
    final editor = await _openEditor(tester, selectable: true);
    await tester.tap(find.text('Done'));
    await tester.pump();
    expect(editor.isSubEditorOpen, isTrue);
    expect(editor.activeLayers, hasLength(1));
    final layer = find.byKey(editor.activeLayers.single.keyInternalSize);
    await tester.tap(layer);
    await tester.tap(layer);
    await tester.pumpAndSettle();
    expect(find.byType(TextEditor), findsNothing);
    expect(editor.activeLayers, hasLength(1));

    editor.undoAction();
    await tester.pumpAndSettle();
    expect(editor.activeLayers, isEmpty);
  });

  testWidgets('editing text keeps undo and redo history in sync', (
    tester,
  ) async {
    final editor = await _openEditor(tester, selectable: true);
    await _tap(tester, find.text('Done'));

    await _tap(tester, find.byTooltip('Edit'));
    await tester.enterText(find.byType(TextField), 'Changed');
    await _tap(tester, find.text('Done'));
    expect((editor.activeLayers.single as TextLayer).text, 'Changed');

    editor.undoAction();
    await tester.pumpAndSettle();
    expect((editor.activeLayers.single as TextLayer).text, 'Hello');

    editor.redoAction();
    await tester.pumpAndSettle();
    expect((editor.activeLayers.single as TextLayer).text, 'Changed');
  });

  testWidgets('pinching and dragging text do not open the text editor', (
    tester,
  ) async {
    final editor = await _openEditor(tester, selectable: true);
    await _tap(tester, find.text('Done'));
    final layer = find.byKey(editor.activeLayers.single.keyInternalSize);
    final center = tester.getCenter(layer);
    final first = await tester.startGesture(center - const Offset(12, 0));
    final second = await tester.startGesture(center + const Offset(12, 0));
    await first.moveBy(const Offset(-20, 0));
    await second.moveBy(const Offset(20, 0));
    await first.up();
    await second.up();
    await tester.pumpAndSettle();
    expect(find.byType(TextEditor), findsNothing);

    await tester.tapAt(center);
    await tester.dragFrom(center, const Offset(45, 0));
    await tester.dragFrom(center + const Offset(45, 0), const Offset(-45, 0));
    await tester.pumpAndSettle();
    expect(find.byType(TextEditor), findsNothing);
  });

  testWidgets('the text field stays put while the keyboard opens and closes', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(402, 874);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await _openEditor(tester);
    await tester.pumpAndSettle();
    final field = find.byType(TextField);
    final resting = tester.getTopLeft(field);

    for (final keyboard in [120.0, 336.0, 0.0]) {
      tester.view.viewInsets = FakeViewPadding(bottom: keyboard);
      await tester.pump();
      expect(tester.getTopLeft(field), resting);
    }
  });

  testWidgets('typed text remains visible above the bar in landscape', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(874, 402);
    tester.view.devicePixelRatio = 1;
    tester.view.viewInsets = const FakeViewPadding(bottom: 250);
    addTearDown(tester.view.reset);
    await _openEditor(tester);
    await tester.pumpAndSettle();

    final fieldBottom = tester.getBottomLeft(find.byType(TextField)).dy;
    final barTop = tester.getTopLeft(find.byType(ImageEditorTextBar)).dy;
    expect(fieldBottom, lessThanOrEqualTo(barTop));
    expect(tester.takeException(), isNull);
  });

  testWidgets('editing text keeps it where it was dragged', (tester) async {
    final editor = await _openEditor(tester, selectable: true);
    await _tap(tester, find.text('Done'));
    final before = editor.activeLayers.single.offset;

    await tester.drag(
      find.byKey(editor.activeLayers.single.keyInternalSize),
      const Offset(60, -80),
    );
    await tester.pumpAndSettle();
    final moved = editor.activeLayers.single.offset;
    expect(moved, isNot(before));

    await _tap(tester, find.byTooltip('Edit'));
    await tester.enterText(find.byType(TextField), 'Hello again');
    await _tap(tester, find.text('Done'));
    expect(editor.activeLayers.single.offset, moved);
  });

  testWidgets('reopening enlarged text does not change its line breaks', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(402, 874);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final editor = await _openEditor(tester, selectable: true);
    await tester.enterText(find.byType(TextField), 'Hello from Ente editor');
    await _tap(tester, find.text('Done'));
    final layer = editor.activeLayers.single as TextLayer;
    layer.scale = 2;
    editor.setState(() {});
    await tester.pumpAndSettle();
    final before = tester.getSize(find.byType(RoundedBackgroundText));

    await _tap(tester, find.byTooltip('Edit'));
    await _tap(tester, find.text('Done'));
    final after = tester.getSize(find.byType(RoundedBackgroundText));
    expect(after.height, closeTo(before.height, 1));
    expect((editor.activeLayers.single as TextLayer).text, layer.text);
  });

  testWidgets('selection actions stay below the app bar for tall layers', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(320, 640);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final editor = await _openEditor(tester, selectable: true);
    await _tap(tester, find.text('Done'));
    final layer = editor.activeLayers.single;
    layer
      ..scale = 12
      ..rotation = math.pi / 2;
    editor.selectLayerById(layer.id);
    await tester.pumpAndSettle();

    final actions = tester.getRect(find.byTooltip('Delete'));
    expect(actions.top, greaterThanOrEqualTo(kToolbarHeight));
    expect(actions.bottom, lessThanOrEqualTo(640 - 80));
  });

  testWidgets('a selected stroke can open its edit sheet', (tester) async {
    final editor = await _openEditor(tester, selectable: true);
    await _tap(tester, find.text('Done'));
    editor.unselectAllLayers();
    final stroke = PaintLayer(
      item: PaintedModel(
        mode: PaintMode.arrow,
        offsets: const [Offset(0, 0), Offset(100, 80)],
        erasedOffsets: const [],
        color: Colors.white,
        strokeWidth: 4,
        opacity: 1,
        fill: false,
      ),
      rawSize: const Size(100, 80),
      opacity: 1,
    );
    editor.addLayer(stroke);
    await tester.pumpAndSettle();
    editor.unselectAllLayers();
    await tester.pump();
    editor.selectLayerById(stroke.id);
    await tester.pumpAndSettle();
    await _tap(tester, find.byTooltip('Edit'));
    expect(find.byType(PaintEditorLayerEditor), findsOneWidget);
  });

  testWidgets('a new drawing is not selected after leaving Draw', (
    tester,
  ) async {
    final editor = await _openEditor(tester, selectable: true);
    await _tap(tester, find.text('Cancel'));
    editor.openPaintEditor();
    await tester.pumpAndSettle();
    await tester.dragFrom(const Offset(200, 300), const Offset(100, 60));
    await tester.pumpAndSettle();
    editor.paintEditor.currentState!.done();
    await tester.pumpAndSettle();
    expect(editor.activeLayers.whereType<PaintLayer>(), isNotEmpty);
    expect(editor.layerInteractionManager.selectedLayerIds, isEmpty);
    expect(find.byTooltip('Delete'), findsNothing);
  });

  testWidgets('rotated text keeps its rotation when reopened and saved', (
    tester,
  ) async {
    final editor = await _openEditor(tester, selectable: true);
    await _tap(tester, find.text('Done'));
    final layer = editor.activeLayers.single;
    layer.rotation = math.pi / 4;
    editor.selectLayerById(layer.id);
    await tester.pumpAndSettle();

    await _tap(tester, find.byTooltip('Edit'));
    expect(tester.widget<TextEditor>(find.byType(TextEditor)).heroTag, isNull);
    await _tap(tester, find.text('Done'));
    expect(editor.activeLayers.single.rotation, math.pi / 4);
    expect(find.byTooltip('Edit'), findsOneWidget);
  });
}

Future<ProImageEditorState> _openEditor(
  WidgetTester tester, {
  double textScale = 1,
  bool selectable = false,
  DateTime Function()? now,
}) async {
  final key = GlobalKey<ProImageEditorState>();
  SubEditor? activeSubEditor;
  final doubleTap = ImageEditorLayerDoubleTap(() => key.currentState, now: now);
  await tester.pumpWidget(
    MaterialApp(
      theme: darkThemeData,
      localizationsDelegates: StringsLocalizations.localizationsDelegates,
      supportedLocales: StringsLocalizations.supportedLocales,
      builder: (context, child) => MediaQuery(
        data: MediaQuery.of(
          context,
        ).copyWith(textScaler: TextScaler.linear(textScale)),
        child: child!,
      ),
      home: Builder(
        builder: (context) => Listener(
          onPointerDown: doubleTap.onPointerDown,
          onPointerMove: doubleTap.onPointerMove,
          onPointerUp: doubleTap.onPointerUp,
          onPointerCancel: doubleTap.onPointerCancel,
          child: ProImageEditor.memory(
            Uint8List.fromList(
              img.encodePng(img.Image(width: 400, height: 300)),
            ),
            key: key,
            callbacks: ProImageEditorCallbacks(
              mainEditorCallbacks: MainEditorCallbacks(
                onOpenSubEditor: (editor) => activeSubEditor = editor,
                onLayerTapDown: selectable ? doubleTap.onLayerDown : null,
                onLayerTapUp: selectable ? doubleTap.onLayerUp : null,
                onCreateTextLayer: () =>
                    imageEditorCreateTextLayer(() => key.currentState),
                onEndCloseSubEditor: (editor) {
                  if (editor == SubEditor.paint) {
                    WidgetsBinding.instance.addPostFrameCallback((_) {
                      key.currentState?.unselectAllLayers();
                    });
                  }
                },
              ),
            ),
            configs: ProImageEditorConfigs(
              theme: Theme.of(context),
              imageGeneration: const ImageGenerationConfigs(
                enableIsolateGeneration: false,
                enableBackgroundGeneration: false,
              ),
              layerInteraction: selectable
                  ? imageEditorLayerInteractionConfigs(
                      context,
                      () => key.currentState,
                    )
                  : const LayerInteractionConfigs(
                      selectable: LayerInteractionSelectable.disabled,
                    ),
              textEditor: imageEditorTextConfigs(context),
              mainEditor: MainEditorConfigs(
                style: MainEditorStyle(
                  subEditorPage: imageEditorSubEditorPageStyle(
                    () => activeSubEditor,
                  ),
                ),
                widgets: MainEditorWidgets(
                  bottomBar: (editor, stream, barKey) => ReactiveWidget(
                    key: barKey,
                    stream: stream,
                    builder: (_) => ImageEditorMainBottomBar(
                      editor: editor,
                      configs: editor.configs,
                      callbacks: editor.callbacks,
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    ),
  );
  await tester.runAsync(() => key.currentState!.decodeImage());
  await tester.pumpAndSettle();
  await tester.ensureVisible(find.text('Text').last);
  await _tap(tester, find.text('Text').last);
  await tester.enterText(find.byType(TextField), 'Hello');
  return key.currentState!;
}

Future<void> _tap(WidgetTester tester, Finder finder) async {
  await tester.tap(finder);
  await tester.pumpAndSettle();
}
