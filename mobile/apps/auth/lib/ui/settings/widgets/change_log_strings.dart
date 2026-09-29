import 'dart:ui';

class ChangeLogStrings {
  final List<ChangeLogEntryStrings> entries;

  const ChangeLogStrings({required this.entries});

  static ChangeLogStrings forLocale(Locale locale) {
    final key = locale.countryCode != null && locale.countryCode!.isNotEmpty
        ? '${locale.languageCode}_${locale.countryCode}'
        : locale.languageCode;

    return _translations[key] ??
        _translations[locale.languageCode] ??
        _translations['en']!;
  }

  static const Map<String, ChangeLogStrings> _translations = {
    'en': ChangeLogStrings(
      entries: [
        ChangeLogEntryStrings(
          title: 'Newest first',
          description: 'Show your most recently added codes first.',
        ),
        ChangeLogEntryStrings(
          title: 'Import from Open Authenticator',
          description:
              'Bring your codes into Ente Auth from an Open Authenticator backup.',
        ),
      ],
    ),
  };
}

class ChangeLogEntryStrings {
  final String title;
  final String description;

  const ChangeLogEntryStrings({required this.title, required this.description});
}
