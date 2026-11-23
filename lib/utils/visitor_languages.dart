/// Visitor translation-target languages for the agent "visitor language" picker.
///
/// This is a translation target only (welcome + agent replies sent to the
/// visitor), deliberately broader than the App UI i18n (11 locales). Codes must
/// stay in sync with the server registry `keiyo-chat-server/app/lib/langs.js`.
///
/// [native] is the endonym shown in the list; [english] is used only as a search
/// keyword (agents may search in Latin), and [code] is what gets POSTed to
/// /api/admin/conversation/set-lang.
class VisitorLang {
  const VisitorLang(this.code, this.native, this.english);

  final String code;
  final String native;
  final String english;
}

/// Stable order; the picker sorts by display name at runtime.
const List<VisitorLang> kVisitorLangs = <VisitorLang>[
  VisitorLang('af', 'Afrikaans', 'Afrikaans'),
  VisitorLang('sq', 'Shqip', 'Albanian'),
  VisitorLang('am', 'አማርኛ', 'Amharic'),
  VisitorLang('ar', 'العربية', 'Arabic'),
  VisitorLang('hy', 'Հայերեն', 'Armenian'),
  VisitorLang('az', 'Azərbaycan dili', 'Azerbaijani'),
  VisitorLang('eu', 'Euskara', 'Basque'),
  VisitorLang('be', 'Беларуская', 'Belarusian'),
  VisitorLang('bn', 'বাংলা', 'Bengali'),
  VisitorLang('bs', 'Bosanski', 'Bosnian'),
  VisitorLang('bg', 'Български', 'Bulgarian'),
  VisitorLang('ca', 'Català', 'Catalan'),
  VisitorLang('ceb', 'Cebuano', 'Cebuano'),
  VisitorLang('ny', 'Chichewa', 'Chichewa'),
  VisitorLang('zh', '中文', 'Chinese'),
  VisitorLang('co', 'Corsu', 'Corsican'),
  VisitorLang('hr', 'Hrvatski', 'Croatian'),
  VisitorLang('cs', 'Čeština', 'Czech'),
  VisitorLang('da', 'Dansk', 'Danish'),
  VisitorLang('nl', 'Nederlands', 'Dutch'),
  VisitorLang('en', 'English', 'English'),
  VisitorLang('eo', 'Esperanto', 'Esperanto'),
  VisitorLang('et', 'Eesti', 'Estonian'),
  VisitorLang('tl', 'Filipino', 'Filipino'),
  VisitorLang('fi', 'Suomi', 'Finnish'),
  VisitorLang('fr', 'Français', 'French'),
  VisitorLang('gl', 'Galego', 'Galician'),
  VisitorLang('ka', 'ქართული', 'Georgian'),
  VisitorLang('de', 'Deutsch', 'German'),
  VisitorLang('el', 'Ελληνικά', 'Greek'),
  VisitorLang('gu', 'ગુજરાતી', 'Gujarati'),
  VisitorLang('ht', 'Kreyòl Ayisyen', 'Haitian Creole'),
  VisitorLang('ha', 'Hausa', 'Hausa'),
  VisitorLang('haw', 'ʻŌlelo Hawaiʻi', 'Hawaiian'),
  VisitorLang('he', 'עברית', 'Hebrew'),
  VisitorLang('hi', 'हिन्दी', 'Hindi'),
  VisitorLang('hmn', 'Hmoob', 'Hmong'),
  VisitorLang('hu', 'Magyar', 'Hungarian'),
  VisitorLang('is', 'Íslenska', 'Icelandic'),
  VisitorLang('ig', 'Igbo', 'Igbo'),
  VisitorLang('id', 'Bahasa Indonesia', 'Indonesian'),
  VisitorLang('ga', 'Gaeilge', 'Irish'),
  VisitorLang('it', 'Italiano', 'Italian'),
  VisitorLang('ja', '日本語', 'Japanese'),
  VisitorLang('jv', 'Basa Jawa', 'Javanese'),
  VisitorLang('kn', 'ಕನ್ನಡ', 'Kannada'),
  VisitorLang('kk', 'Қазақ тілі', 'Kazakh'),
  VisitorLang('km', 'ខ្មែរ', 'Khmer'),
  VisitorLang('rw', 'Kinyarwanda', 'Kinyarwanda'),
  VisitorLang('ko', '한국어', 'Korean'),
  VisitorLang('ku', 'Kurdî', 'Kurdish'),
  VisitorLang('ky', 'Кыргызча', 'Kyrgyz'),
  VisitorLang('lo', 'ລາວ', 'Lao'),
  VisitorLang('la', 'Latina', 'Latin'),
  VisitorLang('lv', 'Latviešu', 'Latvian'),
  VisitorLang('lt', 'Lietuvių', 'Lithuanian'),
  VisitorLang('lb', 'Lëtzebuergesch', 'Luxembourgish'),
  VisitorLang('mk', 'Македонски', 'Macedonian'),
  VisitorLang('mg', 'Malagasy', 'Malagasy'),
  VisitorLang('ms', 'Bahasa Melayu', 'Malay'),
  VisitorLang('ml', 'മലയാളം', 'Malayalam'),
  VisitorLang('mt', 'Malti', 'Maltese'),
  VisitorLang('mi', 'Māori', 'Maori'),
  VisitorLang('mr', 'मराठी', 'Marathi'),
  VisitorLang('mn', 'Монгол', 'Mongolian'),
  VisitorLang('my', 'မြန်မာ', 'Myanmar'),
  VisitorLang('ne', 'नेपाली', 'Nepali'),
  VisitorLang('no', 'Norsk', 'Norwegian'),
  VisitorLang('or', 'ଓଡ଼ିଆ', 'Odia'),
  VisitorLang('ps', 'پښتو', 'Pashto'),
  VisitorLang('fa', 'فارسی', 'Persian'),
  VisitorLang('pl', 'Polski', 'Polish'),
  VisitorLang('pt', 'Português', 'Portuguese'),
  VisitorLang('pa', 'ਪੰਜਾਬੀ', 'Punjabi'),
  VisitorLang('ro', 'Română', 'Romanian'),
  VisitorLang('ru', 'Русский', 'Russian'),
  VisitorLang('sm', 'Gagana Samoa', 'Samoan'),
  VisitorLang('gd', 'Gàidhlig', 'Scottish Gaelic'),
  VisitorLang('sr', 'Српски', 'Serbian'),
  VisitorLang('st', 'Sesotho', 'Sotho'),
  VisitorLang('sn', 'ChiShona', 'Shona'),
  VisitorLang('sd', 'سنڌي', 'Sindhi'),
  VisitorLang('si', 'සිංහල', 'Sinhala'),
  VisitorLang('sk', 'Slovenčina', 'Slovak'),
  VisitorLang('sl', 'Slovenščina', 'Slovenian'),
  VisitorLang('so', 'Soomaali', 'Somali'),
  VisitorLang('es', 'Español', 'Spanish'),
  VisitorLang('su', 'Basa Sunda', 'Sundanese'),
  VisitorLang('sw', 'Kiswahili', 'Swahili'),
  VisitorLang('sv', 'Svenska', 'Swedish'),
  VisitorLang('tg', 'Тоҷикӣ', 'Tajik'),
  VisitorLang('ta', 'தமிழ்', 'Tamil'),
  VisitorLang('tt', 'Татарча', 'Tatar'),
  VisitorLang('te', 'తెలుగు', 'Telugu'),
  VisitorLang('th', 'ไทย', 'Thai'),
  VisitorLang('tr', 'Türkçe', 'Turkish'),
  VisitorLang('tk', 'Türkmençe', 'Turkmen'),
  VisitorLang('uk', 'Українська', 'Ukrainian'),
  VisitorLang('ur', 'اردو', 'Urdu'),
  VisitorLang('ug', 'ئۇيغۇرچە', 'Uyghur'),
  VisitorLang('uz', 'Oʻzbekcha', 'Uzbek'),
  VisitorLang('vi', 'Tiếng Việt', 'Vietnamese'),
  VisitorLang('cy', 'Cymraeg', 'Welsh'),
  VisitorLang('xh', 'isiXhosa', 'Xhosa'),
  VisitorLang('yi', 'יידיש', 'Yiddish'),
  VisitorLang('yo', 'Yorùbá', 'Yoruba'),
  VisitorLang('zu', 'isiZulu', 'Zulu'),
];

/// Endonym for a stored language code; falls back to the raw code, then ''.
String visitorLangNative(String code) {
  if (code.isEmpty) return '';
  for (final l in kVisitorLangs) {
    if (l.code == code) return l.native;
  }
  return code;
}
