import 'dart:convert';

import 'package:ente_auth/models/code.dart';
import 'package:logging/logging.dart';

final _logger = Logger('PlainTextImportParser');

List<Code> parsePlainTextImport(String content) {
  final trimmedContent = content.trim();
  if (trimmedContent.startsWith('otpauth://')) {
    return _parseOTPAuthCodes(trimmedContent);
  }

  final decoded = jsonDecode(trimmedContent);
  if (decoded is! Map || decoded['items'] is! List) {
    throw const FormatException('Expected an export object containing items');
  }

  return _parseEntries(
    (decoded['items'] as List).whereType<Map>(),
    Code.fromExportJson,
  );
}

List<Code> _parseOTPAuthCodes(String content) {
  final entries = content.split(RegExp(r'(?:\r\n?|\n)|,(?=\s*otpauth://)'));
  return _parseEntries(
    entries.map((entry) => entry.trim()).where((entry) => entry.isNotEmpty),
    Code.fromOTPAuthUrl,
  );
}

List<Code> _parseEntries<T>(Iterable<T> entries, Code Function(T entry) parse) {
  final codes = <Code>[];
  for (final entry in entries) {
    try {
      codes.add(parse(entry));
    } catch (error, stackTrace) {
      // Parser errors can contain OTP secrets; omit them from logs and telemetry.
      _logger.warning(
        'Skipping malformed import entry (${error.runtimeType})',
        null,
        stackTrace,
      );
    }
  }
  return codes;
}
