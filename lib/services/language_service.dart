import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

class LanguageService {
  static const String _languageCodeKey = 'language_code';
  static const String _countryCodeKey = 'country_code';

  // Supported languages with their display names
  static final Map<String, Map<String, String>> supportedLanguages = {
    'en': {'name': 'English', 'countryCode': 'US'},
    'es': {'name': 'Español', 'countryCode': 'ES'},
    'fr': {'name': 'Français', 'countryCode': 'FR'},
    'de': {'name': 'Deutsch', 'countryCode': 'DE'},
    'zh': {'name': '中文', 'countryCode': 'CN'},
    'ja': {'name': '日本語', 'countryCode': 'JP'},
    'ar': {'name': 'العربية', 'countryCode': 'SA'},
  };

  // Default language
  static const String defaultLanguageCode = 'en';
  static const String defaultCountryCode = 'US';

  // Get current locale
  static Future<Locale> getCurrentLocale() async {
    final prefs = await SharedPreferences.getInstance();
    final languageCode =
        prefs.getString(_languageCodeKey) ?? defaultLanguageCode;
    final countryCode = prefs.getString(_countryCodeKey) ?? defaultCountryCode;

    return Locale(languageCode, countryCode);
  }

  // Set language
  static Future<void> setLanguage(String languageCode) async {
    final prefs = await SharedPreferences.getInstance();
    final countryCode =
        supportedLanguages[languageCode]?['countryCode'] ?? defaultCountryCode;

    await prefs.setString(_languageCodeKey, languageCode);
    await prefs.setString(_countryCodeKey, countryCode);
  }

  // Get language name by code
  static String getLanguageName(String languageCode) {
    return supportedLanguages[languageCode]?['name'] ?? 'English';
  }

  // Get current language name
  static Future<String> getCurrentLanguageName() async {
    final prefs = await SharedPreferences.getInstance();
    final languageCode =
        prefs.getString(_languageCodeKey) ?? defaultLanguageCode;

    return getLanguageName(languageCode);
  }
}
