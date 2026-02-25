import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:mobile_scanner/mobile_scanner.dart';
import 'package:provider/provider.dart';

import '../../../core/constants/app_colors.dart';
import '../../../l10n/app_localizations.dart';
import '../../../providers/doctor_appointment_provider.dart';

/// QR scanner screen for confirming appointments.
///
/// Returns a Map when popping:
///   { 'matched': true/false, 'failures': int }
/// Returns null if the user closes without scanning.
class QrScanConfirmScreen extends StatefulWidget {
  final String appointmentId;
  final int initialFailures;

  const QrScanConfirmScreen({
    super.key,
    required this.appointmentId,
    required this.initialFailures,
  });

  @override
  State<QrScanConfirmScreen> createState() => _QrScanConfirmScreenState();
}

class _QrScanConfirmScreenState extends State<QrScanConfirmScreen> {
  final MobileScannerController _controller = MobileScannerController();
  late int _failures;
  bool _isProcessing = false;
  String? _errorMessage;

  static const int _maxAttempts = 5;

  @override
  void initState() {
    super.initState();
    _failures = widget.initialFailures;
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _onDetect(BarcodeCapture capture) async {
    if (_isProcessing) return;
    final barcode = capture.barcodes.firstOrNull;
    if (barcode == null || barcode.rawValue == null) return;

    setState(() => _isProcessing = true);

    final expected = 'UHC_APPOINTMENT:${widget.appointmentId}';

    if (barcode.rawValue == expected) {
      // ── Match ──
      if (mounted) {
        Navigator.pop(context, {'matched': true, 'failures': _failures});
      }
      return;
    }

    // ── Wrong QR — increment in Firestore ──
    final provider = context.read<DoctorAppointmentProvider>();
    await provider.incrementQrScanFailures(widget.appointmentId);

    setState(() {
      _failures++;
      _errorMessage = AppLocalizations.of(context).invalidQrCode;
    });

    if (_failures >= _maxAttempts) {
      // Manual mode unlocked — wait briefly then pop
      await Future.delayed(const Duration(milliseconds: 1500));
      if (mounted) {
        Navigator.pop(context, {'matched': false, 'failures': _failures});
      }
    } else {
      // Allow next scan after brief delay
      await Future.delayed(const Duration(seconds: 2));
      if (mounted) {
        setState(() {
          _isProcessing = false;
          _errorMessage = null;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);

    return Scaffold(
      backgroundColor: Colors.black,
      body: Stack(
        children: [
          // ── Camera preview ──
          MobileScanner(
            controller: _controller,
            onDetect: _onDetect,
          ),

          // ── Semi-transparent overlay with viewfinder cutout ──
          CustomPaint(
            size: MediaQuery.of(context).size,
            painter: _ViewfinderPainter(),
          ),

          // ── Top bar ──
          Positioned(
            top: 0,
            left: 0,
            right: 0,
            child: SafeArea(
              bottom: false,
              child: Padding(
                padding:
                    const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                child: Row(
                  children: [
                    IconButton(
                      onPressed: () => Navigator.pop(context),
                      icon: const Icon(Icons.close,
                          color: Colors.white, size: 28),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        l10n.scanPatientQrCode,
                        style: GoogleFonts.poppins(
                          fontSize: 18,
                          fontWeight: FontWeight.w600,
                          color: Colors.white,
                        ),
                      ),
                    ),
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 12, vertical: 6),
                      decoration: BoxDecoration(
                        color: _failures > 0
                            ? AppColors.error.withValues(alpha: 0.8)
                            : Colors.white.withValues(alpha: 0.2),
                        borderRadius: BorderRadius.circular(20),
                      ),
                      child: Text(
                        l10n.qrScanAttempts(_failures, _maxAttempts),
                        style: GoogleFonts.roboto(
                          fontSize: 13,
                          fontWeight: FontWeight.w600,
                          color: Colors.white,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),

          // ── Bottom instruction text ──
          Positioned(
            bottom: 0,
            left: 0,
            right: 0,
            child: SafeArea(
              top: false,
              child: Padding(
                padding: const EdgeInsets.fromLTRB(32, 0, 32, 32),
                child: Text(
                  l10n.pointCameraAtQr,
                  textAlign: TextAlign.center,
                  style: GoogleFonts.roboto(
                    fontSize: 15,
                    color: Colors.white.withValues(alpha: 0.9),
                  ),
                ),
              ),
            ),
          ),

          // ── Error overlay ──
          if (_errorMessage != null)
            Positioned.fill(
              child: Container(
                color: AppColors.error.withValues(alpha: 0.3),
                child: Center(
                  child: Container(
                    margin: const EdgeInsets.symmetric(horizontal: 40),
                    padding: const EdgeInsets.symmetric(
                        horizontal: 24, vertical: 20),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(16),
                    ),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Icon(Icons.error_outline,
                            color: AppColors.error, size: 48),
                        const SizedBox(height: 12),
                        Text(
                          _errorMessage!,
                          textAlign: TextAlign.center,
                          style: GoogleFonts.poppins(
                            fontSize: 16,
                            fontWeight: FontWeight.w600,
                            color: AppColors.error,
                          ),
                        ),
                        if (_failures >= _maxAttempts) ...[
                          const SizedBox(height: 8),
                          Text(
                            l10n.manualConfirmUnlocked,
                            textAlign: TextAlign.center,
                            style: GoogleFonts.roboto(
                              fontSize: 14,
                              color: Colors.grey[700],
                            ),
                          ),
                        ],
                      ],
                    ),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

/// Paints a semi-transparent overlay with a clear square cutout in the center
class _ViewfinderPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()..color = Colors.black.withValues(alpha: 0.5);
    final cutoutSize = size.width * 0.65;
    final left = (size.width - cutoutSize) / 2;
    final top = (size.height - cutoutSize) / 2;

    final cutout = RRect.fromRectAndRadius(
      Rect.fromLTWH(left, top, cutoutSize, cutoutSize),
      const Radius.circular(16),
    );

    // Draw overlay with cutout
    final path = Path()
      ..addRect(Rect.fromLTWH(0, 0, size.width, size.height))
      ..addRRect(cutout)
      ..fillType = PathFillType.evenOdd;
    canvas.drawPath(path, paint);

    // Draw white corner brackets
    final borderPaint = Paint()
      ..color = Colors.white
      ..strokeWidth = 3
      ..style = PaintingStyle.stroke;
    canvas.drawRRect(cutout, borderPaint);
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}
