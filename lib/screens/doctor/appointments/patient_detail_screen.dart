import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:intl/intl.dart';
import '../../../l10n/app_localizations.dart';
import '../../../core/constants/app_colors.dart';
import '../../../core/widgets/glassmorphic_card.dart';
import '../../../core/widgets/loading_skeleton.dart';
import '../../../data/models/appointment_model.dart';
import '../../../data/models/doctor_model.dart';
import '../../../data/models/user_model.dart';
import '../../../data/repositories/appointment_repository.dart';
import '../../../core/utils/locale_utils.dart';
import 'doctor_appointment_detail_screen.dart';

/// Shows a patient's profile + appointment history with the current doctor.
///
/// Navigated-to from the appointment detail screen when the doctor taps
/// on the patient name.
class PatientDetailScreen extends StatefulWidget {
  final String patientId;
  final String patientName;
  final DoctorModel doctor;

  const PatientDetailScreen({
    super.key,
    required this.patientId,
    required this.patientName,
    required this.doctor,
  });

  @override
  State<PatientDetailScreen> createState() => _PatientDetailScreenState();
}

class _PatientDetailScreenState extends State<PatientDetailScreen> {
  final AppointmentRepository _appointmentRepo = AppointmentRepository();

  UserModel? _patient;
  List<AppointmentModel> _history = [];
  bool _isLoading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _loadData();
  }

  Future<void> _loadData() async {
    setState(() {
      _isLoading = true;
      _error = null;
    });

    try {
      // Load patient profile + appointment history in parallel
      final results = await Future.wait([
        _loadPatient(),
        _loadHistory(),
      ]);
      if (mounted) {
        setState(() {
          _patient = results[0] as UserModel?;
          _history = results[1] as List<AppointmentModel>;
          _isLoading = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _error = e.toString();
          _isLoading = false;
        });
      }
    }
  }

  Future<UserModel?> _loadPatient() async {
    try {
      final doc = await FirebaseFirestore.instance
          .collection('users')
          .doc(widget.patientId)
          .get();
      if (doc.exists) {
        return UserModel.fromFirestore(doc);
      }
    } catch (_) {}
    return null;
  }

  Future<List<AppointmentModel>> _loadHistory() async {
    return _appointmentRepo.getPatientAppointmentsWithDoctor(
      widget.patientId,
      widget.doctor.id,
    );
  }

  // ---- build ----
  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final l10n = AppLocalizations.of(context);

    return Scaffold(
      appBar: AppBar(
        title: Text(
          widget.patientName,
          style: GoogleFonts.poppins(fontWeight: FontWeight.w600),
        ),
        centerTitle: true,
      ),
      body: _isLoading
          ? _buildSkeleton()
          : _error != null
              ? _buildError(isDark, l10n)
              : RefreshIndicator(
                  onRefresh: _loadData,
                  child: SingleChildScrollView(
                    physics: const AlwaysScrollableScrollPhysics(),
                    padding: const EdgeInsets.fromLTRB(20, 8, 20, 100),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        _buildProfileCard(isDark, l10n),
                        const SizedBox(height: 20),
                        _buildInfoGrid(isDark, l10n),
                        const SizedBox(height: 24),
                        _buildHistorySection(isDark, l10n),
                      ],
                    ),
                  ),
                ),
    );
  }

  // ---- profile card ----
  Widget _buildProfileCard(bool isDark, AppLocalizations l10n) {
    final patient = _patient;

    return GradientCard(
      colors: AppColors.primaryGradient,
      child: Row(
        children: [
          // Avatar
          CircleAvatar(
            radius: 32,
            backgroundColor: Colors.white.withValues(alpha: 0.2),
            backgroundImage: patient?.photoUrl != null
                ? NetworkImage(patient!.photoUrl!)
                : null,
            child: patient?.photoUrl == null
                ? Text(
                    _initials(patient?.fullName ?? widget.patientName),
                    style: GoogleFonts.outfit(
                      fontSize: 22,
                      fontWeight: FontWeight.bold,
                      color: Colors.white,
                    ),
                  )
                : null,
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  patient?.fullName ?? widget.patientName,
                  style: GoogleFonts.poppins(
                    fontSize: 20,
                    fontWeight: FontWeight.bold,
                    color: Colors.white,
                  ),
                ),
                if (patient?.email != null)
                  Text(
                    patient!.email,
                    style: GoogleFonts.plusJakartaSans(
                      fontSize: 14,
                      fontWeight: FontWeight.w500,
                      color: Colors.white.withValues(alpha: 0.8),
                    ),
                  ),
                const SizedBox(height: 6),
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 4,
                  ),
                  decoration: BoxDecoration(
                    color: Colors.white.withValues(alpha: 0.2),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Text(
                    l10n.visitsCount(_history.length),
                    style: GoogleFonts.roboto(
                      fontSize: 12,
                      fontWeight: FontWeight.w500,
                      color: Colors.white,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    ).animate(delay: 300.ms).fadeIn(duration: 500.ms).slideY(begin: -0.05);
  }

  // ---- info grid ----
  Widget _buildInfoGrid(bool isDark, AppLocalizations l10n) {
    final patient = _patient;
    if (patient == null) return const SizedBox.shrink();

    final items = <_InfoItem>[];

    if (patient.phoneNumber != null && patient.phoneNumber!.isNotEmpty) {
      items.add(_InfoItem(
        icon: Icons.phone_rounded,
        label: l10n.phone,
        value: patient.phoneNumber!,
        color: AppColors.primary,
      ));
    }
    if (patient.dateOfBirth != null) {
      items.add(_InfoItem(
        icon: Icons.cake_rounded,
        label: l10n.dateOfBirth,
        value: DateFormat('dd MMM yyyy').format(patient.dateOfBirth!),
        color: AppColors.info,
      ));
    }
    if (patient.bloodType != null && patient.bloodType!.isNotEmpty) {
      items.add(_InfoItem(
        icon: Icons.bloodtype_rounded,
        label: l10n.bloodType,
        value: patient.bloodType!,
        color: AppColors.error,
      ));
    }
    if (patient.allergies != null && patient.allergies!.isNotEmpty) {
      items.add(_InfoItem(
        icon: Icons.warning_amber_rounded,
        label: l10n.allergies,
        value: patient.allergies!,
        color: AppColors.warning,
      ));
    }
    if (patient.studentId != null && patient.studentId!.isNotEmpty) {
      items.add(_InfoItem(
        icon: Icons.badge_rounded,
        label: l10n.studentId,
        value: patient.studentId!,
        color: AppColors.secondary,
      ));
    }

    if (items.isEmpty) return const SizedBox.shrink();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          l10n.patientInformation,
          style: GoogleFonts.poppins(
            fontSize: 18,
            fontWeight: FontWeight.w600,
            color:
                isDark ? AppColors.textPrimaryDark : AppColors.textPrimaryLight,
          ),
        ),
        const SizedBox(height: 12),
        Wrap(
          spacing: 10,
          runSpacing: 10,
          children: items.map((item) => _infoTile(item, isDark)).toList(),
        ),
      ],
    ).animate(delay: 400.ms).fadeIn(duration: 400.ms).slideY(begin: 0.02);
  }

  Widget _infoTile(_InfoItem item, bool isDark) {
    return Container(
      width: (MediaQuery.of(context).size.width - 50) / 2, // 2 columns
      padding: const EdgeInsets.all(14),
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
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: item.color.withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Icon(item.icon, color: item.color, size: 18),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  item.label,
                  style: GoogleFonts.roboto(
                    fontSize: 11,
                    color: isDark
                        ? AppColors.textSecondaryDark
                        : AppColors.textSecondaryLight,
                  ),
                ),
                FittedBox(
                  fit: BoxFit.scaleDown,
                  alignment: AlignmentDirectional.centerStart,
                  child: Text(
                    item.value,
                    style: GoogleFonts.poppins(
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                      color: isDark
                          ? AppColors.textPrimaryDark
                          : AppColors.textPrimaryLight,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  // ---- history ----
  Widget _buildHistorySection(bool isDark, AppLocalizations l10n) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          l10n.appointmentHistory,
          style: GoogleFonts.poppins(
            fontSize: 18,
            fontWeight: FontWeight.w600,
            color:
                isDark ? AppColors.textPrimaryDark : AppColors.textPrimaryLight,
          ),
        ),
        const SizedBox(height: 10),
        if (_history.isEmpty)
          Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(vertical: 40),
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
            child: Column(
              children: [
                Icon(
                  Icons.history_rounded,
                  size: 48,
                  color: isDark ? Colors.grey[600] : Colors.grey[400],
                ),
                const SizedBox(height: 12),
                Text(
                  l10n.noAppointmentHistory,
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
          )
        else
          ..._history.map((appt) => _historyCard(appt, isDark)),
      ],
    ).animate(delay: 500.ms).fadeIn(duration: 400.ms).slideY(begin: 0.02);
  }

  Widget _historyCard(AppointmentModel appt, bool isDark) {
    final statusColor = _statusColor(appt.status);

    return GestureDetector(
      onTap: () {
        Navigator.push(
          context,
          MaterialPageRoute(
            builder: (_) => DoctorAppointmentDetailScreen(
              appointment: appt,
              doctor: widget.doctor,
            ),
          ),
        ).then((_) => _loadData());
      },
      child: Container(
        margin: const EdgeInsets.only(bottom: 10),
        padding: const EdgeInsets.all(14),
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
        child: Row(
          children: [
            // Date badge
            Container(
              width: 48,
              padding: const EdgeInsets.symmetric(vertical: 6),
              decoration: BoxDecoration(
                color: statusColor.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Column(
                children: [
                  Text(
                    _monthAbbr(appt.appointmentDate.month),
                    style: GoogleFonts.roboto(
                      fontSize: 10,
                      fontWeight: FontWeight.w600,
                      color: statusColor,
                    ),
                  ),
                  Text(
                    '${appt.appointmentDate.day}',
                    style: GoogleFonts.poppins(
                      fontSize: 18,
                      fontWeight: FontWeight.w700,
                      color: statusColor,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    appt.typeDisplay,
                    style: GoogleFonts.poppins(
                      fontSize: 14,
                      fontWeight: FontWeight.w600,
                      color: isDark
                          ? AppColors.textPrimaryDark
                          : AppColors.textPrimaryLight,
                    ),
                  ),
                  Text(
                    '${appt.timeSlot} • ${appt.statusDisplay}',
                    style: GoogleFonts.roboto(
                      fontSize: 12,
                      color: isDark
                          ? AppColors.textSecondaryDark
                          : AppColors.textSecondaryLight,
                    ),
                  ),
                ],
              ),
            ),
            Icon(
              Icons.chevron_right_rounded,
              color: isDark
                  ? AppColors.textSecondaryDark
                  : AppColors.textSecondaryLight,
              size: 20,
            ),
          ],
        ),
      ),
    );
  }

  // ---- skeleton ----
  Widget _buildSkeleton() {
    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(20, 8, 20, 100),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const CardSkeleton(height: 130),
          const SizedBox(height: 20),
          const LoadingSkeleton(width: 160, height: 20),
          const SizedBox(height: 12),
          Row(
            children: const [
              Expanded(child: CardSkeleton(height: 70)),
              SizedBox(width: 10),
              Expanded(child: CardSkeleton(height: 70)),
            ],
          ),
          const SizedBox(height: 10),
          Row(
            children: const [
              Expanded(child: CardSkeleton(height: 70)),
              SizedBox(width: 10),
              Expanded(child: CardSkeleton(height: 70)),
            ],
          ),
          const SizedBox(height: 28),
          const LoadingSkeleton(width: 180, height: 20),
          const SizedBox(height: 12),
          SkeletonList(
            itemCount: 3,
            itemBuilder: (ctx, i) => const AppointmentCardSkeleton(),
          ),
        ],
      ),
    );
  }

  // ---- error ----
  Widget _buildError(bool isDark, AppLocalizations l10n) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(Icons.error_outline_rounded,
                size: 48, color: AppColors.error),
            const SizedBox(height: 16),
            Text(
              l10n.failedToLoadPatientData,
              style: GoogleFonts.poppins(
                fontSize: 16,
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              _error ?? '',
              textAlign: TextAlign.center,
              style: GoogleFonts.roboto(
                fontSize: 13,
                color: isDark
                    ? AppColors.textSecondaryDark
                    : AppColors.textSecondaryLight,
              ),
            ),
            const SizedBox(height: 20),
            ElevatedButton.icon(
              onPressed: _loadData,
              icon: const Icon(Icons.refresh_rounded),
              label: Text(l10n.retry),
              style: ElevatedButton.styleFrom(
                backgroundColor: AppColors.primary,
                foregroundColor: Colors.white,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ---- helpers ----
  String _initials(String name) {
    final parts = name.trim().split(RegExp(r'\s+'));
    if (parts.length >= 2) {
      return '${parts.first[0]}${parts.last[0]}'.toUpperCase();
    }
    return name.isNotEmpty ? name[0].toUpperCase() : '?';
  }

  Color _statusColor(AppointmentStatus status) {
    switch (status) {
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

  String _monthAbbr(int month) {
    final locale = safeIntlLocale(context);
    return DateFormat('MMM', locale).format(DateTime(0, month)).toUpperCase();
  }
}

class _InfoItem {
  final IconData icon;
  final String label;
  final String value;
  final Color color;

  const _InfoItem({
    required this.icon,
    required this.label,
    required this.value,
    required this.color,
  });
}
