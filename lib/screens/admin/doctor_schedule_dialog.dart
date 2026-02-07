import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import '../../core/constants/app_colors.dart';

/// A time slot representing a start and end time
class TimeSlot {
  final TimeOfDay startTime;
  final TimeOfDay endTime;
  bool isAvailable;

  TimeSlot({
    required this.startTime,
    required this.endTime,
    this.isAvailable = true,
  });

  /// Create a copy with optional modifications
  TimeSlot copyWith({
    TimeOfDay? startTime,
    TimeOfDay? endTime,
    bool? isAvailable,
  }) {
    return TimeSlot(
      startTime: startTime ?? this.startTime,
      endTime: endTime ?? this.endTime,
      isAvailable: isAvailable ?? this.isAvailable,
    );
  }

  /// Convert TimeSlot to Map for Firestore (matching existing format)
  Map<String, dynamic> toMap() {
    return {
      'startTime':
          '${startTime.hour.toString().padLeft(2, '0')}:${startTime.minute.toString().padLeft(2, '0')}',
      'endTime':
          '${endTime.hour.toString().padLeft(2, '0')}:${endTime.minute.toString().padLeft(2, '0')}',
      'isAvailable': isAvailable,
    };
  }

  /// Create TimeSlot from Map
  factory TimeSlot.fromMap(Map<String, dynamic> map) {
    final startParts = (map['startTime'] as String).split(':');
    final endParts = (map['endTime'] as String).split(':');
    return TimeSlot(
      startTime: TimeOfDay(
        hour: int.parse(startParts[0]),
        minute: int.parse(startParts[1]),
      ),
      endTime: TimeOfDay(
        hour: int.parse(endParts[0]),
        minute: int.parse(endParts[1]),
      ),
      isAvailable: map['isAvailable'] ?? true,
    );
  }

  /// Format time slot for display (compact 24-hour format)
  String format(BuildContext context) {
    final startStr =
        '${startTime.hour.toString().padLeft(2, '0')}:${startTime.minute.toString().padLeft(2, '0')}';
    final endStr =
        '${endTime.hour.toString().padLeft(2, '0')}:${endTime.minute.toString().padLeft(2, '0')}';
    return '$startStr - $endStr';
  }

  /// Convert TimeOfDay to minutes for comparison
  int _toMinutes(TimeOfDay time) => time.hour * 60 + time.minute;

  /// Check if this slot overlaps with another slot
  bool overlaps(TimeSlot other) {
    final thisStart = _toMinutes(startTime);
    final thisEnd = _toMinutes(endTime);
    final otherStart = _toMinutes(other.startTime);
    final otherEnd = _toMinutes(other.endTime);

    return thisStart < otherEnd && thisEnd > otherStart;
  }

  /// Validate that end time is after start time
  bool isValid() {
    return _toMinutes(endTime) > _toMinutes(startTime);
  }
}

/// A day schedule containing time slots (day is active if it has slots)
class DaySchedule {
  List<TimeSlot> slots;

  DaySchedule({List<TimeSlot>? slots}) : slots = slots ?? [];

  bool get isActive => slots.isNotEmpty;

  /// Convert DaySchedule to List for Firestore (matching existing format)
  List<Map<String, dynamic>> toList() {
    return slots.map((s) => s.toMap()).toList();
  }

  /// Create DaySchedule from List (as stored in Firebase)
  factory DaySchedule.fromList(List<dynamic>? list) {
    if (list == null || list.isEmpty) return DaySchedule();

    final List<TimeSlot> parsedSlots = [];
    for (final slot in list) {
      try {
        Map<String, dynamic> slotMap;
        if (slot is Map<String, dynamic>) {
          slotMap = slot;
        } else if (slot is Map) {
          slotMap = Map<String, dynamic>.from(slot);
        } else {
          continue;
        }
        parsedSlots.add(TimeSlot.fromMap(slotMap));
      } catch (e) {
        // Skip invalid slots
        continue;
      }
    }
    return DaySchedule(slots: parsedSlots);
  }
}

/// Dialog for managing doctor's weekly schedule
class DoctorScheduleDialog extends StatefulWidget {
  final String doctorId;
  final Map<String, dynamic>? currentSchedule;

  const DoctorScheduleDialog({
    super.key,
    required this.doctorId,
    this.currentSchedule,
  });

  @override
  State<DoctorScheduleDialog> createState() => _DoctorScheduleDialogState();
}

class _DoctorScheduleDialogState extends State<DoctorScheduleDialog> {
  final _firestore = FirebaseFirestore.instance;
  bool _isSaving = false;

  // Days of the week
  static const List<String> _days = [
    'monday',
    'tuesday',
    'wednesday',
    'thursday',
    'friday',
    'saturday',
    'sunday',
  ];

  static const Map<String, String> _dayLabels = {
    'monday': 'Monday',
    'tuesday': 'Tuesday',
    'wednesday': 'Wednesday',
    'thursday': 'Thursday',
    'friday': 'Friday',
    'saturday': 'Saturday',
    'sunday': 'Sunday',
  };

  // Schedule data for each day
  late Map<String, DaySchedule> _schedule;
  // Track which days are enabled (user can toggle)
  late Map<String, bool> _dayEnabled;

  @override
  void initState() {
    super.initState();
    _initializeSchedule();
  }

  void _initializeSchedule() {
    _schedule = {};
    _dayEnabled = {};

    for (final day in _days) {
      final dayData = widget.currentSchedule?[day];

      // Firebase stores as List, not Map with isActive
      if (dayData is List && dayData.isNotEmpty) {
        _schedule[day] = DaySchedule.fromList(dayData);
        _dayEnabled[day] = true;
      } else {
        _schedule[day] = DaySchedule();
        _dayEnabled[day] = false;
      }
    }
  }

  Future<void> _addTimeSlot(String day) async {
    // Pick start time
    final startTime = await showTimePicker(
      context: context,
      initialTime: const TimeOfDay(hour: 9, minute: 0),
      helpText: 'Select Start Time',
    );

    if (startTime == null || !mounted) return;

    // Pick end time (default 30 min later)
    final endTime = await showTimePicker(
      context: context,
      initialTime: TimeOfDay(
        hour: startTime.hour + (startTime.minute >= 30 ? 1 : 0),
        minute: (startTime.minute + 30) % 60,
      ),
      helpText: 'Select End Time',
    );

    if (endTime == null || !mounted) return;

    final newSlot = TimeSlot(startTime: startTime, endTime: endTime);

    // Validate end time is after start time
    if (!newSlot.isValid()) {
      _showError('End time must be after start time');
      return;
    }

    // Check for overlapping slots
    for (final existingSlot in _schedule[day]!.slots) {
      if (newSlot.overlaps(existingSlot)) {
        _showError('This time slot overlaps with an existing slot');
        return;
      }
    }

    setState(() {
      _schedule[day]!.slots.add(newSlot);
      // Sort slots by start time
      _schedule[day]!.slots.sort((a, b) {
        final aMinutes = a.startTime.hour * 60 + a.startTime.minute;
        final bMinutes = b.startTime.hour * 60 + b.startTime.minute;
        return aMinutes.compareTo(bMinutes);
      });
    });
  }

  void _removeTimeSlot(String day, int index) {
    setState(() {
      _schedule[day]!.slots.removeAt(index);
    });
  }

  void _toggleDay(String day, bool value) {
    setState(() {
      _dayEnabled[day] = value;
      // Note: We preserve the time slots when day is disabled
      // so they reappear when the day is re-enabled
    });
  }

  void _toggleSlotAvailability(String day, int index) {
    setState(() {
      _schedule[day]!.slots[index].isAvailable =
          !_schedule[day]!.slots[index].isAvailable;
    });
  }

  void _showError(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message), backgroundColor: AppColors.error),
    );
  }

  Future<void> _saveSchedule() async {
    setState(() => _isSaving = true);

    try {
      // Convert schedule to Firestore format (List per day, empty list for off days)
      final scheduleData = <String, dynamic>{};
      for (final day in _days) {
        if (_dayEnabled[day] == true) {
          scheduleData[day] = _schedule[day]!.toList();
        } else {
          scheduleData[day] = <Map<String, dynamic>>[];
        }
      }

      await _firestore.collection('doctors').doc(widget.doctorId).update({
        'weeklySchedule': scheduleData,
        'updatedAt': FieldValue.serverTimestamp(),
      });

      if (mounted) {
        Navigator.pop(context, true);
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Schedule saved successfully'),
            backgroundColor: AppColors.success,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        _showError('Error saving schedule: $e');
      }
    } finally {
      if (mounted) {
        setState(() => _isSaving = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return AlertDialog(
      title: Row(
        children: [
          Icon(Icons.calendar_month, color: AppColors.primary),
          const SizedBox(width: 8),
          const Expanded(child: Text('Manage Schedule')),
        ],
      ),
      //////////
      content: SizedBox(
        width: MediaQuery.of(context).size.width * 0.85,
        height: MediaQuery.of(context).size.height * 0.6,
        child: ListView.builder(
          itemCount: _days.length,
          itemBuilder: (context, index) {
            final day = _days[index];
            return _buildDayItem(day, isDark);
          },
        ),
      ),
      actions: [
        TextButton(
          onPressed: _isSaving ? null : () => Navigator.pop(context),
          child: const Text('Cancel'),
        ),
        ElevatedButton(
          onPressed: _isSaving ? null : _saveSchedule,
          child: _isSaving
              ? const SizedBox(
                  width: 20,
                  height: 20,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    color: Colors.white,
                  ),
                )
              : const Text('Save Schedule'),
        ),
      ],
    );
  }

  Widget _buildDayItem(String day, bool isDark) {
    final isEnabled = _dayEnabled[day] ?? false;
    final daySchedule = _schedule[day]!;

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      decoration: BoxDecoration(
        border: Border.all(
          color: isEnabled
              ? AppColors.primary.withValues(alpha: 0.5)
              : (isDark ? Colors.grey[700]! : Colors.grey[300]!),
          width: 1.5,
        ),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        children: [
          // Day Header with Toggle
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            child: Row(
              children: [
                CircleAvatar(
                  radius: 18,
                  backgroundColor: isEnabled
                      ? AppColors.primary
                      : (isDark ? Colors.grey[700] : Colors.grey[300]),
                  child: Text(
                    _dayLabels[day]![0],
                    style: TextStyle(
                      color: isEnabled
                          ? Colors.white
                          : (isDark ? Colors.white70 : Colors.black54),
                      fontWeight: FontWeight.bold,
                      fontSize: 14,
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        _dayLabels[day]!,
                        style: TextStyle(
                          fontWeight: FontWeight.w600,
                          fontSize: 15,
                          color: isEnabled
                              ? (isDark ? Colors.white : Colors.black87)
                              : (isDark ? Colors.grey[500] : Colors.grey[600]),
                        ),
                      ),
                      Text(
                        isEnabled
                            ? '${daySchedule.slots.length} time slot(s)'
                            : 'Day off',
                        style: TextStyle(
                          fontSize: 12,
                          color: isDark ? Colors.grey[400] : Colors.grey[600],
                          fontStyle: isEnabled
                              ? FontStyle.normal
                              : FontStyle.italic,
                        ),
                      ),
                    ],
                  ),
                ),
                Switch(
                  value: isEnabled,
                  onChanged: (value) => _toggleDay(day, value),
                ),
              ],
            ),
          ),

          // Time Slots (only shown when day is enabled)
          if (isEnabled) ...[
            Divider(
              height: 1,
              color: isDark ? Colors.grey[700] : Colors.grey[300],
            ),
            Padding(
              padding: const EdgeInsets.all(12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Existing Slots - 2 per row
                  if (daySchedule.slots.isNotEmpty)
                    LayoutBuilder(
                      builder: (context, constraints) {
                        return Wrap(
                          spacing: 6,
                          runSpacing: 6,
                          children: daySchedule.slots.asMap().entries.map((
                            entry,
                          ) {
                            final index = entry.key;
                            final slot = entry.value;
                            final slotColor = slot.isAvailable
                                ? AppColors.primary
                                : AppColors.error;
                            // Calculate width for 2 items per row
                            final itemWidth = (constraints.maxWidth - 6) / 2;
                            return SizedBox(
                              width: itemWidth,
                              child: GestureDetector(
                                onTap: () =>
                                    _toggleSlotAvailability(day, index),
                                child: Chip(
                                  avatar: Icon(
                                    slot.isAvailable
                                        ? Icons.check_circle
                                        : Icons.cancel,
                                    size: 14,
                                    color: slotColor,
                                  ),
                                  label: Text(
                                    slot.format(context),
                                    style: TextStyle(
                                      color: slotColor,
                                      fontWeight: FontWeight.w500,
                                      fontSize: 11,
                                      decoration: slot.isAvailable
                                          ? null
                                          : TextDecoration.lineThrough,
                                    ),
                                  ),
                                  backgroundColor: isDark
                                      ? slotColor.withValues(alpha: 0.1)
                                      : Colors.white,
                                  shape: RoundedRectangleBorder(
                                    borderRadius: BorderRadius.circular(16),
                                    side: BorderSide(
                                      color: slotColor.withValues(alpha: 0.5),
                                      width: 1,
                                    ),
                                  ),
                                  deleteIcon: Icon(
                                    Icons.close,
                                    size: 14,
                                    color: slotColor,
                                  ),
                                  onDeleted: () => _removeTimeSlot(day, index),
                                  visualDensity: VisualDensity.compact,
                                  materialTapTargetSize:
                                      MaterialTapTargetSize.shrinkWrap,
                                  padding: EdgeInsets.zero,
                                  labelPadding: const EdgeInsets.only(right: 2),
                                ),
                              ),
                            );
                          }).toList(),
                        );
                      },
                    ),

                  const SizedBox(height: 8),

                  // Add Slot Button
                  TextButton.icon(
                    onPressed: () => _addTimeSlot(day),
                    icon: Icon(
                      Icons.add_circle_outline,
                      size: 18,
                      color: AppColors.primary,
                    ),
                    label: Text(
                      'Add Time Slot',
                      style: TextStyle(color: AppColors.primary, fontSize: 13),
                    ),
                    style: TextButton.styleFrom(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 8,
                        vertical: 4,
                      ),
                      minimumSize: Size.zero,
                      tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }
}
