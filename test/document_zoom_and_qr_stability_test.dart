import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:uhc/core/utils/qr_scan_stability.dart';
import 'package:uhc/l10n/app_localizations.dart';
import 'package:uhc/screens/shared/medical_document_viewer_screen.dart';

const viewportKey = ValueKey('medical-image-viewport');
const contentKey = ValueKey('medical-image-content');

Rect imageBounds(WidgetTester tester) {
  final box = tester.renderObject<RenderBox>(find.byKey(contentKey));
  return MatrixUtils.transformRect(
      box.getTransformTo(null), Offset.zero & box.size);
}

void expectBoundedImage(WidgetTester tester) {
  final image = imageBounds(tester);
  final viewport = tester.getRect(find.byKey(viewportKey));
  void axis(double start, double end, double viewStart, double viewEnd) {
    if (end - start <= viewEnd - viewStart + 0.01) {
      expect((start + end) / 2, closeTo((viewStart + viewEnd) / 2, 0.01));
    } else {
      expect(start, lessThanOrEqualTo(viewStart + 0.01));
      expect(end, greaterThanOrEqualTo(viewEnd - 0.01));
    }
  }

  axis(image.left, image.right, viewport.left, viewport.right);
  axis(image.top, image.bottom, viewport.top, viewport.bottom);
  expect(image.overlaps(viewport), isTrue);
}

Future<void> showDocument(
  WidgetTester tester, {
  Size source = const Size(800, 400),
  Size screen = const Size(390, 844),
}) async {
  await tester.binding.setSurfaceSize(screen);
  addTearDown(() => tester.binding.setSurfaceSize(null));
  await tester.pumpWidget(MaterialApp(
    localizationsDelegates: AppLocalizations.localizationsDelegates,
    supportedLocales: AppLocalizations.supportedLocales,
    home: MedicalDocumentViewerScreen(
      imageUrl: '',
      title: 'Synthetic document',
      captureImageSize: source,
      captureContent: const ColoredBox(color: Colors.white),
    ),
  ));
  await tester.pumpAndSettle();
}

Future<void> doubleTap(WidgetTester tester, Offset point) async {
  await tester.tapAt(point);
  await tester.pump(const Duration(milliseconds: 80));
  await tester.tapAt(point);
  await tester.pumpAndSettle();
}

Future<void> pinch(WidgetTester tester, {required double factor}) async {
  final focal = tester.getCenter(find.byKey(viewportKey));
  final first =
      await tester.startGesture(focal - const Offset(50, 0), pointer: 1);
  final second =
      await tester.startGesture(focal + const Offset(50, 0), pointer: 2);
  // Move through multiple real pointer events, including the recognizer's slop.
  for (var step = 1; step <= 12; step++) {
    final distance = 50 * (1 + (factor - 1) * step / 12);
    await first.moveTo(focal - Offset(distance, 0));
    await second.moveTo(focal + Offset(distance, 0));
    await tester.pump(const Duration(milliseconds: 16));
    expectBoundedImage(tester);
  }
  await first.up();
  await second.up();
  await tester.pumpAndSettle();
}

void main() {
  test('QR needs repeated reads and resets on ambiguity or interruption', () {
    final gate = QrScanStability();
    final start = DateTime(2026, 10, 23);
    bool read(String? value, int ms) =>
        gate.accept(value, start.add(Duration(milliseconds: ms)));
    expect(read('correct', 0), isFalse);
    expect(read('correct', 300), isFalse);
    expect(read('other', 650), isFalse);
    expect(read('correct', 900), isFalse);
    expect(read(null, 1200), isFalse);
    expect(read('correct', 1500), isFalse);
    expect(read('correct', 1800), isFalse);
    expect(read('correct', 2200), isTrue);
    expect(read('correct', 3200), isFalse);
  });

  testWidgets('a zoomed landscape image cannot be panned out vertically',
      (tester) async {
    await showDocument(tester);
    final viewport = tester.getRect(find.byKey(viewportKey));
    await doubleTap(tester, viewport.center);
    await tester.drag(find.byKey(viewportKey), const Offset(0, -600));
    await tester.pumpAndSettle();
    final bounds = imageBounds(tester);
    expect(bounds.center.dy, closeTo(viewport.center.dy, 1));
    expect(bounds.intersect(viewport).height, closeTo(bounds.height, 1));
    expectBoundedImage(tester);
  });

  testWidgets('double tap keeps the tapped image point stationary and resets',
      (tester) async {
    await showDocument(tester, source: const Size(390, 788));
    final before = imageBounds(tester);
    final tap =
        before.topLeft + Offset(before.width * 0.6, before.height * 0.4);
    await doubleTap(tester, tap);
    final after = imageBounds(tester);
    expect(after.width / before.width, closeTo(2.5, 0.01));
    expect(
        (after.topLeft + Offset(after.width * 0.6, after.height * 0.4) - tap)
            .distance,
        lessThan(0.01));
    expectBoundedImage(tester);
    await doubleTap(tester, tap);
    expect(imageBounds(tester), before);
    await doubleTap(tester, tap);
    await tester.tap(find.byTooltip('Reset zoom'));
    await tester.pumpAndSettle();
    expect(imageBounds(tester), before);
  });

  testWidgets(
      'pinch preserves focal point and stays bounded through long sequences',
      (tester) async {
    await showDocument(tester, source: const Size(390, 788));
    final fitted = imageBounds(tester);
    await pinch(tester, factor: 2.5);
    final zoomed = imageBounds(tester);
    expect(zoomed.width, greaterThan(fitted.width * 1.5));
    expect((zoomed.center - fitted.center).distance, lessThan(0.1));
    for (var cycle = 0; cycle < 5; cycle++) {
      for (final delta in const [
        Offset(-1000, -1200),
        Offset(1200, 1000),
        Offset(-1200, 1000),
        Offset(1200, -1000)
      ]) {
        await tester.drag(find.byKey(viewportKey), delta);
        await tester.pumpAndSettle();
        expectBoundedImage(tester);
      }
      await pinch(tester, factor: 0.5);
      await pinch(tester, factor: 2);
    }
    await pinch(tester, factor: 0.1);
    await pinch(tester, factor: 0.1);
    expectBoundedImage(tester);
    expect(imageBounds(tester).width, closeTo(fitted.width, 0.1));
    await tester.tap(find.byTooltip('Reset zoom'));
    await tester.pumpAndSettle();
    expect(imageBounds(tester), fitted);
  });

  testWidgets('adding and lifting a finger does not jump the image',
      (tester) async {
    await showDocument(tester, source: const Size(390, 788));
    await doubleTap(tester, tester.getCenter(find.byKey(viewportKey)));
    final center = tester.getCenter(find.byKey(viewportKey));
    final first = await tester.startGesture(center, pointer: 1);
    await first.moveBy(const Offset(30, 20));
    await tester.pump();
    final before = imageBounds(tester);
    final second =
        await tester.startGesture(center + const Offset(90, 0), pointer: 2);
    await tester.pump();
    expect(imageBounds(tester), before);
    await second.up();
    await tester.pump();
    expect(imageBounds(tester), before);
    await first.moveBy(const Offset(-5, -5));
    await tester.pump();
    expect(
        (imageBounds(tester).topLeft - before.topLeft).distance, lessThan(15));
    await first.up();
    await tester.pumpAndSettle();
    expectBoundedImage(tester);
  });

  for (final source in const [Size(400, 1200), Size(1600, 400), Size(12, 8)]) {
    testWidgets('fits $source after orientation changes and extreme pans',
        (tester) async {
      await showDocument(tester, source: source);
      final initial = imageBounds(tester);
      expectBoundedImage(tester);
      await doubleTap(tester, tester.getCenter(find.byKey(viewportKey)));
      await tester.drag(find.byKey(viewportKey), const Offset(1200, -1200));
      await tester.pumpAndSettle();
      expectBoundedImage(tester);
      await tester.binding.setSurfaceSize(const Size(844, 390));
      await tester.pumpAndSettle();
      final viewport = tester.getRect(find.byKey(viewportKey));
      final fit = imageBounds(tester);
      expect(fit.width, lessThanOrEqualTo(viewport.width + 0.01));
      expect(fit.height, lessThanOrEqualTo(viewport.height + 0.01));
      expect(
          fit.width / fit.height, closeTo(source.width / source.height, 0.01));
      expectBoundedImage(tester);
      await tester.binding.setSurfaceSize(const Size(390, 844));
      await tester.pumpAndSettle();
      expect(imageBounds(tester), initial);
    });
  }

  testWidgets('pointer down interrupts zoom animation without a later jump',
      (tester) async {
    await showDocument(tester, source: const Size(390, 788));
    final center = tester.getCenter(find.byKey(viewportKey));
    await tester.tapAt(center);
    await tester.pump(const Duration(milliseconds: 80));
    await tester.tapAt(center);
    await tester.pump(const Duration(milliseconds: 50));
    final finger = await tester.startGesture(center, pointer: 5);
    final stopped = imageBounds(tester);
    await tester.pump(const Duration(milliseconds: 400));
    expect(imageBounds(tester), stopped);
    await finger.moveBy(const Offset(-40, -50));
    await tester.pump();
    expectBoundedImage(tester);
    await finger.up();
    await tester.tap(find.byTooltip('Reset zoom'));
    await tester.pumpAndSettle();
    expectBoundedImage(tester);
    expect(imageBounds(tester).width, closeTo(390, 0.01));
    expect(tester.takeException(), isNull);
  });

  testWidgets(
      'failed image load offers localized retry without exposing exception',
      (tester) async {
    await tester.pumpWidget(const MaterialApp(
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      home: MedicalDocumentViewerScreen(
          imageUrl: 'invalid://synthetic', title: 'Document'),
    ));
    await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 100)));
    await tester.pump();
    expect(find.text('Image not available'), findsOneWidget);
    expect(
        find.text(
            'The image could not be loaded. Check your connection and try again.'),
        findsOneWidget);
    expect(find.textContaining('Exception'), findsNothing);
    expect(find.textContaining('invalid://'), findsNothing);
    expect(find.text('Retry'), findsOneWidget);
    await tester.tap(find.text('Retry'));
    await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 100)));
    await tester.pump();
    expect(find.text('Image not available'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
