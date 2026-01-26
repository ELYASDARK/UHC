import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import '../../core/constants/app_colors.dart';
import '../../data/models/doctor_model.dart';
import '../../providers/auth_provider.dart';

/// Waiting list model
class WaitingListEntry {
  final String id;
  final String patientId;
  final String patientName;
  final String doctorId;
  final String doctorName;
  final DateTime preferredDate;
  final List<String> preferredTimeSlots;
  final DateTime createdAt;
  final bool isActive;
  final bool isNotified;

  WaitingListEntry({
    required this.id,
    required this.patientId,
    required this.patientName,
    required this.doctorId,
    required this.doctorName,
    required this.preferredDate,
    required this.preferredTimeSlots,
    required this.createdAt,
    this.isActive = true,
    this.isNotified = false,
  });

  factory WaitingListEntry.fromFirestore(DocumentSnapshot doc) {
    final data = doc.data() as Map<String, dynamic>;
    return WaitingListEntry(
      id: doc.id,
      patientId: data['patientId'] ?? '',
      patientName: data['patientName'] ?? '',
      doctorId: data['doctorId'] ?? '',
      doctorName: data['doctorName'] ?? '',
      preferredDate: (data['preferredDate'] as Timestamp).toDate(),
      preferredTimeSlots: List<String>.from(data['preferredTimeSlots'] ?? []),
      createdAt: (data['createdAt'] as Timestamp).toDate(),
      isActive: data['isActive'] ?? true,
      isNotified: data['isNotified'] ?? false,
    );
  }

  Map<String, dynamic> toFirestore() {
    return {
      'patientId': patientId,
      'patientName': patientName,
      'doctorId': doctorId,
      'doctorName': doctorName,
      'preferredDate': Timestamp.fromDate(preferredDate),
      'preferredTimeSlots': preferredTimeSlots,
      'createdAt': Timestamp.fromDate(createdAt),
      'isActive': isActive,
      'isNotified': isNotified,
    };
  }
}

/// Waiting list screen
class WaitingListScreen extends StatefulWidget {
  final DoctorModel doctor;

  const WaitingListScreen({super.key, required this.doctor});

  @override
  State<WaitingListScreen> createState() => _WaitingListScreenState();
}

class _WaitingListScreenState extends State<WaitingListScreen> {
  DateTime? _selectedDate;
  final List<String> _selectedTimeSlots = [];
  bool _isLoading = false;

  final _firestore = FirebaseFirestore.instance;

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
    return widget.doctor.weeklySchedule[dayName] ?? [];
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Scaffold(
      appBar: AppBar(title: const Text('Join Waiting List'), centerTitle: true),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Info Card
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: AppColors.info.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(16),
                border: Border.all(
                  color: AppColors.info.withValues(alpha: 0.3),
                ),
              ),
              child: Row(
                children: [
                  const Icon(Icons.info_outline, color: AppColors.info),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      'You\'ll be notified when a slot becomes available with Dr. ${widget.doctor.name}.',
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
            const SizedBox(height: 24),

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
                        'Dr. ${widget.doctor.name}',
                        style: Theme.of(context).textTheme.titleMedium
                            ?.copyWith(fontWeight: FontWeight.bold),
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
            const SizedBox(height: 24),

            // Select Preferred Date
            Text(
              'Preferred Date',
              style: Theme.of(
                context,
              ).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 12),
            InkWell(
              onTap: _selectDate,
              child: Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: isDark ? AppColors.surfaceDark : Colors.white,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(
                    color: AppColors.primary.withValues(alpha: 0.3),
                  ),
                ),
                child: Row(
                  children: [
                    const Icon(Icons.calendar_today, color: AppColors.primary),
                    const SizedBox(width: 12),
                    Text(
                      _selectedDate != null
                          ? _formatDate(_selectedDate!)
                          : 'Select a date',
                      style: TextStyle(
                        color: _selectedDate != null ? null : Colors.grey,
                      ),
                    ),
                    const Spacer(),
                    const Icon(Icons.arrow_drop_down),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 24),

            // Preferred Time Slots
            if (_selectedDate != null) ...[
              Text(
                'Preferred Time Slots',
                style: Theme.of(
                  context,
                ).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 8),
              Text(
                'Select one or more time slots you prefer',
                style: TextStyle(
                  color: isDark
                      ? AppColors.textSecondaryDark
                      : AppColors.textSecondaryLight,
                  fontSize: 13,
                ),
              ),
              const SizedBox(height: 12),
              _buildTimeSlotSelection(isDark),
            ],
            const SizedBox(height: 32),

            // Join Button
            SizedBox(
              width: double.infinity,
              child: ElevatedButton(
                onPressed:
                    _selectedDate != null &&
                        _selectedTimeSlots.isNotEmpty &&
                        !_isLoading
                    ? _joinWaitingList
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
                    : const Text('Join Waiting List'),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildTimeSlotSelection(bool isDark) {
    final slots = _getAvailableSlots(_selectedDate!);

    if (slots.isEmpty) {
      return Container(
        padding: const EdgeInsets.all(20),
        decoration: BoxDecoration(
          color: isDark ? AppColors.surfaceDark : Colors.grey[100],
          borderRadius: BorderRadius.circular(12),
        ),
        child: const Center(child: Text('Doctor has no schedule on this day')),
      );
    }

    return Wrap(
      spacing: 10,
      runSpacing: 10,
      children: slots.map((slot) {
        final isSelected = _selectedTimeSlots.contains(slot.display);
        return FilterChip(
          label: Text(slot.display),
          selected: isSelected,
          onSelected: (selected) {
            setState(() {
              if (selected) {
                _selectedTimeSlots.add(slot.display);
              } else {
                _selectedTimeSlots.remove(slot.display);
              }
            });
          },
          selectedColor: AppColors.primary,
          labelStyle: TextStyle(color: isSelected ? Colors.white : null),
          checkmarkColor: Colors.white,
        );
      }).toList(),
    );
  }

  Future<void> _selectDate() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: DateTime.now().add(const Duration(days: 1)),
      firstDate: DateTime.now().add(const Duration(days: 1)),
      lastDate: DateTime.now().add(const Duration(days: 60)),
    );

    if (picked != null) {
      setState(() {
        _selectedDate = picked;
        _selectedTimeSlots.clear();
      });
    }
  }

  Future<void> _joinWaitingList() async {
    final user = context.read<AuthProvider>().user;
    if (user == null) return;

    setState(() => _isLoading = true);

    try {
      final entry = WaitingListEntry(
        id: '',
        patientId: user.id,
        patientName: user.fullName,
        doctorId: widget.doctor.id,
        doctorName: widget.doctor.name,
        preferredDate: _selectedDate!,
        preferredTimeSlots: _selectedTimeSlots,
        createdAt: DateTime.now(),
      );

      await _firestore.collection('waiting_list').add(entry.toFirestore());

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Successfully joined waiting list'),
            backgroundColor: AppColors.success,
          ),
        );
        Navigator.pop(context, true);
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error: ${e.toString()}'),
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
    const weekdays = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];
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
    return '${weekdays[date.weekday - 1]}, ${months[date.month - 1]} ${date.day}, ${date.year}';
  }
}
