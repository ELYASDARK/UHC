import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:intl/intl.dart' as intl;
import 'package:provider/provider.dart';
import '../../../core/constants/app_colors.dart';
import '../../../core/widgets/glassmorphic_card.dart';
import '../../../core/widgets/loading_skeleton.dart';
import '../../../data/models/appointment_model.dart';
import '../../../data/models/doctor_model.dart';
import '../../../l10n/app_localizations.dart';
import '../../../providers/doctor_appointment_provider.dart';
import '../../../providers/notification_provider.dart';
import '../../../services/doctor_functions_service.dart';
import '../../../core/utils/locale_utils.dart';
import '../../../core/widgets/responsive_layout.dart';
import '../appointments/doctor_appointment_detail_screen.dart';

/// Doctor dashboard — overview of today's work
///
/// Sections:
///   1. Greeting + availability toggle
///   2. Stats row (Today, Upcoming, Completed, Pending)
///   3. Next appointment card
///   4. Today's appointments list
class DoctorDashboardScreen extends StatefulWidget {
  final DoctorModel doctor;
  final VoidCallback? onDoctorUpdated;
  final VoidCallback? onNotificationsTap;

  const DoctorDashboardScreen({
    super.key,
    required this.doctor,
    this.onDoctorUpdated,
    this.onNotificationsTap,
  });

  @override
  State<DoctorDashboardScreen> createState() => _DoctorDashboardScreenState();
}

class _DoctorDashboardScreenState extends State<DoctorDashboardScreen> {
  late DoctorModel _doctor;
  final DoctorFunctionsService _doctorFunctions = DoctorFunctionsService();
  bool _togglingAvailability = false;

  @override
  void initState() {
    super.initState();
    _doctor = widget.doctor;

    // Configure daily notifications and load appointments
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final provider = context.read<DoctorAppointmentProvider>();

      // Set up daily 9 PM notification config (uses doctor's weeklySchedule)
      provider.configureDailyNotifications(
        doctorUserId: _doctor.userId,
        weeklySchedule: _doctor.weeklySchedule,
        dailyNotificationTime: _doctor.dailyNotificationTime,
      );

      if (provider.appointments.isEmpty && !provider.isLoading) {
        provider.loadDashboardAppointments(_doctor.id);
      }
    });
  }

  @override
  void didUpdateWidget(covariant DoctorDashboardScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.doctor != oldWidget.doctor) {
      setState(() => _doctor = widget.doctor);
    }
  }

  // ---- build ----
  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final l10n = AppLocalizations.of(context);

    return Consumer<DoctorAppointmentProvider>(
      builder: (context, provider, _) {
        final isWide = UhcResponsive.isWide(context);
        return Scaffold(
          body: SafeArea(
            bottom: false,
            child: provider.isLoading
                ? _buildSkeleton(isDark)
                : RefreshIndicator(
                    onRefresh: () =>
                        provider.loadDashboardAppointments(_doctor.id),
                    child: ResponsivePage(
                      physics: const AlwaysScrollableScrollPhysics(),
                      maxWidth: 1560,
                      bottomPadding: isWide ? 32 : 100,
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          if (isWide)
                            Row(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Expanded(
                                  flex: 5,
                                  child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      _buildGreetingCard(isDark, l10n),
                                      const SizedBox(height: 24),
                                      _buildStatsRow(isDark, provider, l10n),
                                      const SizedBox(height: 28),
                                      _buildNextAppointment(
                                        isDark,
                                        provider,
                                        l10n,
                                      ),
                                    ],
                                  ),
                                ),
                                const SizedBox(width: 28),
                                Expanded(
                                  flex: 4,
                                  child: _buildTodaysList(
                                    isDark,
                                    provider,
                                    l10n,
                                  ),
                                ),
                              ],
                            )
                          else ...[
                            _buildGreetingCard(isDark, l10n),
                            const SizedBox(height: 24),
                            _buildStatsRow(isDark, provider, l10n),
                            const SizedBox(height: 28),
                            _buildNextAppointment(isDark, provider, l10n),
                            const SizedBox(height: 28),
                            _buildTodaysList(isDark, provider, l10n),
                          ],
                        ],
                      ),
                    ),
                  ),
          ),
        );
      },
    );
  }

  // ---- 1. Greeting + availability toggle (Merged with Profile & Notifications) ----
  Widget _buildGreetingCard(bool isDark, AppLocalizations l10n) {
    final hour = DateTime.now().hour;
    final greeting = hour < 12
        ? l10n.goodMorning
        : hour < 17
            ? l10n.goodAfternoon
            : l10n.goodEvening;
    final hasPendingAvailabilityRequest = _doctor.hasPendingAvailabilityRequest;
    final availabilityDotColor = hasPendingAvailabilityRequest
        ? AppColors.warning
        : _doctor.isAvailable
            ? AppColors.success
            : Colors.grey.shade400;
    final availabilityLabel = hasPendingAvailabilityRequest
        ? 'Pending approval'
        : _doctor.isAvailable
            ? l10n.available
            : l10n.unavailable;

    return GradientCard(
      colors: AppColors.primaryGradient,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Left side: Profile + Text
              Expanded(
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.center,
                  children: [
                    // Profile Image
                    GestureDetector(
                      onTap: () {},
                      child: Container(
                        width: 58,
                        height: 58,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          border: Border.all(
                            color: Colors.white,
                            width: 2.5,
                          ),
                          boxShadow: [
                            BoxShadow(
                              color: Colors.black.withValues(alpha: 0.15),
                              blurRadius: 10,
                              offset: const Offset(0, 4),
                            ),
                          ],
                        ),
                        child: ClipOval(
                          child: _doctor.photoUrl != null &&
                                  _doctor.photoUrl!.isNotEmpty
                              ? Image.network(
                                  _doctor.photoUrl!,
                                  fit: BoxFit.cover,
                                  errorBuilder: (_, __, ___) =>
                                      _buildCardFallbackAvatar(),
                                )
                              : _buildCardFallbackAvatar(),
                        ),
                      ),
                    ),
                    const SizedBox(width: 16),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            greeting,
                            style: GoogleFonts.plusJakartaSans(
                              fontSize: 14,
                              fontWeight: FontWeight.w500,
                              color: Colors.white.withValues(alpha: 0.8),
                            ),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            'Dr. ${_doctor.name}',
                            style: GoogleFonts.poppins(
                              fontSize: 20,
                              fontWeight: FontWeight.bold,
                              color: Colors.white,
                              height: 1.2,
                            ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                          const SizedBox(height: 2),
                          Text(
                            _doctor.specialization,
                            style: GoogleFonts.roboto(
                              fontSize: 13,
                              color: Colors.white.withValues(alpha: 0.9),
                            ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 12),
              // Right side: Notification Bell
              Consumer<NotificationProvider>(
                builder: (context, notifProvider, _) {
                  final hasUnread = notifProvider.unreadCount > 0;
                  return GestureDetector(
                    onTap: () {
                      if (hasUnread) {
                        notifProvider.markAllAsRead(_doctor.userId);
                      }
                      widget.onNotificationsTap?.call();
                    },
                    child: Container(
                      width: 44,
                      height: 44,
                      decoration: BoxDecoration(
                        color: Colors.white.withValues(alpha: 0.15),
                        shape: BoxShape.circle,
                        border: Border.all(
                          color: Colors.white.withValues(alpha: 0.2),
                          width: 1,
                        ),
                      ),
                      child: Stack(
                        alignment: Alignment.center,
                        children: [
                          const Icon(
                            Icons.notifications_none_rounded,
                            size: 24,
                            color: Colors.white,
                          ),
                          if (hasUnread)
                            Positioned(
                              top: 10,
                              right: 12,
                              child: Container(
                                width: 8,
                                height: 8,
                                decoration: BoxDecoration(
                                  color: AppColors.error,
                                  shape: BoxShape.circle,
                                  border: Border.all(
                                    color: AppColors.primary,
                                    width: 1.5,
                                  ),
                                ),
                              ),
                            ),
                        ],
                      ),
                    ),
                  );
                },
              ),
            ],
          ),
          const SizedBox(height: 24),
          // Availability toggle
          Row(
            children: [
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(
                    color: Colors.white.withValues(alpha: 0.3),
                    width: 1,
                  ),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Container(
                      width: 10,
                      height: 10,
                      decoration: BoxDecoration(
                        color: _doctor.isAvailable
                            ? availabilityDotColor
                            : Colors.grey.shade400,
                        shape: BoxShape.circle,
                        boxShadow: [
                          if (_doctor.isAvailable)
                            BoxShadow(
                              color:
                                  availabilityDotColor.withValues(alpha: 0.4),
                              blurRadius: 6,
                              spreadRadius: 1,
                            )
                        ],
                      ),
                    ),
                    const SizedBox(width: 8),
                    Text(
                      availabilityLabel,
                      style: GoogleFonts.roboto(
                        fontSize: 14,
                        fontWeight: FontWeight.w600,
                        color: Colors.white,
                      ),
                    ),
                  ],
                ),
              ),
              const Spacer(),
              _togglingAvailability
                  ? const SizedBox(
                      width: 24,
                      height: 24,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: Colors.white,
                      ),
                    )
                  : Switch(
                      value: _doctor.isAvailable,
                      onChanged: hasPendingAvailabilityRequest
                          ? null
                          : _toggleAvailability,
                      activeThumbColor: Colors.white,
                      activeTrackColor:
                          AppColors.success.withValues(alpha: 0.8),
                      inactiveTrackColor: Colors.white.withValues(alpha: 0.2),
                      inactiveThumbColor: Colors.white70,
                    ),
            ],
          ),
          if (hasPendingAvailabilityRequest) ...[
            const SizedBox(height: 12),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
              decoration: BoxDecoration(
                color: Colors.white.withValues(alpha: 0.14),
                borderRadius: BorderRadius.circular(14),
                border: Border.all(
                  color: Colors.white.withValues(alpha: 0.22),
                  width: 1,
                ),
              ),
              child: Row(
                children: [
                  const Icon(
                    Icons.hourglass_top_rounded,
                    color: Colors.white,
                    size: 18,
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      'You remain available while admin reviews your request.',
                      style: GoogleFonts.roboto(
                        color: Colors.white,
                        fontSize: 12.5,
                        fontWeight: FontWeight.w500,
                        height: 1.25,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ],
      ),
    ).animate(delay: 300.ms).fadeIn(duration: 500.ms).slideY(begin: -0.05);
  }

  Widget _buildCardFallbackAvatar() {
    return Container(
      color: Colors.white.withValues(alpha: 0.2),
      child: Center(
        child: Text(
          _doctor.name.isNotEmpty ? _doctor.name[0].toUpperCase() : '?',
          style: GoogleFonts.poppins(
            fontSize: 22,
            fontWeight: FontWeight.w600,
            color: Colors.white,
          ),
        ),
      ),
    );
  }

  // ---- 2. Stats row ----
  Widget _buildStatsRow(
      bool isDark, DoctorAppointmentProvider provider, AppLocalizations l10n) {
    final now = DateTime.now();
    final startOfDay = DateTime(now.year, now.month, now.day);
    final endOfDay = startOfDay.add(const Duration(days: 1));
    final todayAppts = provider.appointments.where((apt) {
      return apt.appointmentDate.isAfter(
            startOfDay.subtract(const Duration(seconds: 1)),
          ) &&
          apt.appointmentDate.isBefore(endOfDay);
    });
    final pending =
        todayAppts.where((a) => a.status == AppointmentStatus.pending).length;
    final completed =
        todayAppts.where((a) => a.status == AppointmentStatus.completed).length;

    return Row(
      children: [
        _statTile(
          isDark,
          '${provider.todayCount}',
          l10n.today,
          Icons.today_rounded,
          AppColors.primary,
        ),
        const SizedBox(width: 10),
        _statTile(
          isDark,
          '${provider.upcomingAppointments.length}',
          l10n.upcoming,
          Icons.upcoming_rounded,
          AppColors.info,
        ),
        const SizedBox(width: 10),
        _statTile(
          isDark,
          '$completed',
          l10n.completed,
          Icons.task_alt_rounded,
          AppColors.success,
        ),
        const SizedBox(width: 10),
        _statTile(
          isDark,
          '$pending',
          l10n.pending,
          Icons.pending_actions_rounded,
          AppColors.warning,
        ),
      ],
    ).animate(delay: 400.ms).fadeIn(duration: 400.ms).slideY(begin: 0.02);
  }

  Widget _statTile(
    bool isDark,
    String value,
    String label,
    IconData icon,
    Color color,
  ) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 8),
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
            Container(
              width: 40,
              height: 40,
              decoration: BoxDecoration(
                color: color.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Icon(icon, color: color, size: 22),
            ),
            const SizedBox(height: 8),
            Text(
              value,
              style: GoogleFonts.poppins(
                fontSize: 24,
                fontWeight: FontWeight.bold,
                color: isDark
                    ? AppColors.textPrimaryDark
                    : AppColors.textPrimaryLight,
              ),
            ),
            Text(
              label,
              style: GoogleFonts.roboto(
                fontSize: 11,
                color: isDark
                    ? AppColors.textSecondaryDark
                    : AppColors.textSecondaryLight,
              ),
              overflow: TextOverflow.ellipsis,
            ),
          ],
        ),
      ),
    );
  }

  // ---- 3. Next appointment ----
  Widget _buildNextAppointment(
    bool isDark,
    DoctorAppointmentProvider provider,
    AppLocalizations l10n,
  ) {
    final next = provider.nextAppointment;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          l10n.nextAppointment,
          style: GoogleFonts.poppins(
            fontSize: 18,
            fontWeight: FontWeight.w600,
            color:
                isDark ? AppColors.textPrimaryDark : AppColors.textPrimaryLight,
          ),
        ),
        const SizedBox(height: 12),
        if (next == null)
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(24),
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
                  Icons.event_available_rounded,
                  size: 40,
                  color: isDark
                      ? AppColors.textSecondaryDark
                      : AppColors.textSecondaryLight,
                ),
                const SizedBox(height: 8),
                Text(
                  l10n.noUpcomingAppointments,
                  style: GoogleFonts.roboto(
                    fontSize: 14,
                    color: isDark
                        ? AppColors.textSecondaryDark
                        : AppColors.textSecondaryLight,
                  ),
                ),
              ],
            ),
          )
        else
          GestureDetector(
            onTap: () => _openDetail(next),
            child: Container(
              width: double.infinity,
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: isDark ? AppColors.surfaceDark : AppColors.surfaceLight,
                borderRadius: BorderRadius.circular(16),
                border: Border.all(
                  color: AppColors.primary.withValues(alpha: 0.3),
                  width: 1.5,
                ),
                boxShadow: [
                  BoxShadow(
                    color: AppColors.primary.withValues(alpha: 0.06),
                    blurRadius: 10,
                    offset: const Offset(0, 2),
                  ),
                ],
              ),
              child: Row(
                children: [
                  // Date badge
                  Container(
                    width: 52,
                    padding: const EdgeInsets.symmetric(vertical: 8),
                    decoration: BoxDecoration(
                      color: AppColors.primary.withValues(alpha: 0.1),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Column(
                      children: [
                        Text(
                          _monthAbbr(next.appointmentDate.month),
                          style: GoogleFonts.roboto(
                            fontSize: 11,
                            fontWeight: FontWeight.w600,
                            color: AppColors.primary,
                          ),
                        ),
                        Text(
                          '${next.appointmentDate.day}',
                          style: GoogleFonts.poppins(
                            fontSize: 22,
                            fontWeight: FontWeight.w700,
                            color: AppColors.primary,
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          next.patientName,
                          style: GoogleFonts.poppins(
                            fontSize: 16,
                            fontWeight: FontWeight.w600,
                            color: isDark
                                ? AppColors.textPrimaryDark
                                : AppColors.textPrimaryLight,
                          ),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          '${next.timeSlot}  •  ${next.typeDisplay}',
                          style: GoogleFonts.roboto(
                            fontSize: 14,
                            fontWeight: FontWeight.w500,
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
                      vertical: 4,
                    ),
                    decoration: BoxDecoration(
                      color: (next.status == AppointmentStatus.confirmed
                              ? AppColors.success
                              : AppColors.warning)
                          .withValues(alpha: 0.1),
                      borderRadius: BorderRadius.circular(20),
                    ),
                    child: Text(
                      next.statusDisplay,
                      style: GoogleFonts.roboto(
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                        color: next.status == AppointmentStatus.confirmed
                            ? AppColors.success
                            : AppColors.warning,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
      ],
    ).animate(delay: 500.ms).fadeIn(duration: 400.ms).slideY(begin: 0.02);
  }

  // ---- 4. Today's appointments ----
  Widget _buildTodaysList(
      bool isDark, DoctorAppointmentProvider provider, AppLocalizations l10n) {
    final now = DateTime.now();
    final startOfDay = DateTime(now.year, now.month, now.day);
    final endOfDay = startOfDay.add(const Duration(days: 1));

    final todayAppts = provider.appointments.where((apt) {
      final isToday = apt.appointmentDate.isAfter(
            startOfDay.subtract(const Duration(seconds: 1)),
          ) &&
          apt.appointmentDate.isBefore(endOfDay);
      final isActive = apt.status == AppointmentStatus.pending ||
          apt.status == AppointmentStatus.confirmed;
      return isToday && isActive;
    }).toList()
      ..sort((a, b) => a.appointmentDate.compareTo(b.appointmentDate));

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          l10n.todaysAppointments,
          style: GoogleFonts.poppins(
            fontSize: 18,
            fontWeight: FontWeight.w600,
            color:
                isDark ? AppColors.textPrimaryDark : AppColors.textPrimaryLight,
          ),
        ),
        const SizedBox(height: 12),
        if (todayAppts.isEmpty)
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
                  Icons.event_busy_outlined,
                  size: 45,
                  color: isDark ? Colors.grey[600] : Colors.grey[400],
                ),
                const SizedBox(height: 12),
                Text(
                  l10n.noAppointmentsToday,
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
          ...todayAppts.asMap().entries.map(
                (entry) => _todayCard(entry.value, isDark, entry.key),
              ),
      ],
    ).animate(delay: 600.ms).fadeIn(duration: 400.ms).slideY(begin: 0.02);
  }

  Widget _todayCard(AppointmentModel appt, bool isDark, int index) {
    final statusColor = _statusColor(appt.status);

    return GestureDetector(
      onTap: () => _openDetail(appt),
      child: Container(
        margin: const EdgeInsets.only(bottom: 10),
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: isDark ? AppColors.surfaceDark : AppColors.surfaceLight,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
            color: statusColor.withValues(alpha: 0.3),
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
        child: Row(
          children: [
            // Time badge
            Container(
              width: 50,
              height: 50,
              decoration: BoxDecoration(
                color: AppColors.primary.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Center(
                child: Text(
                  appt.timeSlot.split(' - ').first,
                  style: GoogleFonts.poppins(
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                    color: AppColors.primary,
                  ),
                  textAlign: TextAlign.center,
                ),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    appt.patientName,
                    style: GoogleFonts.poppins(
                      fontSize: 16,
                      fontWeight: FontWeight.w600,
                      color: isDark
                          ? AppColors.textPrimaryDark
                          : AppColors.textPrimaryLight,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    appt.typeDisplay,
                    style: GoogleFonts.roboto(
                      fontSize: 14,
                      fontWeight: FontWeight.w500,
                      color: isDark
                          ? AppColors.textSecondaryDark
                          : AppColors.textSecondaryLight,
                    ),
                  ),
                ],
              ),
            ),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
              decoration: BoxDecoration(
                color: statusColor.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(20),
              ),
              child: Text(
                appt.statusDisplay,
                style: GoogleFonts.roboto(
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                  color: statusColor,
                ),
              ),
            ),
          ],
        ),
      ),
    )
        .animate(delay: Duration(milliseconds: index * 100))
        .fadeIn(duration: 400.ms)
        .slideX(begin: 0.05);
  }

  // ---- skeleton ----
  Widget _buildSkeleton(bool isDark) {
    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(20, 20, 20, 100),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Greeting skeleton
          const CardSkeleton(height: 180),
          const SizedBox(height: 24),
          // Stats row skeleton
          Row(
            children: List.generate(
              4,
              (i) => Expanded(
                child: Padding(
                  padding: EdgeInsets.only(left: i == 0 ? 0 : 10),
                  child: const CardSkeleton(height: 110),
                ),
              ),
            ),
          ),
          const SizedBox(height: 28),
          // Next appointment skeleton
          const LoadingSkeleton(width: 160, height: 20),
          const SizedBox(height: 12),
          const AppointmentCardSkeleton(),
          const SizedBox(height: 28),
          // Today's list skeleton
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

  // ---- handlers ----
  Future<void> _toggleAvailability(bool value) async {
    if (!value) {
      await _showUnavailableRequestDialog();
      return;
    }

    setState(() => _togglingAvailability = true);
    try {
      await _doctorFunctions.setDoctorAvailability(isAvailable: true);
      if (mounted) {
        setState(() {
          _doctor = _doctor.copyWith(isAvailable: true);
          _togglingAvailability = false;
        });
        widget.onDoctorUpdated?.call();
      }
    } on DoctorFunctionException catch (e) {
      if (mounted) {
        setState(() => _togglingAvailability = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(e.userMessage),
            backgroundColor: AppColors.error,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        setState(() => _togglingAvailability = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
                '${AppLocalizations.of(context).failedToUpdateAvailability}: $e'),
            backgroundColor: AppColors.error,
          ),
        );
      }
    }
  }

  Future<void> _showUnavailableRequestDialog() async {
    final controller = TextEditingController();
    String? errorText;
    final reason = await showDialog<String>(
      context: context,
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setDialogState) {
            return AlertDialog(
              title: Row(
                children: [
                  Container(
                    width: 38,
                    height: 38,
                    decoration: BoxDecoration(
                      color: AppColors.warning.withValues(alpha: 0.14),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: const Icon(
                      Icons.pending_actions_rounded,
                      color: AppColors.warning,
                    ),
                  ),
                  const SizedBox(width: 12),
                  const Expanded(
                    child: Text('Request unavailable status'),
                  ),
                ],
              ),
              content: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 520),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Admin approval is required. You will stay available until the request is approved.',
                      style: GoogleFonts.roboto(height: 1.35),
                    ),
                    const SizedBox(height: 16),
                    TextField(
                      controller: controller,
                      autofocus: true,
                      minLines: 3,
                      maxLines: 5,
                      maxLength: 280,
                      textInputAction: TextInputAction.newline,
                      decoration: InputDecoration(
                        labelText: 'Note for admin',
                        hintText: 'Example: clinic duty, emergency, sick leave',
                        errorText: errorText,
                        border: const OutlineInputBorder(),
                      ),
                    ),
                  ],
                ),
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(context),
                  child: const Text('Cancel'),
                ),
                FilledButton.icon(
                  onPressed: () {
                    final trimmed = controller.text.trim();
                    if (trimmed.length < 3) {
                      setDialogState(() {
                        errorText = 'Please write a short note.';
                      });
                      return;
                    }
                    Navigator.pop(context, trimmed);
                  },
                  icon: const Icon(Icons.send_rounded),
                  label: const Text('Send request'),
                ),
              ],
            );
          },
        );
      },
    );
    controller.dispose();

    if (reason == null || !mounted) return;
    await _submitUnavailableRequest(reason);
  }

  Future<void> _submitUnavailableRequest(String reason) async {
    setState(() => _togglingAvailability = true);
    try {
      final result = await _doctorFunctions.requestDoctorUnavailable(
        reason: reason,
      );
      if (!mounted) return;
      final requestId = result['requestId']?.toString() ?? '';
      setState(() {
        _doctor = _doctor.copyWith(
          isAvailable: true,
          availabilityRequestStatus: 'pending',
          pendingAvailabilityRequestId: requestId,
          availabilityRequestReason: reason,
          availabilityRequestedAt: DateTime.now(),
        );
        _togglingAvailability = false;
      });
      widget.onDoctorUpdated?.call();
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'Request sent. You remain available until admin approval.',
          ),
          backgroundColor: AppColors.success,
        ),
      );
    } on DoctorFunctionException catch (e) {
      if (!mounted) return;
      setState(() => _togglingAvailability = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(e.userMessage),
          backgroundColor: AppColors.error,
        ),
      );
    } catch (e) {
      if (!mounted) return;
      setState(() => _togglingAvailability = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Failed to submit availability request: $e'),
          backgroundColor: AppColors.error,
        ),
      );
    }
  }

  void _openDetail(AppointmentModel appt) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => DoctorAppointmentDetailScreen(
          appointment: appt,
          doctor: _doctor,
        ),
      ),
    ).then((_) {
      // Refresh after returning from detail
      if (mounted) {
        context.read<DoctorAppointmentProvider>().loadAppointments(_doctor.id);
      }
    });
  }

  // ---- helpers ----
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
    return intl.DateFormat('MMM', locale)
        .format(DateTime(0, month))
        .toUpperCase();
  }
}
