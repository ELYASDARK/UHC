import 'package:flutter/material.dart';
import 'package:lottie/lottie.dart';
import 'package:qr_flutter/qr_flutter.dart';

import '../../../core/constants/app_colors.dart';
import '../../../core/widgets/responsive_layout.dart';
import '../../../l10n/app_localizations.dart';
import '../../../main.dart' show AppNavigator;

/// Booking success screen with QR code
class BookingSuccessScreen extends StatelessWidget {
  final String appointmentId;
  final String? qrCode;
  final String? bookingReference;
  final String doctorName;
  final DateTime date;
  final String timeSlot;

  const BookingSuccessScreen({
    super.key,
    required this.appointmentId,
    this.qrCode,
    this.bookingReference,
    required this.doctorName,
    required this.date,
    required this.timeSlot,
  });

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final l10n = AppLocalizations.of(context);
    final isWide = UhcResponsive.isWide(context);

    return Scaffold(
      body: ResponsivePage(
        safeArea: true,
        maxWidth: isWide ? 980 : 640,
        bottomPadding: isWide ? 32 : 16,
        child: Column(
          children: [
            SizedBox(height: isWide ? 16 : 40),

            // Success animation
            SizedBox(
              height: 180,
              child: Lottie.asset(
                'assets/animations/success.json',
                repeat: false,
                errorBuilder: (context, error, stackTrace) {
                  return Container(
                    width: 120,
                    height: 120,
                    decoration: BoxDecoration(
                      color: AppColors.success.withValues(alpha: 0.1),
                      shape: BoxShape.circle,
                    ),
                    child: const Icon(
                      Icons.check_circle,
                      size: 80,
                      color: AppColors.success,
                    ),
                  );
                },
              ),
            ),
            const SizedBox(height: 24),

            Text(
              '${l10n.bookingConfirmed}!',
              style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                    fontWeight: FontWeight.bold,
                    color: AppColors.success,
                  ),
            ),
            const SizedBox(height: 8),
            Text(
              l10n.appointmentScheduledSuccessfully,
              textAlign: TextAlign.center,
              style: TextStyle(
                color: isDark
                    ? AppColors.textSecondaryDark
                    : AppColors.textSecondaryLight,
              ),
            ),
            const SizedBox(height: 32),

            // Appointment Card
            Container(
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(
                color: isDark ? AppColors.surfaceDark : Colors.white,
                borderRadius: BorderRadius.circular(20),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.1),
                    blurRadius: 20,
                    offset: const Offset(0, 10),
                  ),
                ],
              ),
              child:
                  _buildConfirmationCardContent(context, isWide, isDark, l10n),
            ),
            SizedBox(height: isWide ? 24 : 32),

            // Buttons
            _buildActionButtons(context, isWide, l10n),
          ],
        ),
      ),
    );
  }

  Widget _buildConfirmationCardContent(
    BuildContext context,
    bool isWide,
    bool isDark,
    AppLocalizations l10n,
  ) {
    if (!isWide) {
      return Column(
        children: [
          _buildQrPanel(isDark, l10n),
          const SizedBox(height: 20),
          const Divider(),
          const SizedBox(height: 20),
          _buildDetailsPanel(context, l10n),
        ],
      );
    }

    return Row(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        Expanded(child: _buildQrPanel(isDark, l10n)),
        const SizedBox(width: 28),
        SizedBox(
          height: 220,
          child: VerticalDivider(
            color: isDark ? Colors.white12 : Colors.black12,
          ),
        ),
        const SizedBox(width: 28),
        Expanded(child: _buildDetailsPanel(context, l10n)),
      ],
    );
  }

  Widget _buildQrPanel(bool isDark, AppLocalizations l10n) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(16),
          ),
          child: QrImageView(
            data: qrCode ?? bookingReference ?? appointmentId,
            version: QrVersions.auto,
            size: 180,
            backgroundColor: Colors.white,
            errorCorrectionLevel: QrErrorCorrectLevel.M,
          ),
        ),
        const SizedBox(height: 16),
        Text(
          l10n.showQRCodeAtCheckIn,
          textAlign: TextAlign.center,
          style: TextStyle(
            color: isDark
                ? AppColors.textSecondaryDark
                : AppColors.textSecondaryLight,
            fontSize: 13,
          ),
        ),
      ],
    );
  }

  Widget _buildDetailsPanel(BuildContext context, AppLocalizations l10n) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        _buildDetailRow(context, Icons.person, l10n.doctor, 'Dr. $doctorName'),
        const SizedBox(height: 14),
        _buildDetailRow(
          context,
          Icons.calendar_month,
          l10n.date,
          _formatDate(date, l10n),
        ),
        const SizedBox(height: 14),
        _buildDetailRow(context, Icons.access_time, l10n.time, timeSlot),
        const SizedBox(height: 14),
        _buildDetailRow(
          context,
          Icons.confirmation_number,
          l10n.bookingId,
          bookingReference ?? appointmentId.substring(0, 8).toUpperCase(),
        ),
      ],
    );
  }

  Widget _buildActionButtons(
    BuildContext context,
    bool isWide,
    AppLocalizations l10n,
  ) {
    final homeButton = ElevatedButton(
      onPressed: () {
        AppNavigator.returnToPatientTab(context, 0);
      },
      style: ElevatedButton.styleFrom(
        backgroundColor: AppColors.primary,
        foregroundColor: Colors.white,
        padding: const EdgeInsets.symmetric(vertical: 16),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      ),
      child: Text(l10n.backToHome),
    );

    final appointmentsButton = OutlinedButton(
      onPressed: () {
        AppNavigator.returnToPatientTab(context, 2);
      },
      style: OutlinedButton.styleFrom(
        padding: const EdgeInsets.symmetric(vertical: 16),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      ),
      child: Text(l10n.viewMyAppointments),
    );

    if (isWide) {
      return Row(
        children: [
          Expanded(child: appointmentsButton),
          const SizedBox(width: 16),
          Expanded(child: homeButton),
        ],
      );
    }

    return Column(
      children: [
        SizedBox(width: double.infinity, child: homeButton),
        const SizedBox(height: 12),
        SizedBox(width: double.infinity, child: appointmentsButton),
      ],
    );
  }

  Widget _buildDetailRow(
    BuildContext context,
    IconData icon,
    String label,
    String value,
  ) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Row(
      children: [
        Icon(icon, color: AppColors.primary, size: 20),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                label,
                style: TextStyle(
                  color: isDark
                      ? AppColors.textSecondaryDark
                      : AppColors.textSecondaryLight,
                  fontSize: 12,
                ),
              ),
              Text(value, style: const TextStyle(fontWeight: FontWeight.w600)),
            ],
          ),
        ),
      ],
    );
  }

  String _formatDate(DateTime date, AppLocalizations l10n) {
    final weekdays = [
      l10n.monday,
      l10n.tuesday,
      l10n.wednesday,
      l10n.thursday,
      l10n.friday,
      l10n.saturday,
      l10n.sunday,
    ];
    final months = [
      l10n.january,
      l10n.february,
      l10n.march,
      l10n.april,
      l10n.may,
      l10n.june,
      l10n.july,
      l10n.august,
      l10n.september,
      l10n.october,
      l10n.november,
      l10n.december,
    ];
    return '${weekdays[date.weekday - 1]}, ${months[date.month - 1]} ${date.day}, ${date.year}';
  }
}
