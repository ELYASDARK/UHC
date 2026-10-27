import 'dart:async';

import 'package:cloud_functions/cloud_functions.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:uhc/core/constants/app_colors.dart';
import 'package:uhc/core/theme/app_theme.dart';
import 'package:uhc/core/utils/app_messages.dart';
import 'package:uhc/l10n/app_localizations.dart';
import 'package:uhc/l10n/kurdish_material_localizations.dart';
import 'package:uhc/services/doctor_functions_service.dart';

void main() {
  setUpAll(() => GoogleFonts.config.allowRuntimeFetching = false);
  for (final code in ['en', 'ar', 'ku']) {
    for (final dark in [false, true]) {
      testWidgets('$code ${dark ? 'dark' : 'light'} messages dismiss and retry',
          (tester) async {
        late BuildContext context;
        var retried = false;
        await tester.pumpWidget(MaterialApp(
          locale: Locale(code),
          theme: dark ? AppTheme.darkTheme : AppTheme.lightTheme,
          localizationsDelegates: [
            ...AppLocalizations.localizationsDelegates,
            const FallbackLocalizationsDelegate(),
            const FallbackCupertinoLocalizationsDelegate(),
            const FallbackWidgetsLocalizationsDelegate(),
          ],
          supportedLocales: AppLocalizations.supportedLocales,
          home: Builder(builder: (value) {
            context = value;
            return const Scaffold(body: SizedBox.expand());
          }),
        ));
        await tester.pumpAndSettle();
        final l10n = AppLocalizations.of(context);
        for (final error in [
          FirebaseFunctionsException(
              code: 'internal',
              message: 'Private\n#0 package:secret/file.dart:9'),
          StateError(r'C:\private\patient-data.json'),
          'Exception: [firebase_functions/internal] private stack',
        ]) {
          expect(AppMessages.error(context, error), l10n.requestFailed);
        }
        expect(AppMessages.error(context, TimeoutException('private')),
            l10n.requestNetworkError);
        expect(
            AppMessages.error(
                context,
                DoctorFunctionException(
                    code: 'permission-denied', message: 'secret')),
            l10n.noPermissionForAction);
        expect(
            AppMessages.error(context,
                '[firebase_functions/already-exists] private\n#0 source.dart'),
            l10n.requestConflict);

        for (final color in [
          AppColors.success,
          AppColors.warning,
          AppColors.error
        ]) {
          AppMessages.show(
              context,
              SnackBar(
                content: Text(l10n.requestFailed),
                backgroundColor: color,
                action: SnackBarAction(
                    label: l10n.retry, onPressed: () => retried = true),
              ));
          await tester.pumpAndSettle();
          final snack = tester.widget<SnackBar>(find.byType(SnackBar));
          expect(snack.showCloseIcon, isTrue);
          expect(
              find.byTooltip(code == 'ku'
                  ? 'داخستن'
                  : code == 'ar'
                      ? 'إغلاق'
                      : 'Close'),
              findsOneWidget);
          final a = snack.backgroundColor!.computeLuminance();
          final b = snack.closeIconColor!.computeLuminance();
          expect((a > b ? (a + .05) / (b + .05) : (b + .05) / (a + .05)),
              greaterThanOrEqualTo(4.5));
          await tester.tap(find.byIcon(Icons.close));
          await tester.pumpAndSettle();
          expect(find.byType(SnackBar), findsNothing);
        }
        AppMessages.show(context, SnackBar(content: Text(l10n.requestFailed)));
        AppMessages.show(
            context,
            SnackBar(
              content:
                  Text(List.filled(40, l10n.requestNetworkError).join(' ')),
              action: SnackBarAction(
                  label: l10n.retry, onPressed: () => retried = true),
            ));
        await tester.pumpAndSettle();
        expect(find.byType(SnackBar), findsOneWidget);
        expect(tester.takeException(), isNull);
        await tester.tap(find.text(l10n.retry));
        await tester.pumpAndSettle();
        expect(retried, isTrue);
        expect(find.byType(SnackBar), findsNothing);
      });
    }
  }
}
