import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:intl/intl.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:provider/provider.dart';
import 'package:table_calendar/table_calendar.dart';
import '../../../core/constants/app_colors.dart';
import '../../../core/widgets/loading_skeleton.dart';
import '../../../data/models/appointment_model.dart';
import '../../../data/models/doctor_model.dart';
import '../../../data/repositories/appointment_repository.dart';
import '../../../providers/doctor_appointment_provider.dart';
import '../../../l10n/app_localizations.dart';
import '../../../core/utils/locale_utils.dart';
import '../../../core/widgets/responsive_layout.dart';
import '../appointments/doctor_appointment_detail_screen.dart';
import 'doctor_schedule_entries.dart';

/// Doctor's own schedule view
///
/// Shows:
///   1. Week calendar (today ± 60 days)
///   2. Day's time slots from weeklySchedule with booked/free/past status
///   3. Booked slot cards linking to appointment details
class DoctorScheduleManagementScreen extends StatefulWidget {
  final DoctorModel doctor;
  final AppointmentRepository? appointmentRepository;
  final bool isActive;

  const DoctorScheduleManagementScreen({
    super.key,
    required this.doctor,
    this.appointmentRepository,
    this.isActive = true,
  });

  @override
  State<DoctorScheduleManagementScreen> createState() =>
      _DoctorScheduleManagementScreenState();
}

class _DoctorScheduleManagementScreenState
    extends State<DoctorScheduleManagementScreen> with WidgetsBindingObserver {
  late final AppointmentRepository _appointmentRepo;

  CalendarFormat _calendarFormat = CalendarFormat.week;
  DateTime _focusedDay = DateTime.now();
  DateTime _selectedDay = DateTime.now();

  List<AppointmentModel> _appointments = [];
  bool _isLoadingSlots = false;
  bool _loadFailed = false;
  int _requestId = 0;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _appointmentRepo = widget.appointmentRepository ?? AppointmentRepository();
    _loadBookedSlots(_selectedDay);
  }

  @override
  void didUpdateWidget(covariant DoctorScheduleManagementScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    final doctorChanged = widget.doctor.id != oldWidget.doctor.id ||
        jsonEncode(widget.doctor.toFirestore()['weeklySchedule']) !=
            jsonEncode(oldWidget.doctor.toFirestore()['weeklySchedule']);
    if (doctorChanged || (widget.isActive && !oldWidget.isActive)) {
      _loadBookedSlots(_selectedDay);
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed && widget.isActive) {
      _loadBookedSlots(_selectedDay);
    }
  }

  @override
  void dispose() {
    _requestId++;
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  // ---- data ----
  Future<void> _loadBookedSlots(DateTime date) async {
    if (!mounted) return;
    final requestId = ++_requestId;
    final doctorId = widget.doctor.id;
    setState(() {
      _isLoadingSlots = true;
      _loadFailed = false;
      _appointments = [];
    });
    try {
      final appointments = await _appointmentRepo.getDoctorAppointments(
        doctorId,
        date,
        requireServer: true,
      );
      if (!mounted || requestId != _requestId) return;
      setState(() {
        _appointments = appointments;
        _isLoadingSlots = false;
      });
    } catch (_) {
      if (!mounted || requestId != _requestId) return;
      setState(() {
        _loadFailed = true;
        _isLoadingSlots = false;
      });
    }
  }

  List<TimeSlot> _getDaySlots(DateTime date) {
    final dayName = DoctorModel.dayOfWeekName(date);
    return widget.doctor.weeklySchedule[dayName] ??
        widget.doctor.weeklySchedule.entries
            .where((entry) => entry.key.toLowerCase() == dayName)
            .map((entry) => entry.value)
            .firstOrNull ??
        [];
  }

  // ---- build ----
  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final l10n = AppLocalizations.of(context);
    final daySlots = _getDaySlots(_selectedDay);
    final entries = doctorScheduleEntries(
      doctorId: widget.doctor.id,
      date: _selectedDay,
      slots: daySlots,
      appointments: _appointments,
    );
    final bookedCount =
        entries.where((entry) => entry.appointment != null).length;

    return Scaffold(
      appBar: AppBar(
        title: Text(
          l10n.schedule,
          style: GoogleFonts.poppins(fontWeight: FontWeight.w600),
        ),
        automaticallyImplyLeading: false,
      ),
      body: Column(
        children: [
          // Calendar
          ResponsiveContent(
            maxWidth: 1180,
            child: Container(
              margin: UhcResponsive.pagePadding(context, top: 8, bottom: 0),
              decoration: BoxDecoration(
                color: isDark ? AppColors.surfaceDark : AppColors.surfaceLight,
                borderRadius: BorderRadius.circular(20),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.05),
                    blurRadius: 10,
                    offset: const Offset(0, 2),
                  ),
                ],
              ),
              child: TableCalendar(
                firstDay: DateTime.now().subtract(const Duration(days: 30)),
                lastDay: DateTime.now().add(const Duration(days: 60)),
                focusedDay: _focusedDay,
                calendarFormat: _calendarFormat,
                selectedDayPredicate: (day) => isSameDay(_selectedDay, day),
                onDaySelected: (selected, focused) {
                  if (!isSameDay(_selectedDay, selected)) {
                    setState(() {
                      _selectedDay = selected;
                      _focusedDay = focused;
                    });
                    _loadBookedSlots(selected);
                  }
                },
                onFormatChanged: (fmt) => setState(() => _calendarFormat = fmt),
                availableCalendarFormats: {
                  CalendarFormat.month: l10n.month,
                  CalendarFormat.twoWeeks: l10n.twoWeeks,
                  CalendarFormat.week: l10n.week,
                },
                calendarStyle: CalendarStyle(
                  selectedDecoration: const BoxDecoration(
                    color: AppColors.primary,
                    shape: BoxShape.circle,
                  ),
                  todayDecoration: BoxDecoration(
                    color: AppColors.primary.withValues(alpha: 0.3),
                    shape: BoxShape.circle,
                  ),
                  disabledTextStyle: TextStyle(
                    color: isDark ? Colors.grey[700]! : Colors.grey[350]!,
                  ),
                  weekendTextStyle: TextStyle(
                    color: isDark
                        ? AppColors.textSecondaryDark
                        : AppColors.textSecondaryLight,
                  ),
                ),
                headerStyle: HeaderStyle(
                  formatButtonVisible: true,
                  titleCentered: true,
                  formatButtonDecoration: BoxDecoration(
                    border: Border.all(color: AppColors.primary),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  formatButtonTextStyle: const TextStyle(
                    color: AppColors.primary,
                  ),
                ),
              ),
            ),
          ).animate(delay: 300.ms).fadeIn(duration: 400.ms).slideY(begin: 0.02),

          const SizedBox(height: 12),

          // Date header
          ResponsiveContent(
            maxWidth: 1180,
            child: Padding(
              padding: UhcResponsive.pagePadding(context, top: 0, bottom: 0),
              child: Row(
                children: [
                  Container(
                    width: 40,
                    height: 40,
                    decoration: BoxDecoration(
                      color: AppColors.primary.withValues(alpha: 0.1),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: const Icon(
                      Icons.calendar_today,
                      color: AppColors.primary,
                      size: 20,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          _formatDate(_selectedDay),
                          style: GoogleFonts.poppins(
                            fontSize: 16,
                            fontWeight: FontWeight.w600,
                            color: isDark
                                ? AppColors.textPrimaryDark
                                : AppColors.textPrimaryLight,
                          ),
                        ),
                        Text(
                          _isLoadingSlots
                              ? l10n.loadingAvailability
                              : _loadFailed
                                  ? l10n.scheduleLoadFailed
                                  : daySlots.isEmpty && bookedCount == 0
                                      ? l10n.noScheduleSet
                                      : '${l10n.slotsLabel(daySlots.length)} • ${l10n.bookedCount(bookedCount)}',
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
                ],
              ),
            ),
          ).animate(delay: 400.ms).fadeIn(duration: 400.ms).slideY(begin: 0.02),

          const SizedBox(height: 12),

          // Slots list
          Expanded(
            child: RefreshIndicator(
              onRefresh: () => _loadBookedSlots(_selectedDay),
              child: _isLoadingSlots
                  ? _buildSlotsSkeleton()
                  : _loadFailed
                      ? _buildLoadError(l10n)
                      : entries.isEmpty
                          ? _buildEmptyDay(isDark, l10n)
                          : _buildSlotsList(entries, isDark, l10n),
            ),
          ),
        ],
      ),
    );
  }

  // ---- slots list ----
  Widget _buildSlotsList(
      List<DoctorScheduleEntry> entries, bool isDark, AppLocalizations l10n) {
    return ResponsiveListView(
      maxWidth: 1180,
      gridOnWide: false,
      tabletColumns: 1,
      laptopColumns: 2,
      desktopColumns: 2,
      childAspectRatio: 6.8,
      padding: UhcResponsive.pagePadding(
        context,
        top: 0,
        bottom: UhcResponsive.scrollBottomPadding(context),
      ),
      physics: const AlwaysScrollableScrollPhysics(),
      itemCount: entries.length,
      itemBuilder: (context, index) {
        final slot = entries[index].slot;
        final isPast =
            scheduleSlotIsPast(_selectedDay, slot.startTime, DateTime.now());

        return _slotCard(entries[index], isDark, isPast, l10n)
            .animate(delay: Duration(milliseconds: index * 100))
            .fadeIn(duration: 400.ms)
            .slideX(begin: 0.05);
      },
    );
  }

  Widget _slotCard(
    DoctorScheduleEntry entry,
    bool isDark,
    bool isPast,
    AppLocalizations l10n,
  ) {
    final slot = entry.slot;
    final appointment = entry.appointment;
    final isBooked = appointment != null;
    final Color statusColor;
    final String statusText;
    final IconData statusIcon;

    if (isBooked) {
      statusColor = AppColors.primary;
      statusText = appointment.patientName;
      statusIcon = Icons.person_rounded;
    } else if (isPast) {
      statusColor = Colors.grey;
      statusText = l10n.passed;
      statusIcon = Icons.history_rounded;
    } else if (!slot.isAvailable) {
      statusColor = Colors.grey;
      statusText = l10n.blocked;
      statusIcon = Icons.block_rounded;
    } else {
      statusColor = AppColors.success;
      statusText = l10n.available;
      statusIcon = Icons.check_circle_outline_rounded;
    }

    return GestureDetector(
      onTap: isBooked ? () => _openAppointment(appointment) : null,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        decoration: BoxDecoration(
          color: isDark ? AppColors.surfaceDark : AppColors.surfaceLight,
          borderRadius: BorderRadius.circular(16),
          border: isBooked
              ? Border.all(
                  color: AppColors.primary.withValues(alpha: 0.3),
                  width: 1.5,
                )
              : null,
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
            // Time
            SizedBox(
              width: MediaQuery.textScalerOf(context).scale(14) * 4.5,
              child: Text(
                slot.display,
                style: GoogleFonts.poppins(
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                  color: isPast && !isBooked
                      ? Colors.grey
                      : isDark
                          ? AppColors.textPrimaryDark
                          : AppColors.textPrimaryLight,
                  decoration:
                      isPast && !isBooked ? TextDecoration.lineThrough : null,
                ),
              ),
            ),
            const SizedBox(width: 12),

            Container(
              width: 3,
              height: 36,
              decoration: BoxDecoration(
                color: statusColor,
                borderRadius: BorderRadius.circular(10),
              ),
            ),
            const SizedBox(width: 12),
            Icon(statusIcon, size: 18, color: statusColor),
            const SizedBox(width: 10),

            // Status info
            Expanded(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    statusText,
                    style: GoogleFonts.poppins(
                      fontSize: 13,
                      fontWeight: isBooked ? FontWeight.w600 : FontWeight.w500,
                      color: isBooked
                          ? (isDark
                              ? AppColors.textPrimaryDark
                              : AppColors.textPrimaryLight)
                          : statusColor,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  if (isBooked)
                    Padding(
                      padding: const EdgeInsets.only(top: 2),
                      child: Text(
                        '${_typeLabel(appointment.type, l10n)} • ${_statusLabel(appointment.status, l10n)}',
                        style: GoogleFonts.roboto(
                          fontSize: 12,
                          color: isDark
                              ? AppColors.textSecondaryDark
                              : AppColors.textSecondaryLight,
                        ),
                      ),
                    ),
                ],
              ),
            ),

            // Arrow for booked
            if (isBooked)
              const Icon(
                Icons.chevron_right_rounded,
                color: AppColors.primary,
                size: 20,
              ),
          ],
        ),
      ),
    );
  }

  // ---- empty & skeleton ----
  Widget _buildLoadError(AppLocalizations l10n) {
    return ListView(
      physics: const AlwaysScrollableScrollPhysics(),
      padding: const EdgeInsets.all(24),
      children: [
        const Icon(Icons.cloud_off_outlined, size: 40),
        const SizedBox(height: 12),
        Text(l10n.scheduleLoadFailed, textAlign: TextAlign.center),
        const SizedBox(height: 12),
        Center(
          child: FilledButton.icon(
            onPressed: () => _loadBookedSlots(_selectedDay),
            icon: const Icon(Icons.refresh),
            label: Text(l10n.retry),
          ),
        ),
      ],
    );
  }

  String _typeLabel(AppointmentType type, AppLocalizations l10n) =>
      switch (type) {
        AppointmentType.regularCheckup => l10n.regularVisit,
        AppointmentType.followUp => l10n.followUp,
        AppointmentType.consultation => l10n.consultation,
        AppointmentType.emergency => l10n.emergency,
      };

  String _statusLabel(AppointmentStatus status, AppLocalizations l10n) =>
      switch (status) {
        AppointmentStatus.pending => l10n.pending,
        AppointmentStatus.confirmed => l10n.confirmed,
        AppointmentStatus.completed => l10n.completed,
        AppointmentStatus.cancelled => l10n.cancelled,
        AppointmentStatus.noShow => l10n.noShowStatus,
      };

  Widget _buildEmptyDay(bool isDark, AppLocalizations l10n) {
    return SingleChildScrollView(
      physics: const AlwaysScrollableScrollPhysics(),
      child: SizedBox(
        height: 300,
        child: Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(
                Icons.calendar_today_outlined,
                size: 80,
                color: isDark ? Colors.grey[600] : Colors.grey[400],
              ),
              const SizedBox(height: 16),
              Text(
                l10n.noScheduleTitle,
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
                l10n.noTimeSlotsConfigured,
                textAlign: TextAlign.center,
                style: GoogleFonts.roboto(
                  fontSize: 14,
                  color: isDark
                      ? AppColors.textSecondaryDark
                      : AppColors.textSecondaryLight,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildSlotsSkeleton() {
    return ResponsiveListView(
      maxWidth: 1180,
      gridOnWide: true,
      tabletColumns: 1,
      laptopColumns: 2,
      desktopColumns: 2,
      childAspectRatio: 6.8,
      padding: UhcResponsive.pagePadding(
        context,
        top: 0,
        bottom: UhcResponsive.scrollBottomPadding(context),
      ),
      itemCount: 6,
      itemBuilder: (_, i) => Padding(
        padding: const EdgeInsets.only(bottom: 10),
        child: const CardSkeleton(height: 56),
      ),
    );
  }

  // ---- navigation ----
  void _openAppointment(AppointmentModel appointment) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => DoctorAppointmentDetailScreen(
          appointment: appointment,
          doctor: widget.doctor,
        ),
      ),
    ).then((_) {
      if (!mounted) return;
      _loadBookedSlots(_selectedDay);
      context
          .read<DoctorAppointmentProvider>()
          .loadAppointments(widget.doctor.id);
    });
  }

  String _formatDate(DateTime date) {
    final locale = safeIntlLocale(context);
    final formatter = DateFormat('EEEE, MMMM d', locale);
    return formatter.format(date);
  }
}
