import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:table_calendar/table_calendar.dart';
import '../../../core/constants/app_colors.dart';
import '../../../data/models/doctor_model.dart';
import '../../../data/repositories/appointment_repository.dart';
import '../../../l10n/app_localizations.dart';
import '../booking/booking_screen.dart';
import '../appointments/emergency_request_screen.dart';

class DoctorScheduleScreen extends StatefulWidget {
  final DoctorModel doctor;

  const DoctorScheduleScreen({super.key, required this.doctor});

  @override
  State<DoctorScheduleScreen> createState() => _DoctorScheduleScreenState();
}

class _DoctorScheduleScreenState extends State<DoctorScheduleScreen> {
  final AppointmentRepository _appointmentRepo = AppointmentRepository();

  CalendarFormat _calendarFormat = CalendarFormat.week;
  DateTime _focusedDay = DateTime.now();
  DateTime _selectedDay = DateTime.now();
  List<String> _bookedSlots = [];
  bool _isLoading = false;

  @override
  void initState() {
    super.initState();
    _loadBookedSlots(_selectedDay);
  }

  Future<void> _loadBookedSlots(DateTime date) async {
    if (!mounted) return;
    setState(() => _isLoading = true);

    try {
      final appointments = await _appointmentRepo.getDoctorAppointments(
        widget.doctor.id,
        date,
      );
      if (!mounted) return;
      setState(() {
        _bookedSlots = appointments.map((a) => a.timeSlot).toList();
      });
    } catch (e) {
      debugPrint('Error loading booked slots: $e');
    } finally {
      if (mounted) {
        setState(() => _isLoading = false);
      }
    }
  }

  void _onDaySelected(DateTime selectedDay, DateTime focusedDay) {
    if (!isSameDay(_selectedDay, selectedDay)) {
      setState(() {
        _selectedDay = selectedDay;
        _focusedDay = focusedDay;
      });
      _loadBookedSlots(selectedDay);
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

  List<TimeSlot> _getAvailableSlots(DateTime date) {
    final dayName = _getDayName(date);
    final doctorSlots = widget.doctor.weeklySchedule[dayName];

    // If doctor has specific slots for this day, use them
    if (doctorSlots != null && doctorSlots.isNotEmpty) {
      return doctorSlots;
    }

    // Check if doctor has ANY schedule set
    final hasAnySchedule = widget.doctor.weeklySchedule.values.any(
      (slots) => slots.isNotEmpty,
    );

    // If doctor has a schedule but this day is not in it, return empty
    if (hasAnySchedule) {
      return [];
    }

    // Fallback: No schedule set at all, return default time slots for weekdays
    if (date.weekday >= 1 && date.weekday <= 5) {
      return [
        TimeSlot(startTime: '09:00', endTime: '09:30'),
        TimeSlot(startTime: '09:30', endTime: '10:00'),
        TimeSlot(startTime: '10:00', endTime: '10:30'),
        TimeSlot(startTime: '10:30', endTime: '11:00'),
        TimeSlot(startTime: '11:00', endTime: '11:30'),
        TimeSlot(startTime: '14:00', endTime: '14:30'),
        TimeSlot(startTime: '14:30', endTime: '15:00'),
        TimeSlot(startTime: '15:00', endTime: '15:30'),
        TimeSlot(startTime: '15:30', endTime: '16:00'),
      ];
    }

    return [];
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final availableSlots = _getAvailableSlots(_selectedDay);
    final l10n = AppLocalizations.of(context);

    return Scaffold(
      appBar: AppBar(
        title: Text(
          '${l10n.doctorScheduleTitle} ${widget.doctor.name}',
          style: GoogleFonts.poppins(fontWeight: FontWeight.w600),
        ),
        centerTitle: true,
        actions: [
          PopupMenuButton<String>(
            onSelected: (value) {
              if (value == 'emergency') {
                Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (context) =>
                        EmergencyRequestScreen(doctor: widget.doctor),
                  ),
                );
              }
            },
            itemBuilder: (context) => [
              const PopupMenuItem(
                value: 'emergency',
                child: Row(
                  children: [
                    Icon(Icons.emergency, size: 20, color: AppColors.error),
                    SizedBox(width: 8),
                    Text('Emergency Request',
                        style: TextStyle(color: AppColors.error)),
                  ],
                ),
              ),
            ],
          ),
        ],
      ),
      body: Column(
        children: [
          // Calendar
          Container(
            margin: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: isDark ? AppColors.surfaceDark : Colors.white,
              borderRadius: BorderRadius.circular(20),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.05),
                  blurRadius: 20,
                  offset: const Offset(0, 5),
                ),
              ],
            ),
            child: TableCalendar(
              firstDay: DateTime.now(),
              lastDay: DateTime.now().add(const Duration(days: 60)),
              focusedDay: _focusedDay,
              calendarFormat: _calendarFormat,
              selectedDayPredicate: (day) => isSameDay(_selectedDay, day),
              onDaySelected: _onDaySelected,
              onFormatChanged: (format) {
                setState(() {
                  _calendarFormat = format;
                });
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
              enabledDayPredicate: (day) {
                // Allow only future days
                return day.isAfter(
                  DateTime.now().subtract(const Duration(days: 1)),
                );
              },
            ),
          ),

          // Selected Date Info
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20),
            child: Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: AppColors.primary.withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: const Icon(
                    Icons.calendar_today,
                    color: AppColors.primary,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        _formatDate(_selectedDay),
                        style: Theme.of(context)
                            .textTheme
                            .titleMedium
                            ?.copyWith(fontWeight: FontWeight.bold),
                      ),
                      Text(
                        l10n.timeSlotsAvailable(availableSlots.length),
                        style: Theme.of(context).textTheme.bodySmall?.copyWith(
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
          const SizedBox(height: 16),

          // Time Slots
          Expanded(
            child: _isLoading
                ? const Center(child: CircularProgressIndicator())
                : availableSlots.isEmpty
                    ? _buildNoSlotsMessage()
                    : _buildTimeSlotsList(availableSlots),
          ),
        ],
      ),
    );
  }

  Widget _buildNoSlotsMessage() {
    final l10n = AppLocalizations.of(context);
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(
            Icons.event_busy_outlined,
            size: 64,
            color: (isDark
                    ? AppColors.textSecondaryDark
                    : AppColors.textSecondaryLight)
                .withValues(alpha: 0.5),
          ),
          const SizedBox(height: 16),
          Text(
            l10n.noAvailableSlots,
            style: Theme.of(
              context,
            ).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 8),
          Text(
            l10n.doctorNotAvailableSelectAnother,
            textAlign: TextAlign.center,
            style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                  color: isDark
                      ? AppColors.textSecondaryDark
                      : AppColors.textSecondaryLight,
                ),
          ),
        ],
      ),
    );
  }

  Widget _buildTimeSlotsList(List<TimeSlot> slots) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final l10n = AppLocalizations.of(context);

    return ListView.builder(
      padding: const EdgeInsets.symmetric(horizontal: 20),
      itemCount: slots.length,
      itemBuilder: (context, index) {
        final slot = slots[index];
        final isBooked = _bookedSlots.contains(slot.display);
        final isPast = _isSlotPast(_selectedDay, slot.startTime);
        final isAvailable = slot.isAvailable && !isBooked && !isPast;

        return Container(
          margin: const EdgeInsets.only(bottom: 12),
          decoration: BoxDecoration(
            color: isDark ? AppColors.surfaceDark : Colors.white,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(
              color: isAvailable
                  ? AppColors.primary.withValues(alpha: 0.3)
                  : Colors.grey.withValues(alpha: 0.2),
              width: 1,
            ),
            boxShadow: isAvailable
                ? [
                    BoxShadow(
                      color: AppColors.primary.withValues(alpha: 0.1),
                      blurRadius: 10,
                      offset: const Offset(0, 4),
                    ),
                  ]
                : null,
          ),
          child: ListTile(
            contentPadding: const EdgeInsets.symmetric(
              horizontal: 20,
              vertical: 8,
            ),
            leading: Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: isAvailable
                    ? AppColors.success.withValues(alpha: 0.1)
                    : Colors.grey.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Icon(
                isAvailable ? Icons.access_time_rounded : Icons.block_rounded,
                color: isAvailable ? AppColors.success : Colors.grey,
              ),
            ),
            title: Text(
              slot.fullDisplay,
              style: GoogleFonts.poppins(
                fontWeight: FontWeight.w600,
                color: isAvailable
                    ? null
                    : (isDark
                        ? AppColors.textSecondaryDark
                        : AppColors.textSecondaryLight),
                decoration: !isAvailable ? TextDecoration.lineThrough : null,
              ),
            ),
            subtitle: Text(
              isBooked
                  ? l10n.alreadyBooked
                  : isPast
                      ? l10n.timeHasPassed
                      : !slot.isAvailable
                          ? l10n.notAvailable
                          : l10n.availableForBooking,
              style: GoogleFonts.roboto(
                color: isAvailable ? AppColors.success : Colors.grey,
                fontSize: 12,
              ),
            ),
            trailing: isAvailable
                ? Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 16,
                      vertical: 8,
                    ),
                    decoration: BoxDecoration(
                      color: AppColors.primary,
                      borderRadius: BorderRadius.circular(20),
                    ),
                    child: Text(
                      l10n.book,
                      style: GoogleFonts.poppins(
                        color: Colors.white,
                        fontWeight: FontWeight.bold,
                        fontSize: 12,
                      ),
                    ),
                  )
                : const Icon(Icons.block, color: Colors.grey, size: 20),
            onTap: isAvailable ? () => _onSlotTap(slot) : null,
          ),
        );
      },
    );
  }

  bool _isSlotPast(DateTime date, String startTime) {
    if (!isSameDay(date, DateTime.now())) return false;

    // Parse start time (e.g., "09:00")
    final parts = startTime.split(':');
    if (parts.length != 2) return false;

    final hour = int.tryParse(parts[0]) ?? 0;
    final minute = int.tryParse(parts[1]) ?? 0;
    final slotTime = DateTime(date.year, date.month, date.day, hour, minute);

    return slotTime.isBefore(DateTime.now());
  }

  void _onSlotTap(TimeSlot slot) {
    // Capture the outer navigator before opening the bottom sheet
    final navigator = Navigator.of(context);

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (sheetContext) => ConstrainedBox(
        constraints: BoxConstraints(
          maxHeight: MediaQuery.of(context).size.height * 0.85,
        ),
        child: _BookingConfirmationSheet(
          doctor: widget.doctor,
          date: _selectedDay,
          timeSlot: slot,
          parentNavigator: navigator,
        ),
      ),
    );
  }

  String _formatDate(DateTime date) {
    const weekdays = [
      'Monday',
      'Tuesday',
      'Wednesday',
      'Thursday',
      'Friday',
      'Saturday',
      'Sunday',
    ];
    const months = [
      'January',
      'February',
      'March',
      'April',
      'May',
      'June',
      'July',
      'August',
      'September',
      'October',
      'November',
      'December',
    ];
    return '${weekdays[date.weekday - 1]}, ${months[date.month - 1]} ${date.day}';
  }
}

class _BookingConfirmationSheet extends StatelessWidget {
  final DoctorModel doctor;
  final DateTime date;
  final TimeSlot timeSlot;
  final NavigatorState parentNavigator;

  const _BookingConfirmationSheet({
    required this.doctor,
    required this.date,
    required this.timeSlot,
    required this.parentNavigator,
  });

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);

    return SafeArea(
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 40,
              height: 4,
              decoration: BoxDecoration(
                color: Colors.grey[300],
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            const SizedBox(height: 24),
            const Icon(
              Icons.calendar_today_rounded,
              size: 48,
              color: AppColors.primary,
            ),
            const SizedBox(height: 16),
            Text(
              l10n.confirmBooking,
              style: Theme.of(
                context,
              ).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 24),

            // Booking Details
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: AppColors.primary.withValues(alpha: 0.05),
                borderRadius: BorderRadius.circular(16),
              ),
              child: Column(
                children: [
                  _buildDetailRow(
                    context,
                    Icons.person,
                    l10n.doctor,
                    doctor.name,
                  ),
                  const Divider(height: 24),
                  _buildDetailRow(
                    context,
                    Icons.medical_services,
                    l10n.specialty,
                    doctor.specialization,
                  ),
                  const Divider(height: 24),
                  _buildDetailRow(
                    context,
                    Icons.calendar_month,
                    l10n.date,
                    _formatDate(date),
                  ),
                  const Divider(height: 24),
                  _buildDetailRow(
                    context,
                    Icons.access_time,
                    l10n.time,
                    timeSlot.fullDisplay,
                  ),
                ],
              ),
            ),
            const SizedBox(height: 24),

            // Buttons
            Row(
              children: [
                Expanded(
                  child: OutlinedButton(
                    onPressed: () => Navigator.pop(context),
                    style: OutlinedButton.styleFrom(
                      padding: const EdgeInsets.symmetric(vertical: 16),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                    ),
                    child: Text(l10n.cancel),
                  ),
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: ElevatedButton(
                    onPressed: () {
                      // Close the bottom sheet first
                      Navigator.pop(context);
                      // Use the parent navigator to push the booking screen
                      parentNavigator.push(
                        MaterialPageRoute(
                          builder: (_) => BookingScreen(
                            doctor: doctor,
                            initialDate: date,
                            initialTimeSlot: timeSlot,
                          ),
                        ),
                      );
                    },
                    style: ElevatedButton.styleFrom(
                      backgroundColor: AppColors.primary,
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(vertical: 16),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                    ),
                    child: Text(l10n.confirm),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
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
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: isDark
                          ? AppColors.textSecondaryDark
                          : AppColors.textSecondaryLight,
                    ),
              ),
              Text(
                value,
                style: Theme.of(
                  context,
                ).textTheme.bodyMedium?.copyWith(fontWeight: FontWeight.w600),
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
              ),
            ],
          ),
        ),
      ],
    );
  }

  String _formatDate(DateTime date) {
    const months = [
      'Jan',
      'Feb',
      'Mar',
      'Apr',
      'May',
      'Jun',
      'Jul',
      'Aug',
      'Sep',
      'Oct',
      'Nov',
      'Dec',
    ];
    return '${months[date.month - 1]} ${date.day}, ${date.year}';
  }
}
