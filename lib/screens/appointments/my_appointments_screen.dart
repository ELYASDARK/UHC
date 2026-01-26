import 'package:flutter/material.dart';
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

/// My appointments screen with tabs
class MyAppointmentsScreen extends StatefulWidget {
  final int initialTabIndex; // 0 = Upcoming, 1 = Past

  const MyAppointmentsScreen({super.key, this.initialTabIndex = 0});

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
        padding: const EdgeInsets.all(16),
        itemCount: 3,
        separatorBuilder: (_, _) => const SizedBox(height: 12),
        itemBuilder: (_, _) => const AppointmentCardSkeleton(),
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
          ],
        ),
      );
    }

    return RefreshIndicator(
      onRefresh: _loadAppointments,
      child: ListView.separated(
        padding: const EdgeInsets.all(16),
        itemCount: appointments.length,
        separatorBuilder: (_, _) => const SizedBox(height: 12),
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

  void _showCancelDialog(AppointmentModel appointment) {
    final TextEditingController reasonController = TextEditingController();

    showDialog(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Cancel Appointment'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Are you sure you want to cancel your appointment with ${appointment.doctorName}?',
            ),
            const SizedBox(height: 16),
            TextField(
              controller: reasonController,
              decoration: const InputDecoration(
                labelText: 'Reason for cancellation (optional)',
                border: OutlineInputBorder(),
              ),
              maxLines: 2,
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: const Text('Keep Appointment'),
          ),
          ElevatedButton(
            onPressed: () async {
              Navigator.pop(dialogContext);
              await _cancelAppointment(appointment, reasonController.text);
            },
            style: ElevatedButton.styleFrom(
              backgroundColor: AppColors.error,
              foregroundColor: Colors.white,
            ),
            child: const Text('Cancel Appointment'),
          ),
        ],
      ),
    );
  }

  Future<void> _cancelAppointment(
    AppointmentModel appointment,
    String reason,
  ) async {
    final authProvider = context.read<AuthProvider>();
    final appointmentProvider = context.read<AppointmentProvider>();

    if (authProvider.user == null) return;

    final success = await appointmentProvider.cancelAppointment(
      appointment.id,
      reason.isEmpty ? 'User requested cancellation' : reason,
      authProvider.user!.id,
    );

    if (mounted) {
      if (success) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Appointment cancelled successfully'),
            backgroundColor: AppColors.success,
          ),
        );
        // Reload appointments
        _loadAppointments();
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              appointmentProvider.error ?? 'Failed to cancel appointment',
            ),
            backgroundColor: AppColors.error,
          ),
        );
      }
    }
  }

  void _showRescheduleDialog(AppointmentModel appointment) {
    DateTime selectedDate = appointment.appointmentDate;
    String? selectedTimeSlot = appointment.timeSlot;
    final reasonController = TextEditingController();

    // Available time slots
    final timeSlots = [
      '09:00 - 09:30',
      '09:30 - 10:00',
      '10:00 - 10:30',
      '10:30 - 11:00',
      '11:00 - 11:30',
      '11:30 - 12:00',
      '14:00 - 14:30',
      '14:30 - 15:00',
      '15:00 - 15:30',
      '15:30 - 16:00',
      '16:00 - 16:30',
    ];

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (bottomSheetContext) {
        return StatefulBuilder(
          builder: (context, setModalState) {
            return Padding(
              padding: EdgeInsets.only(
                bottom: MediaQuery.of(context).viewInsets.bottom,
              ),
              child: Container(
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
                      'Reschedule Appointment',
                      style: GoogleFonts.poppins(
                        fontSize: 20,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      'Select a new date and time for your appointment with ${appointment.doctorName}',
                      style: GoogleFonts.roboto(
                        fontSize: 14,
                        color: Colors.grey[600],
                      ),
                    ),
                    const SizedBox(height: 24),

                    // Date Picker
                    Text(
                      'Select Date',
                      style: GoogleFonts.poppins(
                        fontSize: 14,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const SizedBox(height: 8),
                    InkWell(
                      onTap: () async {
                        final picked = await showDatePicker(
                          context: context,
                          initialDate: selectedDate,
                          firstDate: DateTime.now().add(
                            const Duration(days: 1),
                          ),
                          lastDate: DateTime.now().add(
                            const Duration(days: 90),
                          ),
                          selectableDayPredicate: (day) {
                            // Only allow weekdays
                            return day.weekday >= 1 && day.weekday <= 5;
                          },
                        );
                        if (picked != null) {
                          setModalState(() {
                            selectedDate = picked;
                          });
                        }
                      },
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 16,
                          vertical: 12,
                        ),
                        decoration: BoxDecoration(
                          border: Border.all(color: Colors.grey[300]!),
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: Row(
                          children: [
                            const Icon(
                              Icons.calendar_today,
                              color: AppColors.primary,
                            ),
                            const SizedBox(width: 12),
                            Text(
                              '${selectedDate.day}/${selectedDate.month}/${selectedDate.year}',
                              style: GoogleFonts.roboto(fontSize: 16),
                            ),
                            const Spacer(),
                            const Icon(Icons.arrow_drop_down),
                          ],
                        ),
                      ),
                    ),
                    const SizedBox(height: 16),

                    // Time Slot Picker
                    Text(
                      'Select Time',
                      style: GoogleFonts.poppins(
                        fontSize: 14,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const SizedBox(height: 8),
                    SizedBox(
                      height: 45,
                      child: ListView.separated(
                        scrollDirection: Axis.horizontal,
                        itemCount: timeSlots.length,
                        separatorBuilder: (_, _) => const SizedBox(width: 8),
                        itemBuilder: (context, index) {
                          final slot = timeSlots[index];
                          final isSelected = slot == selectedTimeSlot;
                          return GestureDetector(
                            onTap: () {
                              setModalState(() {
                                selectedTimeSlot = slot;
                              });
                            },
                            child: Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 16,
                              ),
                              decoration: BoxDecoration(
                                color: isSelected
                                    ? AppColors.primary
                                    : Colors.grey[100],
                                borderRadius: BorderRadius.circular(20),
                                border: Border.all(
                                  color: isSelected
                                      ? AppColors.primary
                                      : Colors.grey[300]!,
                                ),
                              ),
                              alignment: Alignment.center,
                              child: Text(
                                slot.split(' - ').first,
                                style: GoogleFonts.roboto(
                                  fontSize: 14,
                                  fontWeight: FontWeight.w500,
                                  color: isSelected
                                      ? Colors.white
                                      : Colors.black87,
                                ),
                              ),
                            ),
                          );
                        },
                      ),
                    ),
                    const SizedBox(height: 16),

                    // Reason
                    TextField(
                      controller: reasonController,
                      decoration: InputDecoration(
                        labelText: 'Reason for rescheduling (optional)',
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                      ),
                    ),
                    const SizedBox(height: 24),

                    // Buttons
                    Row(
                      children: [
                        Expanded(
                          child: OutlinedButton(
                            onPressed: () => Navigator.pop(bottomSheetContext),
                            child: const Text('Cancel'),
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: ElevatedButton(
                            onPressed: selectedTimeSlot != null
                                ? () async {
                                    Navigator.pop(bottomSheetContext);
                                    await _rescheduleAppointment(
                                      appointment,
                                      selectedDate,
                                      selectedTimeSlot!,
                                      reasonController.text,
                                    );
                                  }
                                : null,
                            child: const Text('Confirm'),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 16),
                  ],
                ),
              ),
            );
          },
        );
      },
    );
  }

  Future<void> _rescheduleAppointment(
    AppointmentModel appointment,
    DateTime newDate,
    String newTimeSlot,
    String reason,
  ) async {
    final authProvider = context.read<AuthProvider>();
    final appointmentProvider = context.read<AppointmentProvider>();

    if (authProvider.user == null) return;

    final success = await appointmentProvider.rescheduleAppointment(
      appointmentId: appointment.id,
      newDate: newDate,
      newTimeSlot: newTimeSlot,
      doctorId: appointment.doctorId,
      doctorName: appointment.doctorName,
      userId: authProvider.user!.id,
      reason: reason.isEmpty ? null : reason,
    );

    if (mounted) {
      if (success) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Appointment rescheduled successfully'),
            backgroundColor: AppColors.success,
          ),
        );
        // Reload appointments
        _loadAppointments();
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              appointmentProvider.error ?? 'Failed to reschedule appointment',
            ),
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
          border: Border.all(color: _statusColor.withOpacity(0.3), width: 1.5),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withOpacity(0.05),
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
                    color: AppColors.primary.withOpacity(0.1),
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
                    color: _statusColor.withOpacity(0.1),
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: Text(
                    appointment.statusDisplay,
                    style: GoogleFonts.roboto(
                      fontSize: 12,
                      fontWeight: FontWeight.w500,
                      color: _statusColor,
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
                      onPressed: appointment.canReschedule
                          ? onReschedule
                          : null,
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

          // QR Code placeholder
          if (appointment.isUpcoming)
            Center(
              child: Container(
                width: 180,
                height: 180,
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(color: Colors.grey[300]!),
                ),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(
                      Icons.qr_code_2_rounded,
                      size: 100,
                      color: Colors.grey[400],
                    ),
                    const SizedBox(height: 8),
                    Text(
                      'Check-in QR Code',
                      style: GoogleFonts.roboto(
                        fontSize: 12,
                        color: Colors.grey[500],
                      ),
                    ),
                  ],
                ),
              ),
            ),

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
