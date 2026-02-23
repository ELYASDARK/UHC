import 'package:flutter/widgets.dart';

/// Returns a locale string safe for use with `intl` DateFormat.
/// Kurdish ('ku') is not supported by intl, so we fall back to 'ar'
/// (both RTL, same region).
String safeIntlLocale(BuildContext context) {
  final locale = Localizations.localeOf(context).languageCode;
  if (locale == 'ku') return 'ar';
  return locale;
}
