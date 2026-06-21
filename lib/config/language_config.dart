const kSupportedLanguages = [
  {'value': 'en-US', 'label': 'English (US)'},
  {'value': 'es-US', 'label': 'Spanish (US)'},
  {'value': 'fr-FR', 'label': 'French (France)'},
  {'value': 'de-DE', 'label': 'German (Germany)'},
  {'value': 'it-IT', 'label': 'Italian (Italy)'},
  {'value': 'pt-BR', 'label': 'Portuguese (Brazil)'},
  {'value': 'ar-XA', 'label': 'Arabic'},
];

const kDefaultUserLanguage = 'en-US';
const kDefaultPartnerLanguage = 'en-US';

String languageLabelForLocale(String locale) {
  final match = kSupportedLanguages.firstWhere(
    (l) => l['value'] == locale,
    orElse: () => {'value': locale, 'label': locale},
  );
  return match['label']!;
}
