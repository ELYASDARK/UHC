import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:provider/provider.dart';
import '../../../core/constants/app_colors.dart';
import '../../../data/models/appointment_model.dart';
import '../../../data/models/doctor_model.dart';
import '../../../providers/doctor_appointment_provider.dart';
import '../../../l10n/app_localizations.dart';
import 'patient_detail_screen.dart';
import '../qr/qr_scan_confirm_screen.dart';

/// Detail screen for a single appointment (doctor view)
///
/// Shows patient info, appointment details, and provides actions:
///   - Confirm (if pending)
///   - Complete + add medical notes (if confirmed)
///   - Mark No-Show
///   - Cancel with reason
///   - Edit medical notes (if already completed)
class DoctorAppointmentDetailScreen extends StatefulWidget {
  final AppointmentModel appointment;
  final DoctorModel doctor;

  const DoctorAppointmentDetailScreen({
    super.key,
    required this.appointment,
    required this.doctor,
  });

  @override
  State<DoctorAppointmentDetailScreen> createState() =>
      _DoctorAppointmentDetailScreenState();
}

class _DoctorAppointmentDetailScreenState
    extends State<DoctorAppointmentDetailScreen> {
  late AppointmentModel _appointment;
  final _notesController = TextEditingController();
  bool _isSaving = false;
  int _qrScanFailures = 0;
  DateTime _now = DateTime.now();
  Timer? _timeCheckTimer;

  @override
  void initState() {
    super.initState();
    _appointment = widget.appointment;
    _notesController.text = _appointment.medicalNotes ?? '';
    _qrScanFailures = _appointment.qrScanFailures;
    // Refresh _now every 30 s to keep the confirm-window UI accurate
    _timeCheckTimer = Timer.periodic(
      const Duration(seconds: 30),
      (_) => setState(() => _now = DateTime.now()),
    );
  }

  @override
  void dispose() {
    _timeCheckTimer?.cancel();
    _notesController.dispose();
    super.dispose();
  }

  // ---- helpers ----
  Color get _statusColor {
    switch (_appointment.status) {
      case AppointmentStatus.pending:
        return AppColors.warning;
      case AppointmentStatus.confirmed:
        return AppColors.success;
      case AppointmentStatus.completed:
        return AppColors.info;
      case AppointmentStatus.cancelled:
        return AppColors.error;
      case AppointmentStatus.noShow:
        return Colors.grey;
    }
  }

  /// Full DateTime of the appointment (date + timeSlot parsed)
  DateTime get _appointmentFullTime {
    final parts = _appointment.timeSlot.split(':');
    final hour = int.tryParse(parts[0]) ?? 0;
    final minute = parts.length > 1 ? (int.tryParse(parts[1]) ?? 0) : 0;
    return DateTime(
      _appointment.appointmentDate.year,
      _appointment.appointmentDate.month,
      _appointment.appointmentDate.day,
      hour,
      minute,
    );
  }

  bool get _isInConfirmWindow {
    final apptTime = _appointmentFullTime;
    final windowStart = apptTime.subtract(const Duration(minutes: 5));
    final windowEnd = apptTime.add(const Duration(minutes: 10));
    return _now.isAfter(windowStart) && _now.isBefore(windowEnd);
  }

  bool get _isBeforeConfirmWindow {
    final apptTime = _appointmentFullTime;
    final windowStart = apptTime.subtract(const Duration(minutes: 5));
    return _now.isBefore(windowStart);
  }

  int get _minutesUntilConfirmWindow {
    final apptTime = _appointmentFullTime;
    final windowStart = apptTime.subtract(const Duration(minutes: 5));
    return windowStart.difference(_now).inMinutes + 1;
  }

  String _formatTimeUntilConfirm(AppLocalizations l10n) {
    final totalMinutes = _minutesUntilConfirmWindow;
    if (totalMinutes >= 1440) {
      final days = (totalMinutes / 1440).ceil();
      return l10n.confirmAvailableInDays(days);
    } else if (totalMinutes >= 60) {
      final hours = (totalMinutes / 60).ceil();
      return l10n.confirmAvailableInHours(hours);
    } else {
      return l10n.confirmAvailableInMinutes(totalMinutes);
    }
  }

  Future<void> _openQrScanner() async {
    final result = await Navigator.push<Map<String, dynamic>>(
      context,
      MaterialPageRoute(
        builder: (_) => QrScanConfirmScreen(
          appointmentId: _appointment.id,
          initialFailures: _qrScanFailures,
        ),
      ),
    );
    if (!mounted || result == null) return;
    final failures = result['failures'] as int;
    setState(() => _qrScanFailures = failures);
    if (result['matched'] == true) {
      _updateStatus(AppointmentStatus.confirmed);
    } else if (failures >= 5) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(AppLocalizations.of(context).manualConfirmUnlocked),
          backgroundColor: AppColors.warning,
        ),
      );
    }
  }

  // ---- build ----
  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final l10n = AppLocalizations.of(context);
    final patientPhoto = context
        .read<DoctorAppointmentProvider>()
        .patientPhotos[_appointment.patientId];

    return Scaffold(
      appBar: AppBar(
        title: Text(
          l10n.appointmentDetails,
          style: GoogleFonts.poppins(fontWeight: FontWeight.w600),
        ),
      ),
      body: Stack(
        children: [
          SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(20, 16, 20, 320),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // ── Patient info card ──
                GestureDetector(
                  onTap: () => _viewPatientProfile(),
                  child: _sectionCard(
                    isDark: isDark,
                    child: Column(
                      children: [
                        Row(
                          children: [
                            Container(
                              width: 56,
                              height: 56,
                              decoration: BoxDecoration(
                                shape: BoxShape.circle,
                                color:
                                    AppColors.secondary.withValues(alpha: 0.15),
                              ),
                              child: ClipOval(
                                child: patientPhoto != null &&
                                        patientPhoto.isNotEmpty
                                    ? Image.network(
                                        patientPhoto,
                                        width: 56,
                                        height: 56,
                                        fit: BoxFit.cover,
                                        errorBuilder: (_, __, ___) => Center(
                                          child: Text(
                                            _appointment.patientName.isNotEmpty
                                                ? _appointment.patientName[0]
                                                    .toUpperCase()
                                                : '?',
                                            style: GoogleFonts.outfit(
                                              fontSize: 24,
                                              fontWeight: FontWeight.bold,
                                              color: AppColors.secondary,
                                            ),
                                          ),
                                        ),
                                      )
                                    : Center(
                                        child: Text(
                                          _appointment.patientName.isNotEmpty
                                              ? _appointment.patientName[0]
                                                  .toUpperCase()
                                              : '?',
                                          style: GoogleFonts.outfit(
                                            fontSize: 24,
                                            fontWeight: FontWeight.bold,
                                            color: AppColors.secondary,
                                          ),
                                        ),
                                      ),
                              ),
                            ),
                            const SizedBox(width: 16),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    _appointment.patientName,
                                    style: GoogleFonts.poppins(
                                      fontSize: 18,
                                      fontWeight: FontWeight.w600,
                                      color: isDark
                                          ? AppColors.textPrimaryDark
                                          : AppColors.textPrimaryLight,
                                    ),
                                  ),
                                  const SizedBox(height: 2),
                                  Text(
                                    _appointment.patientEmail,
                                    style: GoogleFonts.roboto(
                                      fontSize: 13,
                                      color: isDark
                                          ? AppColors.textSecondaryDark
                                          : AppColors.textSecondaryLight,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                            Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 12,
                                vertical: 6,
                              ),
                              decoration: BoxDecoration(
                                color: _statusColor.withValues(alpha: 0.1),
                                borderRadius: BorderRadius.circular(20),
                              ),
                              child: Text(
                                _appointment.statusDisplay,
                                style: GoogleFonts.roboto(
                                  fontSize: 13,
                                  fontWeight: FontWeight.w600,
                                  color: _statusColor,
                                ),
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 8),
                        Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Icon(Icons.visibility_rounded,
                                size: 14, color: AppColors.primary),
                            const SizedBox(width: 4),
                            Text(
                              l10n.viewPatientProfile,
                              style: GoogleFonts.roboto(
                                fontSize: 12,
                                color: AppColors.primary,
                                fontWeight: FontWeight.w500,
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                )
                    .animate(delay: 300.ms)
                    .fadeIn(duration: 400.ms)
                    .slideY(begin: 0.02),

                const SizedBox(height: 16),

                // ── Appointment details card ──
                _sectionCard(
                  isDark: isDark,
                  child: Column(
                    children: [
                      _detailRow(
                        Icons.calendar_today_rounded,
                        l10n.date,
                        '${_appointment.appointmentDate.day}/${_appointment.appointmentDate.month}/${_appointment.appointmentDate.year}',
                        isDark,
                      ),
                      const Divider(height: 24),
                      _detailRow(
                        Icons.access_time_rounded,
                        l10n.time,
                        _appointment.timeSlot,
                        isDark,
                      ),
                      const Divider(height: 24),
                      _detailRow(
                        Icons.medical_services_outlined,
                        l10n.type,
                        _appointment.typeDisplay,
                        isDark,
                      ),
                      const Divider(height: 24),
                      _detailRow(
                        Icons.local_hospital_outlined,
                        l10n.department,
                        _appointment.department,
                        isDark,
                      ),
                      if (_appointment.bookingReference != null) ...[
                        const Divider(height: 24),
                        _detailRow(
                          Icons.confirmation_number_outlined,
                          l10n.bookingRef,
                          _appointment.bookingReference!,
                          isDark,
                        ),
                      ],
                      if (_appointment.notes != null &&
                          _appointment.notes!.isNotEmpty) ...[
                        const Divider(height: 24),
                        _detailRow(
                          Icons.note_outlined,
                          l10n.patientNotes,
                          _appointment.notes!,
                          isDark,
                        ),
                      ],
                      if (_appointment.cancelReason != null) ...[
                        const Divider(height: 24),
                        _detailRow(
                          Icons.cancel_outlined,
                          l10n.cancelReason,
                          _appointment.cancelReason!,
                          isDark,
                        ),
                      ],
                    ],
                  ),
                )
                    .animate(delay: 400.ms)
                    .fadeIn(duration: 400.ms)
                    .slideY(begin: 0.02),

                const SizedBox(height: 16),

                // ── Medical notes section ──
                _sectionCard(
                  isDark: isDark,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Icon(
                            Icons.edit_note_rounded,
                            color: isDark
                                ? AppColors.textSecondaryDark
                                : AppColors.textSecondaryLight,
                          ),
                          const SizedBox(width: 8),
                          Text(
                            l10n.medicalNotes,
                            style: GoogleFonts.poppins(
                              fontSize: 16,
                              fontWeight: FontWeight.w600,
                              color: isDark
                                  ? AppColors.textPrimaryDark
                                  : AppColors.textPrimaryLight,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 12),
                      TextField(
                        controller: _notesController,
                        maxLines: 5,
                        decoration: InputDecoration(
                          hintText: l10n.addMedicalNotesHint,
                          hintStyle: GoogleFonts.roboto(
                            color: isDark
                                ? AppColors.textSecondaryDark
                                : AppColors.textSecondaryLight,
                          ),
                          filled: true,
                          fillColor:
                              isDark ? Colors.grey[900] : Colors.grey[50],
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(12),
                            borderSide: BorderSide.none,
                          ),
                        ),
                        style: GoogleFonts.roboto(
                          color: isDark
                              ? AppColors.textPrimaryDark
                              : AppColors.textPrimaryLight,
                        ),
                      ),
                      const SizedBox(height: 12),
                      Align(
                        alignment: Alignment.centerRight,
                        child: TextButton.icon(
                          onPressed: _saveMedicalNotes,
                          icon: const Icon(Icons.save_outlined, size: 18),
                          label: Text(l10n.saveNotes),
                        ),
                      ),
                      if (_appointment.medicalNotesUpdatedAt != null)
                        Padding(
                          padding: const EdgeInsets.only(top: 4),
                          child: Text(
                            '${l10n.lastUpdated} ${_formatDateTime(_appointment.medicalNotesUpdatedAt!)}',
                            style: GoogleFonts.roboto(
                              fontSize: 11,
                              color: isDark
                                  ? AppColors.textSecondaryDark
                                  : AppColors.textSecondaryLight,
                            ),
                          ),
                        ),
                    ],
                  ),
                ).animate(delay: 500.ms).fadeIn(duration: 400.ms)
              ],
            ),
          ),

          // ── Sticky bottom action buttons ──
          if (_appointment.status != AppointmentStatus.cancelled &&
              _appointment.status != AppointmentStatus.noShow)
            Positioned(
              left: 0,
              right: 0,
              bottom: 0,
              child: Container(
                decoration: BoxDecoration(
                  color: Theme.of(context).scaffoldBackgroundColor,
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withValues(alpha: 0.08),
                      blurRadius: 10,
                      offset: const Offset(0, -2),
                    ),
                  ],
                ),
                child: SafeArea(
                  top: false,
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(20, 16, 20, 24),
                    child: _buildActions(isDark, l10n),
                  ),
                ),
              ),
            ),

          if (_isSaving)
            Container(
              color: Colors.black.withValues(alpha: 0.3),
              child: const Center(child: CircularProgressIndicator()),
            ),
        ],
      ),
    );
  }

  // ---- actions section ----
  Widget _buildActions(bool isDark, AppLocalizations l10n) {
    final status = _appointment.status;

    if (status == AppointmentStatus.cancelled ||
        status == AppointmentStatus.noShow) {
      return const SizedBox.shrink();
    }

    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (status == AppointmentStatus.pending) ...[
          // ── Time-gated QR confirm button ──
          if (!_isInConfirmWindow)
            // Outside confirm window
            Column(
              children: [
                ElevatedButton.icon(
                  onPressed: null,
                  icon: const Icon(Icons.lock_clock),
                  label: Text(
                    _isBeforeConfirmWindow
                        ? _formatTimeUntilConfirm(l10n)
                        : l10n.confirmWindowExpired,
                  ),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.grey[300],
                    foregroundColor: Colors.grey[600],
                    disabledBackgroundColor: Colors.grey[300],
                    disabledForegroundColor: Colors.grey[600],
                    minimumSize: const Size.fromHeight(48),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                  ),
                ),
                const SizedBox(height: 12),
              ],
            )
          else if (_qrScanFailures < 5)
            // In window — QR scan required
            Column(
              children: [
                ElevatedButton.icon(
                  onPressed: _openQrScanner,
                  icon: const Icon(Icons.qr_code_scanner),
                  label: Text(l10n.scanQrToConfirm),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppColors.success,
                    foregroundColor: Colors.white,
                    minimumSize: const Size.fromHeight(48),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                  ),
                ),
                const SizedBox(height: 12),
              ],
            )
          else
            // In window — manual fallback after 5 failures
            Column(
              children: [
                ElevatedButton.icon(
                  onPressed: () => _updateStatus(AppointmentStatus.confirmed),
                  icon: const Icon(Icons.check_circle_outline),
                  label: Text(l10n.confirmManual),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppColors.success,
                    foregroundColor: Colors.white,
                    minimumSize: const Size.fromHeight(48),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                  ),
                ),
                const SizedBox(height: 12),
              ],
            ),
        ],
        if (status == AppointmentStatus.pending ||
            status == AppointmentStatus.confirmed) ...[
          ElevatedButton.icon(
            onPressed: _completeAppointment,
            icon: const Icon(Icons.task_alt_rounded),
            label: Text(l10n.completed),
            style: ElevatedButton.styleFrom(
              backgroundColor: AppColors.info,
              foregroundColor: Colors.white,
              minimumSize: const Size.fromHeight(48),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
              ),
            ),
          ),
          const SizedBox(height: 12),
          OutlinedButton.icon(
            onPressed: () => _updateStatus(AppointmentStatus.noShow),
            icon: const Icon(Icons.person_off_outlined),
            label: Text(l10n.noShowStatus),
            style: OutlinedButton.styleFrom(
              foregroundColor: Colors.grey[700],
              minimumSize: const Size.fromHeight(48),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
              ),
            ),
          ),
          const SizedBox(height: 12),
          OutlinedButton.icon(
            onPressed: _cancelWithReason,
            icon: const Icon(Icons.cancel_outlined),
            label: Text(l10n.cancel),
            style: OutlinedButton.styleFrom(
              foregroundColor: AppColors.error,
              side: const BorderSide(color: AppColors.error),
              minimumSize: const Size.fromHeight(48),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
              ),
            ),
          ),
        ],
        if (status == AppointmentStatus.completed) ...[
          // Already completed — only notes editing is meaningful
          Center(
            child: Padding(
              padding: const EdgeInsets.only(top: 8),
              child: Text(
                l10n.thisAppointmentIsCompleted,
                style: GoogleFonts.roboto(
                  color: isDark
                      ? AppColors.textSecondaryDark
                      : AppColors.textSecondaryLight,
                ),
              ),
            ),
          ),
        ],
      ],
    );
  }

  // ---- handlers ----

  Future<void> _updateStatus(AppointmentStatus status) async {
    setState(() => _isSaving = true);
    final l10n = AppLocalizations.of(context);
    final provider = context.read<DoctorAppointmentProvider>();
    final ok = await provider.updateStatus(
      _appointment.id,
      status,
      widget.doctor.id,
      statusUpdatedBy: widget.doctor.id,
      appointment: _appointment,
      doctorName: widget.doctor.name,
    );
    if (mounted) {
      if (ok) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(l10n.statusUpdatedTo(status.name)),
            backgroundColor: AppColors.success,
          ),
        );
        Navigator.pop(context);
      } else {
        setState(() => _isSaving = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(provider.error ?? 'Failed to update status'),
            backgroundColor: AppColors.error,
          ),
        );
      }
    }
  }

  Future<void> _completeAppointment() async {
    setState(() => _isSaving = true);
    final l10n = AppLocalizations.of(context);
    final provider = context.read<DoctorAppointmentProvider>();
    final notes = _notesController.text.trim().isEmpty
        ? null
        : _notesController.text.trim();
    final ok = await provider.completeAppointment(
      _appointment.id,
      widget.doctor.id,
      notes: notes,
      statusUpdatedBy: widget.doctor.id,
      appointment: _appointment,
      doctorName: widget.doctor.name,
    );
    if (mounted) {
      if (ok) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(l10n.appointmentCompleted),
            backgroundColor: AppColors.success,
          ),
        );
        Navigator.pop(context);
      } else {
        setState(() => _isSaving = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(provider.error ?? 'Failed to complete'),
            backgroundColor: AppColors.error,
          ),
        );
      }
    }
  }

  void _viewPatientProfile() {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => PatientDetailScreen(
          patientId: _appointment.patientId,
          patientName: _appointment.patientName,
          doctor: widget.doctor,
        ),
      ),
    );
  }

  Future<void> _cancelWithReason() async {
    final reasonController = TextEditingController();
    final l10n = AppLocalizations.of(context);
    final reason = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(l10n.cancelAppointmentDialogTitle),
        content: TextField(
          controller: reasonController,
          decoration: InputDecoration(
            hintText: l10n.reasonForCancellationHint,
          ),
          maxLines: 3,
          autofocus: true,
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: Text(l10n.back),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, reasonController.text.trim()),
            child: Text(l10n.confirmCancel),
          ),
        ],
      ),
    );
    reasonController.dispose();

    if (reason == null || reason.isEmpty) return;

    if (!mounted) return;
    setState(() => _isSaving = true);
    final provider = context.read<DoctorAppointmentProvider>();
    final ok = await provider.cancelAppointment(
      _appointment.id,
      reason,
      widget.doctor.id,
      statusUpdatedBy: widget.doctor.id,
      appointment: _appointment,
      doctorName: widget.doctor.name,
    );
    if (mounted) {
      if (ok) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(l10n.appointmentCancelled),
            backgroundColor: AppColors.success,
          ),
        );
        Navigator.pop(context);
      } else {
        setState(() => _isSaving = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(provider.error ?? 'Failed to cancel'),
            backgroundColor: AppColors.error,
          ),
        );
      }
    }
  }

  Future<void> _saveMedicalNotes() async {
    final notes = _notesController.text.trim();
    if (notes.isEmpty) return;

    setState(() => _isSaving = true);
    final provider = context.read<DoctorAppointmentProvider>();
    final ok = await provider.updateMedicalNotes(
      _appointment.id,
      notes,
      widget.doctor.id,
    );
    if (mounted) {
      if (ok) {
        setState(() {
          _appointment = _appointment.copyWith(
            medicalNotes: notes,
            medicalNotesUpdatedAt: DateTime.now(),
          );
          _isSaving = false;
        });
      } else {
        setState(() => _isSaving = false);
      }
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(ok ? 'Notes saved' : 'Failed to save notes'),
          backgroundColor: ok ? AppColors.success : AppColors.error,
        ),
      );
    }
  }

  // ---- reusable widgets ----

  Widget _sectionCard({required bool isDark, required Widget child}) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: isDark ? AppColors.surfaceDark : AppColors.surfaceLight,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.05),
            blurRadius: 10,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: child,
    );
  }

  Widget _detailRow(
    IconData icon,
    String label,
    String value,
    bool isDark,
  ) {
    return Row(
      children: [
        Icon(icon, size: 20, color: AppColors.primary),
        const SizedBox(width: 12),
        Text(
          label,
          style: GoogleFonts.roboto(
            fontSize: 14,
            color: isDark
                ? AppColors.textSecondaryDark
                : AppColors.textSecondaryLight,
          ),
        ),
        const Spacer(),
        Flexible(
          child: Text(
            value,
            style: GoogleFonts.poppins(
              fontSize: 14,
              fontWeight: FontWeight.w500,
              color: isDark
                  ? AppColors.textPrimaryDark
                  : AppColors.textPrimaryLight,
            ),
            textAlign: TextAlign.end,
            overflow: TextOverflow.ellipsis,
            maxLines: 2,
          ),
        ),
      ],
    );
  }

  String _formatDateTime(DateTime dt) {
    return '${dt.day}/${dt.month}/${dt.year} ${dt.hour.toString().padLeft(2, '0')}:${dt.minute.toString().padLeft(2, '0')}';
  }
}
