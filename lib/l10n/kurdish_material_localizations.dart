import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter_localizations/flutter_localizations.dart';

/// Custom MaterialLocalizations for Kurdish language.
class KurdishMaterialLocalizations extends DefaultMaterialLocalizations {
  const KurdishMaterialLocalizations();

  @override
  String get okButtonLabel => 'باشە';

  @override
  String get cancelButtonLabel => 'پاشگەزبوونەوە';

  @override
  String get closeButtonLabel => 'داخستن';

  @override
  String get continueButtonLabel => 'بەردەوامبوون';

  @override
  String get copyButtonLabel => 'کۆپی';

  @override
  String get cutButtonLabel => 'بڕین';

  @override
  String get pasteButtonLabel => 'لکاندن';

  @override
  String get selectAllButtonLabel => 'هەڵبژاردنی هەموو';

  @override
  String get searchFieldLabel => 'گەڕان';

  @override
  String get deleteButtonTooltip => 'سڕینەوە';

  @override
  String get nextPageTooltip => 'لاپەڕەی داهاتوو';

  @override
  String get previousPageTooltip => 'لاپەڕەی پێشوو';

  @override
  String get firstPageTooltip => 'لاپەڕەی یەکەم';

  @override
  String get lastPageTooltip => 'لاپەڕەی کۆتایی';

  @override
  String get showMenuTooltip => 'پیشاندانی مینیو';

  @override
  String get drawerLabel => 'مینیوی ناوبری';

  @override
  String get popupMenuLabel => 'مینیوی popup';

  @override
  String get dialogLabel => 'دیالۆگ';

  @override
  String get alertDialogLabel => 'ئاگاداری';

  @override
  String get moreButtonTooltip => 'زیاتر';

  @override
  String get backButtonTooltip => 'گەڕانەوە';

  @override
  String get openAppDrawerTooltip => 'کردنەوەی مینیوی ناوبری';

  @override
  String get signedInLabel => 'چوونە ژوورەوە';

  @override
  String get hideAccountsLabel => 'شاردنەوەی هەژمارەکان';

  @override
  String get showAccountsLabel => 'پیشاندانی هەژمارەکان';

  @override
  String get modalBarrierDismissLabel => 'پشتگوێخستن';

  @override
  String get saveButtonLabel => 'هەڵگرتن';
}

/// Custom CupertinoLocalizations for Kurdish language.
class KurdishCupertinoLocalizations extends DefaultCupertinoLocalizations {
  const KurdishCupertinoLocalizations();
}

/// Custom WidgetsLocalizations for Kurdish with RTL support.
class KurdishWidgetsLocalizations extends DefaultWidgetsLocalizations {
  const KurdishWidgetsLocalizations();

  @override
  TextDirection get textDirection => TextDirection.rtl;
}

/// Fallback MaterialLocalizations delegate that handles Kurdish.
class FallbackLocalizationsDelegate
    extends LocalizationsDelegate<MaterialLocalizations> {
  const FallbackLocalizationsDelegate();

  @override
  bool isSupported(Locale locale) => true;

  @override
  Future<MaterialLocalizations> load(Locale locale) {
    if (locale.languageCode == 'ku') {
      return SynchronousFuture<MaterialLocalizations>(
        const KurdishMaterialLocalizations(),
      );
    }
    return GlobalMaterialLocalizations.delegate.load(locale);
  }

  @override
  bool shouldReload(FallbackLocalizationsDelegate old) => false;
}

/// Fallback CupertinoLocalizations delegate that handles Kurdish.
class FallbackCupertinoLocalizationsDelegate
    extends LocalizationsDelegate<CupertinoLocalizations> {
  const FallbackCupertinoLocalizationsDelegate();

  @override
  bool isSupported(Locale locale) => true;

  @override
  Future<CupertinoLocalizations> load(Locale locale) {
    if (locale.languageCode == 'ku') {
      return SynchronousFuture<CupertinoLocalizations>(
        const KurdishCupertinoLocalizations(),
      );
    }
    return GlobalCupertinoLocalizations.delegate.load(locale);
  }

  @override
  bool shouldReload(FallbackCupertinoLocalizationsDelegate old) => false;
}

/// Fallback WidgetsLocalizations delegate that handles Kurdish RTL.
class FallbackWidgetsLocalizationsDelegate
    extends LocalizationsDelegate<WidgetsLocalizations> {
  const FallbackWidgetsLocalizationsDelegate();

  @override
  bool isSupported(Locale locale) => true;

  @override
  Future<WidgetsLocalizations> load(Locale locale) {
    if (locale.languageCode == 'ku') {
      return SynchronousFuture<WidgetsLocalizations>(
        const KurdishWidgetsLocalizations(),
      );
    }
    return GlobalWidgetsLocalizations.delegate.load(locale);
  }

  @override
  bool shouldReload(FallbackWidgetsLocalizationsDelegate old) => false;
}
