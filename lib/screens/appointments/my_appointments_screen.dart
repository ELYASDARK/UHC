import 'package:flutter/material.dart';
import 'package:qr_flutter/qr_flutter.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:provider/provider.dart';
import '../../core/constants/app_colors.dart';
import '../../core/constants/app_strings.dart';
import '../../core/widgets/loading_skeleton.dart';
import '../../data/models/appointment_model.dart';
import '../../providers/appointment_provider.dart';
import '../../providers/auth_provider.dart';
import '../../l10n/app_localizations.dart';
import '../../providers/doctor_provider.dart';
import 'cancel_dialog.dart';
import 'reschedule_screen.dart';

/// My appointments screen with tabs
class MyAppointmentsScreen extends StatefulWidget {
  final int initialTabIndex; // 0 = Upcoming, 1 = Past
  final VoidCallback? onBookNow; // Callback to switch to Doctors tab

  const MyAppointmentsScreen({
    super.key,
    this.initialTabIndex = 0,
    this.onBookNow,
  });

  @override
  MyAppointmentsScreenState createState() => MyAppointmentsScreenState();
}

// Made public so it can be accessed via GlobalKey
class MyAppointmentsScreenState extends State<MyAppointmentsScreen>
    with SingleTickerProviderStateMixin {
  late TabController _tabController;

  // Public method to switch tabs from outside
  void switchToTab(int index) {
    if (_tabController.index != index) {
      _tabController.animateTo(index);
    }
  }

  @override
  void initState() {
    super.initState();
    _tabController = TabController(
      length: 2,
      vsync: this,
      initialIndex: widget.initialTabIndex,
    );
    // Defer loading to avoid setState during build
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _loadAppointments();
    });
  }

  @override
  void didUpdateWidget(covariant MyAppointmentsScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    // Update tab when initialTabIndex changes
    if (oldWidget.initialTabIndex != widget.initialTabIndex) {
      _tabController.animateTo(widget.initialTabIndex);
    }
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  Future<void> _loadAppointments() async {
    final authProvider = context.read<AuthProvider>();
    final appointmentProvider = context.read<AppointmentProvider>();

    if (authProvider.user != null) {
      await appointmentProvider.loadAppointments(
        authProvider.user!.id,
        email: authProvider.user!.email,
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final l10n = AppLocalizations.of(context);

    return Consumer<AppointmentProvider>(
      builder: (context, appointmentProvider, child) {
        final upcomingAppointments = appointmentProvider.upcomingAppointments;
        final pastAppointments = appointmentProvider.pastAppointments;
        final isLoading = appointmentProvider.isLoading;

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
              _buildAppointmentList(
                upcomingAppointments,
                true,
                isDark,
                isLoading,
              ),
              _buildAppointmentList(pastAppointments, false, isDark, isLoading),
            ],
          ),
        );
      },
    );
  }

  Widget _buildAppointmentList(
    List<AppointmentModel> appointments,
    bool isUpcoming,
    bool isDark,
    bool isLoading,
  ) {
    final l10n = AppLocalizations.of(context);

    if (isLoading) {
      return ListView.separated(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 100),
        itemCount: 3,
        separatorBuilder: (context, index) => const SizedBox(height: 12),
        itemBuilder: (context, index) => const AppointmentCardSkeleton(),
      );
    }

    if (appointments.isEmpty) {
      return Center(
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
              isUpcoming ? 'Book your first appointment!' : 'No history yet',
              style: GoogleFonts.roboto(
                fontSize: 14,
                color: isDark
                    ? AppColors.textSecondaryDark
                    : AppColors.textSecondaryLight,
              ),
            ),
            if (isUpcoming && widget.onBookNow != null) ...[
              const SizedBox(height: 24),
              ElevatedButton.icon(
                onPressed: widget.onBookNow,
                icon: const Icon(Icons.search),
                label: const Text('Find a Doctor'),
                style: ElevatedButton.styleFrom(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 24,
                    vertical: 12,
                  ),
                ),
              ),
            ],
          ],
        ),
      );
    }

    return RefreshIndicator(
      onRefresh: _loadAppointments,
      child: ListView.separated(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 100),
        itemCount: appointments.length,
        separatorBuilder: (context, index) => const SizedBox(height: 12),
        itemBuilder: (context, index) {
          final appointment = appointments[index];
          return _AppointmentCard(
            appointment: appointment,
            isDark: isDark,
            onTap: () => _showAppointmentDetail(appointment),
            onCancel: () => _showCancelDialog(appointment),
            onReschedule: () => _showRescheduleDialog(appointment),
          )
              .animate(delay: Duration(milliseconds: index * 100))
              .fadeIn(duration: 400.ms)
              .slideX(begin: 0.05);
        },
      ),
    );
  }

  Future<void> _showCancelDialog(AppointmentModel appointment) async {
    final result = await CancelAppointmentDialog.show(context, appointment);
    if (result == true) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Appointment cancelled successfully'),
            backgroundColor: AppColors.success,
          ),
        );
        _loadAppointments();
      }
    }
  }

  Future<void> _showRescheduleDialog(AppointmentModel appointment) async {
    // Show loading indicator
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (_) => const Center(child: CircularProgressIndicator()),
    );

    try {
      // Get doctor details first
      final doctorProvider = context.read<DoctorProvider>();
      final doctor = await doctorProvider.getDoctorById(appointment.doctorId);

      // Hide loading
      if (mounted) Navigator.pop(context);

      if (mounted) {
        if (doctor != null) {
          final result = await Navigator.push(
            context,
            MaterialPageRoute(
              builder: (_) =>
                  RescheduleScreen(appointment: appointment, doctor: doctor),
            ),
          );

          if (result == true) {
            _loadAppointments();
          }
        } else {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Could not load doctor details'),
              backgroundColor: AppColors.error,
            ),
          );
        }
      }
    } catch (e) {
      // Hide loading
      if (mounted) Navigator.pop(context);

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error: ${e.toString()}'),
            backgroundColor: AppColors.error,
          ),
        );
      }
    }
  }

  void _showAppointmentDetail(AppointmentModel appointment) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (context) => _AppointmentDetailSheet(appointment: appointment),
    );
  }
}

/// Appointment card widget
class _AppointmentCard extends StatelessWidget {
  final AppointmentModel appointment;
  final bool isDark;
  final VoidCallback onTap;
  final VoidCallback? onCancel;
  final VoidCallback? onReschedule;

  const _AppointmentCard({
    required this.appointment,
    required this.isDark,
    required this.onTap,
    this.onCancel,
    this.onReschedule,
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
            // Header
            Row(
              children: [
                Container(
                  width: 50,
                  height: 50,
                  decoration: BoxDecoration(
                    color: AppColors.primary.withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: const Icon(
                    Icons.person_rounded,
                    color: AppColors.primary,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        appointment.doctorName,
                        style: GoogleFonts.poppins(
                          fontSize: 16,
                          fontWeight: FontWeight.w600,
                          color: isDark
                              ? AppColors.textPrimaryDark
                              : AppColors.textPrimaryLight,
                        ),
                      ),
                      Text(
                        appointment.department,
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

            // Date and time
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
                        _formatDate(appointment.appointmentDate, context),
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

            // Actions for upcoming appointments
            if (appointment.isUpcoming) ...[
              const SizedBox(height: 16),
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton(
                      onPressed: appointment.canCancel ? onCancel : null,
                      style: OutlinedButton.styleFrom(
                        foregroundColor: AppColors.error,
                        side: const BorderSide(color: AppColors.error),
                      ),
                      child: Text(l10n.cancel),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: ElevatedButton(
                      onPressed:
                          appointment.canReschedule ? onReschedule : null,
                      child: Text(l10n.reschedule),
                    ),
                  ),
                ],
              ),
            ],
          ],
        ),
      ),
    );
  }

  String _formatDate(DateTime date, BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final now = DateTime.now();
    final tomorrow = DateTime(now.year, now.month, now.day + 1);
    final appointmentDay = DateTime(date.year, date.month, date.day);

    if (appointmentDay == DateTime(now.year, now.month, now.day)) {
      return l10n.today;
    } else if (appointmentDay == tomorrow) {
      return l10n.tomorrow;
    } else {
      return '${date.day}/${date.month}/${date.year}';
    }
  }
}

/// Appointment detail bottom sheet
class _AppointmentDetailSheet extends StatelessWidget {
  final AppointmentModel appointment;

  const _AppointmentDetailSheet({required this.appointment});

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Container(
      padding: const EdgeInsets.all(24),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Handle
          Center(
            child: Container(
              width: 40,
              height: 4,
              decoration: BoxDecoration(
                color: Colors.grey[400],
                borderRadius: BorderRadius.circular(2),
              ),
            ),
          ),
          const SizedBox(height: 20),

          Text(
            AppStrings.appointmentDetails,
            style: GoogleFonts.poppins(
              fontSize: 22,
              fontWeight: FontWeight.bold,
              color: isDark
                  ? AppColors.textPrimaryDark
                  : AppColors.textPrimaryLight,
            ),
          ),

          const SizedBox(height: 24),

          // QR Code
          if (appointment.isUpcoming) ...[
            Center(
              child: Column(
                children: [
                  Container(
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(16),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black.withValues(alpha: 0.1),
                          blurRadius: 10,
                          offset: const Offset(0, 4),
                        ),
                      ],
                    ),
                    child: QrImageView(
                      data: 'UHC_APPOINTMENT:${appointment.id}',
                      version: QrVersions.auto,
                      size: 160,
                      backgroundColor: Colors.white,
                    ),
                  ),
                  const SizedBox(height: 16),
                  Text(
                    'Booking ID',
                    style: GoogleFonts.roboto(
                      fontSize: 12,
                      color: isDark
                          ? AppColors.textSecondaryDark
                          : AppColors.textSecondaryLight,
                    ),
                  ),
                  Text(
                    appointment.bookingReference ??
                        appointment.id.substring(0, 8).toUpperCase(),
                    style: GoogleFonts.poppins(
                      fontSize: 20,
                      fontWeight: FontWeight.bold,
                      letterSpacing: 1,
                      color: isDark
                          ? AppColors.textPrimaryDark
                          : AppColors.textPrimaryLight,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    'Show this at check-in',
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
            const SizedBox(height: 24),
          ],

          const SizedBox(height: 24),

          // Details
          _buildDetailRow('Doctor', appointment.doctorName, isDark),
          _buildDetailRow('Department', appointment.department, isDark),
          _buildDetailRow('Type', appointment.typeDisplay, isDark),
          _buildDetailRow(
            'Date',
            '${appointment.appointmentDate.day}/${appointment.appointmentDate.month}/${appointment.appointmentDate.year}',
            isDark,
          ),
          _buildDetailRow('Time', appointment.timeSlot, isDark),
          _buildDetailRow('Status', appointment.statusDisplay, isDark),

          if (appointment.medicalNotes != null) ...[
            const SizedBox(height: 16),
            Text(
              'Medical Notes',
              style: GoogleFonts.poppins(
                fontSize: 14,
                fontWeight: FontWeight.w600,
                color: isDark
                    ? AppColors.textPrimaryDark
                    : AppColors.textPrimaryLight,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              appointment.medicalNotes!,
              style: GoogleFonts.roboto(
                fontSize: 14,
                height: 1.5,
                color: isDark
                    ? AppColors.textSecondaryDark
                    : AppColors.textSecondaryLight,
              ),
            ),
          ],

          const SizedBox(height: 24),
        ],
      ),
    );
  }

  Widget _buildDetailRow(String label, String value, bool isDark) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(
            label,
            style: GoogleFonts.roboto(
              fontSize: 14,
              color: isDark
                  ? AppColors.textSecondaryDark
                  : AppColors.textSecondaryLight,
            ),
          ),
          Text(
            value,
            style: GoogleFonts.poppins(
              fontSize: 14,
              fontWeight: FontWeight.w500,
              color: isDark
                  ? AppColors.textPrimaryDark
                  : AppColors.textPrimaryLight,
            ),
          ),
        ],
      ),
    );
  }
}
