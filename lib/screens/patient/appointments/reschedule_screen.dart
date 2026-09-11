import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:table_calendar/table_calendar.dart';
import '../../../core/constants/app_colors.dart';
import '../../../core/widgets/responsive_layout.dart';
import '../../../data/models/doctor_model.dart';
import '../../../data/models/appointment_model.dart';
import '../../../data/repositories/appointment_repository.dart';
import '../../../providers/appointment_provider.dart';
import 'package:uhc/l10n/app_localizations.dart';

/// Reschedule appointment screen
class RescheduleScreen extends StatefulWidget {
  final AppointmentModel appointment;
  final DoctorModel? doctor;
  final AppointmentRepository? appointmentRepository;

  const RescheduleScreen({
    super.key,
    required this.appointment,
    this.doctor,
    this.appointmentRepository,
  });

  @override
  State<RescheduleScreen> createState() => _RescheduleScreenState();
}

class _RescheduleScreenState extends State<RescheduleScreen> {
  late final AppointmentRepository _appointmentRepo;
  DateTime _focusedDay = DateTime.now();
  DateTime? _selectedDay;
  TimeSlot? _selectedTimeSlot;
  CalendarFormat _calendarFormat = CalendarFormat.month;
  final _reasonController = TextEditingController();
  bool _isLoading = false;

  bool _isLoadingAvailability = false;
  String? _availabilityError;
  int _availabilityRequestId = 0;
  Map<String, bool>? _serverAvailability;

  @override
  void initState() {
    super.initState();
    _appointmentRepo = widget.appointmentRepository ?? AppointmentRepository();
    _selectedDay = widget.appointment.appointmentDate;
    _focusedDay = _selectedDay!;
    _fetchAvailability(_selectedDay!);
  }

  Future<void> _fetchAvailability(DateTime date) async {
    if (widget.doctor == null) return;

    final requestId = ++_availabilityRequestId;
    setState(() {
      _isLoadingAvailability = true;
      _availabilityError = null;
    });

    try {
      final availability = await _appointmentRepo.getDoctorDayAvailability(
        doctorId: widget.doctor!.id,
        date: date,
      );
      if (!mounted || requestId != _availabilityRequestId) return;
      if (_selectedDay == null || !isSameDay(_selectedDay!, date)) return;

      final map = <String, bool>{};
      for (final slot in availability.slots) {
        map[slot.startTime] = slot.isAvailable;
        if (slot.timeSlot.isNotEmpty) {
          map[slot.timeSlot] = slot.isAvailable;
        }
      }

      setState(() {
        _serverAvailability = map;
        _isLoadingAvailability = false;
        _availabilityError = null;

        if (_selectedTimeSlot != null) {
          final isAvail = (map[_selectedTimeSlot!.startTime] ??
                  map[_selectedTimeSlot!.fullDisplay]) ??
              false;
          if (!isAvail) {
            _selectedTimeSlot = null;
          }
        }
      });
    } catch (e) {
      if (!mounted || requestId != _availabilityRequestId) return;
      debugPrint('Error loading availability for reschedule: $e');
      setState(() {
        _serverAvailability = null;
        _isLoadingAvailability = false;
        _availabilityError = e.toString();
        _selectedTimeSlot = null;
      });
    }
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

  @override
  void dispose() {
    _reasonController.dispose();
    super.dispose();
  }

  List<TimeSlot> _getAvailableSlots(DateTime date) {
    if (widget.doctor == null) return [];
    return widget.doctor!.getAvailableSlots(date);
  }

  DateTime _getExactAppointmentTime() {
    // Extract the calendar day in clinic time, regardless of device timezone.
    final date = widget.appointment.appointmentDate.toUtc()
        .add(const Duration(hours: 3));
    final timeSlot = widget.appointment.timeSlot; // e.g., '14:30 - 15:00'
    final startTimeStr = timeSlot.split(' - ').first.trim(); // '14:30'
    final parts = startTimeStr.split(':');
    int hour = 0;
    int minute = 0;
    if (parts.length == 2) {
      hour = int.tryParse(parts[0]) ?? 0;
      minute = int.tryParse(parts[1]) ?? 0;
    }
    // Clinic is in Baghdad timezone (UTC+3, no DST)
    return DateTime.utc(date.year, date.month, date.day, hour, minute)
        .subtract(const Duration(hours: 3));
  }

  bool _canReschedule() {
    // Check 24-hour policy against canonical UTC appointment time
    final appointmentTime = _getExactAppointmentTime();
    final now = DateTime.now().toUtc();
    return appointmentTime.difference(now).inMinutes >= 24 * 60;
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final canReschedule = _canReschedule();

    return Scaffold(
      appBar: AppBar(
        title: Text(l10n.rescheduleAppointmentTitle),
        centerTitle: true,
      ),
      body: !canReschedule
          ? _buildPolicyViolation(isDark)
          : ResponsivePage(
              maxWidth: 860,
              bottomPadding: UhcResponsive.isWide(context) ? 32 : 100,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Current Appointment Info
                  _buildCurrentAppointmentCard(isDark),
                  const SizedBox(height: 24),

                  Text(
                    l10n.selectNewDate,
                    style: Theme.of(context).textTheme.titleMedium?.copyWith(
                          fontWeight: FontWeight.bold,
                        ),
                  ),
                  const SizedBox(height: 12),

                  // Calendar
                  Container(
                    decoration: BoxDecoration(
                      color: isDark ? AppColors.surfaceDark : Colors.white,
                      borderRadius: BorderRadius.circular(16),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black.withValues(alpha: 0.05),
                          blurRadius: 10,
                          offset: const Offset(0, 4),
                        ),
                      ],
                    ),
                    child: TableCalendar(
                      firstDay: DateTime.now(),
                      lastDay: DateTime.now().add(const Duration(days: 60)),
                      focusedDay: _focusedDay,
                      calendarFormat: _calendarFormat,
                      selectedDayPredicate: (day) =>
                          isSameDay(_selectedDay, day),
                      onDaySelected: (selectedDay, focusedDay) {
                        setState(() {
                          _selectedDay = selectedDay;
                          _focusedDay = focusedDay;
                          _selectedTimeSlot = null;
                          _serverAvailability = null;
                          _availabilityError = null;
                        });
                        _fetchAvailability(selectedDay);
                      },
                      onFormatChanged: (format) {
                        setState(() {
                          _calendarFormat = format;
                        });
                      },
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
                          color: isDark ? Colors.grey[700] : Colors.grey[400],
                        ),
                      ),
                      headerStyle: const HeaderStyle(
                        formatButtonVisible: true,
                        titleCentered: true,
                      ),
                      enabledDayPredicate: (day) {
                        final slots = _getAvailableSlots(day);
                        return slots.any(
                          (slot) => !_isSlotPast(day, slot.startTime),
                        );
                      },
                    ),
                  ),
                  const SizedBox(height: 24),

                  // Time Slots
                  if (_selectedDay != null) ...[
                    Text(
                      l10n.selectNewTime,
                      style: Theme.of(context).textTheme.titleMedium?.copyWith(
                            fontWeight: FontWeight.bold,
                          ),
                    ),
                    const SizedBox(height: 12),
                    _buildTimeSlots(isDark),
                  ],
                  const SizedBox(height: 24),

                  // Reason
                  Text(
                    l10n.reasonForReschedule,
                    style: Theme.of(context).textTheme.titleMedium?.copyWith(
                          fontWeight: FontWeight.bold,
                        ),
                  ),
                  const SizedBox(height: 8),
                  TextField(
                    controller: _reasonController,
                    maxLines: 3,
                    decoration: InputDecoration(
                      hintText: l10n.pleaseProvideReason,
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                    ),
                  ),
                  const SizedBox(height: 32),

                  // Confirm Button
                  SizedBox(
                    width: double.infinity,
                    child: ElevatedButton(
                      onPressed: _selectedDay != null &&
                              _selectedTimeSlot != null &&
                              !_isLoading
                          ? _confirmReschedule
                          : null,
                      style: ElevatedButton.styleFrom(
                        backgroundColor: AppColors.primary,
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(vertical: 16),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                      ),
                      child: _isLoading
                          ? const SizedBox(
                              width: 24,
                              height: 24,
                              child: CircularProgressIndicator(
                                strokeWidth: 2,
                                color: Colors.white,
                              ),
                            )
                          : Text(l10n.confirmReschedule),
                    ),
                  ),
                ],
              ),
            ),
    );
  }

  Widget _buildCurrentAppointmentCard(bool isDark) {
    final l10n = AppLocalizations.of(context);
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.warning.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppColors.warning.withValues(alpha: 0.3)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.event, color: AppColors.warning),
              const SizedBox(width: 8),
              Text(
                l10n.currentAppointment,
                style: Theme.of(context).textTheme.titleSmall?.copyWith(
                      fontWeight: FontWeight.bold,
                      color: AppColors.warning,
                    ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Text('${l10n.doctor}: Dr. ${widget.appointment.doctorName}'),
          const SizedBox(height: 4),
          Text(
            '${l10n.date}: ${_formatDate(widget.appointment.appointmentDate, l10n)}',
          ),
          const SizedBox(height: 4),
          Text('${l10n.time}: ${widget.appointment.timeSlot}'),
        ],
      ),
    );
  }

  Widget _buildTimeSlots(bool isDark) {
    final l10n = AppLocalizations.of(context);

    if (_isLoadingAvailability) {
      return const Center(
        child: Padding(
          padding: EdgeInsets.symmetric(vertical: 24.0),
          child: CircularProgressIndicator(),
        ),
      );
    }

    if (_availabilityError != null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 20.0),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(
                Icons.error_outline_rounded,
                size: 48,
                color: AppColors.error,
              ),
              const SizedBox(height: 12),
              Text(
                l10n.somethingWentWrong,
                style: Theme.of(context).textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.bold,
                    ),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 12),
              ElevatedButton.icon(
                onPressed: () => _fetchAvailability(_selectedDay!),
                icon: const Icon(Icons.refresh, size: 18),
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

    final slots = _getAvailableSlots(_selectedDay!);

    if (slots.isEmpty) {
      final hasSchedule = widget.doctor?.hasActiveSchedule ?? false;
      return Container(
        padding: const EdgeInsets.all(20),
        decoration: BoxDecoration(
          color: isDark ? AppColors.surfaceDark : Colors.grey[100],
          borderRadius: BorderRadius.circular(12),
        ),
        child: Center(
          child: Text(
            hasSchedule ? l10n.noAvailableSlotsOnThisDay : l10n.noScheduleSet,
          ),
        ),
      );
    }

    return Wrap(
      spacing: 10,
      runSpacing: 10,
      children: slots.map((slot) {
        final isPast = _isSlotPast(_selectedDay!, slot.startTime);
        final serverAvailable = (_serverAvailability?[slot.startTime] ??
                _serverAvailability?[slot.fullDisplay]) ??
            false;
        final isAvailable = slot.isAvailable && !isPast && serverAvailable;
        final isSelected = _selectedTimeSlot == slot;

        return GestureDetector(
          onTap: isAvailable
              ? () => setState(() => _selectedTimeSlot = slot)
              : null,
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            decoration: BoxDecoration(
              color: isSelected
                  ? AppColors.primary
                  : isAvailable
                      ? (isDark ? AppColors.surfaceDark : Colors.white)
                      : Colors.grey.withValues(alpha: 0.2),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(
                color: isSelected
                    ? AppColors.primary
                    : isAvailable
                        ? AppColors.primary.withValues(alpha: 0.3)
                        : Colors.grey.withValues(alpha: 0.2),
              ),
              boxShadow: isSelected
                  ? [
                      BoxShadow(
                        color: AppColors.primary.withValues(alpha: 0.3),
                        blurRadius: 8,
                        offset: const Offset(0, 4),
                      ),
                    ]
                  : null,
            ),
            child: Text(
              slot.display,
              style: TextStyle(
                color: isSelected
                    ? Colors.white
                    : isAvailable
                        ? (isDark
                            ? AppColors.textPrimaryDark
                            : AppColors.textPrimaryLight)
                        : Colors.grey,
                fontWeight: isSelected ? FontWeight.bold : FontWeight.w500,
                decoration: !isAvailable ? TextDecoration.lineThrough : null,
              ),
            ),
          ),
        );
      }).toList(),
    );
  }

  Widget _buildPolicyViolation(bool isDark) {
    final l10n = AppLocalizations.of(context);
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              padding: const EdgeInsets.all(24),
              decoration: BoxDecoration(
                color: AppColors.error.withValues(alpha: 0.1),
                shape: BoxShape.circle,
              ),
              child: const Icon(Icons.block, size: 64, color: AppColors.error),
            ),
            const SizedBox(height: 24),
            Text(
              l10n.cannotReschedule,
              style: Theme.of(
                context,
              ).textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 12),
            Text(
              l10n.reschedulePolicyMessage,
              textAlign: TextAlign.center,
              style: TextStyle(
                color: isDark
                    ? AppColors.textSecondaryDark
                    : AppColors.textSecondaryLight,
              ),
            ),
            const SizedBox(height: 32),
            SizedBox(
              width: double.infinity,
              child: OutlinedButton(
                onPressed: () => Navigator.pop(context),
                child: Text(l10n.goBack),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _confirmReschedule() async {
    final l10n = AppLocalizations.of(context);
    if (widget.doctor != null && !widget.doctor!.canBook) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(l10n.doctorNotAvailableSelectAnother),
          backgroundColor: AppColors.error,
        ),
      );
      return;
    }
    setState(() => _isLoading = true);

    try {
      final provider = context.read<AppointmentProvider>();
      final success = await provider.rescheduleAppointment(
        appointmentId: widget.appointment.id,
        newDate: _selectedDay!,
        newTimeSlot: _selectedTimeSlot!.display,
        doctorId: widget.appointment.doctorId,
        doctorName: widget.appointment.doctorName,
        userId: widget.appointment.patientId,
        reason: _reasonController.text.isEmpty ? null : _reasonController.text,
      );

      if (success) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(l10n.rescheduleSuccess),
              backgroundColor: AppColors.success,
            ),
          );
          Navigator.pop(context, true);
        }
      } else {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(l10n.rescheduleFailedSlotTaken),
              backgroundColor: AppColors.error,
            ),
          );
        }
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('${l10n.error}: ${e.toString()}'),
            backgroundColor: AppColors.error,
          ),
        );
      }
    } finally {
      if (mounted) {
        setState(() => _isLoading = false);
      }
    }
  }

  String _formatDate(DateTime date, AppLocalizations l10n) {
    final months = [
      l10n.jan,
      l10n.feb,
      l10n.mar,
      l10n.apr,
      l10n.mayShort,
      l10n.jun,
      l10n.jul,
      l10n.aug,
      l10n.sep,
      l10n.oct,
      l10n.nov,
      l10n.dec,
    ];
    return '${months[date.month - 1]} ${date.day}, ${date.year}';
  }
}
