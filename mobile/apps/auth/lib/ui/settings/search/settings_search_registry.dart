import 'dart:io';

import 'package:ente_auth/core/configuration.dart';
import 'package:ente_auth/ui/settings/about_settings_page.dart';
import 'package:ente_auth/ui/settings/account_settings_page.dart';
import 'package:ente_auth/ui/settings/data/data_settings_page.dart';
import 'package:ente_auth/ui/settings/general_settings_page.dart';
import 'package:ente_auth/ui/settings/security_settings_page.dart';
import 'package:ente_auth/ui/settings/support_settings_page.dart';
import 'package:ente_auth/ui/settings/theme_settings_page.dart';
import 'package:ente_strings/ente_strings.dart';
import 'package:ente_ui/models/settings_search_item.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:hugeicons/hugeicons.dart';

class SettingsSearchRegistry {
  static List<SettingsSearchItem> getSearchableItems(BuildContext context) {
    final l10n = context.strings;
    return [
      if (Configuration.instance.hasConfiguredAccount())
        SettingsSearchItem(
          title: l10n.account,
          sectionPath: l10n.account,
          icon: HugeIcons.strokeRoundedUser,
          routeBuilder: (_) => const AccountSettingsPage(),
        ),
      SettingsSearchItem(
        title: l10n.data,
        sectionPath: l10n.data,
        icon: HugeIcons.strokeRoundedDatabase01,
        routeBuilder: (_) => const DataSettingsPage(),
      ),
      SettingsSearchItem(
        title: l10n.security,
        sectionPath: l10n.security,
        icon: HugeIcons.strokeRoundedSecurityCheck,
        routeBuilder: (_) => const SecuritySettingsPage(),
      ),
      if (Platform.isAndroid ||
          Platform.isWindows ||
          Platform.isLinux ||
          kDebugMode)
        SettingsSearchItem(
          title: l10n.theme,
          sectionPath: l10n.theme,
          icon: HugeIcons.strokeRoundedSun03,
          routeBuilder: (_) => const ThemeSettingsPage(),
        ),
      SettingsSearchItem(
        title: l10n.general,
        sectionPath: l10n.general,
        icon: HugeIcons.strokeRoundedSettings01,
        routeBuilder: (_) => const GeneralSettingsPage(),
      ),
      SettingsSearchItem(
        title: l10n.support,
        sectionPath: l10n.support,
        icon: HugeIcons.strokeRoundedHelpCircle,
        routeBuilder: (_) => const SupportSettingsPage(),
      ),
      SettingsSearchItem(
        title: l10n.about,
        sectionPath: l10n.about,
        icon: HugeIcons.strokeRoundedInformationCircle,
        routeBuilder: (_) => const AboutSettingsPage(),
      ),
      SettingsSearchItem(
        title: l10n.whatsNew,
        sectionPath: l10n.about,
        icon: HugeIcons.strokeRoundedParty,
        routeBuilder: (_) => const AboutSettingsPage(),
        keywords: ['changelog', 'release notes', 'updates'],
      ),
    ];
  }

  static List<SettingsSearchSuggestion> getSuggestions(
    BuildContext context,
    List<SettingsSearchItem> items,
  ) {
    final l10n = context.strings;
    final titles = {l10n.data, l10n.security, l10n.whatsNew};
    return [
      for (final item in items)
        if (titles.contains(item.title))
          SettingsSearchSuggestion(
            title: item.title,
            routeBuilder: item.routeBuilder,
          ),
    ];
  }
}
