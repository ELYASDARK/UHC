import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:table_calendar/table_calendar.dart';
import '../../core/constants/app_colors.dart';
import '../../data/models/doctor_model.dart';
import '../../data/models/appointment_model.dart';
import '../../providers/appointment_provider.dart';
import 'package:uhc/l10n/app_localizations.dart';

/// Reschedule appointment screen
class RescheduleScreen extends StatefulWidget {
  final AppointmentModel appointment;
  final DoctorModel? doctor;

  const RescheduleScreen({super.key, required this.appointment, this.doctor});

  @override
  State<RescheduleScreen> createState() => _RescheduleScreenState();
}

class _RescheduleScreenState extends State<RescheduleScreen> {
  DateTime _focusedDay = DateTime.now();
  DateTime? _selectedDay;
  TimeSlot? _selectedTimeSlot;
  CalendarFormat _calendarFormat = CalendarFormat.month;
  final _reasonController = TextEditingController();
  bool _isLoading = false;

  @override
  void initState() {
    super.initState();
    _selectedDay = widget.appointment.appointmentDate;
    _focusedDay = _selectedDay!;
  }

  @override
  void dispose() {
    _reasonController.dispose();
    super.dispose();
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
    if (widget.doctor == null) return [];
    final dayName = _getDayName(date);
    return widget.doctor!.weeklySchedule[dayName] ?? [];
  }

  bool _canReschedule() {
    // Check 24-hour policy using UTC to avoid timezone issues
    final appointmentTime = widget.appointment.appointmentDate.toUtc();
    final now = DateTime.now().toUtc();
    final hoursUntil = appointmentTime.difference(now).inHours;
    return hoursUntil >= 24;
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
          : SingleChildScrollView(
              padding: const EdgeInsets.all(20),
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
                        });
                      },
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
                        return slots.isNotEmpty;
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
                      onPressed:
                          _selectedDay != null &&
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
            '${l10n.date}: ${_formatDate(widget.appointment.appointmentDate)}',
          ),
          const SizedBox(height: 4),
          Text('${l10n.time}: ${widget.appointment.timeSlot}'),
        ],
      ),
    );
  }

  Widget _buildTimeSlots(bool isDark) {
    final l10n = AppLocalizations.of(context);
    final slots = _getAvailableSlots(_selectedDay!);

    if (slots.isEmpty) {
      return Container(
        padding: const EdgeInsets.all(20),
        decoration: BoxDecoration(
          color: isDark ? AppColors.surfaceDark : Colors.grey[100],
          borderRadius: BorderRadius.circular(12),
        ),
        child: Center(child: Text(l10n.noAvailableSlotsOnThisDay)),
      );
    }

    return Wrap(
      spacing: 10,
      runSpacing: 10,
      children: slots.where((s) => s.isAvailable).map((slot) {
        final isSelected = _selectedTimeSlot == slot;
        return GestureDetector(
          onTap: () => setState(() => _selectedTimeSlot = slot),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            decoration: BoxDecoration(
              color: isSelected
                  ? AppColors.primary
                  : (isDark ? AppColors.surfaceDark : Colors.white),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(
                color: isSelected
                    ? AppColors.primary
                    : AppColors.primary.withValues(alpha: 0.3),
              ),
            ),
            child: Text(
              slot.display,
              style: TextStyle(
                color: isSelected ? Colors.white : null,
                fontWeight: isSelected ? FontWeight.bold : null,
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
            const SnackBar(
              content: Text('Failed to reschedule. The slot might be taken.'),
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
