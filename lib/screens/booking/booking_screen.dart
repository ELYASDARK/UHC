import 'dart:math';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:table_calendar/table_calendar.dart';
import 'package:qr_flutter/qr_flutter.dart';
import 'package:lottie/lottie.dart';
import 'package:intl/intl.dart';
import '../../core/constants/app_colors.dart';
import '../../data/models/doctor_model.dart';
import '../../data/models/appointment_model.dart';
import '../../providers/appointment_provider.dart';
import '../../providers/auth_provider.dart';
import '../../l10n/app_localizations.dart';

import '../home/main_shell.dart';

/// Main booking screen with calendar and time selection
class BookingScreen extends StatefulWidget {
  final DoctorModel doctor;

  const BookingScreen({super.key, required this.doctor});

  @override
  State<BookingScreen> createState() => _BookingScreenState();
}

class _BookingScreenState extends State<BookingScreen> {
  CalendarFormat _calendarFormat = CalendarFormat.month;
  DateTime _focusedDay = DateTime.now();
  DateTime? _selectedDay;
  TimeSlot? _selectedTimeSlot;
  AppointmentType _appointmentType = AppointmentType.regularCheckup;
  final _notesController = TextEditingController();
  int _currentStep = 0;
  bool _isLoading = false;

  @override
  void dispose() {
    _notesController.dispose();
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
    final dayName = _getDayName(date);
    final doctorSlots = widget.doctor.weeklySchedule[dayName];

    // If doctor has specific slots, use them
    if (doctorSlots != null && doctorSlots.isNotEmpty) {
      return doctorSlots;
    }

    // Otherwise, return default time slots for weekdays
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
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Scaffold(
      appBar: AppBar(
        title: Text(AppLocalizations.of(context).bookAppointment),
        centerTitle: true,
      ),
      body: Stepper(
        currentStep: _currentStep,
        onStepContinue: _onStepContinue,
        onStepCancel: _onStepCancel,
        controlsBuilder: (context, details) {
          return Padding(
            padding: const EdgeInsets.only(top: 20),
            child: Row(
              children: [
                Expanded(
                  child: ElevatedButton(
                    onPressed: _isLoading ? null : details.onStepContinue,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: AppColors.primary,
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(vertical: 14),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                    ),
                    child: _isLoading
                        ? const SizedBox(
                            width: 20,
                            height: 20,
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              valueColor: AlwaysStoppedAnimation<Color>(
                                Colors.white,
                              ),
                            ),
                          )
                        : Text(
                            _currentStep == 2
                                ? AppLocalizations.of(context).confirmBooking
                                : AppLocalizations.of(context).continueText,
                          ),
                  ),
                ),
                if (_currentStep > 0) ...[
                  const SizedBox(width: 12),
                  Expanded(
                    child: OutlinedButton(
                      onPressed: details.onStepCancel,
                      style: OutlinedButton.styleFrom(
                        padding: const EdgeInsets.symmetric(vertical: 14),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                      ),
                      child: Text(AppLocalizations.of(context).back),
                    ),
                  ),
                ],
              ],
            ),
          );
        },
        steps: [
          // Step 1: Select Date
          Step(
            title: Text(AppLocalizations.of(context).selectDate),
            subtitle: _selectedDay != null
                ? Text(_formatDate(_selectedDay!))
                : null,
            isActive: _currentStep >= 0,
            state: _currentStep > 0 ? StepState.complete : StepState.indexed,
            content: _buildCalendarStep(isDark),
          ),
          // Step 2: Select Time
          Step(
            title: Text(AppLocalizations.of(context).selectTime),
            subtitle: _selectedTimeSlot != null
                ? Text(_selectedTimeSlot!.display)
                : null,
            isActive: _currentStep >= 1,
            state: _currentStep > 1 ? StepState.complete : StepState.indexed,
            content: _buildTimeSlotStep(isDark),
          ),
          // Step 3: Confirm
          Step(
            title: Text(AppLocalizations.of(context).confirmDetails),
            isActive: _currentStep >= 2,
            state: StepState.indexed,
            content: _buildConfirmationStep(isDark),
          ),
        ],
      ),
    );
  }

  Widget _buildCalendarStep(bool isDark) {
    return Container(
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
        selectedDayPredicate: (day) => isSameDay(_selectedDay, day),
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
          // Allow all future weekdays (Monday-Friday)
          final isWeekday = day.weekday >= 1 && day.weekday <= 5;
          final isFuture = day.isAfter(
            DateTime.now().subtract(const Duration(days: 1)),
          );
          return isWeekday && isFuture;
        },
      ),
    );
  }

  Widget _buildTimeSlotStep(bool isDark) {
    final l10n = AppLocalizations.of(context);
    if (_selectedDay == null) {
      return Center(child: Text(l10n.pleaseSelectDateFirst));
    }

    final slots = _getAvailableSlots(_selectedDay!);

    if (slots.isEmpty) {
      return Center(
        child: Column(
          children: [
            Icon(Icons.event_busy, size: 48, color: Colors.grey[400]),
            const SizedBox(height: 12),
            Text(l10n.noAvailableSlotsOnThisDay),
          ],
        ),
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          '${l10n.availableTimesFor} ${_formatDate(_selectedDay!)}',
          style: Theme.of(
            context,
          ).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold),
        ),
        const SizedBox(height: 16),
        Wrap(
          spacing: 10,
          runSpacing: 10,
          children: slots.map((slot) {
            final isPast = _isSlotPast(_selectedDay!, slot.startTime);
            final isAvailable = slot.isAvailable && !isPast;
            final isSelected = _selectedTimeSlot == slot;

            return GestureDetector(
              onTap: isAvailable
                  ? () => setState(() => _selectedTimeSlot = slot)
                  : null,
              child: Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 16,
                  vertical: 12,
                ),
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
                    decoration: !isAvailable
                        ? TextDecoration.lineThrough
                        : null,
                  ),
                ),
              ),
            );
          }).toList(),
        ),
        const SizedBox(height: 24),

        // Appointment Type
        Text(
          l10n.appointmentType,
          style: Theme.of(
            context,
          ).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold),
        ),
        const SizedBox(height: 12),
        Wrap(
          spacing: 10,
          runSpacing: 10,
          children: AppointmentType.values.map((type) {
            final isSelected = _appointmentType == type;
            return ChoiceChip(
              label: Text(_getTypeName(type)),
              selected: isSelected,
              onSelected: (_) => setState(() => _appointmentType = type),
              selectedColor: AppColors.primary,
              backgroundColor: isDark ? Colors.grey[800] : Colors.grey[200],
              labelStyle: TextStyle(
                color: isSelected
                    ? Colors.white
                    : (isDark
                          ? AppColors.textPrimaryDark
                          : AppColors.textPrimaryLight),
                fontWeight: isSelected ? FontWeight.w600 : FontWeight.w500,
              ),
              showCheckmark: false,
            );
          }).toList(),
        ),
        const SizedBox(height: 24),

        // Notes
        Text(
          l10n.additionalNotesOptional,
          style: Theme.of(
            context,
          ).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold),
        ),
        const SizedBox(height: 12),
        TextField(
          controller: _notesController,
          maxLines: 3,
          decoration: InputDecoration(
            hintText: l10n.describeSymptoms,
            border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
          ),
        ),
      ],
    );
  }

  Widget _buildConfirmationStep(bool isDark) {
    return Container(
      padding: const EdgeInsets.all(20),
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
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Doctor Info
          Row(
            children: [
              CircleAvatar(
                radius: 30,
                backgroundImage: widget.doctor.photoUrl != null
                    ? NetworkImage(widget.doctor.photoUrl!)
                    : null,
                child: widget.doctor.photoUrl == null
                    ? const Icon(Icons.person, size: 30)
                    : null,
              ),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      widget.doctor.name,
                      style: Theme.of(context).textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    Text(
                      widget.doctor.specialization,
                      style: TextStyle(
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
          const SizedBox(height: 20),
          const Divider(),
          const SizedBox(height: 20),

          // Booking Details
          _buildDetailRow(
            Icons.calendar_month,
            'Date',
            _selectedDay != null ? _formatDate(_selectedDay!) : 'Not selected',
          ),
          const SizedBox(height: 12),
          _buildDetailRow(
            Icons.access_time,
            'Time',
            _selectedTimeSlot?.display ?? 'Not selected',
          ),
          const SizedBox(height: 12),
          _buildDetailRow(
            Icons.medical_services,
            'Type',
            _getTypeName(_appointmentType),
          ),
          if (_notesController.text.isNotEmpty) ...[
            const SizedBox(height: 12),
            _buildDetailRow(Icons.notes, 'Notes', _notesController.text),
          ],

          const SizedBox(height: 20),

          // Policy reminder
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: AppColors.warning.withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Row(
              children: [
                const Icon(Icons.info_outline, color: AppColors.warning),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    AppLocalizations.of(context).bookingCancellationPolicy,
                    style: TextStyle(
                      color: isDark
                          ? AppColors.textSecondaryDark
                          : AppColors.textSecondaryLight,
                      fontSize: 13,
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

  Widget _buildDetailRow(IconData icon, String label, String value) {
    return Row(
      children: [
        Icon(icon, color: AppColors.primary, size: 20),
        const SizedBox(width: 12),
        Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              label,
              style: TextStyle(
                color: Theme.of(context).brightness == Brightness.dark
                    ? AppColors.textSecondaryDark
                    : AppColors.textSecondaryLight,
                fontSize: 12,
              ),
            ),
            Text(value, style: const TextStyle(fontWeight: FontWeight.w600)),
          ],
        ),
      ],
    );
  }

  void _onStepContinue() {
    if (_currentStep == 0 && _selectedDay == null) {
      _showError(AppLocalizations.of(context).pleaseSelectDate);
      return;
    }
    if (_currentStep == 1 && _selectedTimeSlot == null) {
      _showError(AppLocalizations.of(context).pleaseSelectTime);
      return;
    }
    if (_currentStep < 2) {
      setState(() => _currentStep++);
    } else {
      _submitBooking();
    }
  }

  void _onStepCancel() {
    if (_currentStep > 0) {
      setState(() => _currentStep--);
    }
  }

  void _showError(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: AppColors.error,
        behavior: SnackBarBehavior.floating,
      ),
    );
  }

  String _generateBookingReference() {
    const chars = 'ABCDEFGHJKLMNPQRSTUVWXYZ23456789';
    final random = Random();
    return List.generate(
      8,
      (index) => chars[random.nextInt(chars.length)],
    ).join();
  }

  Future<void> _submitBooking() async {
    if (_isLoading) return;

    setState(() {
      _isLoading = true;
    });

    try {
      final authProvider = context.read<AuthProvider>();
      final appointmentProvider = context.read<AppointmentProvider>();
      final user = authProvider.user;

      if (user == null) {
        _showError(AppLocalizations.of(context).pleaseLoginToBook);
        return;
      }

      final bookingReference = _generateBookingReference();

      final appointment = AppointmentModel(
        id: '',
        bookingReference: bookingReference,
        patientId: user.id,
        patientName: user.fullName,
        patientEmail: user.email,
        doctorId: widget.doctor.id,
        doctorName: widget.doctor.name,
        department: widget.doctor.department.name,
        appointmentDate: _selectedDay!,
        timeSlot: _selectedTimeSlot!.display,
        type: _appointmentType,
        status: AppointmentStatus.pending,
        notes: _notesController.text.isEmpty ? null : _notesController.text,
        createdAt: DateTime.now(),
        updatedAt: DateTime.now(),
      );

      final appointmentId = await appointmentProvider.bookAppointment(
        appointment,
      );

      if (appointmentId != null && mounted) {
        Navigator.pushReplacement(
          context,
          MaterialPageRoute(
            builder: (_) => BookingSuccessScreen(
              appointmentId: appointmentId,
              bookingReference: bookingReference,
              doctorName: widget.doctor.name,
              date: _selectedDay!,
              timeSlot: _selectedTimeSlot!.display,
            ),
          ),
        );
      } else if (mounted) {
        _showError(
          appointmentProvider.error ??
              AppLocalizations.of(context).bookingFailed,
        );
      }
    } finally {
      if (mounted) {
        setState(() {
          _isLoading = false;
        });
      }
    }
  }

  String _formatDate(DateTime date) {
    final locale = Localizations.localeOf(context).toString();
    return DateFormat.yMMMMEEEEd(locale).format(date);
  }

  String _getTypeName(AppointmentType type) {
    final l10n = AppLocalizations.of(context);
    switch (type) {
      case AppointmentType.regularCheckup:
        return l10n.regularVisit;
      case AppointmentType.followUp:
        return l10n.followUp;
      case AppointmentType.emergency:
        return l10n.emergency;
      case AppointmentType.consultation:
        return l10n.consultation;
    }
  }
}

/// Booking success screen with QR code
class BookingSuccessScreen extends StatelessWidget {
  final String appointmentId;
  final String? bookingReference;
  final String doctorName;
  final DateTime date;
  final String timeSlot;

  const BookingSuccessScreen({
    super.key,
    required this.appointmentId,
    this.bookingReference,
    required this.doctorName,
    required this.date,
    required this.timeSlot,
  });

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final l10n = AppLocalizations.of(context);

    return Scaffold(
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: Column(
            children: [
              const SizedBox(height: 40),

              // Success animation
              SizedBox(
                height: 180,
                child: Lottie.asset(
                  'assets/animations/success.json',
                  repeat: false,
                  errorBuilder: (context, error, stackTrace) {
                    return Container(
                      width: 120,
                      height: 120,
                      decoration: BoxDecoration(
                        color: AppColors.success.withValues(alpha: 0.1),
                        shape: BoxShape.circle,
                      ),
                      child: const Icon(
                        Icons.check_circle,
                        size: 80,
                        color: AppColors.success,
                      ),
                    );
                  },
                ),
              ),
              const SizedBox(height: 24),

              Text(
                '${l10n.bookingConfirmed}!',
                style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                  fontWeight: FontWeight.bold,
                  color: AppColors.success,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                l10n.appointmentScheduledSuccessfully,
                textAlign: TextAlign.center,
                style: TextStyle(
                  color: isDark
                      ? AppColors.textSecondaryDark
                      : AppColors.textSecondaryLight,
                ),
              ),
              const SizedBox(height: 32),

              // Appointment Card
              Container(
                padding: const EdgeInsets.all(20),
                decoration: BoxDecoration(
                  color: isDark ? AppColors.surfaceDark : Colors.white,
                  borderRadius: BorderRadius.circular(20),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withValues(alpha: 0.1),
                      blurRadius: 20,
                      offset: const Offset(0, 10),
                    ),
                  ],
                ),
                child: Column(
                  children: [
                    // QR Code
                    Container(
                      padding: const EdgeInsets.all(16),
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(16),
                      ),
                      child: QrImageView(
                        data: 'UHC_APPOINTMENT:$appointmentId',
                        version: QrVersions.auto,
                        size: 180,
                        backgroundColor: Colors.white,
                        errorCorrectionLevel: QrErrorCorrectLevel.M,
                      ),
                    ),
                    const SizedBox(height: 16),
                    Text(
                      l10n.showQRCodeAtCheckIn,
                      style: TextStyle(
                        color: isDark
                            ? AppColors.textSecondaryDark
                            : AppColors.textSecondaryLight,
                        fontSize: 13,
                      ),
                    ),
                    const SizedBox(height: 20),
                    const Divider(),
                    const SizedBox(height: 20),

                    // Details
                    _buildDetailRow(
                      context,
                      Icons.person,
                      l10n.doctor,
                      'Dr. $doctorName',
                    ),
                    const SizedBox(height: 12),
                    _buildDetailRow(
                      context,
                      Icons.calendar_month,
                      l10n.date,
                      _formatDate(date),
                    ),
                    const SizedBox(height: 12),
                    _buildDetailRow(
                      context,
                      Icons.access_time,
                      l10n.time,
                      timeSlot,
                    ),
                    const SizedBox(height: 12),
                    _buildDetailRow(
                      context,
                      Icons.confirmation_number,
                      l10n.bookingId,
                      bookingReference ??
                          appointmentId.substring(0, 8).toUpperCase(),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 32),

              // Buttons
              SizedBox(
                width: double.infinity,
                child: ElevatedButton(
                  onPressed: () {
                    // Navigate to Home (Tab 0) and clear stack
                    Navigator.of(context).pushAndRemoveUntil(
                      MaterialPageRoute(
                        builder: (_) => const MainShell(initialIndex: 0),
                      ),
                      (route) => false,
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
                  child: Text(l10n.backToHome),
                ),
              ),
              const SizedBox(height: 12),
              SizedBox(
                width: double.infinity,
                child: OutlinedButton(
                  onPressed: () {
                    // Navigate to Appointments (Tab 2) and clear stack
                    Navigator.of(context).pushAndRemoveUntil(
                      MaterialPageRoute(
                        builder: (_) => const MainShell(initialIndex: 2),
                      ),
                      (route) => false,
                    );
                  },
                  style: OutlinedButton.styleFrom(
                    padding: const EdgeInsets.symmetric(vertical: 16),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                  ),
                  child: Text(l10n.viewMyAppointments),
                ),
              ),
            ],
          ),
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
                style: TextStyle(
                  color: isDark
                      ? AppColors.textSecondaryDark
                      : AppColors.textSecondaryLight,
                  fontSize: 12,
                ),
              ),
              Text(value, style: const TextStyle(fontWeight: FontWeight.w600)),
            ],
          ),
        ),
      ],
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
    return '${weekdays[date.weekday - 1]}, ${months[date.month - 1]} ${date.day}, ${date.year}';
  }
}
