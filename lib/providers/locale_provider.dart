import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Supported locales in the app
class AppLocale {
  static const Locale english = Locale('en');
  static const Locale arabic = Locale('ar');
  static const Locale kurdish = Locale('ku');

  static const List<Locale> supportedLocales = [english, arabic, kurdish];

  static const Map<String, String> languageNames = {
    'en': 'English',
    'ar': 'العربية',
    'ku': 'کوردی',
  };

  /// Check if locale is RTL
  static bool isRtl(Locale locale) {
    return locale.languageCode == 'ar' || locale.languageCode == 'ku';
  }
}

/// Provider for managing app locale/language
class LocaleProvider extends ChangeNotifier {
  static const String _localeKey = 'app_locale';

  Locale _locale = AppLocale.english;

  Locale get locale => _locale;

  bool get isRtl => AppLocale.isRtl(_locale);

  String get languageName =>
      AppLocale.languageNames[_locale.languageCode] ?? 'English';

  LocaleProvider() {
    _loadLocale();
  }

  Future<void> _loadLocale() async {
    final prefs = await SharedPreferences.getInstance();
    final languageCode = prefs.getString(_localeKey);
    if (languageCode != null) {
      _locale = Locale(languageCode);
      notifyListeners();
    }
  }

  Future<void> setLocale(Locale locale) async {
    if (!AppLocale.supportedLocales.contains(locale)) return;

    _locale = locale;
    notifyListeners();

    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_localeKey, locale.languageCode);
  }

  Future<void> setLocaleByCode(String languageCode) async {
    final locale = Locale(languageCode);
    await setLocale(locale);
  }
}
