import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:provider/provider.dart';
import '../../../core/constants/app_colors.dart';
import '../../../core/widgets/loading_skeleton.dart';
import '../../../data/models/appointment_model.dart';
import '../../../data/models/doctor_model.dart';
import '../../../providers/doctor_appointment_provider.dart';
import '../../../l10n/app_localizations.dart';
import 'doctor_appointment_detail_screen.dart';

/// Doctor-facing appointments screen with Upcoming / Past tabs
class DoctorAppointmentsScreen extends StatefulWidget {
  final DoctorModel doctor;

  const DoctorAppointmentsScreen({super.key, required this.doctor});

  @override
  State<DoctorAppointmentsScreen> createState() =>
      _DoctorAppointmentsScreenState();
}

class _DoctorAppointmentsScreenState extends State<DoctorAppointmentsScreen>
    with SingleTickerProviderStateMixin {
  late TabController _tabController;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _loadAppointments();
    });
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  Future<void> _loadAppointments() async {
    final provider = context.read<DoctorAppointmentProvider>();
    await provider.loadAppointments(widget.doctor.id);
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final l10n = AppLocalizations.of(context);

    return Consumer<DoctorAppointmentProvider>(
      builder: (context, provider, child) {
        return Scaffold(
          appBar: AppBar(
            title: Text(
              l10n.appointments,
              style: GoogleFonts.poppins(fontWeight: FontWeight.w600),
            ),
            bottom: TabBar(
              controller: _tabController,
              tabs: [
                Tab(text: l10n.upcoming),
                Tab(text: l10n.past),
              ],
            ),
          ),
          body: TabBarView(
            controller: _tabController,
             children: [
              _buildList(
                provider.upcomingAppointments,
                true,
                isDark,
                provider.isLoading,
                l10n,
                provider,
              ),
              _buildList(
                provider.pastAppointments,
                false,
                isDark,
                provider.isLoading,
                l10n,
                provider,
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _buildList(
    List<AppointmentModel> appointments,
    bool isUpcoming,
    bool isDark,
    bool isLoading,
    AppLocalizations l10n,
    DoctorAppointmentProvider provider,
  ) {
    if (isLoading) {
      return ListView.separated(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 100),
        itemCount: 3,
        separatorBuilder: (_, __) => const SizedBox(height: 12),
        itemBuilder: (_, __) => const AppointmentCardSkeleton(),
      );
    }

    if (appointments.isEmpty) {
      return SingleChildScrollView(
        physics: const AlwaysScrollableScrollPhysics(),
        child: SizedBox(
          height: MediaQuery.of(context).size.height * 0.6,
          child: Center(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(
                  isUpcoming
                      ? Icons.calendar_today_outlined
                      : Icons.history_rounded,
                  size: 80,
                  color: isDark ? Colors.grey[600] : Colors.grey[400],
                ),
                const SizedBox(height: 16),
                Text(
                  isUpcoming
                      ? l10n.noUpcomingAppointments
                      : l10n.noPastAppointments,
                  style: GoogleFonts.poppins(
                    fontSize: 18,
                    fontWeight: FontWeight.w600,
                    color: isDark
                        ? AppColors.textPrimaryDark
                        : AppColors.textPrimaryLight,
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  isUpcoming
                      ? l10n.noUpcomingPatientVisits
                      : l10n.noPastAppointments,
                  style: GoogleFonts.roboto(
                    fontSize: 14,
                    color: isDark
                        ? AppColors.textSecondaryDark
                        : AppColors.textSecondaryLight,
                  ),
                  textAlign: TextAlign.center,
                ),
              ],
            ),
          ),
        ),
      );
    }

    return RefreshIndicator(
      onRefresh: _loadAppointments,
      child: ListView.separated(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 100),
        itemCount: appointments.length,
        separatorBuilder: (_, __) => const SizedBox(height: 12),
        itemBuilder: (context, index) {
          final appointment = appointments[index];
          final patientPhoto =
              provider.patientPhotos[appointment.patientId];
          return _DoctorAppointmentCard(
            appointment: appointment,
            isDark: isDark,
            photoUrl: patientPhoto,
            onTap: () => _openDetail(appointment),
          )
              .animate(delay: Duration(milliseconds: index * 100))
              .fadeIn(duration: 400.ms)
              .slideX(begin: 0.05);
        },
      ),
    );
  }

  void _openDetail(AppointmentModel appointment) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => DoctorAppointmentDetailScreen(
          appointment: appointment,
          doctor: widget.doctor,
        ),
      ),
    ).then((_) => _loadAppointments());
  }
}

// ---------------------------------------------------------------------------
// Card widget — doctor-facing (shows patient info, not doctor info)
// ---------------------------------------------------------------------------
class _DoctorAppointmentCard extends StatelessWidget {
  final AppointmentModel appointment;
  final bool isDark;
  final String? photoUrl;
  final VoidCallback onTap;

  const _DoctorAppointmentCard({
    required this.appointment,
    required this.isDark,
    this.photoUrl,
    required this.onTap,
  });

  Color get _statusColor {
    switch (appointment.status) {
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

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);

    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: isDark ? AppColors.surfaceDark : AppColors.surfaceLight,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
            color: _statusColor.withValues(alpha: 0.3),
            width: 1.5,
          ),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.05),
              blurRadius: 10,
              offset: const Offset(0, 2),
            ),
          ],
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Header — patient info
            Row(
              children: [
                Container(
                  width: 50,
                  height: 50,
                  decoration: BoxDecoration(
                    color: AppColors.secondary.withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(12),
                    child: photoUrl != null && photoUrl!.isNotEmpty
                        ? Image.network(
                            photoUrl!,
                            width: 50,
                            height: 50,
                            fit: BoxFit.cover,
                            errorBuilder: (_, __, ___) => Center(
                              child: Text(
                                appointment.patientName.isNotEmpty
                                    ? appointment.patientName[0].toUpperCase()
                                    : '?',
                                style: GoogleFonts.outfit(
                                  fontSize: 22,
                                  fontWeight: FontWeight.bold,
                                  color: AppColors.secondary,
                                ),
                              ),
                            ),
                          )
                        : Center(
                            child: Text(
                              appointment.patientName.isNotEmpty
                                  ? appointment.patientName[0].toUpperCase()
                                  : '?',
                              style: GoogleFonts.outfit(
                                fontSize: 22,
                                fontWeight: FontWeight.bold,
                                color: AppColors.secondary,
                              ),
                            ),
                          ),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        appointment.patientName,
                        style: GoogleFonts.poppins(
                          fontSize: 16,
                          fontWeight: FontWeight.w600,
                          color: isDark
                              ? AppColors.textPrimaryDark
                              : AppColors.textPrimaryLight,
                        ),
                      ),
                      Text(
                        appointment.typeDisplay,
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
                    horizontal: 10,
                    vertical: 4,
                  ),
                  decoration: BoxDecoration(
                    color: _statusColor.withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: Text(
                    appointment.statusDisplay,
                    style: GoogleFonts.roboto(
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                      color: (appointment.status == AppointmentStatus.pending &&
                              !isDark)
                          ? Colors.orange.shade900
                          : _statusColor,
                    ),
                  ),
                ),
              ],
            ),

            const SizedBox(height: 16),
            const Divider(height: 1),
            const SizedBox(height: 16),

            // Date + time row
            Row(
              children: [
                Expanded(
                  child: Row(
                    children: [
                      Icon(
                        Icons.calendar_today_rounded,
                        size: 18,
                        color: isDark
                            ? AppColors.textSecondaryDark
                            : AppColors.textSecondaryLight,
                      ),
                      const SizedBox(width: 8),
                      Text(
                        _formatDate(appointment.appointmentDate, l10n),
                        style: GoogleFonts.roboto(
                          fontSize: 13,
                          fontWeight: FontWeight.w500,
                          color: isDark
                              ? AppColors.textPrimaryDark
                              : AppColors.textPrimaryLight,
                        ),
                      ),
                    ],
                  ),
                ),
                Expanded(
                  child: Row(
                    children: [
                      Icon(
                        Icons.access_time_rounded,
                        size: 18,
                        color: isDark
                            ? AppColors.textSecondaryDark
                            : AppColors.textSecondaryLight,
                      ),
                      const SizedBox(width: 8),
                      Text(
                        appointment.timeSlot.split(' - ').first,
                        style: GoogleFonts.roboto(
                          fontSize: 13,
                          fontWeight: FontWeight.w500,
                          color: isDark
                              ? AppColors.textPrimaryDark
                              : AppColors.textPrimaryLight,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),

            // Quick-action chips for actionable statuses
            if (appointment.status == AppointmentStatus.pending ||
                appointment.status == AppointmentStatus.confirmed) ...[
              const SizedBox(height: 12),
              Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  Icon(
                    Icons.chevron_right_rounded,
                    color: isDark
                        ? AppColors.textSecondaryDark
                        : AppColors.textSecondaryLight,
                  ),
                ],
              ),
            ],
          ],
        ),
      ),
    );
  }

  String _formatDate(DateTime date, AppLocalizations l10n) {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final tomorrow = today.add(const Duration(days: 1));
    final appointmentDay = DateTime(date.year, date.month, date.day);

    if (appointmentDay == today) return l10n.today;
    if (appointmentDay == tomorrow) return l10n.tomorrow;
    return '${date.day}/${date.month}/${date.year}';
  }
}
