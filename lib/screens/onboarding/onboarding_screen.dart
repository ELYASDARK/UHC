import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../core/constants/app_colors.dart';

import '../../core/widgets/responsive_layout.dart';
import '../../l10n/app_localizations.dart';

// ──────────────────────────────────────────────────────────────────────────────
//  DATA MODEL
// ──────────────────────────────────────────────────────────────────────────────

class _SlideData {
  final String title;
  final String description;
  final Color gradientStart;
  final Color gradientEnd;
  final int illustrationIndex;

  const _SlideData({
    required this.title,
    required this.description,
    required this.gradientStart,
    required this.gradientEnd,
    required this.illustrationIndex,
  });
}

// ──────────────────────────────────────────────────────────────────────────────
//  ONBOARDING SCREEN
// ──────────────────────────────────────────────────────────────────────────────

/// Premium onboarding screen with 3 immersive slides.
class OnboardingScreen extends StatefulWidget {
  final VoidCallback onComplete;

  const OnboardingScreen({super.key, required this.onComplete});

  @override
  State<OnboardingScreen> createState() => _OnboardingScreenState();
}

class _OnboardingScreenState extends State<OnboardingScreen> {
  final PageController _pageController = PageController();
  int _currentPage = 0;

  List<_SlideData> _getSlides(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return [
      _SlideData(
        title: l10n.onboardingTitle1,
        description: l10n.onboardingDesc1,
        gradientStart: AppColors.primaryGradient[0],
        gradientEnd: AppColors.primaryGradient[1],
        illustrationIndex: 0,
      ),
      _SlideData(
        title: l10n.onboardingTitle2,
        description: l10n.onboardingDesc2,
        gradientStart: AppColors.secondaryGradient[0],
        gradientEnd: AppColors.secondaryGradient[1],
        illustrationIndex: 1,
      ),
      _SlideData(
        title: l10n.onboardingTitle3,
        description: l10n.onboardingDesc3,
        gradientStart: const Color(0xFFF0A830),
        gradientEnd: const Color(0xFF6D4524),
        illustrationIndex: 2,
      ),
    ];
  }

  @override
  void dispose() {
    _pageController.dispose();
    super.dispose();
  }

  void _nextPage() {
    final slides = _getSlides(context);
    if (_currentPage < slides.length - 1) {
      _pageController.nextPage(
        duration: const Duration(milliseconds: 450),
        curve: Curves.easeInOutCubic,
      );
    } else {
      widget.onComplete();
    }
  }

  @override
  Widget build(BuildContext context) {
    final slides = _getSlides(context);
    final l10n = AppLocalizations.of(context);
    final currentSlide = slides[_currentPage];

    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: const SystemUiOverlayStyle(
        statusBarColor: Colors.transparent,
        statusBarIconBrightness: Brightness.light,
        systemNavigationBarColor: Colors.transparent,
        systemNavigationBarIconBrightness: Brightness.light,
      ),
      child: PopScope(
        canPop: _currentPage == 0,
        onPopInvokedWithResult: (didPop, result) {
          if (didPop) return;
          if (_currentPage > 0) {
            _pageController.previousPage(
              duration: const Duration(milliseconds: 450),
              curve: Curves.easeInOutCubic,
            );
          }
        },
        child: Scaffold(
          body: AnimatedContainer(
            duration: const Duration(milliseconds: 500),
            curve: Curves.easeInOut,
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [currentSlide.gradientStart, currentSlide.gradientEnd],
              ),
            ),
            child: SafeArea(
              child: Column(
                children: [
                  // ── Skip button ─────────────────────────────────────
                  Align(
                    alignment: AlignmentDirectional.topEnd,
                    child: Padding(
                      padding: const EdgeInsets.only(top: 8, right: 8),
                      child: TextButton(
                        onPressed: widget.onComplete,
                        style: TextButton.styleFrom(
                          foregroundColor: Colors.white70,
                          padding: const EdgeInsets.symmetric(
                            horizontal: 16,
                            vertical: 8,
                          ),
                        ),
                        child: Text(
                          l10n.skip,
                          style: GoogleFonts.poppins(
                            fontSize: 15,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                      ),
                    ),
                  ),

                  // ── Illustration (PageView for swiping) ─────────────
                  Expanded(
                    child: PageView.builder(
                      controller: _pageController,
                      itemCount: slides.length,
                      onPageChanged: (index) {
                        setState(() => _currentPage = index);
                      },
                      itemBuilder: (context, index) {
                        return Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 40),
                          child: Center(
                            child: SizedBox(
                              width: 240,
                              height: 240,
                              child: CustomPaint(
                                painter: _IllustrationPainter(
                                  slideIndex: index,
                                ),
                                size: const Size(240, 240),
                              ),
                            ),
                          )
                              .animate()
                              .scale(
                                begin: const Offset(0.88, 0.88),
                                end: const Offset(1.0, 1.0),
                                duration: 500.ms,
                                curve: Curves.easeOutBack,
                              )
                              .fadeIn(duration: 400.ms),
                        );
                      },
                    ),
                  ),

                  // ── Bottom content area ─────────────────────────────
                  ResponsiveContent(
                    maxWidth: 520,
                    child: Padding(
                      padding: EdgeInsets.fromLTRB(
                        28,
                        0,
                        28,
                        MediaQuery.paddingOf(context).bottom > 0 ? 16 : 28,
                      ),
                      child: Column(
                        children: [
                          // Title
                          AnimatedSwitcher(
                            duration: const Duration(milliseconds: 300),
                            transitionBuilder: (child, animation) {
                              return FadeTransition(
                                opacity: animation,
                                child: SlideTransition(
                                  position: Tween<Offset>(
                                    begin: const Offset(0, 0.12),
                                    end: Offset.zero,
                                  ).animate(CurvedAnimation(
                                    parent: animation,
                                    curve: Curves.easeOut,
                                  )),
                                  child: child,
                                ),
                              );
                            },
                            child: Text(
                              currentSlide.title,
                              key: ValueKey<int>(_currentPage),
                              style: GoogleFonts.poppins(
                                fontSize: 28,
                                fontWeight: FontWeight.bold,
                                color: Colors.white,
                                height: 1.2,
                              ),
                              textAlign: TextAlign.center,
                            ),
                          ),

                          const SizedBox(height: 14),

                          // Description
                          AnimatedSwitcher(
                            duration: const Duration(milliseconds: 300),
                            transitionBuilder: (child, animation) {
                              return FadeTransition(
                                opacity: animation,
                                child: child,
                              );
                            },
                            child: Text(
                              currentSlide.description,
                              key: ValueKey<String>(currentSlide.description),
                              style: GoogleFonts.roboto(
                                fontSize: 15,
                                height: 1.6,
                                color: Colors.white.withValues(alpha: 0.75),
                              ),
                              textAlign: TextAlign.center,
                              maxLines: 5,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),

                          const SizedBox(height: 36),

                          // Page indicators (simple animated pills)
                          Row(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: List.generate(slides.length, (index) {
                              final isActive = _currentPage == index;
                              return AnimatedContainer(
                                duration: const Duration(milliseconds: 350),
                                curve: Curves.easeInOut,
                                margin:
                                    const EdgeInsets.symmetric(horizontal: 4),
                                width: isActive ? 28 : 8,
                                height: 8,
                                decoration: BoxDecoration(
                                  borderRadius: BorderRadius.circular(4),
                                  color: isActive
                                      ? Colors.white
                                      : Colors.white.withValues(alpha: 0.3),
                                ),
                              );
                            }),
                          ),

                          const SizedBox(height: 32),

                          // Next / Get Started button
                          _GradientPillButton(
                            text: _currentPage == slides.length - 1
                                ? l10n.getStarted
                                : l10n.next,
                            gradientStart: currentSlide.gradientStart,
                            gradientEnd: currentSlide.gradientEnd,
                            onTap: _nextPage,
                            showArrow: true,
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

// ──────────────────────────────────────────────────────────────────────────────
//  GRADIENT PILL BUTTON
// ──────────────────────────────────────────────────────────────────────────────

class _GradientPillButton extends StatelessWidget {
  final String text;
  final Color gradientStart;
  final Color gradientEnd;
  final VoidCallback onTap;
  final bool showArrow;

  const _GradientPillButton({
    required this.text,
    required this.gradientStart,
    required this.gradientEnd,
    required this.onTap,
    this.showArrow = false,
  });

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: double.infinity,
      height: 56,
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(28),
          child: Ink(
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(28),
              color: Colors.white.withValues(alpha: 0.2),
              border: Border.all(
                color: Colors.white.withValues(alpha: 0.3),
                width: 1,
              ),
            ),
            child: Center(
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                mainAxisSize: MainAxisSize.min,
                children: [
                  AnimatedSwitcher(
                    duration: const Duration(milliseconds: 250),
                    transitionBuilder: (child, animation) {
                      return FadeTransition(opacity: animation, child: child);
                    },
                    child: Text(
                      text,
                      key: ValueKey<String>(text),
                      style: GoogleFonts.poppins(
                        fontSize: 16,
                        fontWeight: FontWeight.w600,
                        color: Colors.white,
                      ),
                    ),
                  ),
                  if (showArrow) ...[
                    const SizedBox(width: 8),
                    const Icon(
                      Icons.arrow_forward_rounded,
                      color: Colors.white,
                      size: 20,
                    ),
                  ],
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

// ──────────────────────────────────────────────────────────────────────────────
//  CUSTOM PAINTED ILLUSTRATIONS
// ──────────────────────────────────────────────────────────────────────────────

class _IllustrationPainter extends CustomPainter {
  final int slideIndex;

  _IllustrationPainter({required this.slideIndex});

  @override
  void paint(Canvas canvas, Size size) {
    switch (slideIndex) {
      case 0:
        _paintCalendar(canvas, size);
        break;
      case 1:
        _paintBell(canvas, size);
        break;
      case 2:
        _paintClipboard(canvas, size);
        break;
    }
  }

  /// Slide 1: Stylized calendar with clock overlay.
  void _paintCalendar(Canvas canvas, Size size) {
    final cx = size.width / 2;
    final cy = size.height / 2;
    final unit = size.width / 10;

    // Outer glow circle
    canvas.drawCircle(
      Offset(cx, cy),
      unit * 4.5,
      Paint()
        ..color = Colors.white.withValues(alpha: 0.06)
        ..style = PaintingStyle.fill,
    );

    // Calendar body
    final calendarRect = RRect.fromRectAndRadius(
      Rect.fromCenter(
        center: Offset(cx, cy + unit * 0.3),
        width: unit * 6,
        height: unit * 6.5,
      ),
      Radius.circular(unit * 0.7),
    );
    canvas.drawRRect(
      calendarRect,
      Paint()
        ..color = Colors.white.withValues(alpha: 0.15)
        ..style = PaintingStyle.fill,
    );
    canvas.drawRRect(
      calendarRect,
      Paint()
        ..color = Colors.white.withValues(alpha: 0.3)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.5,
    );

    // Calendar header bar
    canvas.drawRRect(
      RRect.fromRectAndCorners(
        Rect.fromLTWH(cx - unit * 3, cy - unit * 2.95, unit * 6, unit * 1.6),
        topLeft: Radius.circular(unit * 0.7),
        topRight: Radius.circular(unit * 0.7),
      ),
      Paint()
        ..color = Colors.white.withValues(alpha: 0.2)
        ..style = PaintingStyle.fill,
    );

    // Calendar binding rings
    final ringPaint = Paint()
      ..color = Colors.white.withValues(alpha: 0.45)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2
      ..strokeCap = StrokeCap.round;
    for (var i = 0; i < 3; i++) {
      final rx = cx - unit * 1.5 + i * unit * 1.5;
      canvas.drawLine(
        Offset(rx, cy - unit * 3.4),
        Offset(rx, cy - unit * 2.6),
        ringPaint,
      );
    }

    // Calendar grid dots
    for (var row = 0; row < 3; row++) {
      for (var col = 0; col < 4; col++) {
        final dx = cx - unit * 2 + col * unit * 1.3;
        final dy = cy - unit * 0.5 + row * unit * 1.3;
        final isHighlighted = (row == 1 && col == 2);
        canvas.drawCircle(
          Offset(dx, dy),
          isHighlighted ? unit * 0.35 : unit * 0.2,
          Paint()
            ..color = Colors.white
                .withValues(alpha: isHighlighted ? 0.85 : 0.35)
            ..style = PaintingStyle.fill,
        );
      }
    }

    // Clock overlay (bottom-right)
    final clockCenter = Offset(cx + unit * 2.2, cy + unit * 2.0);
    canvas.drawCircle(
      clockCenter,
      unit * 1.2,
      Paint()
        ..color = Colors.white.withValues(alpha: 0.15)
        ..style = PaintingStyle.fill,
    );
    canvas.drawCircle(
      clockCenter,
      unit * 1.2,
      Paint()
        ..color = Colors.white.withValues(alpha: 0.4)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.5,
    );
    final handPaint = Paint()
      ..color = Colors.white.withValues(alpha: 0.7)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2
      ..strokeCap = StrokeCap.round;
    canvas.drawLine(clockCenter,
        Offset(clockCenter.dx, clockCenter.dy - unit * 0.7), handPaint);
    canvas.drawLine(clockCenter,
        Offset(clockCenter.dx + unit * 0.5, clockCenter.dy + unit * 0.2),
        handPaint);

    // Plus sign accent (top-right)
    final plusPaint = Paint()
      ..color = Colors.white.withValues(alpha: 0.4)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2.5
      ..strokeCap = StrokeCap.round;
    final plusCenter = Offset(cx + unit * 3.5, cy - unit * 3.2);
    canvas.drawLine(Offset(plusCenter.dx - unit * 0.4, plusCenter.dy),
        Offset(plusCenter.dx + unit * 0.4, plusCenter.dy), plusPaint);
    canvas.drawLine(Offset(plusCenter.dx, plusCenter.dy - unit * 0.4),
        Offset(plusCenter.dx, plusCenter.dy + unit * 0.4), plusPaint);
  }

  /// Slide 2: Notification bell with pulse rings.
  void _paintBell(Canvas canvas, Size size) {
    final cx = size.width / 2;
    final cy = size.height / 2;
    final unit = size.width / 10;

    // Pulse rings
    for (var i = 3; i >= 1; i--) {
      canvas.drawCircle(
        Offset(cx, cy - unit * 0.5),
        unit * (2.5 + i * 0.9),
        Paint()
          ..color =
              Colors.white.withValues(alpha: 0.03 * (4 - i).toDouble())
          ..style = PaintingStyle.fill,
      );
    }

    // Bell body
    final bellPath = Path()
      ..moveTo(cx - unit * 2, cy + unit * 0.8)
      ..quadraticBezierTo(cx - unit * 2, cy - unit * 2.5, cx, cy - unit * 3)
      ..quadraticBezierTo(
          cx + unit * 2, cy - unit * 2.5, cx + unit * 2, cy + unit * 0.8)
      ..quadraticBezierTo(cx + unit * 2.2, cy + unit * 1.3,
          cx + unit * 2.6, cy + unit * 1.5)
      ..lineTo(cx - unit * 2.6, cy + unit * 1.5)
      ..quadraticBezierTo(cx - unit * 2.2, cy + unit * 1.3, cx - unit * 2,
          cy + unit * 0.8)
      ..close();

    canvas.drawPath(
      bellPath,
      Paint()
        ..color = Colors.white.withValues(alpha: 0.15)
        ..style = PaintingStyle.fill,
    );
    canvas.drawPath(
      bellPath,
      Paint()
        ..color = Colors.white.withValues(alpha: 0.4)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2
        ..strokeJoin = StrokeJoin.round,
    );

    // Bell clapper
    canvas.drawCircle(
      Offset(cx, cy + unit * 2.0),
      unit * 0.4,
      Paint()
        ..color = Colors.white.withValues(alpha: 0.45)
        ..style = PaintingStyle.fill,
    );

    // Bell top nub
    canvas.drawCircle(
      Offset(cx, cy - unit * 3),
      unit * 0.3,
      Paint()
        ..color = Colors.white.withValues(alpha: 0.5)
        ..style = PaintingStyle.fill,
    );

    // Notification badge (top-right)
    final badgeCenter = Offset(cx + unit * 2.0, cy - unit * 2.4);
    canvas.drawCircle(
      badgeCenter,
      unit * 0.65,
      Paint()
        ..color = Colors.white.withValues(alpha: 0.8)
        ..style = PaintingStyle.fill,
    );
    // Mini clock in badge
    final miniPaint = Paint()
      ..color = const Color(0xFF26A69A)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.5
      ..strokeCap = StrokeCap.round;
    canvas.drawCircle(badgeCenter, unit * 0.35, miniPaint);
    canvas.drawLine(badgeCenter,
        Offset(badgeCenter.dx, badgeCenter.dy - unit * 0.2), miniPaint);
    canvas.drawLine(badgeCenter,
        Offset(badgeCenter.dx + unit * 0.15, badgeCenter.dy), miniPaint);

    // Sound waves (simple arcs on each side)
    for (var side = -1; side <= 1; side += 2) {
      for (var i = 1; i <= 2; i++) {
        canvas.drawArc(
          Rect.fromCenter(
            center: Offset(cx + side * unit * 2.8, cy - unit * 0.5),
            width: unit * 0.6 * i,
            height: unit * 1.2 * i,
          ),
          side == 1 ? -3.14 / 3 : 3.14 * 2 / 3,
          3.14 * 2 / 3,
          false,
          Paint()
            ..color = Colors.white.withValues(alpha: 0.2 / i)
            ..style = PaintingStyle.stroke
            ..strokeWidth = 1.5
            ..strokeCap = StrokeCap.round,
        );
      }
    }
  }

  /// Slide 3: Medical clipboard with heart-pulse line and shield.
  void _paintClipboard(Canvas canvas, Size size) {
    final cx = size.width / 2;
    final cy = size.height / 2;
    final unit = size.width / 10;

    // Outer glow
    canvas.drawCircle(
      Offset(cx, cy),
      unit * 4.5,
      Paint()
        ..color = Colors.white.withValues(alpha: 0.05)
        ..style = PaintingStyle.fill,
    );

    // Clipboard body
    final clipRect = RRect.fromRectAndRadius(
      Rect.fromCenter(
        center: Offset(cx, cy + unit * 0.5),
        width: unit * 5.5,
        height: unit * 7,
      ),
      Radius.circular(unit * 0.6),
    );
    canvas.drawRRect(
      clipRect,
      Paint()
        ..color = Colors.white.withValues(alpha: 0.15)
        ..style = PaintingStyle.fill,
    );
    canvas.drawRRect(
      clipRect,
      Paint()
        ..color = Colors.white.withValues(alpha: 0.3)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.5,
    );

    // Clip at top
    final clipTopRect = RRect.fromRectAndRadius(
      Rect.fromCenter(
        center: Offset(cx, cy - unit * 2.8),
        width: unit * 2.5,
        height: unit * 1,
      ),
      Radius.circular(unit * 0.3),
    );
    canvas.drawRRect(
      clipTopRect,
      Paint()
        ..color = Colors.white.withValues(alpha: 0.25)
        ..style = PaintingStyle.fill,
    );
    canvas.drawRRect(
      clipTopRect,
      Paint()
        ..color = Colors.white.withValues(alpha: 0.4)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.5,
    );

    // Heart-pulse line
    final pulseY = cy - unit * 0.3;
    final pulsePath = Path()
      ..moveTo(cx - unit * 2.2, pulseY)
      ..lineTo(cx - unit * 1.2, pulseY)
      ..lineTo(cx - unit * 0.7, pulseY - unit * 1.0)
      ..lineTo(cx - unit * 0.1, pulseY + unit * 0.8)
      ..lineTo(cx + unit * 0.4, pulseY - unit * 1.3)
      ..lineTo(cx + unit * 0.9, pulseY + unit * 0.5)
      ..lineTo(cx + unit * 1.3, pulseY)
      ..lineTo(cx + unit * 2.2, pulseY);
    canvas.drawPath(
      pulsePath,
      Paint()
        ..color = Colors.white.withValues(alpha: 0.6)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2.2
        ..strokeCap = StrokeCap.round
        ..strokeJoin = StrokeJoin.round,
    );

    // Text placeholder lines
    final linePaint = Paint()
      ..color = Colors.white.withValues(alpha: 0.2)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2
      ..strokeCap = StrokeCap.round;
    for (var i = 0; i < 3; i++) {
      final lineY = cy + unit * 1.2 + i * unit * 0.8;
      final lineWidth = i == 2 ? unit * 2.5 : unit * 3.5;
      canvas.drawLine(
        Offset(cx - unit * 1.8, lineY),
        Offset(cx - unit * 1.8 + lineWidth, lineY),
        linePaint,
      );
    }

    // Shield accent (bottom-right)
    final sc = Offset(cx + unit * 2.5, cy + unit * 2.5);
    final shieldPath = Path()
      ..moveTo(sc.dx, sc.dy - unit * 1.0)
      ..quadraticBezierTo(
          sc.dx + unit * 1.0, sc.dy - unit * 0.7, sc.dx + unit * 1.0, sc.dy)
      ..quadraticBezierTo(
          sc.dx + unit * 0.8, sc.dy + unit * 1.0, sc.dx, sc.dy + unit * 1.3)
      ..quadraticBezierTo(
          sc.dx - unit * 0.8, sc.dy + unit * 1.0, sc.dx - unit * 1.0, sc.dy)
      ..quadraticBezierTo(
          sc.dx - unit * 1.0, sc.dy - unit * 0.7, sc.dx, sc.dy - unit * 1.0)
      ..close();
    canvas.drawPath(
      shieldPath,
      Paint()
        ..color = Colors.white.withValues(alpha: 0.15)
        ..style = PaintingStyle.fill,
    );
    canvas.drawPath(
      shieldPath,
      Paint()
        ..color = Colors.white.withValues(alpha: 0.4)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.5,
    );

    // Checkmark inside shield
    final checkPath = Path()
      ..moveTo(sc.dx - unit * 0.35, sc.dy + unit * 0.1)
      ..lineTo(sc.dx - unit * 0.05, sc.dy + unit * 0.4)
      ..lineTo(sc.dx + unit * 0.4, sc.dy - unit * 0.25);
    canvas.drawPath(
      checkPath,
      Paint()
        ..color = Colors.white.withValues(alpha: 0.65)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2
        ..strokeCap = StrokeCap.round
        ..strokeJoin = StrokeJoin.round,
    );
  }

  @override
  bool shouldRepaint(covariant _IllustrationPainter oldDelegate) {
    return oldDelegate.slideIndex != slideIndex;
  }
}
