import 'package:flutter/material.dart';
import 'package:pro_image_editor/features/tune_editor/utils/tune_presets.dart';
import 'package:pro_image_editor/pro_image_editor.dart';

List<TuneAdjustmentItem> imageEditorTuneAdjustments(
  I18nTuneEditor i18n,
  String sharpnessLabel,
  String luminanceLabel,
) {
  final presets = tunePresets(icons: const TuneEditorIcons(), i18n: i18n);
  // Keep Ente's existing controls and their appearance across the 13.x update.
  return [
    ...presets.take(6),
    TuneAdjustmentItem(
      id: 'sharpness',
      icon: Icons.shutter_speed,
      label: sharpnessLabel,
      min: 0,
      max: 1,
      divisions: 100,
      toMatrix: _sharpnessMatrix,
    ),
    TuneAdjustmentItem(
      id: 'luminance',
      icon: Icons.light_mode_outlined,
      label: luminanceLabel,
      min: -1,
      max: 1,
      divisions: 200,
      toMatrix: _luminanceMatrix,
    ),
    presets.last.copyWith(toMatrix: _fadeMatrix),
  ];
}

List<double> _sharpnessMatrix(double value) {
  final factor = 1 + value * 2;
  final offset = -(factor - 1) * 128;
  return [
    factor,
    0,
    0,
    0,
    offset,
    0,
    factor,
    0,
    0,
    offset,
    0,
    0,
    factor,
    0,
    offset,
    0,
    0,
    0,
    1,
    0,
  ];
}

List<double> _luminanceMatrix(double value) {
  const red = 0.2126;
  const green = 0.7152;
  const blue = 0.0722;
  final original = 1 - value;
  return [
    red * value + original,
    green * value,
    blue * value,
    0,
    0,
    red * value,
    green * value + original,
    blue * value,
    0,
    0,
    red * value,
    green * value,
    blue * value + original,
    0,
    0,
    0,
    0,
    0,
    1,
    0,
  ];
}

List<double> _fadeMatrix(double value) {
  const red = 0.3086;
  const green = 0.6094;
  const blue = 0.082;
  final original = 1 - value;
  return [
    original + red * value,
    green * value,
    blue * value,
    0,
    0,
    red * value,
    original + green * value,
    blue * value,
    0,
    0,
    red * value,
    green * value,
    original + blue * value,
    0,
    0,
    0,
    0,
    0,
    1,
    0,
  ];
}
