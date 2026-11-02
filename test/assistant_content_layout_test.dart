import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:uhc/core/utils/content_direction.dart';
import 'package:uhc/core/widgets/content_text.dart';
import 'package:uhc/core/widgets/management_action_footer.dart';

void main() {
  testWidgets(
      'mixed paragraphs keep punctuation and content independent of UI direction',
      (tester) async {
    const english = 'Appointment at 09:00 (Clinic A).';
    const arabic = 'موعد في العيادة (09:00).';
    const sorani = 'کات لە نەخۆشخانە (09:00).';
    for (final direction in TextDirection.values) {
      await tester.pumpWidget(MaterialApp(
          home: Directionality(
              textDirection: direction,
              child: const ContentText('$english\n$arabic\n$sorani'))));
      for (final pair in [
        (english, TextDirection.ltr),
        (arabic, TextDirection.rtl),
        (sorani, TextDirection.rtl)
      ]) {
        expect(tester.widget<Text>(find.text(pair.$1)).textDirection, pair.$2);
      }
      expect(contentDirection('09:00 (123)', direction), TextDirection.ltr);
      expect(contentDirection('...', direction), direction);
    }
  });

  testWidgets(
      'measured management footer clears last menu across insets, scales and widths',
      (tester) async {
    for (final width in [320.0, 600.0]) {
      tester.view.physicalSize = Size(width, 800);
      tester.view.devicePixelRatio = 1;
      for (final inset in [0.0, 48.0]) {
        for (final scale in [1.0, 1.6]) {
          await tester.pumpWidget(MaterialApp(
              home: MediaQuery(
                  data: MediaQueryData(
                      size: Size(width, 800),
                      padding: EdgeInsets.only(bottom: inset),
                      textScaler: TextScaler.linear(scale)),
                  child: Scaffold(
                      bottomNavigationBar: ManagementActionFooter(
                          child: FloatingActionButton.extended(
                              onPressed: () {},
                              label: const Text('Add Department'))),
                      body: ListView(padding: EdgeInsets.zero, children: [
                        const SizedBox(height: 900),
                        Card(
                            margin: const EdgeInsets.only(bottom: 12),
                            child: ListTile(
                                title: const Text('Final synthetic item'),
                                trailing: PopupMenuButton<String>(
                                    itemBuilder: (_) => [
                                          const PopupMenuItem(
                                              value: 'edit',
                                              child: Text('Edit item'))
                                        ])))
                      ])))));
          await tester.drag(find.byType(ListView), const Offset(0, -1400));
          await tester.pumpAndSettle();
          final menu = tester.getRect(find.byType(PopupMenuButton<String>));
          final action = tester.getRect(find.byType(FloatingActionButton));
          expect(menu.bottom, lessThan(action.top));
          expect(action.bottom, lessThanOrEqualTo(800 - inset));
          await tester.tap(find.byType(PopupMenuButton<String>));
          await tester.pumpAndSettle();
          expect(find.text('Edit item'), findsOneWidget);
          await tester.tap(find.text('Edit item'));
          await tester.pumpAndSettle();
          expect(tester.takeException(), isNull);
        }
      }
    }
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
  });
}
