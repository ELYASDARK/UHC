import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:uhc/l10n/app_localizations.dart';
import 'package:uhc/screens/admin/doctors/doctor_schedule_dialog.dart';

Widget scheduleApp(Future<SavedDoctorSchedule> Function() load) => MaterialApp(
      locale: const Locale('en'),
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      home: Builder(
        builder: (context) => Scaffold(
          body: TextButton(
            onPressed: () => showDialog<void>(
              context: context,
              builder: (_) => DoctorScheduleLoader(
                  doctorId: 'synthetic-doctor', load: load),
            ),
            child: const Text('Open schedule'),
          ),
        ),
      ),
    );

void main() {
  testWidgets(
      'cancel pending schedule load ignores a late failure and does not reopen',
      (tester) async {
    final pending = Completer<SavedDoctorSchedule>();
    await tester.pumpWidget(scheduleApp(() => pending.future));
    await tester.tap(find.text('Open schedule'));
    await tester.pump(const Duration(milliseconds: 250));
    expect(find.byType(CircularProgressIndicator), findsOneWidget);
    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();
    pending.completeError(StateError('Synthetic network failure'));
    await tester.pump();
    expect(find.text('Manage Schedule'), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
      'failed schedule read retains dialog geometry and remains cancellable',
      (tester) async {
    final pending = Completer<SavedDoctorSchedule>();
    var reads = 0;
    await tester.pumpWidget(scheduleApp(() {
      reads++;
      return pending.future;
    }));
    await tester.tap(find.text('Open schedule'));
    await tester.pump(const Duration(milliseconds: 250));
    final card = find.byWidgetPredicate(
        (widget) => widget is Material && widget.type == MaterialType.card);
    final loadingBounds = tester.getRect(card);
    pending.completeError(StateError('Synthetic network failure'));
    await tester.pumpAndSettle();
    expect(tester.getRect(card), loadingBounds);
    expect(find.byType(CircularProgressIndicator), findsNothing);
    expect(reads, 1);
    expect(tester.takeException(), isNull);
    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();
    expect(find.text('Manage Schedule'), findsNothing);
  });
}
