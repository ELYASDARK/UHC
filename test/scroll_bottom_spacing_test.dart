import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:uhc/core/widgets/responsive_layout.dart';

void main() {
  for (final scenario in [
    (name: 'standalone gesture navigation', shell: false, keyboard: false),
    (name: 'shell already reserves navigation', shell: true, keyboard: false),
    (name: 'keyboard resized form', shell: false, keyboard: true),
  ]) {
    testWidgets(
        '${scenario.name} keeps the final action reachable without a bar-sized gap',
        (tester) async {
      tester.view.devicePixelRatio = 1;
      tester.view.physicalSize = const Size(412, 892);
      tester.view.padding = FakeViewPadding(bottom: scenario.keyboard ? 0 : 24);
      tester.view.viewInsets =
          FakeViewPadding(bottom: scenario.keyboard ? 300 : 0);
      addTearDown(tester.view.reset);
      await tester.pumpWidget(MaterialApp(
        home: Scaffold(
          bottomNavigationBar: scenario.shell
              ? const SafeArea(
                  key: ValueKey('navigation'),
                  top: false,
                  child: SizedBox(height: 70))
              : null,
          body: Builder(
              builder: (context) => ResponsivePage(
                    bottomPadding: UhcResponsive.scrollBottomPadding(context),
                    child: const Column(children: [
                      SizedBox(height: 1100),
                      SizedBox(
                          key: ValueKey('final-action'),
                          height: 48,
                          width: 200),
                    ]),
                  )),
        ),
      ));
      await tester.drag(
          find.byType(SingleChildScrollView), const Offset(0, -2000));
      await tester.pumpAndSettle();
      final boundary = scenario.shell
          ? tester.getTopLeft(find.byKey(const ValueKey('navigation'))).dy
          : scenario.keyboard
              ? 592.0
              : 892.0;
      final gap = boundary -
          tester.getBottomLeft(find.byKey(const ValueKey('final-action'))).dy;
      expect(gap, closeTo(scenario.shell || scenario.keyboard ? 16 : 40, 0.1));
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets('short content stays its natural height instead of stretching',
      (tester) async {
    await tester.pumpWidget(MaterialApp(
        home: Scaffold(
            body: Builder(
      builder: (context) => ResponsivePage(
        bottomPadding: UhcResponsive.scrollBottomPadding(context),
        child: const SizedBox(key: ValueKey('short-content'), height: 80),
      ),
    ))));
    expect(
        tester.getSize(find.byKey(const ValueKey('short-content'))).height, 80);
  });
}
