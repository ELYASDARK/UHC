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
import '../appointments/doctor_appointment_detail_screen.dart';

/// Doctor's own schedule view
///
/// Shows:
///   1. Week calendar (today ± 60 days)
///   2. Day's time slots from weeklySchedule with booked/free/past status
///   3. Booked slot cards linking to appointment details
class DoctorScheduleManagementScreen extends StatefulWidget {
  final DoctorModel doctor;

  const DoctorScheduleManagementScreen({super.key, required this.doctor});

  @override
  State<DoctorScheduleManagementScreen> createState() =>
      _DoctorScheduleManagementScreenState();
}

class _DoctorScheduleManagementScreenState
    extends State<DoctorScheduleManagementScreen> {
  final AppointmentRepository _appointmentRepo = AppointmentRepository();

  CalendarFormat _calendarFormat = CalendarFormat.week;
  DateTime _focusedDay = DateTime.now();
  DateTime _selectedDay = DateTime.now();

  List<String> _bookedSlots = [];
  Map<String, AppointmentModel> _slotAppointments = {};
  bool _isLoadingSlots = false;

  @override
  void initState() {
    super.initState();
    _loadBookedSlots(_selectedDay);
  }

  // ---- data ----
  Future<void> _loadBookedSlots(DateTime date) async {
    setState(() => _isLoadingSlots = true);
    try {
      final appointments = await _appointmentRepo.getDoctorAppointments(
        widget.doctor.id,
        date,
      );
      setState(() {
        _bookedSlots = appointments.map((a) => a.timeSlot).toList();
        _slotAppointments = {
          for (final a in appointments) a.timeSlot: a,
        };
      });
    } catch (e) {
      debugPrint('Failed to load booked slots: $e');
    } finally {
      setState(() => _isLoadingSlots = false);
    }
  }

  String _getDayName(DateTime date) {
    const days = [
      'monday',
      'tuesday',
      'wednesday',
      'thursday',
      'friday',
      'saturday',
      'sunday',
    ];
    return days[date.weekday - 1];
  }

  List<TimeSlot> _getDaySlots(DateTime date) {
    final dayName = _getDayName(date);
    return widget.doctor.weeklySchedule[dayName] ?? [];
  }

  bool _isWorkingDay(DateTime date) {
    return _getDaySlots(date).isNotEmpty;
  }

  bool _isSlotPast(DateTime date, String startTime) {
    if (!isSameDay(date, DateTime.now())) return false;
    final parts = startTime.split(':');
    if (parts.length != 2) return false;
    final hour = int.tryParse(parts[0]) ?? 0;
    final minute = int.tryParse(parts[1]) ?? 0;
    final slotTime = DateTime(date.year, date.month, date.day, hour, minute);
    return slotTime.isBefore(DateTime.now());
  }

  // ---- build ----
  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final l10n = AppLocalizations.of(context);
    final daySlots = _getDaySlots(_selectedDay);

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
          Container(
            margin: const EdgeInsets.fromLTRB(16, 8, 16, 0),
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
              enabledDayPredicate: _isWorkingDay,
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
          ).animate(delay: 300.ms).fadeIn(duration: 400.ms).slideY(begin: 0.02),

          const SizedBox(height: 12),

          // Date header
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20),
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
                        daySlots.isEmpty
                            ? l10n.noScheduleSet
                            : '${l10n.slotsLabel(daySlots.length)} • ${l10n.bookedCount(_bookedSlots.length)}',
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
          ).animate(delay: 400.ms).fadeIn(duration: 400.ms).slideY(begin: 0.02),

          const SizedBox(height: 12),

          // Slots list
          Expanded(
            child: _isLoadingSlots
                ? _buildSlotsSkeleton()
                : daySlots.isEmpty
                    ? _buildEmptyDay(isDark, l10n)
                    : _buildSlotsList(daySlots, isDark, l10n),
          ),
        ],
      ),
    );
  }

  // ---- slots list ----
  Widget _buildSlotsList(
      List<TimeSlot> slots, bool isDark, AppLocalizations l10n) {
    return ListView.builder(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 100),
      physics: const AlwaysScrollableScrollPhysics(),
      itemCount: slots.length,
      itemBuilder: (context, index) {
        final slot = slots[index];
        final isBooked = _bookedSlots.contains(slot.display);
        final isPast = _isSlotPast(_selectedDay, slot.startTime);
        final appointment = _slotAppointments[slot.display];

        return _slotCard(
                slot, isDark, isBooked, isPast, appointment, l10n, index)
            .animate(delay: Duration(milliseconds: index * 100))
            .fadeIn(duration: 400.ms)
            .slideX(begin: 0.05);
      },
    );
  }

  Widget _slotCard(
    TimeSlot slot,
    bool isDark,
    bool isBooked,
    bool isPast,
    AppointmentModel? appointment,
    AppLocalizations l10n,
    int index,
  ) {
    final Color statusColor;
    final String statusText;
    final IconData statusIcon;

    if (isBooked) {
      statusColor = AppColors.primary;
      statusText = appointment?.patientName ?? l10n.booked;
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
      onTap: isBooked && appointment != null
          ? () => _openAppointment(appointment)
          : null,
      child: Container(
        margin: const EdgeInsets.only(bottom: 10),
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
              width: 58,
              child: Text(
                slot.display,
                style: GoogleFonts.poppins(
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                  color: isPast
                      ? Colors.grey
                      : isDark
                          ? AppColors.textPrimaryDark
                          : AppColors.textPrimaryLight,
                  decoration: isPast ? TextDecoration.lineThrough : null,
                ),
              ),
            ),
            const SizedBox(width: 10),

            // Status line
            Container(
              width: 3,
              height: 36,
              decoration: BoxDecoration(
                color: statusColor,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            const SizedBox(width: 12),

            // Status info
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Icon(statusIcon, size: 16, color: statusColor),
                      const SizedBox(width: 6),
                      Expanded(
                        child: Text(
                          statusText,
                          style: GoogleFonts.poppins(
                            fontSize: 13,
                            fontWeight:
                                isBooked ? FontWeight.w600 : FontWeight.w400,
                            color: isBooked
                                ? (isDark
                                    ? AppColors.textPrimaryDark
                                    : AppColors.textPrimaryLight)
                                : statusColor,
                          ),
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                    ],
                  ),
                  if (isBooked && appointment != null)
                    Padding(
                      padding: const EdgeInsets.only(top: 2, left: 22),
                      child: Text(
                        '${appointment.typeDisplay} • ${appointment.statusDisplay}',
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
            if (isBooked && appointment != null)
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
    return ListView.builder(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 100),
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
      _loadBookedSlots(_selectedDay);
      if (mounted) {
        context
            .read<DoctorAppointmentProvider>()
            .loadAppointments(widget.doctor.id);
      }
    });
  }

  String _formatDate(DateTime date) {
    final locale = safeIntlLocale(context);
    final formatter = DateFormat('EEEE, MMMM d', locale);
    return formatter.format(date);
  }
}
