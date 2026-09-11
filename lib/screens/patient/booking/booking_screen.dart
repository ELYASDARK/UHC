import 'dart:async';
import 'dart:math';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:table_calendar/table_calendar.dart';
import 'package:qr_flutter/qr_flutter.dart';
import 'package:lottie/lottie.dart';
import 'package:intl/intl.dart';
import '../../../core/constants/app_colors.dart';
import '../../../data/models/doctor_model.dart';
import '../../../data/models/appointment_model.dart';
import '../../../data/repositories/appointment_repository.dart';
import '../../../providers/appointment_provider.dart';
import '../../../providers/auth_provider.dart';
import '../../../l10n/app_localizations.dart';
import '../../../core/utils/locale_utils.dart';
import '../../../core/widgets/responsive_layout.dart';

import '../main_shell.dart';

/// Main booking screen with calendar and time selection
class BookingScreen extends StatefulWidget {
  final DoctorModel doctor;
  final DateTime? initialDate;
  final TimeSlot? initialTimeSlot;
  final AppointmentRepository? appointmentRepository;

  const BookingScreen({
    super.key,
    required this.doctor,
    this.initialDate,
    this.initialTimeSlot,
    this.appointmentRepository,
  });

  @override
  State<BookingScreen> createState() => _BookingScreenState();
}

class _BookingScreenState extends State<BookingScreen> {
  late final AppointmentRepository _appointmentRepo;
  CalendarFormat _calendarFormat = CalendarFormat.month;
  DateTime _focusedDay = DateTime.now();
  DateTime? _selectedDay;
  TimeSlot? _selectedTimeSlot;
  AppointmentType _appointmentType = AppointmentType.regularCheckup;
  final _notesController = TextEditingController();
  int _currentStep = 0;
  bool _isLoading = false;

  // Real-time updates for doctor schedule
  late DoctorModel _doctor;
  StreamSubscription<DocumentSnapshot>? _doctorSubscription;

  // Server availability state
  bool _isLoadingAvailability = false;
  String? _availabilityError;
  int _availabilityRequestId = 0;
  Map<String, bool>? _serverAvailability;

  @override
  void initState() {
    super.initState();
    _appointmentRepo = widget.appointmentRepository ?? AppointmentRepository();
    _doctor = widget.doctor;
    _subscribeToDoctor();

    // Pre-select date and time if provided from DoctorScheduleScreen
    if (widget.initialDate != null) {
      _selectedDay = widget.initialDate;
      _focusedDay = widget.initialDate!;
      _currentStep = 1; // Jump to time selection step
      _fetchAvailability(widget.initialDate!);

      if (widget.initialTimeSlot != null) {
        final availableSlots = _getAvailableSlots(widget.initialDate!);
        final slotStillExists = availableSlots.any(
          (s) => s.startTime == widget.initialTimeSlot!.startTime,
        );
        if (slotStillExists) {
          _selectedTimeSlot = widget.initialTimeSlot;
        }
      }
    }
  }

  /// Subscribe to real-time updates for the doctor's schedule
  void _subscribeToDoctor() {
    _doctorSubscription = FirebaseFirestore.instance
        .collection('doctors')
        .doc(widget.doctor.id)
        .snapshots()
        .listen((snapshot) {
      if (snapshot.exists && mounted) {
        setState(() {
          _doctor = DoctorModel.fromFirestore(snapshot);
          if (!_doctorCanBook) {
            _selectedTimeSlot = null;
          }
          // Reset selected time slot if it's no longer available
          if (_selectedDay != null && _selectedTimeSlot != null) {
            final availableSlots = _getAvailableSlots(_selectedDay!);
            final slotStillExists = availableSlots.any(
              (s) => s.startTime == _selectedTimeSlot!.startTime,
            );
            if (!slotStillExists) {
              _selectedTimeSlot = null;
            }
          }
        });
        if (_selectedDay != null) {
          _fetchAvailability(_selectedDay!);
        }
      }
    });
  }

  /// Fetch availability for the selected date via trusted callable
  Future<void> _fetchAvailability(DateTime date) async {
    final requestId = ++_availabilityRequestId;
    setState(() {
      _isLoadingAvailability = true;
      _availabilityError = null;
    });

    try {
      final availability = await _appointmentRepo.getDoctorDayAvailability(
        doctorId: _doctor.id,
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

        // Reset selected time slot if it's no longer available
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
      debugPrint('Error fetching availability: $e');
      setState(() {
        _serverAvailability = null;
        _isLoadingAvailability = false;
        _availabilityError = e.toString();
        _selectedTimeSlot = null;
      });
    }
  }

  @override
  void dispose() {
    _notesController.dispose();
    _doctorSubscription?.cancel();
    super.dispose();
  }

  List<TimeSlot> _getAvailableSlots(DateTime date) {
    return _doctor.getAvailableSlots(date);
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

  bool get _doctorCanBook => _doctor.canBook;

  String get _doctorUnavailableMessage =>
      'This doctor is not available for booking right now.';

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final body = !_doctorCanBook
        ? ResponsivePage(
            maxWidth: 720,
            child: _buildDoctorUnavailableState(isDark),
          )
        : ResponsivePage(
            scrollable: false,
            maxWidth: 980,
            padding: EdgeInsets.zero,
            child: Stepper(
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
                                      ? AppLocalizations.of(context)
                                          .confirmBooking
                                      : AppLocalizations.of(context)
                                          .continueText,
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
                  state:
                      _currentStep > 0 ? StepState.complete : StepState.indexed,
                  content: _buildCalendarStep(isDark),
                ),
                // Step 2: Select Time
                Step(
                  title: Text(AppLocalizations.of(context).selectTime),
                  subtitle: _selectedTimeSlot != null
                      ? Text(_selectedTimeSlot!.display)
                      : null,
                  isActive: _currentStep >= 1,
                  state:
                      _currentStep > 1 ? StepState.complete : StepState.indexed,
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

    return Scaffold(
      appBar: AppBar(
        title: Text(AppLocalizations.of(context).bookAppointment),
        centerTitle: true,
      ),
      body: body,
    );
  }

  Widget _buildDoctorUnavailableState(bool isDark) {
    return Center(
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.all(24),
        decoration: BoxDecoration(
          color: isDark ? AppColors.surfaceDark : Colors.white,
          borderRadius: BorderRadius.circular(16),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 64,
              height: 64,
              decoration: BoxDecoration(
                color: AppColors.error.withValues(alpha: 0.12),
                shape: BoxShape.circle,
              ),
              child: const Icon(
                Icons.event_busy_rounded,
                color: AppColors.error,
                size: 34,
              ),
            ),
            const SizedBox(height: 16),
            Text(
              _doctor.name,
              style: Theme.of(context).textTheme.titleLarge?.copyWith(
                    fontWeight: FontWeight.bold,
                  ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 8),
            Text(
              _doctorUnavailableMessage,
              style: TextStyle(
                color: isDark
                    ? AppColors.textSecondaryDark
                    : AppColors.textSecondaryLight,
              ),
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildCalendarStep(bool isDark) {
    final l10n = AppLocalizations.of(context);
    final hasSchedule = _doctor.hasActiveSchedule;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (!hasSchedule)
          Container(
            margin: const EdgeInsets.only(bottom: 16),
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: AppColors.warning.withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(
                color: AppColors.warning.withValues(alpha: 0.3),
              ),
            ),
            child: Row(
              children: [
                const Icon(Icons.info_outline, color: AppColors.warning),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    l10n.noScheduleSet,
                    style: TextStyle(
                      color: isDark
                          ? AppColors.textPrimaryDark
                          : AppColors.textPrimaryLight,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ),
              ],
            ),
          ),
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
            selectedDayPredicate: (day) => isSameDay(_selectedDay, day),
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
              // Enabled days: black text
              defaultTextStyle: TextStyle(
                color: isDark ? Colors.white : Colors.black,
                fontWeight: FontWeight.w500,
              ),
              // Weekend days (if enabled): same as default
              weekendTextStyle: TextStyle(
                color: isDark ? Colors.white : Colors.black,
                fontWeight: FontWeight.w500,
              ),
              // Disabled days: gray text
              disabledTextStyle: TextStyle(
                color: isDark ? Colors.grey[600] : Colors.grey[400],
              ),
              // Selected day styling
              selectedDecoration: const BoxDecoration(
                color: AppColors.primary,
                shape: BoxShape.circle,
              ),
              selectedTextStyle: const TextStyle(
                color: Colors.white,
                fontWeight: FontWeight.bold,
              ),
              // Today styling
              todayDecoration: BoxDecoration(
                color: AppColors.primary.withValues(alpha: 0.3),
                shape: BoxShape.circle,
              ),
              todayTextStyle: TextStyle(
                color: isDark ? Colors.white : Colors.black,
                fontWeight: FontWeight.bold,
              ),
              // Outside days (other months): lighter color
              outsideTextStyle: TextStyle(
                color: isDark ? Colors.grey[700] : Colors.grey[300],
              ),
            ),
            headerStyle: const HeaderStyle(
              formatButtonVisible: true,
              titleCentered: true,
            ),
            enabledDayPredicate: (day) {
              if (!_doctorCanBook) return false;

              // Check if this day is in the future
              final isFuture = day.isAfter(
                DateTime.now().subtract(const Duration(days: 1)),
              );
              if (!isFuture) return false;

              // Only enable the day if doctor has active, valid slots for this day
              return _getAvailableSlots(day).isNotEmpty;
            },
          ),
        ),
      ],
    );
  }

  Widget _buildTimeSlotStep(bool isDark) {
    final l10n = AppLocalizations.of(context);
    if (_selectedDay == null) {
      return Center(child: Text(l10n.pleaseSelectDateFirst));
    }

    if (_isLoadingAvailability) {
      return const Center(
        child: Padding(
          padding: EdgeInsets.symmetric(vertical: 32.0),
          child: CircularProgressIndicator(),
        ),
      );
    }

    if (_availabilityError != null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 24.0, horizontal: 16.0),
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
      return Center(
        child: Column(
          children: [
            Icon(Icons.event_busy, size: 48, color: Colors.grey[400]),
            const SizedBox(height: 12),
            Text(
              _doctor.hasActiveSchedule
                  ? l10n.noAvailableSlotsOnThisDay
                  : l10n.noScheduleSet,
            ),
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
            final serverAvailable = (_serverAvailability?[slot.startTime] ??
                    _serverAvailability?[slot.fullDisplay]) ??
                false;
            final isAvailable = slot.isAvailable && !isPast && serverAvailable;
            final isSelected = _selectedTimeSlot?.startTime == slot.startTime;

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
                    decoration:
                        !isAvailable ? TextDecoration.lineThrough : null,
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
                backgroundImage: _doctor.photoUrl != null
                    ? NetworkImage(_doctor.photoUrl!)
                    : null,
                child: _doctor.photoUrl == null
                    ? const Icon(Icons.person, size: 30)
                    : null,
              ),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      _doctor.name,
                      style: Theme.of(context).textTheme.titleMedium?.copyWith(
                            fontWeight: FontWeight.bold,
                          ),
                    ),
                    Text(
                      _doctor.specialization,
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
    if (!_doctorCanBook) {
      _showError(_doctorUnavailableMessage);
      return;
    }
    if (_currentStep == 0) {
      if (_selectedDay == null) {
        _showError(AppLocalizations.of(context).pleaseSelectDate);
        return;
      }
      if (_getAvailableSlots(_selectedDay!).isEmpty) {
        _showError(
          _doctor.hasActiveSchedule
              ? AppLocalizations.of(context).noAvailableSlotsOnThisDay
              : AppLocalizations.of(context).noScheduleSet,
        );
        return;
      }
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
    if (!_doctorCanBook) {
      _showError(_doctorUnavailableMessage);
      return;
    }
    if (_selectedDay == null || _selectedTimeSlot == null) {
      return;
    }
    final currentAvailable = _getAvailableSlots(_selectedDay!);
    if (!currentAvailable.any((s) => s.startTime == _selectedTimeSlot!.startTime)) {
      _showError(AppLocalizations.of(context).noAvailableSlotsOnThisDay);
      return;
    }

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
        doctorId: _doctor.id,
        doctorName: _doctor.name,
        department: _doctor.department.name,
        appointmentDate: _selectedDay!,
        timeSlot: _selectedTimeSlot!.display,
        type: _appointmentType,
        status: AppointmentStatus.pending,
        notes: _notesController.text.isEmpty ? null : _notesController.text,
        createdAt: DateTime.now(),
        updatedAt: DateTime.now(),
      );

      final bookingResult = await appointmentProvider.bookAppointment(
        appointment,
      );

      if (bookingResult != null && mounted) {
        Navigator.pushReplacement(
          context,
          MaterialPageRoute(
            builder: (_) => BookingSuccessScreen(
              appointmentId: bookingResult.appointmentId,
              qrCode: bookingResult.qrCode,
              bookingReference: bookingReference,
              doctorName: _doctor.name,
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
    final locale = safeIntlLocale(context);
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
  final String? qrCode;
  final String? bookingReference;
  final String doctorName;
  final DateTime date;
  final String timeSlot;

  const BookingSuccessScreen({
    super.key,
    required this.appointmentId,
    this.qrCode,
    this.bookingReference,
    required this.doctorName,
    required this.date,
    required this.timeSlot,
  });

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final l10n = AppLocalizations.of(context);
    final isWide = UhcResponsive.isWide(context);

    return Scaffold(
      body: ResponsivePage(
        safeArea: true,
        maxWidth: isWide ? 980 : 640,
        bottomPadding: isWide ? 32 : 100,
        child: Column(
          children: [
            SizedBox(height: isWide ? 16 : 40),

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
              child:
                  _buildConfirmationCardContent(context, isWide, isDark, l10n),
            ),
            SizedBox(height: isWide ? 24 : 32),

            // Buttons
            _buildActionButtons(context, isWide, l10n),
          ],
        ),
      ),
    );
  }

  Widget _buildConfirmationCardContent(
    BuildContext context,
    bool isWide,
    bool isDark,
    AppLocalizations l10n,
  ) {
    if (!isWide) {
      return Column(
        children: [
          _buildQrPanel(isDark, l10n),
          const SizedBox(height: 20),
          const Divider(),
          const SizedBox(height: 20),
          _buildDetailsPanel(context, l10n),
        ],
      );
    }

    return Row(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        Expanded(child: _buildQrPanel(isDark, l10n)),
        const SizedBox(width: 28),
        SizedBox(
          height: 220,
          child: VerticalDivider(
            color: isDark ? Colors.white12 : Colors.black12,
          ),
        ),
        const SizedBox(width: 28),
        Expanded(child: _buildDetailsPanel(context, l10n)),
      ],
    );
  }

  Widget _buildQrPanel(bool isDark, AppLocalizations l10n) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(16),
          ),
          child: QrImageView(
            data: qrCode ?? bookingReference ?? appointmentId,
            version: QrVersions.auto,
            size: 180,
            backgroundColor: Colors.white,
            errorCorrectionLevel: QrErrorCorrectLevel.M,
          ),
        ),
        const SizedBox(height: 16),
        Text(
          l10n.showQRCodeAtCheckIn,
          textAlign: TextAlign.center,
          style: TextStyle(
            color: isDark
                ? AppColors.textSecondaryDark
                : AppColors.textSecondaryLight,
            fontSize: 13,
          ),
        ),
      ],
    );
  }

  Widget _buildDetailsPanel(BuildContext context, AppLocalizations l10n) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        _buildDetailRow(context, Icons.person, l10n.doctor, 'Dr. $doctorName'),
        const SizedBox(height: 14),
        _buildDetailRow(
          context,
          Icons.calendar_month,
          l10n.date,
          _formatDate(date, l10n),
        ),
        const SizedBox(height: 14),
        _buildDetailRow(context, Icons.access_time, l10n.time, timeSlot),
        const SizedBox(height: 14),
        _buildDetailRow(
          context,
          Icons.confirmation_number,
          l10n.bookingId,
          bookingReference ?? appointmentId.substring(0, 8).toUpperCase(),
        ),
      ],
    );
  }

  Widget _buildActionButtons(
    BuildContext context,
    bool isWide,
    AppLocalizations l10n,
  ) {
    final homeButton = ElevatedButton(
      onPressed: () {
        Navigator.of(context).pushAndRemoveUntil(
          MaterialPageRoute(builder: (_) => const MainShell(initialIndex: 0)),
          (route) => false,
        );
      },
      style: ElevatedButton.styleFrom(
        backgroundColor: AppColors.primary,
        foregroundColor: Colors.white,
        padding: const EdgeInsets.symmetric(vertical: 16),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      ),
      child: Text(l10n.backToHome),
    );

    final appointmentsButton = OutlinedButton(
      onPressed: () {
        Navigator.of(context).pushAndRemoveUntil(
          MaterialPageRoute(builder: (_) => const MainShell(initialIndex: 2)),
          (route) => false,
        );
      },
      style: OutlinedButton.styleFrom(
        padding: const EdgeInsets.symmetric(vertical: 16),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      ),
      child: Text(l10n.viewMyAppointments),
    );

    if (isWide) {
      return Row(
        children: [
          Expanded(child: appointmentsButton),
          const SizedBox(width: 16),
          Expanded(child: homeButton),
        ],
      );
    }

    return Column(
      children: [
        SizedBox(width: double.infinity, child: homeButton),
        const SizedBox(height: 12),
        SizedBox(width: double.infinity, child: appointmentsButton),
      ],
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

  String _formatDate(DateTime date, AppLocalizations l10n) {
    final weekdays = [
      l10n.monday,
      l10n.tuesday,
      l10n.wednesday,
      l10n.thursday,
      l10n.friday,
      l10n.saturday,
      l10n.sunday,
    ];
    final months = [
      l10n.january,
      l10n.february,
      l10n.march,
      l10n.april,
      l10n.may,
      l10n.june,
      l10n.july,
      l10n.august,
      l10n.september,
      l10n.october,
      l10n.november,
      l10n.december,
    ];
    return '${weekdays[date.weekday - 1]}, ${months[date.month - 1]} ${date.day}, ${date.year}';
  }
}
