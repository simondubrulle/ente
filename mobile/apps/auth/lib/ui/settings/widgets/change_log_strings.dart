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
    'ar': ChangeLogStrings(
      entries: [
        ChangeLogEntryStrings(
          title: "الأحدث أولاً",
          description: "اعرض الرموز التي أضفتها مؤخراً أولاً.",
        ),
        ChangeLogEntryStrings(
          title: "استيراد من Open Authenticator",
          description:
              "انقل رموزك إلى Ente Auth باستخدام نسخة احتياطية من Open Authenticator.",
        ),
      ],
    ),
    'bg': ChangeLogStrings(
      entries: [
        ChangeLogEntryStrings(
          title: "Най-новите първо",
          description:
              "Показвайте първо кодовете, които сте добавили най-скоро.",
        ),
        ChangeLogEntryStrings(
          title: "Импортиране от Open Authenticator",
          description:
              "Прехвърлете кодовете си в Ente Auth от резервно копие на Open Authenticator.",
        ),
      ],
    ),
    'ca': ChangeLogStrings(
      entries: [
        ChangeLogEntryStrings(
          title: "Els més recents primer",
          description: "Mostra primer els codis que has afegit més recentment.",
        ),
        ChangeLogEntryStrings(
          title: "Importa des d’Open Authenticator",
          description:
              "Porta els teus codis a Ente Auth des d’una còpia de seguretat d’Open Authenticator.",
        ),
      ],
    ),
    'cs': ChangeLogStrings(
      entries: [
        ChangeLogEntryStrings(
          title: "Nejnovější nahoře",
          description: "Zobrazte nejdříve naposledy přidané kódy.",
        ),
        ChangeLogEntryStrings(
          title: "Import z Open Authenticator",
          description:
              "Přeneste své kódy do Ente Auth ze zálohy aplikace Open Authenticator.",
        ),
      ],
    ),
    'de': ChangeLogStrings(
      entries: [
        ChangeLogEntryStrings(
          title: "Neueste zuerst",
          description: "Zeige deine zuletzt hinzugefügten Codes zuerst an.",
        ),
        ChangeLogEntryStrings(
          title: "Import aus Open Authenticator",
          description:
              "Übertrage deine Codes aus einem Open Authenticator-Backup in Ente Auth.",
        ),
      ],
    ),
    'el': ChangeLogStrings(
      entries: [
        ChangeLogEntryStrings(
          title: "Τα νεότερα πρώτα",
          description:
              "Εμφανίστε πρώτα τους κωδικούς που προσθέσατε πιο πρόσφατα.",
        ),
        ChangeLogEntryStrings(
          title: "Εισαγωγή από το Open Authenticator",
          description:
              "Μεταφέρετε τους κωδικούς σας στο Ente Auth από ένα αντίγραφο ασφαλείας του Open Authenticator.",
        ),
      ],
    ),
    'es': ChangeLogStrings(
      entries: [
        ChangeLogEntryStrings(
          title: "Más recientes primero",
          description:
              "Muestra primero los códigos que has añadido más recientemente.",
        ),
        ChangeLogEntryStrings(
          title: "Importar desde Open Authenticator",
          description:
              "Trae tus códigos a Ente Auth desde una copia de seguridad de Open Authenticator.",
        ),
      ],
    ),
    'fa': ChangeLogStrings(
      entries: [
        ChangeLogEntryStrings(
          title: "جدیدترین‌ها در ابتدا",
          description:
              "کدهایی را که به‌تازگی اضافه کرده‌اید، در ابتدا نمایش دهید.",
        ),
        ChangeLogEntryStrings(
          title: "وارد کردن از Open Authenticator",
          description:
              "کدهای خود را از یک نسخهٔ پشتیبان Open Authenticator به Ente Auth منتقل کنید.",
        ),
      ],
    ),
    'fr': ChangeLogStrings(
      entries: [
        ChangeLogEntryStrings(
          title: "Les plus récents d’abord",
          description: "Affichez d’abord les codes ajoutés le plus récemment.",
        ),
        ChangeLogEntryStrings(
          title: "Importer depuis Open Authenticator",
          description:
              "Transférez vos codes vers Ente Auth à partir d’une sauvegarde Open Authenticator.",
        ),
      ],
    ),
    'he': ChangeLogStrings(
      entries: [
        ChangeLogEntryStrings(
          title: "החדשים ביותר תחילה",
          description: "הציגו תחילה את הקודים שהוספתם לאחרונה.",
        ),
        ChangeLogEntryStrings(
          title: "ייבוא מ־Open Authenticator",
          description:
              "העבירו את הקודים שלכם אל Ente Auth מגיבוי של Open Authenticator.",
        ),
      ],
    ),
    'hu': ChangeLogStrings(
      entries: [
        ChangeLogEntryStrings(
          title: "Legújabbak elöl",
          description: "A legutóbb hozzáadott kódok megjelenítése elsőként.",
        ),
        ChangeLogEntryStrings(
          title: "Importálás az Open Authenticator alkalmazásból",
          description:
              "Vigye át kódjait az Ente Auth alkalmazásba az Open Authenticator biztonsági mentéséből.",
        ),
      ],
    ),
    'id': ChangeLogStrings(
      entries: [
        ChangeLogEntryStrings(
          title: "Terbaru lebih dulu",
          description:
              "Tampilkan kode yang paling baru ditambahkan terlebih dahulu.",
        ),
        ChangeLogEntryStrings(
          title: "Impor dari Open Authenticator",
          description:
              "Pindahkan kode Anda ke Ente Auth dari cadangan Open Authenticator.",
        ),
      ],
    ),
    'it': ChangeLogStrings(
      entries: [
        ChangeLogEntryStrings(
          title: "Prima i più recenti",
          description: "Mostra per primi i codici aggiunti più di recente.",
        ),
        ChangeLogEntryStrings(
          title: "Importa da Open Authenticator",
          description:
              "Trasferisci i tuoi codici in Ente Auth da un backup di Open Authenticator.",
        ),
      ],
    ),
    'ja': ChangeLogStrings(
      entries: [
        ChangeLogEntryStrings(title: "新しい順", description: "最近追加したコードを先に表示します。"),
        ChangeLogEntryStrings(
          title: "Open Authenticatorからインポート",
          description: "Open AuthenticatorのバックアップからEnte Authにコードを移行できます。",
        ),
      ],
    ),
    'ko': ChangeLogStrings(
      entries: [
        ChangeLogEntryStrings(
          title: "최신순",
          description: "가장 최근에 추가한 코드를 먼저 표시하세요.",
        ),
        ChangeLogEntryStrings(
          title: "Open Authenticator에서 가져오기",
          description: "Open Authenticator 백업에서 Ente Auth로 코드를 가져오세요.",
        ),
      ],
    ),
    'lt': ChangeLogStrings(
      entries: [
        ChangeLogEntryStrings(
          title: "Naujausi pirmiausia",
          description: "Pirmiausia rodykite naujausiai pridėtus kodus.",
        ),
        ChangeLogEntryStrings(
          title: "Importavimas iš Open Authenticator",
          description:
              "Perkelkite kodus į Ente Auth iš Open Authenticator atsarginės kopijos.",
        ),
      ],
    ),
    'nl': ChangeLogStrings(
      entries: [
        ChangeLogEntryStrings(
          title: "Nieuwste eerst",
          description: "Toon je meest recent toegevoegde codes eerst.",
        ),
        ChangeLogEntryStrings(
          title: "Importeren uit Open Authenticator",
          description:
              "Zet je codes over naar Ente Auth vanuit een back-up van Open Authenticator.",
        ),
      ],
    ),
    'pl': ChangeLogStrings(
      entries: [
        ChangeLogEntryStrings(
          title: "Najnowsze najpierw",
          description: "Wyświetlaj ostatnio dodane kody jako pierwsze.",
        ),
        ChangeLogEntryStrings(
          title: "Import z Open Authenticator",
          description:
              "Przenieś swoje kody do Ente Auth z kopii zapasowej Open Authenticator.",
        ),
      ],
    ),
    'pt': ChangeLogStrings(
      entries: [
        ChangeLogEntryStrings(
          title: "Mais recentes primeiro",
          description:
              "Mostre primeiro os códigos que adicionou mais recentemente.",
        ),
        ChangeLogEntryStrings(
          title: "Importar do Open Authenticator",
          description:
              "Transfira os seus códigos para o Ente Auth a partir de uma cópia de segurança do Open Authenticator.",
        ),
      ],
    ),
    'pt_BR': ChangeLogStrings(
      entries: [
        ChangeLogEntryStrings(
          title: "Mais recentes primeiro",
          description:
              "Mostre primeiro os códigos que você adicionou mais recentemente.",
        ),
        ChangeLogEntryStrings(
          title: "Importar do Open Authenticator",
          description:
              "Transfira seus códigos para o Ente Auth a partir de um backup do Open Authenticator.",
        ),
      ],
    ),
    'ro': ChangeLogStrings(
      entries: [
        ChangeLogEntryStrings(
          title: "Cele mai noi mai întâi",
          description: "Afișează mai întâi codurile adăugate cel mai recent.",
        ),
        ChangeLogEntryStrings(
          title: "Importă din Open Authenticator",
          description:
              "Transferă codurile în Ente Auth dintr-o copie de rezervă Open Authenticator.",
        ),
      ],
    ),
    'ru': ChangeLogStrings(
      entries: [
        ChangeLogEntryStrings(
          title: "Сначала новые",
          description: "Показывайте недавно добавленные коды первыми.",
        ),
        ChangeLogEntryStrings(
          title: "Импорт из Open Authenticator",
          description:
              "Перенесите свои коды в Ente Auth из резервной копии Open Authenticator.",
        ),
      ],
    ),
    'sl': ChangeLogStrings(
      entries: [
        ChangeLogEntryStrings(
          title: "Najnovejše najprej",
          description: "Najprej prikažite nazadnje dodane kode.",
        ),
        ChangeLogEntryStrings(
          title: "Uvoz iz Open Authenticator",
          description:
              "Prenesite svoje kode v Ente Auth iz varnostne kopije Open Authenticator.",
        ),
      ],
    ),
    'sk': ChangeLogStrings(
      entries: [
        ChangeLogEntryStrings(
          title: "Najnovšie navrchu",
          description: "Zobrazte najskôr naposledy pridané kódy.",
        ),
        ChangeLogEntryStrings(
          title: "Import z Open Authenticator",
          description:
              "Preneste svoje kódy do Ente Auth zo zálohy aplikácie Open Authenticator.",
        ),
      ],
    ),
    'tr': ChangeLogStrings(
      entries: [
        ChangeLogEntryStrings(
          title: "Önce en yeniler",
          description: "En son eklediğiniz kodları önce gösterin.",
        ),
        ChangeLogEntryStrings(
          title: "Open Authenticator’dan içe aktar",
          description:
              "Kodlarınızı bir Open Authenticator yedeğinden Ente Auth’a aktarın.",
        ),
      ],
    ),
    'uk': ChangeLogStrings(
      entries: [
        ChangeLogEntryStrings(
          title: "Спочатку нові",
          description: "Показуйте нещодавно додані коди першими.",
        ),
        ChangeLogEntryStrings(
          title: "Імпорт з Open Authenticator",
          description:
              "Перенесіть свої коди до Ente Auth із резервної копії Open Authenticator.",
        ),
      ],
    ),
    'vi': ChangeLogStrings(
      entries: [
        ChangeLogEntryStrings(
          title: "Mới nhất trước",
          description: "Hiển thị các mã được thêm gần đây nhất lên đầu.",
        ),
        ChangeLogEntryStrings(
          title: "Nhập từ Open Authenticator",
          description:
              "Chuyển các mã của bạn vào Ente Auth từ bản sao lưu Open Authenticator.",
        ),
      ],
    ),
    'zh_CN': ChangeLogStrings(
      entries: [
        ChangeLogEntryStrings(title: "最新添加优先", description: "优先显示最近添加的验证码。"),
        ChangeLogEntryStrings(
          title: "从 Open Authenticator 导入",
          description: "将 Open Authenticator 备份中的验证码导入 Ente Auth。",
        ),
      ],
    ),
    'zh_TW': ChangeLogStrings(
      entries: [
        ChangeLogEntryStrings(title: "最新加入優先", description: "優先顯示最近加入的驗證碼。"),
        ChangeLogEntryStrings(
          title: "從 Open Authenticator 匯入",
          description: "將 Open Authenticator 備份中的驗證碼匯入 Ente Auth。",
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
